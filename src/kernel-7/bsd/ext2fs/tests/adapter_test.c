/* Run against the real local inode layout and production inode adapter. */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/queue.h>
#include <sys/vnode.h>
#include <ufs/ufs/quota.h>
#include <ufs/ufs/inode.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "../ext2_disk.h"
#include "../ext2fs_rhapsody.h"

int main(void)
{
    struct ext2fs_node node;
    struct vnode vnode;
    struct ext2fs_dinode raw, saved;
    unsigned char *bytes = (unsigned char *)&raw;
    struct inode *ip = &node.inode;
    memset(&node,0,sizeof(node)); memset(&vnode,0,sizeof(vnode));
    memset(&raw,0xa5,sizeof(raw));
    vnode.v_tag = VT_EXT2FS; ip->i_vnode = &vnode;
    assert(offsetof(struct ext2fs_node,inode) == 0);
    ext2_put_le16(bytes,0100644); ext2_put_le16(bytes+2,123);
    ext2_put_le32(bytes+4,123456); ext2_put_le16(bytes+24,456);
    ext2_put_le16(bytes+26,3); ext2_put_le32(bytes+28,99);
    ext2_put_le32(bytes+8,11); ext2_put_le32(bytes+12,22); ext2_put_le32(bytes+16,33);
    ext2_put_le32(bytes+40,0x12345678);
    ext2fs_inode_load(ip,&raw);
    assert(ip->i_mode == 0100644 && ip->i_uid == 123 && ip->i_gid == 456);
    assert(ip->i_size == 123456 && ip->i_nlink == 3 && ip->i_blocks == 99);
    assert(ip->i_atime == 11 && ip->i_ctime == 22 && ip->i_mtime == 33);
    assert(!memcmp(ext2fs_dinode(ip)->e2di_blocks,bytes+40,60));
    ip->i_size = 7; ip->i_uid = 321; ip->i_gid = 654; ip->i_blocks = 8;
    assert(ip->i_e2fs_size == 7 && ip->i_e2fs_uid == 321);
    ext2fs_inode_save(ip,&saved);
    assert(ext2_get_le32((char *)&saved+4) == 7);
    assert(ext2_get_le16((char *)&saved+2) == 321);
    assert(ext2_get_le16((char *)&saved+24) == 654);
    assert(ext2_get_le32((char *)&saved+28) == 8);
    assert(!memcmp((char *)&saved+32,bytes+32,96));
    ext2_put_le16(bytes,0020600); ext2_put_le32(bytes+40,0x1234);
    ext2fs_inode_load(ip,&raw); assert(ip->i_rdev == 0x1234);
    ip->i_rdev = 0x2345; ext2fs_inode_save(ip,&saved);
    assert(ext2_get_le32((char *)&saved+40) == 0x2345);
    ext2_put_le16(bytes,0120777); memcpy(bytes+40,"a/b/c",6);
    ext2fs_inode_load(ip,&raw); ext2fs_inode_save(ip,&saved);
    assert(!memcmp((char *)&saved+40,bytes+40,60));
    vnode.v_tag = VT_UFS; assert(ext2fs_dinode(ip) == NULL);
    puts("EXT2_OK adapter"); return 0;
}
