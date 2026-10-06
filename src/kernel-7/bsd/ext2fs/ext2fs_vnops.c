/*	$NetBSD: ext2fs_vnops.c,v 1.52.2.1 2004/05/23 11:56:04 grant Exp $	*/

/*
 * Copyright (c) 1982, 1986, 1989, 1993
 *	The Regents of the University of California.  All rights reserved.
 * (c) UNIX System Laboratories, Inc.
 * All or some portions of this file are derived from material licensed
 * to the University of California by American Telephone and Telegraph
 * Co. or Unix System Laboratories, Inc. and are reproduced herein with
 * the permission of UNIX System Laboratories, Inc.
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
 *	@(#)ufs_vnops.c	8.14 (Berkeley) 10/26/94
 * Modified for ext2fs by Manuel Bouyer.
 */

/*
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
 *	@(#)ufs_vnops.c	8.14 (Berkeley) 10/26/94
 * Modified for ext2fs by Manuel Bouyer.
 */

#include "ext2fs_extern.h"
#include <sys/unistd.h>
#include <machine/spl.h>
#include <mach_nbc.h>
#if MACH_NBC
#include <kern/mapfs.h>
void vmp_get(struct vm_info *);
void vmp_put(struct vm_info *);
int vmp_push_range(struct vm_info *,vm_offset_t,vm_size_t);
#endif
int groupmember(gid_t,struct ucred *);
#include <miscfs/specfs/specdev.h>
#include <miscfs/fifofs/fifo.h>
static int ext2fs_chmod(struct vnode *,int,struct ucred *,struct proc *);
static int ext2fs_chown(struct vnode *,uid_t,gid_t,struct ucred *,struct proc *);

int
ext2fs_create(v)
	void *v;
{
	struct vop_create_args /* {
		struct vnode *a_dvp;
		struct vnode **a_vpp;
		struct componentname *a_cnp;
		struct vattr *a_vap;
	} */ *ap = v;
	int	error;

	error =
	    ext2fs_makeinode(MAKEIMODE(ap->a_vap->va_type, ap->a_vap->va_mode),
			     ap->a_dvp, ap->a_vpp, ap->a_cnp);

	if (error)
		return (error);

	return (0);
}

int
ext2fs_mknod(v)
	void *v;
{
	struct vop_mknod_args /* {
		struct vnode *a_dvp;
		struct vnode **a_vpp;
		struct componentname *a_cnp;
		struct vattr *a_vap;
	} */ *ap = v;
	struct vattr *vap = ap->a_vap;
	struct vnode **vpp = ap->a_vpp;
	struct inode *ip;
	int error;

	if ((error = ext2fs_makeinode(MAKEIMODE(vap->va_type, vap->va_mode),
		    ap->a_dvp, vpp, ap->a_cnp)) != 0)
		return (error);

	ip = VTOI(*vpp);
	ip->i_flag |= IN_ACCESS | IN_CHANGE | IN_UPDATE;
	if (vap->va_rdev != VNOVAL) {
		/*
		 * Want to be able to use this to make badblock
		 * inodes, so don't truncate the dev number.
		 */
		ip->i_rdev = vap->va_rdev;
	}
	/*
	 * Remove inode so that it will be reloaded by VFS_VGET and
	 * checked to see if it is an alias of an existing entry in
	 * the inode cache.
	 */
	vput(*vpp);
	(*vpp)->v_type = VNON;
	vgone(*vpp);
	*vpp = NULL;
	return (0);
}

int
ext2fs_open(v)
	void *v;
{
	struct vop_open_args /* {
		struct vnode *a_vp;
		int  a_mode;
		struct ucred *a_cred;
		struct proc *a_p;
	} */ *ap = v;

	/*
	 * Files marked append-only must be opened for appending.
	 */
	if ((ext2fs_dinode(VTOI(ap->a_vp))->e2di_flags & EXT2_APPEND) &&
		(ap->a_mode & (FWRITE | O_APPEND)) == FWRITE)
		return (EPERM);
	return (0);
}

int
ext2fs_access(v)
	void *v;
{
	struct vop_access_args /* {
		struct vnode *a_vp;
		int  a_mode;
		struct ucred *a_cred;
		struct proc *a_p;
	} */ *ap = v;
	struct vnode *vp = ap->a_vp;
	struct inode *ip = VTOI(vp);
	mode_t mode = ap->a_mode;

	/*
	 * Disallow write attempts on read-only file systems;
	 * unless the file is a socket, fifo, or a block or
	 * character device resident on the file system.
	 */
	if (mode & VWRITE) {
		switch (vp->v_type) {
		case VDIR:
		case VLNK:
		case VREG:
			if (vp->v_mount->mnt_flag & MNT_RDONLY)
				return (EROFS);
			break;
		default:
			break;
		}
	}

	/* If immutable bit set, nobody gets to write it. */
	if ((mode & VWRITE) && (ext2fs_dinode(ip)->e2di_flags & EXT2_IMMUTABLE))
		return (EPERM);

	if (ap->a_cred->cr_uid == 0) return 0;
    if (ap->a_cred->cr_uid != ip->i_uid) {
        mode >>= 3;
        if (!groupmember(ip->i_gid,ap->a_cred)) mode >>= 3;
    }
    return (ip->i_mode & mode) == mode ? 0 : EACCES;
}

