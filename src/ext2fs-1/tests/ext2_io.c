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

static int read_at(int fd, off_t offset, const void *want, size_t length)
{
    unsigned char bytes[32];
    CHECK(length <= sizeof(bytes));
    CHECK(lseek(fd,offset,SEEK_SET) == offset);
    CHECK(read(fd,bytes,length) == (ssize_t)length && !memcmp(bytes,want,length));
    return 0;
}

static int mapping(const char *point)
{
    struct statfs fs;
    struct stat st;
    off_t edges[3], size;
    unsigned char zeros[32], bytes[8192];
    int fd,i,n;
    unsigned long hash = 2166136261UL, want_hash;
    ssize_t got;
    CHECK(chdir(point) == 0 && statfs(".",&fs) == 0);
    CHECK(fs.f_bsize == 1024 || fs.f_bsize == 2048 || fs.f_bsize == 4096);
    edges[0]=12*fs.f_bsize;
    edges[1]=(12+fs.f_bsize/4)*fs.f_bsize;
    edges[2]=67383296;
    n=fs.f_bsize == 1024 ? 3 : 2;
    size=edges[n-1]+1;
    CHECK((fd=open("boundary.bin",O_RDONLY)) >= 0);
    CHECK(fstat(fd,&st) == 0 && st.st_size == size);
    CHECK(read_at(fd,0,"Z",1) == 0);
    for(i=0;i<n;i++) {
        bytes[0]='A'+i*2; bytes[1]='B'+i*2;
        CHECK(read_at(fd,edges[i]-1,bytes,2) == 0);
    }
    memset(zeros,0,sizeof(zeros));
    CHECK(read_at(fd,2*fs.f_bsize+13,zeros,32) == 0);
    CHECK(read_at(fd,14*fs.f_bsize,zeros,32) == 0);
    CHECK(lseek(fd,0,SEEK_SET) == 0);
    while ((got=read(fd,bytes,sizeof(bytes))) > 0)
        for(i=0;i<got;i++) hash=((hash^bytes[i])*16777619UL)&0xffffffffUL;
    CHECK(got == 0);
    /* Literal FNV-1a values independently computed from the sparse sources. */
    want_hash=fs.f_bsize == 1024 ? 0x7d4e67d2UL :
        fs.f_bsize == 2048 ? 0x4769816dUL : 0x4409016dUL;
    printf("boundary payload: block=%ld bytes=%ld fnv1a=%08lx\n",
        fs.f_bsize,(long)size,hash);
    CHECK(hash == want_hash);
    CHECK(close(fd) == 0);
    puts("EXT2_OK mapping");
    return 0;
}

static int directory(const char *point)
{
    DIR *dir;
    struct dirent *entry;
    struct stat st,first;
    char name[256],target[128],long_target[128],buf[512];
    int i,fd,saw=0;
    long base;
    ssize_t got;
    CHECK(chdir(point) == 0);
    memset(name,'n',255); name[255]=0;
    CHECK(lstat(name,&first) == 0 && S_ISREG(first.st_mode));
    for(i=0;i<64;i++) {
        CHECK(lstat(name,&st) == 0 && st.st_ino == first.st_ino);
        CHECK(stat("short-link",&st) == 0 && st.st_size == 16);
        CHECK(stat("lost+found/..",&st) == 0 && st.st_ino == 2);
        errno=0; CHECK(stat("absent",&st) == -1 && errno == ENOENT);
    }
    CHECK((dir=opendir(".")) != NULL);
    errno=0;
    while((entry=readdir(dir)) != NULL) {
        if(!strcmp(entry->d_name,name)) {
            CHECK(entry->d_namlen == 255 && entry->d_fileno == first.st_ino);
            saw++;
        }
    }
    CHECK(errno == 0 && saw == 1 && closedir(dir) == 0);
    CHECK(readlink("short-link",target,sizeof(target)) == 9 && !memcmp(target,"hello.txt",9));
    long_target[0]=0;
    for(i=0;i<20;i++) strcat(long_target,"deep/");
    strcat(long_target,"hello.txt");
    got=readlink("long-link",target,sizeof(target));
    CHECK(got == 109 && !memcmp(target,long_target,109));
    CHECK((fd=open(".",O_RDONLY)) >= 0);
    errno=0;
    CHECK(getdirentries(fd,buf,1,&base) == -1 && errno == EINVAL);
    CHECK(lseek(fd,0,SEEK_CUR) == 0);
    CHECK(getdirentries(fd,buf,sizeof(buf),&base) > 0);
    CHECK(close(fd) == 0);
    puts("EXT2_OK directory");
    return 0;
}

static int malformed(const char *point,const char *kind)
{
    struct stat st;
    struct statfs fs;
    int fd;
    long base;
    char bytes[4096];
    CHECK(chdir(point) == 0);
    if(!strcmp(kind,"directory")) {
        CHECK((fd=open(point,O_RDONLY)) >= 0);
        errno=0; CHECK(getdirentries(fd,bytes,sizeof(bytes),&base) == -1 && errno == EIO);
        CHECK(close(fd) == 0);
        errno=0; CHECK(stat("hello.txt",&st) == -1 && errno == EIO);
    } else {
        CHECK(!strcmp(kind,"indirect"));
        CHECK(statfs(".",&fs) == 0);
        CHECK((fd=open("boundary.bin",O_RDONLY)) >= 0);
        CHECK(lseek(fd,12*fs.f_bsize,SEEK_SET) == 12*fs.f_bsize);
        errno=0; CHECK(read(fd,bytes,1) == -1 && errno == EIO);
        CHECK(close(fd) == 0);
    }
    puts("EXT2_OK malformed");
    return 0;
}

static int truncated(const char *device,const char *point)
{
    struct ext2fs_args args;
    struct statfs before,after;
    CHECK(statfs(point,&before) == 0);
    args.fspec=(char *)device;
    errno=0;
    CHECK(mount("ext2fs",point,MNT_RDONLY,&args) == -1 && errno == EINVAL);
    CHECK(statfs(point,&after) == 0);
    CHECK(!memcmp(&before.f_fsid,&after.f_fsid,sizeof(before.f_fsid)));
    puts("EXT2_OK truncated");
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
    if (argc == 3 && !strcmp(argv[1],"mapping")) return mapping(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"directory")) return directory(argv[2]);
    if (argc == 4 && !strcmp(argv[1],"malformed")) return malformed(argv[2],argv[3]);
    if (argc == 4 && !strcmp(argv[1],"truncated")) return truncated(argv[2],argv[3]);
    if (argc == 3 && !strcmp(argv[1],"unmount")) {
        CHECK(unmount(argv[2],0) == 0);
        return 0;
    }
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
