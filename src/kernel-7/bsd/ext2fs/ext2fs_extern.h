/*	$NetBSD: ext2fs_extern.h,v 1.22.2.1 2004/05/23 10:46:17 tron Exp $	*/

/*-
 * Copyright (c) 1991, 1993, 1994
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
 *	@(#)ffs_extern.h	8.3 (Berkeley) 4/16/94
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
 *	@(#)ffs_extern.h	8.3 (Berkeley) 4/16/94
 * Modified for ext2fs by Manuel Bouyer.
 */

#ifndef _EXT2FS_EXTERN_H_
#define _EXT2FS_EXTERN_H_
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/kernel.h>
#include <sys/proc.h>
#include <sys/resourcevar.h>
#include <sys/mount.h>
#include <sys/vnode.h>
#include <sys/buf.h>
#include <sys/malloc.h>
#include <sys/namei.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/dirent.h>
#include <ufs/ufs/quota.h>
#include <ufs/ufs/inode.h>
#include <ufs/ufs/ufsmount.h>
#include <ufs/ufs/ufs_extern.h>
#include "ext2_disk.h"
#include "ext2fs_rhapsody.h"

void vnode_pager_setsize(struct vnode *,u_long);

/* Native vfs_cache.c exports these without declarations in sys/namei.h. */
void cache_enter(struct vnode *,struct vnode *,struct componentname *);
void cache_purge(struct vnode *);

#define IS_EXT2_VNODE(vp) ((vp)->v_tag == VT_EXT2FS)
extern struct vfsops ext2fs_vfsops;
extern int (**ext2fs_vnodeop_p)();
extern int (**ext2fs_specop_p)();
extern int (**ext2fs_fifoop_p)();
extern struct vnodeopv_desc ext2fs_vnodeop_opv_desc;
extern struct vnodeopv_desc ext2fs_specop_opv_desc;
extern struct vnodeopv_desc ext2fs_fifoop_opv_desc;
int ext2fs_mount(struct mount *,char *,caddr_t,struct nameidata *,struct proc *);
int ext2fs_unmount(struct mount *,int,struct proc *);
int ext2fs_statfs(struct mount *,struct statfs *,struct proc *);
int ext2fs_sync(struct mount *,int,struct ucred *,struct proc *);
int ext2fs_vget(struct mount *,void *,struct vnode **);
int ext2fs_init(struct vfsconf *);
void ext2fs_ihashrem(struct inode *);
int ext2fs_update_inode(struct vnode *,struct timeval *,struct timeval *,int);
int ext2fs_update(struct vop_update_args *);
int ext2fs_read(void *);
int ext2fs_write(void *);
int ext2fs_bmap(void *);
int ext2fs_lookup(void *);
int ext2fs_readdir(void *);
int ext2fs_blkatoff(void *);
int ext2fs_inactive(void *);
int ext2fs_reclaim(void *);
int ext2fs_truncate(struct vop_truncate_args *);
int ext2fs_valloc(struct vop_valloc_args *);
int ext2fs_vfree(struct vop_vfree_args *);
int ext2fs_reallocblks(void *);
int ext2fs_vinit(struct mount *,int (**)(),int (**)(),struct vnode **);
int ext2fs_alloc(struct inode *,daddr_t,daddr_t,struct ucred *,daddr_t *);
int ext2fs_balloc(struct inode *,daddr_t,int,struct ucred *,struct buf **,int);
daddr_t ext2fs_blkpref(struct inode *,daddr_t,int,int32_t *);
void ext2fs_blkfree(struct inode *,daddr_t);
int ext2fs_vget_alloc(struct mount *,ino_t,struct vnode **);
int ext2fs_direnter(struct inode *,struct vnode *,struct componentname *);
int ext2fs_dirremove(struct vnode *,struct componentname *);
int ext2fs_dirrewrite(struct inode *,struct inode *,struct componentname *);
int ext2fs_dirempty(struct inode *,ino_t,struct ucred *);
int ext2fs_checkpath(struct inode *,struct inode *,struct ucred *);
int ext2fs_makeinode(int,struct vnode *,struct vnode **,struct componentname *);
int ext2fs_fsync(struct vop_fsync_args *);
int ext2fs_sbupdate(struct ufsmount *,int);
int ext2fs_cgupdate(struct ufsmount *,int);
int ext2fs_vm_flush(struct vnode *,struct proc *,int,vm_offset_t);
#endif