int
ext2fs_setattr(v)
	void *v;
{
	struct vop_setattr_args /* {
		struct vnode *a_vp;
		struct vattr *a_vap;
		struct ucred *a_cred;
		struct proc *a_p;
	} */ *ap = v;
	struct vattr *vap = ap->a_vap;
	struct vnode *vp = ap->a_vp;
	struct inode *ip = VTOI(vp);
	struct ucred *cred = ap->a_cred;
	struct proc *p = ap->a_p;
	int error;
	struct timeval atime,mtime;

	/*
	 * Check for unsettable attributes.
	 */
	if ((vap->va_type != VNON) || (vap->va_nlink != VNOVAL) ||
	    (vap->va_fsid != VNOVAL) || (vap->va_fileid != VNOVAL) ||
	    (vap->va_blocksize != VNOVAL) || (vap->va_rdev != VNOVAL) ||
	    ((int)vap->va_bytes != VNOVAL) || (vap->va_gen != VNOVAL)) {
		return (EINVAL);
	}
	if (vap->va_flags != VNOVAL) {
		if (vp->v_mount->mnt_flag & MNT_RDONLY)
			return (EROFS);
		if (cred->cr_uid != ip->i_e2fs_uid &&
			(error = suser(cred, &p->p_acflag)))
			return (error);
#ifdef EXT2FS_SYSTEM_FLAGS
		if (cred->cr_uid == 0) {
			if ((ext2fs_dinode(ip)->e2di_flags &
			    (EXT2_APPEND | EXT2_IMMUTABLE)) && securelevel > 0)
				return (EPERM);
			ext2fs_dinode(ip)->e2di_flags &= ~(EXT2_APPEND | EXT2_IMMUTABLE);
			ext2fs_dinode(ip)->e2di_flags |=
			    (vap->va_flags & SF_APPEND) ?  EXT2_APPEND : 0 |
			    (vap->va_flags & SF_IMMUTABLE) ? EXT2_IMMUTABLE : 0;
		} else
			return (EPERM);
#else
		ext2fs_dinode(ip)->e2di_flags &= ~(EXT2_APPEND | EXT2_IMMUTABLE);
		ext2fs_dinode(ip)->e2di_flags |=
		    ((vap->va_flags & UF_APPEND) ? EXT2_APPEND : 0) |
		    ((vap->va_flags & UF_IMMUTABLE) ? EXT2_IMMUTABLE : 0);
#endif
		ip->i_flag |= IN_CHANGE;
		if (vap->va_flags & (IMMUTABLE | APPEND))
			return (0);
	}
	if (ext2fs_dinode(ip)->e2di_flags & (EXT2_APPEND | EXT2_IMMUTABLE))
		return (EPERM);
	/*
	 * Go through the fields and update iff not VNOVAL.
	 */
	if (vap->va_uid != (uid_t)VNOVAL || vap->va_gid != (gid_t)VNOVAL) {
		if (vp->v_mount->mnt_flag & MNT_RDONLY)
			return (EROFS);
		error = ext2fs_chown(vp, vap->va_uid, vap->va_gid, cred, p);
		if (error)
			return (error);
	}
	if (vap->va_size != VNOVAL) {
		/*
		 * Disallow write attempts on read-only file systems;
		 * unless the file is a socket, fifo, or a block or
		 * character device resident on the file system.
		 */
		switch (vp->v_type) {
		case VDIR:
			return (EISDIR);
		case VLNK:
		case VREG:
			if (vp->v_mount->mnt_flag & MNT_RDONLY)
				return (EROFS);
		default:
			break;
		}
		error = VOP_TRUNCATE(vp, vap->va_size, 0, cred, p);
		if (error)
			return (error);
	}
	ip = VTOI(vp);
	if (vap->va_atime.tv_sec != VNOVAL || vap->va_mtime.tv_sec != VNOVAL) {
		if (vp->v_mount->mnt_flag & MNT_RDONLY)
			return (EROFS);
		if (cred->cr_uid != ip->i_e2fs_uid &&
			(error = suser(cred, &p->p_acflag)) &&
			((vap->va_vaflags & VA_UTIMES_NULL) == 0 || 
			(error = VOP_ACCESS(vp, VWRITE, cred, p))))
			return (error);
		if (vap->va_atime.tv_sec != VNOVAL)
			ip->i_flag |= IN_ACCESS;
		if (vap->va_mtime.tv_sec != VNOVAL)
			ip->i_flag |= IN_CHANGE | IN_UPDATE;
		atime.tv_sec=vap->va_atime.tv_sec; atime.tv_usec=vap->va_atime.tv_nsec/1000;
		mtime.tv_sec=vap->va_mtime.tv_sec; mtime.tv_usec=vap->va_mtime.tv_nsec/1000;
		error = VOP_UPDATE(vp, &atime, &mtime,
			MNT_WAIT);
		if (error)
			return (error);
	}
	error = 0;
	if (vap->va_mode != (mode_t)VNOVAL) {
		if (vp->v_mount->mnt_flag & MNT_RDONLY)
			return (EROFS);
		error = ext2fs_chmod(vp, (int)vap->va_mode, cred, p);
	}

	return (error);
}

static int
ext2fs_chmod(vp, mode, cred, p)
	struct vnode *vp;
	int mode;
	struct ucred *cred;
	struct proc *p;
{
	struct inode *ip = VTOI(vp);
	int error;

	if (cred->cr_uid != ip->i_e2fs_uid &&
		(error = suser(cred, &p->p_acflag)))
		return (error);
	if (cred->cr_uid) {
		if (vp->v_type != VDIR && (mode & S_ISTXT))
			return (EFTYPE);
		if (!groupmember(ip->i_e2fs_gid, cred) && (mode & ISGID))
			return (EPERM);
	}
	ip->i_e2fs_mode &= ~ALLPERMS;
	ip->i_e2fs_mode |= (mode & ALLPERMS);
	ip->i_flag |= IN_CHANGE;
	return (0);
}

static int
ext2fs_chown(vp, uid, gid, cred, p)
	struct vnode *vp;
	uid_t uid;
	gid_t gid;
	struct ucred *cred;
	struct proc *p;
{
	struct inode *ip = VTOI(vp);
	uid_t ouid;
	gid_t ogid;
	int error = 0;

	if (uid == (uid_t)VNOVAL)
		uid = ip->i_e2fs_uid;
	if (gid == (gid_t)VNOVAL)
		gid = ip->i_e2fs_gid;
	/*
	 * If we don't own the file, are trying to change the owner
	 * of the file, or are not a member of the target group,
	 * the caller must be superuser or the call fails.
	 */
	if ((cred->cr_uid != ip->i_e2fs_uid || uid != ip->i_e2fs_uid ||
		(gid != ip->i_e2fs_gid &&
		 !(cred->cr_gid == gid || groupmember((gid_t)gid, cred)))) &&
		(error = suser(cred, &p->p_acflag)))
		return (error);
	ogid = ip->i_e2fs_gid;
	ouid = ip->i_e2fs_uid;

	ip->i_e2fs_gid = gid;
	ip->i_e2fs_uid = uid;
	if (ouid != uid || ogid != gid)
		ip->i_flag |= IN_CHANGE;
	if (ouid != uid && cred->cr_uid != 0)
		ip->i_e2fs_mode &= ~ISUID;
	if (ogid != gid && cred->cr_uid != 0)
		ip->i_e2fs_mode &= ~ISGID;
	return (0);
}

int
ext2fs_remove(v)
	void *v;
{
	struct vop_remove_args /* {
		struct vnode *a_dvp;
		struct vnode *a_vp;
		struct componentname *a_cnp;
	} */ *ap = v;
	struct inode *ip;
	struct vnode *vp = ap->a_vp;
	struct vnode *dvp = ap->a_dvp;
	int error;

	ip = VTOI(vp);
	if (vp->v_type == VDIR ||
		(ext2fs_dinode(ip)->e2di_flags & (EXT2_IMMUTABLE | EXT2_APPEND)) ||
		(ext2fs_dinode(VTOI(dvp))->e2di_flags & EXT2_APPEND)) {
		error = EPERM;
	} else {
		error = ext2fs_dirremove(dvp, ap->a_cnp);
		if (error == 0) {
			ip->i_e2fs_nlink--;
			ip->i_flag |= IN_CHANGE;
		}
	}


	if (dvp == vp)
		vrele(vp);
	else
		vput(vp);
	vput(dvp);
	return (error);
}

