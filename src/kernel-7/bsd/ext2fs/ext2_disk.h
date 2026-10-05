/* Bounded ext2 disk admission; exported with the imported disk headers. */
#ifndef _EXT2_DISK_H_
#define _EXT2_DISK_H_
#include <sys/types.h>
#ifndef _KERNEL
#include <stddef.h>
#endif
#include "ext2_fs.h"
#include "ext2fs_dinode.h"
#include "ext2fs_dir.h"

#define EXT2_FILESIZE_MAX 2147483647U
int ext2_super_decode(const void *, size_t, struct ext2fs *);
void ext2_super_encode(const struct ext2fs *, void *);
int ext2_validate_super(const struct ext2fs *, u_int64_t, int);
u_int16_t ext2_get_le16(const void *);
u_int32_t ext2_get_le32(const void *);
void ext2_put_le16(void *, u_int16_t);
void ext2_put_le32(void *, u_int32_t);
#endif
