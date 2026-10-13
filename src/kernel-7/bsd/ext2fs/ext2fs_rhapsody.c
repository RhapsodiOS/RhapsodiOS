/* Rhapsody's canonical inode and ext2's private disk snapshot. */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/queue.h>
#ifdef _KERNEL
#include <sys/systm.h>
#else
#include <string.h>
#endif
#include <sys/vnode.h>
#include <ufs/ufs/quota.h>
#include <ufs/ufs/inode.h>
#include "ext2_disk.h"
#include "ext2fs_rhapsody.h"

struct ext2fs_dinode *
ext2fs_dinode(struct inode *ip)
{
    if (ip == NULL || ip->i_vnode == NULL || ip->i_vnode->v_tag != VT_EXT2FS)
        return NULL;
    return &((struct ext2fs_node *)ip)->dinode;
}

void
ext2fs_inode_load(struct inode *ip, const struct ext2fs_dinode *raw)
{
    struct ext2fs_dinode *di = ext2fs_dinode(ip);
    e2fs_iload((struct ext2fs_dinode *)raw,di);
    memset(&ip->i_din,0,sizeof(ip->i_din));
    ip->i_mode = di->e2di_mode;
    ip->i_nlink = di->e2di_nlink;
    ip->i_uid = di->e2di_uid;
    ip->i_gid = di->e2di_gid;
    ip->i_size = di->e2di_size;
    ip->i_blocks = di->e2di_nblock;
    ip->i_atime = di->e2di_atime;
    ip->i_mtime = di->e2di_mtime;
    ip->i_ctime = di->e2di_ctime;
    ip->i_gen = di->e2di_gen;
    if ((ip->i_mode & EXT2_IFMT) == EXT2_IFCHR ||
        (ip->i_mode & EXT2_IFMT) == EXT2_IFBLK)
        ip->i_rdev = fs2h32(di->e2di_rdev);
}

void
ext2fs_inode_save(const struct inode *ip, struct ext2fs_dinode *raw)
{
    struct ext2fs_dinode di;
    di = ((const struct ext2fs_node *)ip)->dinode;
    di.e2di_mode = ip->i_mode;
    di.e2di_nlink = ip->i_nlink;
    di.e2di_uid = ip->i_uid;
    di.e2di_gid = ip->i_gid;
    di.e2di_size = ip->i_size;
    di.e2di_nblock = ip->i_blocks;
    di.e2di_atime = ip->i_atime;
    di.e2di_mtime = ip->i_mtime;
    di.e2di_ctime = ip->i_ctime;
    di.e2di_gen = ip->i_gen;
    if ((ip->i_mode & EXT2_IFMT) == EXT2_IFCHR ||
        (ip->i_mode & EXT2_IFMT) == EXT2_IFBLK)
        di.e2di_rdev = h2fs32(ip->i_rdev);
    e2fs_isave(&di,raw);
}