int
ext2fs_link(v)
	void *v;
{
	struct vop_link_args /* {
		struct vnode *a_tdvp;
		struct vnode *a_vp;
		struct componentname *a_cnp;
	} */ *ap = v;
	struct vnode *dvp = ap->a_tdvp;
	struct vnode *vp = ap->a_vp;
	struct componentname *cnp = ap->a_cnp;
	struct inode *ip;
	int error;

#ifdef DIAGNOSTIC
	if ((cnp->cn_flags & HASBUF) == 0)
		panic("ext2fs_link: no name");
#endif
	if (vp->v_type == VDIR) {
		VOP_ABORTOP(dvp, cnp);
		error = EISDIR;
		goto out2;
	}
	if (dvp->v_mount != vp->v_mount) {
		VOP_ABORTOP(dvp, cnp);
		error = EXDEV;
		goto out2;
	}
	if (dvp != vp && (error = vn_lock(vp, LK_EXCLUSIVE, current_proc()))) {
		VOP_ABORTOP(dvp, cnp);
		goto out2;
	}
	ip = VTOI(vp);
	if ((nlink_t)ip->i_e2fs_nlink >= LINK_MAX) {
		VOP_ABORTOP(dvp, cnp);
		error = EMLINK;
		goto out1;
	}
	if (ext2fs_dinode(ip)->e2di_flags & (EXT2_IMMUTABLE | EXT2_APPEND)) {
		VOP_ABORTOP(dvp, cnp);
		error = EPERM;
		goto out1;
	}
	ip->i_e2fs_nlink++;
	ip->i_flag |= IN_CHANGE;
	error = VOP_UPDATE(vp, NULL, NULL, MNT_WAIT);
	if (!error)
		error = ext2fs_direnter(ip, dvp, cnp);
	if (error) {
		ip->i_e2fs_nlink--;
		ip->i_flag |= IN_CHANGE;
	}
	_FREE_ZONE(cnp->cn_pnbuf, cnp->cn_pnlen, M_NAMEI);
out1:
	if (dvp != vp)
		VOP_UNLOCK(vp, 0, current_proc());
out2:


	vput(dvp);
	return (error);
}

