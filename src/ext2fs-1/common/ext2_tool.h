/* Shared native ext2 command operations. */
#ifndef EXT2_TOOL_H
#define EXT2_TOOL_H
int ext2_device_is_mounted(const char *);
int ext2_run_tool(const char *,char *const []);
int ext2_probe(const char *,char [17]);
int ext2_format_size(const char *,unsigned int,unsigned long);
int ext2_mount_probe(const char *,int);
#ifndef EXT2_MKE2FS
#define EXT2_MKE2FS "/sbin/mke2fs"
#endif
#ifndef EXT2_E2FSCK
#define EXT2_E2FSCK "/sbin/e2fsck"
#endif
#ifndef EXT2_NEWFS
#define EXT2_NEWFS "/sbin/newfs_ext2fs"
#endif
#ifndef EXT2_FSCK
#define EXT2_FSCK "/sbin/fsck_ext2fs"
#endif
#ifndef EXT2_MOUNT
#define EXT2_MOUNT "/sbin/mount"
#endif
#ifndef EXT2_UMOUNT
#define EXT2_UMOUNT "/sbin/umount"
#endif
#endif
