/* Native syscall checks: no substituted filesystem implementation. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <ext2fs/ext2_mount.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"%s:%d: %s (errno %d)\n",__FILE__,__LINE__,#x,errno); return 1; } } while (0)

static int tiny_mounts(const char *point)
{
    struct disk_partition_info capacity;
    struct ext2fs_args args;
    struct statfs before,after;
    char device[] = "/dev/hd1a";
    int i,fd;
    CHECK(statfs(point,&before) == 0);
    for (i=1;i<=4;i++) {
        device[8] = 'a'+i-1;
        CHECK((fd=open(device,O_RDONLY)) >= 0);
        CHECK(ioctl(fd,DKIOCGPARTINFO,&capacity) == 0);
        CHECK(capacity.block_size == 512 && capacity.block_count == i);
        CHECK(close(fd) == 0);
        args.fspec=device;
        errno=0;
        CHECK(mount("ext2fs",point,MNT_RDONLY,&args) == -1 && errno == EINVAL);
        CHECK(statfs(point,&after) == 0);
        CHECK(memcmp(&before.f_fsid,&after.f_fsid,sizeof(before.f_fsid)) == 0);
        CHECK(!strcmp(before.f_fstypename,after.f_fstypename));
        printf("tiny partition %s: %d sectors rejected\n",device,i);
    }
    puts("EXT2_OK tiny");
    return 0;
}

int main(int argc,char **argv)
{
    struct stat st;
    struct statfs fs;
    struct ext2fs_args args;
    struct dirent *entry;
    DIR *dir;
    int fd, saw_dot = 0, saw_parent = 0;
    char data[32];
    ssize_t count;
    if (argc == 3 && !strcmp(argv[1],"tiny")) return tiny_mounts(argv[2]);
    CHECK(argc == 3 && strcmp(argv[1],"readonly") == 0);
    CHECK(chdir(argv[2]) == 0);
    CHECK(stat(".",&st) == 0 && S_ISDIR(st.st_mode) && st.st_ino == 2 &&
        (st.st_mode & 0777) == 0755);
    CHECK(statfs(".",&fs) == 0 && strcmp(fs.f_fstypename,"ext2fs") == 0);
    CHECK(fs.f_flags & MNT_RDONLY);
    args.fspec = NULL;
    errno = 0;
    CHECK(mount("ext2fs",argv[2],MNT_UPDATE,&args) == -1 && errno == EROFS);
    CHECK((dir = opendir(".")) != NULL);
    while ((entry = readdir(dir)) != NULL) {
        if (!strcmp(entry->d_name,".")) saw_dot++;
        if (!strcmp(entry->d_name,"..")) saw_parent++;
    }
    CHECK(closedir(dir) == 0 && saw_dot == 1 && saw_parent == 1);
    CHECK((fd = open("hello.txt",O_RDONLY)) >= 0);
    count = read(fd,data,sizeof(data));
    CHECK(count == 16 && memcmp(data,"hello from ext2\n",16) == 0);
    CHECK(close(fd) == 0);
    errno = 0; CHECK(open("hello.txt",O_WRONLY) == -1 && errno == EROFS);
    errno = 0;
    fd = open("must-not-exist",O_CREAT|O_WRONLY,0600);
    CHECK(fd == -1 && errno == EROFS);
    errno = 0;
    CHECK(stat("must-not-exist",&st) == -1 && errno == ENOENT);
    errno = 0; CHECK(mkdir("must-not-exist",0700) == -1 && errno == EROFS);
    errno = 0; CHECK(mknod("must-not-exist",S_IFIFO|0600,0) == -1 && errno == EROFS);
    errno = 0; CHECK(rmdir("lost+found") == -1 && errno == EROFS);
    errno = 0; CHECK(link("hello.txt","must-not-exist") == -1 && errno == EROFS);
    errno = 0; CHECK(symlink("hello.txt","must-not-exist") == -1 && errno == EROFS);
    errno = 0; CHECK(unlink("hello.txt") == -1 && errno == EROFS);
    errno = 0; CHECK(rename("hello.txt","must-not-exist") == -1 && errno == EROFS);
    errno = 0; CHECK(chmod("hello.txt",0600) == -1 && errno == EROFS);
    errno = 0; CHECK(chown("hello.txt",1,1) == -1 && errno == EROFS);
    errno = 0; CHECK(truncate("hello.txt",0) == -1 && errno == EROFS);
    errno = 0; CHECK(utimes("hello.txt",NULL) == -1 && errno == EROFS);
    CHECK(stat("hello.txt",&st) == 0 && st.st_size == 16 && (st.st_mode & 0777) == 0644);
    puts("EXT2_OK readonly");
    return 0;
}