int
ext2fs_rename(v)
	void *v;
{
	struct vop_rename_args  /* {
		struct vnode *a_fdvp;
		struct vnode *a_fvp;
		struct componentname *a_fcnp;
		struct vnode *a_tdvp;
		struct vnode *a_tvp;
		struct componentname *a_tcnp;
	} */ *ap = v;
	struct vnode *tvp = ap->a_tvp;
	struct vnode *tdvp = ap->a_tdvp;
	struct vnode *fvp = ap->a_fvp;
	struct vnode *fdvp = ap->a_fdvp;
	struct componentname *tcnp = ap->a_tcnp;
	struct componentname *fcnp = ap->a_fcnp;
	struct inode *ip, *xp, *dp;
	struct ext2fs_dirtemplate dirbuf;
	int doingdirectory = 0, oldparent = 0, newparent = 0;
	int error = 0;
	u_char namlen;

#ifdef DIAGNOSTIC
	if ((tcnp->cn_flags & HASBUF) == 0 ||
	    (fcnp->cn_flags & HASBUF) == 0)
		panic("ext2fs_rename: no name");
#endif
	/*
	 * Check for cross-device rename.
	 */
	if ((fvp->v_mount != tdvp->v_mount) ||
	    (tvp && (fvp->v_mount != tvp->v_mount))) {
		error = EXDEV;
abortit:
		VOP_ABORTOP(tdvp, tcnp); /* XXX, why not in NFS? */
		if (tdvp == tvp)
			vrele(tdvp);
		else
			vput(tdvp);
		if (tvp)
			vput(tvp);
		VOP_ABORTOP(fdvp, fcnp); /* XXX, why not in NFS? */
		vrele(fdvp);
		vrele(fvp);
		return (error);
	}

	/*
	 * Check if just deleting a link name.
	 */
	if (tvp && ((ext2fs_dinode(VTOI(tvp))->e2di_flags & (EXT2_IMMUTABLE | EXT2_APPEND)) ||
	    (ext2fs_dinode(VTOI(tdvp))->e2di_flags & EXT2_APPEND))) {
		error = EPERM;
		goto abortit;
	}
	if (fvp == tvp) {
		if (fvp->v_type == VDIR) {
			error = EINVAL;
			goto abortit;
		}

		/* Release destination completely. */
		VOP_ABORTOP(tdvp, tcnp);
		vput(tdvp);
		vput(tvp);

		/* Delete source. */
		vrele(fdvp);
		vrele(fvp);
		fcnp->cn_flags &= ~MODMASK;
		fcnp->cn_flags |= LOCKPARENT | LOCKLEAF;
		if ((fcnp->cn_flags & SAVESTART) == 0)
			panic("ext2fs_rename: lost from startdir");
		fcnp->cn_nameiop = DELETE;
		(void) relookup(fdvp, &fvp, fcnp);
		return (VOP_REMOVE(fdvp, fvp, fcnp));
	}
	if ((error = vn_lock(fvp, LK_EXCLUSIVE, current_proc())) != 0)
		goto abortit;
	dp = VTOI(fdvp);
	ip = VTOI(fvp);
	if ((nlink_t) ip->i_e2fs_nlink >= LINK_MAX) {
		VOP_UNLOCK(fvp, 0, current_proc());
		error = EMLINK;
		goto abortit;
	}
	if ((ext2fs_dinode(ip)->e2di_flags & (EXT2_IMMUTABLE | EXT2_APPEND)) ||
		(ext2fs_dinode(dp)->e2di_flags & EXT2_APPEND)) {
		VOP_UNLOCK(fvp, 0, current_proc());
		error = EPERM;
		goto abortit;
	}
	if ((ip->i_e2fs_mode & IFMT) == IFDIR) {
        	error = VOP_ACCESS(fvp, VWRITE, tcnp->cn_cred, tcnp->cn_proc);
        	if (!error && tvp)
                	error = VOP_ACCESS(tvp, VWRITE, tcnp->cn_cred,
			    tcnp->cn_proc);
        	if (error) {
			VOP_UNLOCK(fvp, 0, current_proc());
                	error = EACCES;
                	goto abortit;
        	}
		/*
		 * Avoid ".", "..", and aliases of "." for obvious reasons.
		 */
		if ((fcnp->cn_namelen == 1 && fcnp->cn_nameptr[0] == '.') ||
		    dp == ip ||
		    (fcnp->cn_flags&ISDOTDOT) ||
		    (tcnp->cn_flags & ISDOTDOT) ||
		    (ip->i_flag & IN_RENAME)) {
			VOP_UNLOCK(fvp, 0, current_proc());
			error = EINVAL;
			goto abortit;
		}
		ip->i_flag |= IN_RENAME;
		oldparent = dp->i_number;
		doingdirectory++;
	}
	vrele(fdvp);

	/*
	 * When the target exists, both the directory
	 * and target vnodes are returned locked.
	 */
	dp = VTOI(tdvp);
	xp = NULL;
	if (tvp)
		xp = VTOI(tvp);

	/*
	 * 1) Bump link count while we're moving stuff
	 *    around.  If we crash somewhere before
	 *    completing our work, the link count
	 *    may be wrong, but correctable.
	 */
	ip->i_e2fs_nlink++;
	ip->i_flag |= IN_CHANGE;
	if ((error = VOP_UPDATE(fvp, NULL, NULL, MNT_WAIT)) != 0) {
		VOP_UNLOCK(fvp, 0, current_proc());
		goto bad;
	}

	/*
	 * If ".." must be changed (ie the directory gets a new
	 * parent) then the source directory must not be in the
	 * directory hierarchy above the target, as this would
	 * orphan everything below the source directory. Also
	 * the user must have write permission in the source so
	 * as to be able to change "..". We must repeat the call 
	 * to namei, as the parent directory is unlocked by the
	 * call to checkpath().
	 */
	error = VOP_ACCESS(fvp, VWRITE, tcnp->cn_cred, tcnp->cn_proc);
	VOP_UNLOCK(fvp, 0, current_proc());
	if (oldparent != dp->i_number)
		newparent = dp->i_number;
	if (doingdirectory && newparent) {
		if (error)	/* write access check above */
			goto bad;
		if (xp != NULL)
			vput(tvp);
		error = ext2fs_checkpath(ip, dp, tcnp->cn_cred);
		if (error != 0)
			goto out;
		if ((tcnp->cn_flags & SAVESTART) == 0)
			panic("ext2fs_rename: lost to startdir");
		if ((error = relookup(tdvp, &tvp, tcnp)) != 0)
			goto out;
		dp = VTOI(tdvp);
		xp = NULL;
		if (tvp)
			xp = VTOI(tvp);
	}
	/*
	 * 2) If target doesn't exist, link the target
	 *    to the source and unlink the source. 
	 *    Otherwise, rewrite the target directory
	 *    entry to reference the source inode and
	 *    expunge the original entry's existence.
	 */
	if (xp == NULL) {
		if (dp->i_dev != ip->i_dev)
			panic("rename: EXDEV");
		/*
		 * Account for ".." in new directory.
		 * When source and destination have the same
		 * parent we don't fool with the link count.
		 */
		if (doingdirectory && newparent) {
			if ((nlink_t)dp->i_e2fs_nlink >= LINK_MAX) {
				error = EMLINK;
				goto bad;
			}
			dp->i_e2fs_nlink++;
			dp->i_flag |= IN_CHANGE;
			if ((error = VOP_UPDATE(tdvp, NULL, NULL, MNT_WAIT))
			    != 0)
				goto bad;
		}
		error = ext2fs_direnter(ip, tdvp, tcnp);
		if (error != 0) {
			if (doingdirectory && newparent) {
				dp->i_e2fs_nlink--;
				dp->i_flag |= IN_CHANGE;
				(void)VOP_UPDATE(tdvp, NULL, NULL, MNT_WAIT);
			}
			goto bad;
		}

		vput(tdvp);
	} else {
		if (xp->i_dev != dp->i_dev || xp->i_dev != ip->i_dev)
			panic("rename: EXDEV");
		/*
		 * Short circuit rename(foo, foo).
		 */
		if (xp->i_number == ip->i_number)
			panic("rename: same file");
		/*
		 * If the parent directory is "sticky", then the user must
		 * own the parent directory, or the destination of the rename,
		 * otherwise the destination may not be changed (except by
		 * root). This implements append-only directories.
		 */
		if ((dp->i_e2fs_mode & S_ISTXT) && tcnp->cn_cred->cr_uid != 0 &&
		    tcnp->cn_cred->cr_uid != dp->i_e2fs_uid &&
		    xp->i_e2fs_uid != tcnp->cn_cred->cr_uid) {
			error = EPERM;
			goto bad;
		}
		/*
		 * Target must be empty if a directory and have no links
		 * to it. Also, ensure source and target are compatible
		 * (both directories, or both not directories).
		 */
		if ((xp->i_e2fs_mode & IFMT) == IFDIR) {
			if (!ext2fs_dirempty(xp, dp->i_number, tcnp->cn_cred) ||
				xp->i_e2fs_nlink > 2) {
				error = ENOTEMPTY;
				goto bad;
			}
			if (!doingdirectory) {
				error = ENOTDIR;
				goto bad;
			}
			cache_purge(tdvp);
		} else if (doingdirectory) {
			error = EISDIR;
			goto bad;
		}
		error = ext2fs_dirrewrite(dp, ip, tcnp);
		if (error != 0)
			goto bad;
		/*
		 * If the target directory is in the same
		 * directory as the source directory,
		 * decrement the link count on the parent
		 * of the target directory.
		 */
		 if (doingdirectory && !newparent) {
			dp->i_e2fs_nlink--;
			dp->i_flag |= IN_CHANGE;
		}

		vput(tdvp);
		/*
		 * Adjust the link count of the target to
		 * reflect the dirrewrite above.  If this is
		 * a directory it is empty and there are
		 * no links to it, so we can squash the inode and
		 * any space associated with it.  We disallowed
		 * renaming over top of a directory with links to
		 * it above, as the remaining link would point to
		 * a directory without "." or ".." entries.
		 */
		xp->i_e2fs_nlink--;
		if (doingdirectory) {
			if (--xp->i_e2fs_nlink != 0)
				panic("rename: linked directory");
			error = VOP_TRUNCATE(tvp, (off_t)0, IO_SYNC,
			    tcnp->cn_cred, tcnp->cn_proc);
		}
		xp->i_flag |= IN_CHANGE;

		vput(tvp);
		xp = NULL;
	}

	/*
	 * 3) Unlink the source.
	 */
	fcnp->cn_flags &= ~MODMASK;
	fcnp->cn_flags |= LOCKPARENT | LOCKLEAF;
	if ((fcnp->cn_flags & SAVESTART) == 0)
		panic("ext2fs_rename: lost from startdir");
	(void) relookup(fdvp, &fvp, fcnp);
	if (fvp != NULL) {
		xp = VTOI(fvp);
		dp = VTOI(fdvp);
	} else {
		/*
		 * From name has disappeared.
		 */
		if (doingdirectory)
			panic("ext2fs_rename: lost dir entry");
		vrele(ap->a_fvp);
		return (0);
	}
	/*
	 * Ensure that the directory entry still exists and has not
	 * changed while the new name has been entered. If the source is
	 * a file then the entry may have been unlinked or renamed. In
	 * either case there is no further work to be done. If the source
	 * is a directory then it cannot have been rmdir'ed; its link
	 * count of three would cause a rmdir to fail with ENOTEMPTY.
	 * The IRENAME flag ensures that it cannot be moved by another
	 * rename.
	 */
	if (xp != ip) {
		if (doingdirectory)
			panic("ext2fs_rename: lost dir entry");
	} else {
		/*
		 * If the source is a directory with a
		 * new parent, the link count of the old
		 * parent directory must be decremented
		 * and ".." set to point to the new parent.
		 */
		if (doingdirectory && newparent) {
			dp->i_e2fs_nlink--;
			dp->i_flag |= IN_CHANGE;
			error = vn_rdwr(UIO_READ, fvp, (caddr_t)&dirbuf,
				sizeof (struct ext2fs_dirtemplate), (off_t)0,
				UIO_SYSSPACE, IO_NODELOCKED, 
				tcnp->cn_cred, (int *)0, (struct proc *)0);
			if (error == 0) {
					namlen = dirbuf.dotdot_namlen;
				if (namlen != 2 ||
				    dirbuf.dotdot_name[0] != '.' ||
				    dirbuf.dotdot_name[1] != '.') {
					error = EIO;
				} else {
					dirbuf.dotdot_ino = h2fs32(newparent);
					(void) vn_rdwr(UIO_WRITE, fvp,
					    (caddr_t)&dirbuf,
					    sizeof (struct ext2fs_dirtemplate),
					    (off_t)0, UIO_SYSSPACE,
					    IO_NODELOCKED|IO_SYNC,
					    tcnp->cn_cred, (int *)0,
					    (struct proc *)0);
					cache_purge(fdvp);
				}
			}
		}
		error = ext2fs_dirremove(fdvp, fcnp);
		if (!error) {
			xp->i_e2fs_nlink--;
			xp->i_flag |= IN_CHANGE;
		}
		xp->i_flag &= ~IN_RENAME;
	}

	if (dp)
		vput(fdvp);
	if (xp)
		vput(fvp);
	vrele(ap->a_fvp);
	return (error);

bad:
	if (xp)
		vput(ITOV(xp));
	vput(ITOV(dp));
out:
	if (doingdirectory)
		ip->i_flag &= ~IN_RENAME;
	if (vn_lock(fvp, LK_EXCLUSIVE, current_proc()) == 0) {
		ip->i_e2fs_nlink--;
		ip->i_flag |= IN_CHANGE;
		vput(fvp);
	} else
		vrele(fvp);
	return (error);
}

