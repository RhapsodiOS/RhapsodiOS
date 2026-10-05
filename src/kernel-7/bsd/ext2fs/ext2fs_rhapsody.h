#ifndef _EXT2FS_RHAPSODY_H_
#define _EXT2FS_RHAPSODY_H_
/* Include the local UFS inode before this header. Its layout is unchanged. */
#include "ext2fs_dinode.h"
struct ext2fs_node {
    struct inode inode;
    struct ext2fs_dinode dinode;
};
#define i_e2fs_mode i_mode
#define i_e2fs_nlink i_nlink
#define i_e2fs_uid i_uid
#define i_e2fs_gid i_gid
#define i_e2fs_size i_size
#define i_e2fs_nblock i_blocks
#define i_e2fs_atime i_atime
#define i_e2fs_mtime i_mtime
#define i_e2fs_ctime i_ctime
#define i_e2fs_gen i_gen
struct ext2fs_dinode *ext2fs_dinode(struct inode *);
void ext2fs_inode_load(struct inode *, const struct ext2fs_dinode *);
void ext2fs_inode_save(const struct inode *, struct ext2fs_dinode *);
#endif
