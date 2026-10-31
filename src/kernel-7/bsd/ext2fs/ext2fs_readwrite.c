/*	$NetBSD: ext2fs_readwrite.c,v 1.32 2004/03/22 19:23:08 bouyer Exp $	*/

/*-
 * Copyright (c) 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *	@(#)ufs_readwrite.c	8.8 (Berkeley) 8/4/94
 * Modified for ext2fs by Manuel Bouyer.
 */

/*-
 * Copyright (c) 1997 Manuel Bouyer.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by Manuel Bouyer.
 * 4. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *	@(#)ufs_readwrite.c	8.8 (Berkeley) 8/4/94
 * Modified for ext2fs by Manuel Bouyer.
 */

#include "ext2fs_extern.h"
#include <sys/resource.h>
#include <sys/signalvar.h>
#include <vm/vnode_pager.h>
#include <mach_nbc.h>
#if MACH_NBC
#include <kern/mapfs.h>
#endif



#define doclusterread 0 /* XXX underway */
#define doclusterwrite 0

/*
 * Vnode op for reading.
 */
/* ARGSUSED */
int
ext2fs_read(v)
	void *v;
{
	struct vop_read_args /* {
		struct vnode *a_vp;
		struct uio *a_uio;
		int a_ioflag;
		struct ucred *a_cred;
	} */ *ap = v;
	struct vnode *vp;
	struct inode *ip;
	struct uio *uio;
	struct m_ext2fs *fs;
	struct buf *bp;
	daddr_t lbn, nextlbn;
	off_t bytesinfile;
	long size, xfersize, blkoffset;
	int error, resid;

	vp = ap->a_vp;
	ip = VTOI(vp);
	uio = ap->a_uio;
	resid = uio->uio_resid;

#if MACH_NBC
	/* Native pager pass-through uses UIO_SYSSPACE and must stay buffered. */
	if (vp->v_type == VREG && vp->v_vm_info && vp->v_vm_info->pager &&
	    uio->uio_segflg == UIO_USERSPACE) {
		error = ext2fs_vm_io(vp,uio,ap->a_ioflag,ap->a_cred);
		goto accessed;
	}
#endif

#ifdef DIAGNOSTIC
	if (uio->uio_rw != UIO_READ)
		panic("%s: mode", "ext2fs_read");

	if (vp->v_type == VLNK) {
		if ((int)ip->i_e2fs_size < vp->v_mount->mnt_maxsymlinklen ||
			(vp->v_mount->mnt_maxsymlinklen == 0 &&
			 ip->i_e2fs_nblock == 0))
			panic("%s: short symlink", "ext2fs_read");
	} else if (vp->v_type != VREG && vp->v_type != VDIR)
		panic("%s: type %d", "ext2fs_read", vp->v_type);
#endif
	fs = ip->i_e2fs;
	if ((u_int64_t)uio->uio_offset >
		EXT2_FILESIZE_MAX)
		return (EFBIG);
	if (uio->uio_resid == 0)
		return (0);
	if (uio->uio_offset >= ip->i_e2fs_size)
		return (0);


	for (error = 0, bp = NULL; uio->uio_resid > 0; bp = NULL) {
		if ((bytesinfile = ip->i_e2fs_size - uio->uio_offset) <= 0)
			break;
		lbn = lblkno(fs, uio->uio_offset);
		nextlbn = lbn + 1;
		size = fs->e2fs_bsize;
		blkoffset = blkoff(fs, uio->uio_offset);
		xfersize = fs->e2fs_bsize - blkoffset;
		if (uio->uio_resid < xfersize)
			xfersize = uio->uio_resid;
		if (bytesinfile < xfersize)
			xfersize = bytesinfile;

		if (lblktosize(fs, nextlbn) >= ip->i_e2fs_size)
			error = bread(vp, lbn, size, NOCRED, &bp);
		else {
			int nextsize = fs->e2fs_bsize;
			error = breadn(vp, lbn,
				size, &nextlbn, &nextsize, 1, NOCRED, &bp);
		}
		if (error)
			break;

		/*
		 * We should only get non-zero b_resid when an I/O error
		 * has occurred, which should cause us to break above.
		 * However, if the short read did not cause an error,
		 * then we want to ensure that we do not uiomove bad
		 * or uninitialized data.
		 */
		size -= bp->b_resid + blkoffset;
		if (size < xfersize) {
			if (size <= 0) { error = EIO; break; }
			xfersize = size;
		}
		error = uiomove((char *)bp->b_un.b_addr + blkoffset, xfersize, uio);
		if (error)
			break;
		brelse(bp);
	}
	if (bp != NULL)
		brelse(bp);


#if MACH_NBC
accessed:
#endif
	if (uio->uio_resid < resid && !(vp->v_mount->mnt_flag & MNT_RDONLY))
		ip->i_flag |= IN_ACCESS;
	return (error);
}

/*
 * Vnode op for writing.
 */