int
ext2fs_mkdir(v)
	void *v;
{
	struct vop_mkdir_args /* {
		struct vnode *a_dvp;
		struct vnode **a_vpp;
		struct componentname *a_cnp;
		struct vattr *a_vap;
	} */ *ap = v;
	struct vnode *dvp = ap->a_dvp;
	struct vattr *vap = ap->a_vap;
	struct componentname *cnp = ap->a_cnp;
	struct inode *ip, *dp;
	struct vnode *tvp;
	struct ext2fs_dirtemplate dirtemplate;
	int error, dmode;

#ifdef DIAGNOSTIC
	if ((cnp->cn_flags & HASBUF) == 0)
		panic("ext2fs_mkdir: no name");
#endif
	dp = VTOI(dvp);
	if ((nlink_t)dp->i_e2fs_nlink >= LINK_MAX) {
		error = EMLINK;
		goto out;
	}
	dmode = vap->va_mode & ACCESSPERMS;
	dmode |= IFDIR;
	/*
	 * Must simulate part of ext2fs_makeinode here to acquire the inode,
	 * but not have it entered in the parent directory. The entry is
	 * made later after writing "." and ".." entries.
	 */
	if ((error = VOP_VALLOC(dvp, dmode, cnp->cn_cred, &tvp)) != 0)
		goto out;
	ip = VTOI(tvp);
	ip->i_e2fs_uid = cnp->cn_cred->cr_uid;
	ip->i_e2fs_gid = dp->i_e2fs_gid;
	ip->i_flag |= IN_ACCESS | IN_CHANGE | IN_UPDATE;
	ip->i_e2fs_mode = dmode;
	tvp->v_type = VDIR;	/* Rest init'd in getnewvnode(). */
	ip->i_e2fs_nlink = 2;
	error = VOP_UPDATE(tvp, NULL, NULL, MNT_WAIT);

	/*
	 * Bump link count in parent directory
	 * to reflect work done below.  Should
	 * be done before reference is created
	 * so reparation is possible if we crash.
	 */
	dp->i_e2fs_nlink++;
	dp->i_flag |= IN_CHANGE;
	if ((error = VOP_UPDATE(dvp, NULL, NULL, MNT_WAIT)) != 0)
		goto bad;

	/* Initialize directory with "." and ".." from static template. */
	memset(&dirtemplate, 0, sizeof(dirtemplate));
	dirtemplate.dot_ino = h2fs32(ip->i_number);
	dirtemplate.dot_reclen = h2fs16(12);
	dirtemplate.dot_namlen = 1;
	if (ip->i_e2fs->e2fs.e2fs_rev > E2FS_REV0 &&
	    (ip->i_e2fs->e2fs.e2fs_features_incompat & EXT2F_INCOMPAT_FTYPE)) {
		dirtemplate.dot_type = EXT2_FT_DIR;
	}
	dirtemplate.dot_name[0] = '.';
	dirtemplate.dotdot_ino = h2fs32(dp->i_number);
    dirtemplate.dotdot_reclen = h2fs16(VTOI(dvp)->i_e2fs->e2fs_bsize - 12);
	dirtemplate.dotdot_namlen = 2;
	if (ip->i_e2fs->e2fs.e2fs_rev > E2FS_REV0 &&
	    (ip->i_e2fs->e2fs.e2fs_features_incompat & EXT2F_INCOMPAT_FTYPE)) {
		dirtemplate.dotdot_type = EXT2_FT_DIR;
	}
	dirtemplate.dotdot_name[0] = dirtemplate.dotdot_name[1] = '.';
	error = vn_rdwr(UIO_WRITE, tvp, (caddr_t)&dirtemplate,
	    sizeof (dirtemplate), (off_t)0, UIO_SYSSPACE,
	    IO_NODELOCKED|IO_SYNC, cnp->cn_cred, (int *)0, (struct proc *)0);
	if (error) {
		dp->i_e2fs_nlink--;
		dp->i_flag |= IN_CHANGE;
		goto bad;
	}
	if (VTOI(dvp)->i_e2fs->e2fs_bsize >
							VFSTOUFS(dvp->v_mount)->um_mountp->mnt_stat.f_bsize)
		panic("ext2fs_mkdir: blksize"); /* XXX should grow with balloc() */
	else {
		ip->i_e2fs_size = VTOI(dvp)->i_e2fs->e2fs_bsize;
		ip->i_flag |= IN_CHANGE;
	}

	/* Directory set up, now install it's entry in the parent directory. */
	error = ext2fs_direnter(ip, dvp, cnp);
	if (error != 0) {
		dp->i_e2fs_nlink--;
		dp->i_flag |= IN_CHANGE;
	}
bad:
	/*
	 * No need to do an explicit VOP_TRUNCATE here, vrele will do this
	 * for us because we set the link count to 0.
	 */
	if (error) {
		ip->i_e2fs_nlink = 0;
		ip->i_flag |= IN_CHANGE;
		vput(tvp);
	} else {

		*ap->a_vpp = tvp;
	}
out:
	_FREE_ZONE(cnp->cn_pnbuf, cnp->cn_pnlen, M_NAMEI);
	vput(dvp);
	return (error);
}

int
ext2fs_rmdir(v)
	void *v;
{
	struct vop_rmdir_args /* {
		struct vnode *a_dvp;
		struct vnode *a_vp;
		struct componentname *a_cnp;
	} */ *ap = v;
	struct vnode *vp = ap->a_vp;
	struct vnode *dvp = ap->a_dvp;
	struct componentname *cnp = ap->a_cnp;
	struct inode *ip, *dp;
	int error;

	ip = VTOI(vp);
	dp = VTOI(dvp);
	/*
	 * No rmdir "." please.
	 */
	if (dp == ip) {
		vrele(dvp);
		vput(vp);
		return (EINVAL);
	}
	/*
	 * Verify the directory is empty (and valid).
	 * (Rmdir ".." won't be valid since
	 *  ".." will contain a reference to
	 *  the current directory and thus be
	 *  non-empty.)
	 */
	error = 0;
	if (ip->i_e2fs_nlink != 2 ||
	    !ext2fs_dirempty(ip, dp->i_number, cnp->cn_cred)) {
		error = ENOTEMPTY;
		goto out;
	}
	if ((ext2fs_dinode(dp)->e2di_flags & EXT2_APPEND) ||
				 (ext2fs_dinode(ip)->e2di_flags & (EXT2_IMMUTABLE | EXT2_APPEND))) {
		error = EPERM;
		goto out;
	}
	/*
	 * Delete reference to directory before purging
	 * inode.  If we crash in between, the directory
	 * will be reattached to lost+found,
	 */
	error = ext2fs_dirremove(dvp, cnp);
	if (error != 0)
		goto out;
	dp->i_e2fs_nlink--;
	dp->i_flag |= IN_CHANGE;

	cache_purge(dvp);
	vput(dvp);
	dvp = NULL;
	/*
	 * Truncate inode.  The only stuff left
	 * in the directory is "." and "..".  The
	 * "." reference is inconsequential since
	 * we're quashing it.  The ".." reference
	 * has already been adjusted above.  We've
	 * removed the "." reference and the reference
	 * in the parent directory, but there may be
	 * other hard links so decrement by 2 and
	 * worry about them later.
	 */
	ip->i_e2fs_nlink -= 2;
	error = VOP_TRUNCATE(vp, (off_t)0, IO_SYNC, cnp->cn_cred,
	    cnp->cn_proc);
	cache_purge(ITOV(ip));
out:

	if (dvp)
		vput(dvp);
	vput(vp);
	return (error);
}

int
ext2fs_symlink(v)
	void *v;
{
	struct vop_symlink_args /* {
		struct vnode *a_dvp;
		struct vnode **a_vpp;
		struct componentname *a_cnp;
		struct vattr *a_vap;
		char *a_target;
	} */ *ap = v;
	struct vnode *vp, **vpp = ap->a_vpp;
	struct inode *ip;
	int len, error;

	error = ext2fs_makeinode(IFLNK | ap->a_vap->va_mode, ap->a_dvp,
			      vpp, ap->a_cnp);
	if (error)
		return (error);

	vp = *vpp;
	len = strlen(ap->a_target);
	if (len < vp->v_mount->mnt_maxsymlinklen) {
		ip = VTOI(vp);
		memcpy((char *)ext2fs_dinode(ip)->e2di_shortlink, ap->a_target, len);
		ip->i_e2fs_size = len;
		ip->i_flag |= IN_CHANGE | IN_UPDATE;
	} else
		error = vn_rdwr(UIO_WRITE, vp, ap->a_target, len, (off_t)0,
		    UIO_SYSSPACE, IO_NODELOCKED, ap->a_cnp->cn_cred,
		    (int *)0, (struct proc *)0);
	vput(vp);
	return (error);
}

int
ext2fs_makeinode(mode, dvp, vpp, cnp)
	int mode;
	struct vnode *dvp;
	struct vnode **vpp;
	struct componentname *cnp;
{
	struct inode *ip, *pdir;
	struct vnode *tvp;
	int error;

	pdir = VTOI(dvp);
#ifdef DIAGNOSTIC
	if ((cnp->cn_flags & HASBUF) == 0)
		panic("ext2fs_makeinode: no name");
#endif
	*vpp = NULL;
	if ((mode & IFMT) == 0)
		mode |= IFREG;

	if ((error = VOP_VALLOC(dvp, mode, cnp->cn_cred, &tvp)) != 0) {
		_FREE_ZONE(cnp->cn_pnbuf, cnp->cn_pnlen, M_NAMEI);
		vput(dvp);
		return (error);
	}
	ip = VTOI(tvp);
	ip->i_e2fs_gid = pdir->i_e2fs_gid;
	ip->i_e2fs_uid = cnp->cn_cred->cr_uid;
	ip->i_flag |= IN_ACCESS | IN_CHANGE | IN_UPDATE;
	ip->i_e2fs_mode = mode;
	tvp->v_type = IFTOVT(mode);	/* Rest init'd in getnewvnode(). */
	ip->i_e2fs_nlink = 1;
	if ((ip->i_e2fs_mode & ISGID) &&
		!groupmember(ip->i_e2fs_gid, cnp->cn_cred) &&
	    suser(cnp->cn_cred, NULL))
		ip->i_e2fs_mode &= ~ISGID;