int
ext2fs_write(v)
	void *v;
{
	struct vop_write_args /* {
		struct vnode *a_vp;
		struct uio *a_uio;
		int a_ioflag;
		struct ucred *a_cred;
	} */ *ap = v;
	struct vnode *vp;
	struct uio *uio;
	struct inode *ip;
	struct m_ext2fs *fs;
	struct buf *bp;
	struct proc *p;
	daddr_t lbn;
	off_t osize;
	int blkoffset, error, flags, ioflag, resid, xfersize;

	ioflag = ap->a_ioflag;
	uio = ap->a_uio;
	vp = ap->a_vp;
	ip = VTOI(vp);
	error = 0;
	if (ip->i_e2fs->e2fs_suspended) return ip->i_e2fs->e2fs_ioerror;
	if ((vp->v_mount->mnt_flag & MNT_RDONLY) &&
        !(uio->uio_segflg == UIO_SYSSPACE && !ip->i_e2fs->e2fs_ronly)) return EROFS;

#if MACH_NBC
	if (vp->v_type == VREG && vp->v_vm_info && vp->v_vm_info->pager &&
	    uio->uio_segflg == UIO_USERSPACE)
		return ext2fs_vm_io(vp,uio,ioflag,ap->a_cred);
#endif

#ifdef DIAGNOSTIC
	if (uio->uio_rw != UIO_WRITE)
		panic("%s: mode", "ext2fs_write");
#endif

	switch (vp->v_type) {
	case VREG:
		if (ioflag & IO_APPEND)
			uio->uio_offset = ip->i_e2fs_size;
		if ((ext2fs_dinode(ip)->e2di_flags & EXT2_APPEND) &&
			uio->uio_offset != ip->i_e2fs_size)
			return (EPERM);
		/* FALLTHROUGH */
	case VLNK:
		break;
	case VDIR:
		if ((ioflag & IO_SYNC) == 0)
			panic("%s: nonsync dir write", "ext2fs_write");
		break;
	default:
		panic("%s: type", "ext2fs_write");
	}

	fs = ip->i_e2fs;
	if (uio->uio_offset < 0 ||
		(u_int64_t)uio->uio_offset + uio->uio_resid >
		EXT2_FILESIZE_MAX)
		return (EFBIG);
	/*
	 * Maybe this should be above the vnode op call, but so long as
	 * file servers have no limits, I don't think it matters.
	 */
	p = uio->uio_procp;
	if (vp->v_type == VREG && p &&
		uio->uio_offset + uio->uio_resid >
		p->p_rlimit[RLIMIT_FSIZE].rlim_cur) {
		psignal(p, SIGXFSZ);
		return (EFBIG);
	}
	if (uio->uio_resid == 0)
		return (0);

	resid = uio->uio_resid;
	osize = ip->i_e2fs_size;

	flags = ioflag & IO_SYNC ? B_SYNC : 0;
	for (error = 0; uio->uio_resid > 0;) {
		lbn = lblkno(fs, uio->uio_offset);
		blkoffset = blkoff(fs, uio->uio_offset);
		xfersize = MIN(fs->e2fs_bsize - blkoffset, uio->uio_resid);
		if (xfersize < fs->e2fs_bsize)
			flags |= B_CLRBUF;
		else
			flags &= ~B_CLRBUF;
		error = ext2fs_balloc(ip,
		    lbn, blkoffset + xfersize, ap->a_cred, &bp, flags);
		if (error)
			break;
		if (ip->i_e2fs_size < uio->uio_offset + xfersize) {
			ip->i_e2fs_size = uio->uio_offset + xfersize;
		}
		error = uiomove((char *)bp->b_un.b_addr + blkoffset, xfersize, uio);

#if MACH_NBC
        if (vp->v_type == VREG && vp->v_vm_info && !vp->v_vm_info->mapped)
#endif
            vnode_pager_setsize(vp, (u_long)ip->i_size);
#if !MACH_NBC
        (void)vnode_uncache(vp);
#endif

		{ int e=ext2_buf_write(bp,(ioflag & IO_SYNC) ? MNT_WAIT : MNT_NOWAIT);
          if (!error) error=e; }
		if (error || xfersize == 0)
			break;
	}

	/*
	 * If we successfully wrote any data, and we are not the superuser
	 * we clear the setuid and setgid bits as a precaution against
	 * tampering.
	 */

	ip->i_flag |= IN_CHANGE | IN_UPDATE;
	if (resid > uio->uio_resid && ap->a_cred && ap->a_cred->cr_uid != 0)
		ip->i_e2fs_mode &= ~(ISUID | ISGID);
	if (error && (ioflag & IO_UNIT)) {
		(void) VOP_TRUNCATE(vp, osize, ioflag & IO_SYNC, ap->a_cred,
		    uio->uio_procp);
		uio->uio_offset -= resid - uio->uio_resid;
		uio->uio_resid = resid;
	} else if (!error && resid > uio->uio_resid && (ioflag & IO_SYNC) == IO_SYNC)
		error = VOP_UPDATE(vp, NULL, NULL, MNT_WAIT);
	if (error == ENOSPC && resid > uio->uio_resid && !(ioflag & IO_UNIT)) error=0;
	return (error);
}