	/*
	 * Make sure inode goes to disk before directory entry.
	 */
	if ((error = VOP_UPDATE(tvp, NULL, NULL, MNT_WAIT)) != 0)
		goto bad;
	error = ext2fs_direnter(ip, dvp, cnp);
	if (error != 0)
		goto bad;
	if ((cnp->cn_flags & SAVESTART) == 0)
		_FREE_ZONE(cnp->cn_pnbuf, cnp->cn_pnlen, M_NAMEI);
	vput(dvp);
	*vpp = tvp;
	return (0);

bad:
	/*
	 * Write error occurred trying to update the inode
	 * or the directory so must deallocate the inode.
	 */
	tvp->v_type = VNON;	/* Stop explosion if VBLK */
	ip->i_e2fs_nlink = 0;
	ip->i_flag |= IN_CHANGE;
	vput(tvp);
	_FREE_ZONE(cnp->cn_pnbuf, cnp->cn_pnlen, M_NAMEI);
	vput(dvp);
	return (error);
}

/* User mmap creates a pager without enrolling it in the native MapFS cache.
 * Hold only a temporary native mapping reference; linked cache state survives
 * unmap_vnode and subsequent opens retain their normal count ownership. */
int
ext2fs_vm_flush(struct vnode *vp,struct proc *p,int truncate,vm_offset_t length)
{
#if MACH_NBC
    struct vm_info *vmp=vp->v_vm_info;
    int held=0,error=0;
    if (vp->v_type != VREG || !vmp || !vmp->pager)
        return truncate ? mapfs_trunc(vp,length) : 0;
    if (vmp->error) return vmp->error;
    if (!vmp->mapped) {
        if (vmp->map_count) return EIO;
        map_vnode(vp,p);
        held=1;
    }
    vmp_get(vmp);
    if (vmp->error) error=vmp->error;
    else if (vmp->busy) error=EBUSY;
    else if (!vmp->mapped || !vmp->object) error=EIO;
    else if (truncate) error=mapfs_trunc(vp,length);
    else {
        /* Hardware-dirty user pages are outside the MapFS I/O window. */
        vmp->dirty=TRUE;
        vmp->dirtyoffset=0;
        vmp->dirtysize=vmp->vnode_size;
        error=vmp_push_range(vmp,0,vmp->vnode_size);
    }
    if (!error) error=vmp->error;
    vmp_put(vmp);
    if (held) unmap_vnode(vp,p);
    /* Native cleanup may retry a push and clear its error. Retain the first
     * failure only while the same live cache still belongs to this vnode. */
    if (error && vp->v_vm_info == vmp && vmp->mapped) vmp->error=error;
    return error;
#else
    return 0;
#endif
}

int
ext2fs_fsync(struct vop_fsync_args *ap)
{
    struct vnode *vp=ap->a_vp;
    struct buf *bp;
    int s,error,allerror=0;
    if (vp->v_mount->mnt_flag & MNT_RDONLY) return 0;
    if ((error=ext2fs_vm_flush(vp,ap->a_p,0,0))) return error;
    for (;;) {
        s=splbio();
        for (bp=vp->v_dirtyblkhd.lh_first;bp;bp=bp->b_vnbufs.le_next)
            if (!(bp->b_flags & B_BUSY)) break;
        if (!bp) {
            if (ap->a_waitfor == MNT_WAIT && vp->v_numoutput) {
                vp->v_flag |= VBWAIT;
                tsleep((caddr_t)&vp->v_numoutput,PRIBIO+1,"ext2fs_fsync",0);
                splx(s); continue;
            }
            splx(s); break;
        }
        bremfree(bp); bp->b_flags |= B_BUSY; splx(s);
        if (ap->a_waitfor == MNT_WAIT) {
            error=bwrite(bp); if (error) allerror=error;
        } else bawrite(bp);
    }
    error=VOP_UPDATE(vp,&time,&time,ap->a_waitfor == MNT_WAIT);
    return allerror ? allerror : error;
}

#include "ext2fs_extern.h"
#include <miscfs/specfs/specdev.h>
#include <miscfs/fifofs/fifo.h>

static int ext2fs_nop(void *v) { return 0; }
static int
ext2fs_getattr(struct vop_getattr_args *ap)
{
    struct inode *ip=VTOI(ap->a_vp);
    struct vattr *vap=ap->a_vap;
    u_int32_t flags=ext2fs_dinode(ip)->e2di_flags;
    vap->va_type=ap->a_vp->v_type; vap->va_mode=ip->i_mode & ALLPERMS;
    vap->va_nlink=ip->i_nlink; vap->va_uid=ip->i_uid; vap->va_gid=ip->i_gid;
    vap->va_fsid=ip->i_dev; vap->va_fileid=ip->i_number;
    vap->va_size=ip->i_size; vap->va_rdev=ip->i_rdev;
#if MACH_NBC
    if (ISMAPFSFILE(ap->a_vp) && !ap->a_vp->v_vm_info->filesize)
        vap->va_size=ap->a_vp->v_vm_info->vnode_size;
#endif
    vap->va_atime.tv_sec=ip->i_atime; vap->va_atime.tv_nsec=0;
    vap->va_mtime.tv_sec=ip->i_mtime; vap->va_mtime.tv_nsec=0;
    vap->va_ctime.tv_sec=ip->i_ctime; vap->va_ctime.tv_nsec=0;
    vap->va_flags=((flags&EXT2_APPEND)?UF_APPEND:0) |
        ((flags&EXT2_IMMUTABLE)?UF_IMMUTABLE:0) | ((flags&EXT2_NODUMP)?UF_NODUMP:0);
    vap->va_gen=ip->i_gen; vap->va_filerev=ip->i_modrev;
    vap->va_blocksize=ip->i_e2fs->e2fs_bsize; vap->va_bytes=(u_quad_t)ip->i_blocks*512;
    return 0;
}
static int
ext2fs_readlink(struct vop_readlink_args *ap)
{
    struct inode *ip=VTOI(ap->a_vp);
    if (ip->i_blocks == 0) {
        if (ip->i_size > EXT2_MAXSYMLINKLEN) return EIO;
        return uiomove((caddr_t)ext2fs_dinode(ip)->e2di_shortlink,ip->i_size,ap->a_uio);
    }
    return VOP_READ(ap->a_vp,ap->a_uio,0,ap->a_cred);
}
int
ext2fs_vinit(struct mount *mp,int (**specops)(),int (**fifoops)(),struct vnode **vpp)
{
    int error=ufs_vinit(mp,specops,fifoops,vpp);
    if (!error) (*vpp)->v_tag=VT_EXT2FS;
    return error;
}
int
ext2fs_reclaim(void *v)
{
    struct vop_reclaim_args *ap=v;
    struct vnode *vp=ap->a_vp;
    struct inode *ip=VTOI(vp);
    if (!ip) return 0;
    ext2fs_ihashrem(ip);
    cache_purge(vp);
    if (ip->i_devvp) vrele(ip->i_devvp);
    FREE(vp->v_data,M_MISCFSNODE);
    vp->v_data=NULL;
    return 0;
}

int (**ext2fs_vnodeop_p)();
struct vnodeopv_entry_desc ext2fs_vnodeop_entries[] = {
    { &vop_default_desc, vn_default_error },
    { &vop_lookup_desc, ext2fs_lookup },
    { &vop_create_desc, ext2fs_create },
    { &vop_mknod_desc, ext2fs_mknod },
    { &vop_open_desc, ext2fs_open },
    { &vop_close_desc, ext2fs_nop },
    { &vop_access_desc, ext2fs_access },
    { &vop_getattr_desc, ext2fs_getattr },
    { &vop_setattr_desc, ext2fs_setattr },
    { &vop_read_desc, ext2fs_read },
    { &vop_write_desc, ext2fs_write },
    { &vop_lease_desc, ext2fs_nop },
    { &vop_ioctl_desc, vn_default_error },
    { &vop_select_desc, ufs_select },
    { &vop_revoke_desc, ufs_revoke },
    { &vop_mmap_desc, ufs_mmap },
    { &vop_fsync_desc, ext2fs_fsync },
    { &vop_seek_desc, ufs_seek },
    { &vop_remove_desc, ext2fs_remove },
    { &vop_link_desc, ext2fs_link },
    { &vop_rename_desc, ext2fs_rename },
    { &vop_mkdir_desc, ext2fs_mkdir },
    { &vop_rmdir_desc, ext2fs_rmdir },
    { &vop_symlink_desc, ext2fs_symlink },
    { &vop_readdir_desc, ext2fs_readdir },
    { &vop_readlink_desc, ext2fs_readlink },
    { &vop_abortop_desc, ufs_abortop },
    { &vop_inactive_desc, ext2fs_inactive },
    { &vop_reclaim_desc, ext2fs_reclaim },
    { &vop_lock_desc, ufs_lock },
    { &vop_unlock_desc, ufs_unlock },
    { &vop_bmap_desc, ext2fs_bmap },
    { &vop_strategy_desc, ufs_strategy },
    { &vop_islocked_desc, ufs_islocked },
    { &vop_pathconf_desc, ufs_pathconf },
    { &vop_advlock_desc, ufs_advlock },
    { &vop_blkatoff_desc, ext2fs_blkatoff },
    { &vop_valloc_desc, ext2fs_valloc },
    { &vop_reallocblks_desc, ext2fs_reallocblks },
    { &vop_vfree_desc, ext2fs_vfree },
    { &vop_truncate_desc, ext2fs_truncate },
    { &vop_update_desc, ext2fs_update },
    { &vop_bwrite_desc, vn_bwrite },
    { &vop_pagein_desc, ufs_pagein },
    { &vop_pageout_desc, ufs_pageout },
    { NULL, NULL }
};
struct vnodeopv_desc ext2fs_vnodeop_opv_desc={ &ext2fs_vnodeop_p,ext2fs_vnodeop_entries };
int (**ext2fs_specop_p)();
struct vnodeopv_entry_desc ext2fs_specop_entries[] = {
    { &vop_default_desc, vn_default_error },
    { &vop_lookup_desc, spec_lookup },
    { &vop_open_desc, spec_open },
    { &vop_close_desc, spec_close },
    { &vop_access_desc, ext2fs_access },
    { &vop_getattr_desc, ext2fs_getattr },
    { &vop_setattr_desc, ext2fs_setattr },
    { &vop_read_desc, spec_read },
    { &vop_write_desc, spec_write },
    { &vop_ioctl_desc, spec_ioctl },
    { &vop_select_desc, spec_select },
    { &vop_revoke_desc, ufs_revoke },
    { &vop_inactive_desc, ext2fs_inactive },
    { &vop_reclaim_desc, ext2fs_reclaim },
    { &vop_lock_desc, ufs_lock },
    { &vop_unlock_desc, ufs_unlock },
    { &vop_islocked_desc, ufs_islocked },
    { &vop_fsync_desc, ext2fs_fsync },
    { &vop_update_desc, ext2fs_update },
    { &vop_strategy_desc, spec_strategy },
    { &vop_devblocksize_desc, spec_devblocksize },
    { &vop_vfree_desc, ext2fs_vfree },
    { &vop_truncate_desc, ext2fs_truncate },
    { NULL,NULL }
};
struct vnodeopv_desc ext2fs_specop_opv_desc={ &ext2fs_specop_p,ext2fs_specop_entries };
int (**ext2fs_fifoop_p)();
struct vnodeopv_entry_desc ext2fs_fifoop_entries[] = {
    { &vop_default_desc, vn_default_error },
#if FIFO
    { &vop_open_desc, fifo_open },
    { &vop_close_desc, fifo_close },
    { &vop_read_desc, fifo_read },
    { &vop_write_desc, fifo_write },
    { &vop_ioctl_desc, fifo_ioctl },
    { &vop_select_desc, fifo_select },
#endif
    { &vop_access_desc, ext2fs_access },
    { &vop_getattr_desc, ext2fs_getattr },
    { &vop_setattr_desc, ext2fs_setattr },
    { &vop_inactive_desc, ext2fs_inactive },
    { &vop_reclaim_desc, ext2fs_reclaim },
    { &vop_lock_desc, ufs_lock },
    { &vop_unlock_desc, ufs_unlock },
    { &vop_islocked_desc, ufs_islocked },
    { &vop_fsync_desc, ext2fs_fsync },
    { &vop_update_desc, ext2fs_update },
    { &vop_vfree_desc, ext2fs_vfree },
    { &vop_truncate_desc, ext2fs_truncate },
    { NULL,NULL }
};
struct vnodeopv_desc ext2fs_fifoop_opv_desc={ &ext2fs_fifoop_p,ext2fs_fifoop_entries };
