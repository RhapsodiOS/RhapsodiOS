/* Native syscall checks: no substituted filesystem implementation. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <ufs/ufs/quota.h>
#include <dev/disk.h>
#include <ext2fs/ext2_mount.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef EXT2FS_TEST_IO
#include <ext2fs/tests/fault_io.c>
#endif

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


/* Each case first attempts a real mutation, and therefore fails on the RO
 * milestone. Kept files are checked again after unmount/remount by verify. */
static int mutation(const char *point)
{
    struct stat st,other;
    struct statfs before,after;
    char b[32],target[100];
    off_t edges[3];
    int fd,i,n;
    CHECK(chdir(point) == 0 && statfs(".",&before) == 0);
    umask(0);
    CHECK(mkdir("mutation",0751) == 0 && chdir("mutation") == 0);
    CHECK(mkdir("left",0710) == 0 && mkdir("right",0755) == 0);
    CHECK((fd=open("left/file",O_CREAT|O_RDWR,0640)) >= 0);
    CHECK(write(fd,"persisted",9) == 9 && fsync(fd) == 0);
    CHECK(fchown(fd,123,456) == 0 && fchmod(fd,0641) == 0);
    CHECK(fstat(fd,&st) == 0 && st.st_uid == 123 && st.st_gid == 456 && (st.st_mode&07777) == 0641);
    CHECK(link("left/file","left/hard") == 0);
    CHECK(stat("left/hard",&other) == 0 && other.st_ino == st.st_ino && other.st_nlink == 2);
    CHECK(symlink("file","left/short") == 0);
    CHECK(readlink("left/short",b,sizeof(b)) == 4 && !memcmp(b,"file",4));
    memset(target,'x',99); target[99]=0;
    CHECK(symlink(target,"left/long") == 0);
    { char linkbytes[100]; CHECK(readlink("left/long",linkbytes,100) == 99 && !memcmp(linkbytes,target,99)); }
    CHECK(rename("left/file","right/file") == 0);
    CHECK(unlink("left/hard") == 0 && unlink("right/file") == 0);
    CHECK(fstat(fd,&st) == 0 && st.st_nlink == 0);
    CHECK(read_at(fd,0,"persisted",9) == 0 && close(fd) == 0);
    CHECK(unlink("left/short") == 0 && unlink("left/long") == 0);
    CHECK(mkdir("left/child",0755) == 0 && rename("left/child","right/child") == 0);
    CHECK(stat("right/child/..",&st) == 0 && stat("right",&other) == 0 && st.st_ino == other.st_ino);
    CHECK(rmdir("right/child") == 0);
    CHECK((fd=open("sparse",O_CREAT|O_RDWR,0600)) >= 0);
    edges[0]=12*before.f_bsize;
    edges[1]=(12+before.f_bsize/4)*before.f_bsize;
    edges[2]=67383296;
    n=before.f_bsize == 1024 ? 3 : 2;
    for(i=0;i<n;i++) {
        CHECK(lseek(fd,edges[i]-1,SEEK_SET) == edges[i]-1 && write(fd,"AB",2) == 2);
        CHECK(read_at(fd,edges[i]-1,"AB",2) == 0);
    }
    memset(b,0,sizeof(b)); CHECK(read_at(fd,13,b,sizeof(b)) == 0);
    CHECK(ftruncate(fd,17) == 0 && ftruncate(fd,8192) == 0);
    CHECK(read_at(fd,17,b,sizeof(b)) == 0);
    CHECK(close(fd) == 0 && unlink("sparse") == 0);
    CHECK(rmdir("left") == 0 && rmdir("right") == 0 && chdir("..") == 0 && rmdir("mutation") == 0);
    sync(); CHECK(statfs(".",&after) == 0);
    CHECK(after.f_bfree == before.f_bfree && after.f_ffree == before.f_ffree);
    CHECK((fd=open("mutation-proof",O_CREAT|O_RDWR,0641)) >= 0);
    CHECK(write(fd,"persisted",9) == 9 && fchown(fd,123,456) == 0 && fsync(fd) == 0 && close(fd) == 0);
    puts("EXT2_OK mutation"); return 0;
}

static int limits(const char *point)
{
    struct stat st;
    struct statfs before,after;
    char bytes[8192],got[8192],name[32];
    off_t total=0,offset;
    ssize_t n;
    int fd,i,j,count;
    CHECK(chdir(point) == 0 && statfs(".",&before) == 0);
    CHECK(mkdir("limits",0700) == 0 && chdir("limits") == 0);
    CHECK((fd=open("large",O_CREAT|O_RDWR,0600)) >= 0);
    errno=0; CHECK(ftruncate(fd,(off_t)2147483647+1) == -1 && errno == EFBIG);
    CHECK(lseek(fd,(off_t)2147483646,SEEK_SET) == (off_t)2147483646);
    errno=0; n=write(fd,"XY",2); CHECK(n == 1 || (n == -1 && errno == EFBIG));
    CHECK(fstat(fd,&st) == 0 && st.st_size == (n == 1 ? (off_t)2147483647 : 0));
    if(n == 1) CHECK(read_at(fd,2147483646,"X",1) == 0);
    CHECK(ftruncate(fd,0) == 0 && lseek(fd,0,SEEK_SET) == 0);
    for(i=0;;i++) {
        for(j=0;j<sizeof(bytes);j++) bytes[j]=(char)((i >> ((j%4)*8)) ^ (j*13));
        n=write(fd,bytes,sizeof(bytes));
        if(n == -1) { CHECK(errno == ENOSPC); break; }
        CHECK(n > 0 && n <= sizeof(bytes)); total+=n;
    }
    CHECK(total > before.f_bsize*1024L && fstat(fd,&st) == 0 && st.st_size == total);
    CHECK(lseek(fd,0,SEEK_SET) == 0);
    for(offset=0;offset<total;offset+=n) {
        n=read(fd,got,sizeof(got)); CHECK(n > 0);
        for(j=0;j<n;j++) CHECK(got[j] == (char)(((offset/8192) >> ((j%4)*8)) ^ (j*13)));
    }
    CHECK(fsync(fd) == 0 && close(fd) == 0 && unlink("large") == 0);
    for(count=0;;count++) {
        sprintf(name,"inode-%d",count);
        fd=open(name,O_CREAT|O_EXCL|O_WRONLY,0600);
        if(fd < 0) { CHECK(errno == ENOSPC); break; }
        CHECK(close(fd) == 0);
    }
    CHECK(count > 0 && statfs(".",&after) == 0 && after.f_ffree == 0);
    for(i=0;i<count;i++) { sprintf(name,"inode-%d",i); CHECK(unlink(name) == 0); }
    CHECK(chdir("..") == 0 && rmdir("limits") == 0);
    sync(); CHECK(statfs(".",&after) == 0);
    CHECK(after.f_bfree == before.f_bfree && after.f_ffree == before.f_ffree);
    printf("limits: %ld persisted bytes, %d allocated inodes\n",(long)total,count);
    puts("EXT2_OK limits"); return 0;
}

static int mapped_size(const char *point)
{
    int fd,tail_ok,extension_ok;
    char *shared,zero[4],got[4];
    struct stat st;
    CHECK(chdir(point) == 0);
    CHECK((fd=open("mmap-size",O_CREAT|O_RDWR,0600)) >= 0);
    CHECK(ftruncate(fd,8192) == 0);
    shared=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(shared != (void *)-1);
    memcpy(shared+6000,"tail",4); CHECK(fsync(fd) == 0);
    CHECK(lseek(fd,6000,SEEK_SET) == 6000 && read(fd,got,4) == 4);
    printf("before shrink: mapped=%02x%02x%02x%02x buffered=%02x%02x%02x%02x\n",(unsigned char)shared[6000],(unsigned char)shared[6001],(unsigned char)shared[6002],(unsigned char)shared[6003],(unsigned char)got[0],(unsigned char)got[1],(unsigned char)got[2],(unsigned char)got[3]);
    CHECK(ftruncate(fd,4096) == 0 && fstat(fd,&st) == 0 && st.st_size == 4096);
    CHECK(ftruncate(fd,8192) == 0 && fstat(fd,&st) == 0 && st.st_size == 8192);
    memset(zero,0,sizeof(zero));
    CHECK(lseek(fd,6000,SEEK_SET) == 6000 && read(fd,got,4) == 4);
    printf("after grow: mapped=%02x%02x%02x%02x buffered=%02x%02x%02x%02x\n",(unsigned char)shared[6000],(unsigned char)shared[6001],(unsigned char)shared[6002],(unsigned char)shared[6003],(unsigned char)got[0],(unsigned char)got[1],(unsigned char)got[2],(unsigned char)got[3]);
    tail_ok=!memcmp(shared+6000,zero,4) && !memcmp(got,zero,4);
    CHECK(lseek(fd,10000,SEEK_SET) == 10000 && write(fd,"x",1) == 1);
    CHECK(fstat(fd,&st) == 0); extension_ok=st.st_size == 10001;
    printf("mapped size: zero tail=%d, extension=%ld (expected10001)\n",tail_ok,(long)st.st_size);
    CHECK(fsync(fd) == 0 && munmap(shared,8192) == 0 && close(fd) == 0);
    CHECK(unlink("mmap-size") == 0);
    CHECK(tail_ok && extension_ok);
    puts("EXT2_OK mmap-size"); return 0;
}

static int ufs_append_control(const char *point)
{
    int fd;
    char *pages;
    struct stat st;
    CHECK(chdir(point) == 0 && (fd=open("ufs-append",O_CREAT|O_RDWR,0600)) >= 0);
    CHECK(ftruncate(fd,4096) == 0 && write(fd,"base",4) == 4 && fsync(fd) == 0);
    pages=mmap(0,4096,PROT_READ,MAP_SHARED,fd,0);
    CHECK(pages != (void *)-1 && !memcmp(pages,"base",4));
    /* Reopening an existing pager enrolls the ordinary native UFS MapFS path. */
    CHECK(close(fd) == 0 && (fd=open("ufs-append",O_RDWR|O_APPEND)) >= 0);
    CHECK(lseek(fd,0,SEEK_SET) == 0 && write(fd,"AB",2) == 2);
    CHECK(fstat(fd,&st) == 0 && st.st_size == 4098);
    CHECK(read_at(fd,4096,"AB",2) == 0 && read_at(fd,0,"base",4) == 0);
    CHECK(fsync(fd) == 0 && munmap(pages,4096) == 0 && close(fd) == 0);
    CHECK((fd=open("ufs-append",O_RDONLY)) >= 0);
    CHECK(fstat(fd,&st) == 0 && st.st_size == 4098 && read_at(fd,4096,"AB",2) == 0);
    CHECK(close(fd) == 0 && unlink("ufs-append") == 0);
    puts("UFS_OK mapped bounded append/read"); return 0;
}

static int mapped_lifetime(void)
{
    struct statfs before,after;
    char *pages;
    int fd,i;
    CHECK(statfs(".",&before) == 0);
    CHECK((fd=open("mmap-unlinked",O_CREAT|O_RDWR,0600)) >= 0);
    CHECK(ftruncate(fd,8192) == 0);
    pages=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(pages != (void *)-1 && unlink("mmap-unlinked") == 0);
    memcpy(pages+32,"alive",5);
    CHECK(fsync(fd) == 0 && read_at(fd,32,"alive",5) == 0);
    memcpy(pages+64,"again",5);
    CHECK(fsync(fd) == 0 && read_at(fd,64,"again",5) == 0);
    CHECK(close(fd) == 0 && !memcmp(pages+32,"alive",5));
    CHECK(munmap(pages,8192) == 0);
    for(i=0;i<20;i++) {
        CHECK((fd=open("mmap-cycle",O_CREAT|O_RDWR,0600)) >= 0);
        CHECK(ftruncate(fd,4096) == 0);
        pages=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        CHECK(pages != (void *)-1); pages[0]=(char)i;
        CHECK(fsync(fd) == 0 && munmap(pages,4096) == 0 && close(fd) == 0);
    }
    CHECK(unlink("mmap-cycle") == 0);
    sync(); CHECK(statfs(".",&after) == 0);
    CHECK(before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    puts("EXT2_OK mmap-lifetime"); return 0;
}

static int mapped_limits(const char *point)
{
    struct stat st;
    struct statfs before,after;
    char *pages;
    ssize_t n;
    int fd,saved;
    CHECK(chdir(point) == 0 && statfs(".",&before) == 0);
    CHECK((fd=open("mapped-limit",O_CREAT|O_RDWR,0600)) >= 0 && ftruncate(fd,4096) == 0);
    pages=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(pages != (void *)-1); pages[0]='p'; CHECK(fsync(fd) == 0);
    errno=0; CHECK(ftruncate(fd,(off_t)2147483647+1) == -1 && errno == EFBIG);
    CHECK(lseek(fd,2147483646,SEEK_SET) == (off_t)2147483646);
    errno=0; n=write(fd,"XY",2); saved=errno;
    CHECK(fstat(fd,&st) == 0);
    printf("mapped crossing: count=%ld errno=%d size=%ld\n",(long)n,saved,(long)st.st_size);
    CHECK(n == -1 && saved == EFBIG);
    CHECK(st.st_size == 4096);
    CHECK(ftruncate(fd,2147483646) == 0 && lseek(fd,0,SEEK_SET) == 0 && fcntl(fd,F_SETFL,O_APPEND) == 0);
    errno=0; n=write(fd,"AB",2); saved=errno;
    CHECK(fstat(fd,&st) == 0);
    printf("mapped append: count=%ld errno=%d size=%lu\n",(long)n,saved,(unsigned long)st.st_size);
    CHECK(n == -1 && saved == EFBIG);
    CHECK(st.st_size == (off_t)2147483646);
    CHECK(write(fd,"A",1) == 1 && fsync(fd) == 0);
    CHECK(fstat(fd,&st) == 0 && st.st_size == (off_t)2147483647);
    CHECK(read_at(fd,2147483646,"A",1) == 0);
    errno=0; CHECK(write(fd,"B",1) == -1 && errno == EFBIG);
    CHECK(fstat(fd,&st) == 0 && st.st_size == (off_t)2147483647);
    CHECK(fsync(fd) == 0 && munmap(pages,4096) == 0 && close(fd) == 0);
    CHECK(unlink("mapped-limit") == 0); sync(); CHECK(statfs(".",&after) == 0);
    CHECK(before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    puts("EXT2_OK mmap-limits"); return 0;
}

static int mapped(const char *point,int use_msync)
{
    int fd;
    char *shared,*private;
    CHECK(chdir(point) == 0);
    CHECK((fd=open("mmap-proof",O_CREAT|O_RDWR,0600)) >= 0);
    CHECK(ftruncate(fd,8192) == 0);
    shared=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(shared != (void *)-1);
    memcpy(shared+4093,"mapped",6);
    if(use_msync) CHECK(msync(shared,8192) == 0);
    CHECK(fsync(fd) == 0);
    CHECK(read_at(fd,4093,"mapped",6) == 0);
    CHECK(lseek(fd,16,SEEK_SET) == 16 && write(fd,"buffered",8) == 8 && fsync(fd) == 0);
    CHECK(!memcmp(shared+16,"buffered",8));
    private=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_PRIVATE,fd,0);
    CHECK(private != (void *)-1); memcpy(private+16,"private!",8);
    CHECK(munmap(private,8192) == 0 && read_at(fd,16,"buffered",8) == 0);
    CHECK(mapped_lifetime() == 0);
    /* A user-only store after fsync must survive cached/no-fd mount sync. */
    memcpy(shared+32,"late",4);
    CHECK(close(fd) == 0); sync();
    CHECK(munmap(shared,8192) == 0);
    puts(use_msync ? "EXT2_OK mmap" : "EXT2_OK mmap-fsync"); return 0;
}

/* Real transitions must flush before changing mode, and leave no cached
 * writable state behind. Each route repeats to expose leaked references. */
static int remount_cycle(const char *point,const char *device)
{
    struct ext2fs_args args;
    struct statfs fs;
    int fd,i,result,saved;
    args.fspec=(char *)device;
    CHECK(chdir(point) == 0);
    for(i=0;i<3;i++) {
        CHECK((fd=open("remount-proof",O_CREAT|O_RDWR,0600)) >= 0);
        CHECK(write(fd,"rw",2) == 2 && close(fd) == 0);
        CHECK(chdir("/") == 0);
        errno=0; result=mount("ext2fs",point,MNT_UPDATE|MNT_RDONLY,&args); saved=errno;
        printf("remount cycle=%d route=%s RW-RO result=%d errno=%d\n",i,device ? "device" : "NULL",result,saved);
        CHECK(result == 0 && statfs(point,&fs) == 0 && (fs.f_flags&MNT_RDONLY));
        CHECK(chdir(point) == 0 && (fd=open("remount-proof",O_RDONLY)) >= 0);
        CHECK(read_at(fd,0,"rw",2) == 0 && close(fd) == 0);
        errno=0; CHECK(open("remount-proof",O_WRONLY) == -1 && errno == EROFS);
        CHECK(chdir("/") == 0);
        errno=0; result=mount("ext2fs",point,MNT_UPDATE,&args); saved=errno;
        printf("remount cycle=%d route=%s RO-RW result=%d errno=%d\n",i,device ? "device" : "NULL",result,saved);
        CHECK(result == 0 && statfs(point,&fs) == 0 && !(fs.f_flags&MNT_RDONLY));
        CHECK(chdir(point) == 0 && (fd=open("remount-proof",O_RDWR)) >= 0);
        CHECK(write(fd,"ok",2) == 2 && fsync(fd) == 0 && read_at(fd,0,"ok",2) == 0);
        CHECK(close(fd) == 0 && unlink("remount-proof") == 0);
    }
    CHECK(chdir("/") == 0);
    puts("EXT2_OK remount"); return 0;
}

static int remount_references(const char *point)
{
    struct ext2fs_args args;
    struct statfs fs;
    int fd,i,result,saved;
    char *shared;
    args.fspec=NULL;
    CHECK(chdir(point) == 0 && (fd=open("remount-mapped",O_CREAT|O_RDWR,0600)) >= 0);
    CHECK(ftruncate(fd,4096) == 0);
    shared=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(shared != (void *)-1);
    shared[0]='A'; CHECK(fsync(fd) == 0 && chdir("/") == 0);
    for(i=0;i<2;i++) {
        errno=0; result=mount("ext2fs",point,MNT_UPDATE|MNT_RDONLY,&args); saved=errno;
        printf("remount busy descriptor=%d result=%d errno=%d\n",!i,result,saved);
        CHECK(result == -1 && saved == EBUSY && statfs(point,&fs) == 0 && !(fs.f_flags&MNT_RDONLY));
        shared[1]='B';
        if(!i) {
            CHECK(read_at(fd,0,"AB",2) == 0 && fsync(fd) == 0 && close(fd) == 0);
        }
    }
    CHECK(munmap(shared,4096) == 0 && chdir(point) == 0);
    CHECK((fd=open("remount-mapped",O_RDWR)) >= 0 && read_at(fd,0,"AB",2) == 0);
    CHECK(write(fd,"ok",2) == 2 && fsync(fd) == 0 && close(fd) == 0);
    CHECK(unlink("remount-mapped") == 0 && chdir("/") == 0);
    puts("EXT2_OK remount-busy"); return 0;
}

/* A busy unmount must retain the mount, descriptor and later write ability. */
static int busy_unmount(const char *point)
{
    struct statfs before,after;
    int fd,i,result,saved;
    CHECK(statfs(point,&before) == 0);
    for(i=0;i<3;i++) {
        CHECK(chdir(point) == 0 && (fd=open("busy-proof",O_CREAT|O_RDWR,0600)) >= 0);
        CHECK(write(fd,"before",6) == 6 && fsync(fd) == 0 && chdir("/") == 0);
        errno=0; result=unmount(point,0); saved=errno;
        printf("busy cycle=%d result=%d errno=%d\n",i,result,saved);
        CHECK(result == -1 && saved == EBUSY && statfs(point,&after) == 0);
        CHECK(!memcmp(&before.f_fsid,&after.f_fsid,sizeof(before.f_fsid)));
        CHECK(read_at(fd,0,"before",6) == 0 && lseek(fd,0,SEEK_SET) == 0);
        CHECK(write(fd,"after!",6) == 6 && fsync(fd) == 0 && read_at(fd,0,"after!",6) == 0);
        CHECK(close(fd) == 0 && chdir(point) == 0 && unlink("busy-proof") == 0 && chdir("/") == 0);
    }
    puts("EXT2_OK busy"); return 0;
}

/* Only this explicitly fsynced payload is promised after an interrupted run. */
static int persistence(const char *point,int verify)
{
    int fd;
    CHECK(chdir(point) == 0);
    CHECK((fd=open("persistence-proof",verify ? O_RDONLY : O_CREAT|O_TRUNC|O_RDWR,0600)) >= 0);
    if(!verify) {
        CHECK(write(fd,"ext2 fsynced payload",20) == 20);
        CHECK(fsync(fd) == 0);
    }
    CHECK(read_at(fd,0,"ext2 fsynced payload",20) == 0 && close(fd) == 0);
    CHECK(chdir("/") == 0);
    puts(verify ? "EXT2_OK persistence-read" : "EXT2_OK persistence-write"); return 0;
}

static int dirty_refusal(const char *point,const char *device)
{
    struct ext2fs_args args;
    struct statfs before,after;
    int i,result,saved;
    args.fspec=(char *)device;
    CHECK(statfs(point,&before) == 0);
    for(i=0;i<5;i++) {
        errno=0; result=mount("ext2fs",point,0,&args); saved=errno;
        printf("dirty refusal cycle=%d result=%d errno=%d\n",i,result,saved);
        CHECK(result == -1 && saved == EROFS);
        CHECK(statfs(point,&after) == 0 && !memcmp(&before.f_fsid,&after.f_fsid,sizeof(before.f_fsid)));
    }
    CHECK(mount("ext2fs",point,MNT_RDONLY,&args) == 0);
    CHECK(persistence(point,1) == 0 && unmount(point,0) == 0);
    puts("EXT2_OK dirty-refusal"); return 0;
}

static int permissions(const char *point)
{
    struct ext2fs_args args;
    int fd,status;
    pid_t pid;
    CHECK(chdir(point) == 0);
    CHECK((fd=open("permission-proof",O_CREAT|O_WRONLY,0600)) >= 0 && close(fd) == 0);
    CHECK((pid=fork()) >= 0);
    if(!pid) {
        if(setgid(456) || setuid(123)) _exit(2);
        errno=0; fd=open("permission-proof",O_WRONLY);
        _exit(fd == -1 && errno == EACCES ? 0 : 3);
    }
    CHECK(waitpid(pid,&status,0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    errno=0; CHECK(quotactl((char *)point,QCMD(Q_SYNC,USRQUOTA),0,NULL) == -1 && errno == EOPNOTSUPP);
    /* Native export updates use the NULL-device route. Generic mount strips
     * MNT_EXPORTED; ext2 has no export payload in its one-pointer ABI. */
    args.fspec=NULL;
    errno=0; CHECK(mount("ext2fs",point,MNT_UPDATE|MNT_EXPORTED,&args) == -1 && errno == EOPNOTSUPP);
    CHECK(unlink("permission-proof") == 0);
    puts("EXT2_OK permissions"); return 0;
}

static int special(const char *point)
{
    struct stat dev,st;
    int rd,wr;
    char b[4];
    CHECK(stat("/dev/null",&dev) == 0 && chdir(point) == 0);
    CHECK(mkfifo("fifo-proof",0600) == 0);
    CHECK((rd=open("fifo-proof",O_RDONLY|O_NONBLOCK)) >= 0);
    CHECK((wr=open("fifo-proof",O_WRONLY|O_NONBLOCK)) >= 0);
    CHECK(write(wr,"fifo",4) == 4 && read(rd,b,4) == 4 && !memcmp(b,"fifo",4));
    CHECK(close(rd) == 0 && close(wr) == 0 && unlink("fifo-proof") == 0);
    CHECK(mknod("device-proof",S_IFCHR|0600,dev.st_rdev) == 0);
    CHECK(lstat("device-proof",&st) == 0 && S_ISCHR(st.st_mode) && st.st_rdev == dev.st_rdev);
    CHECK((wr=open("device-proof",O_WRONLY)) >= 0 && write(wr,"null",4) == 4 && close(wr) == 0);
    CHECK(unlink("device-proof") == 0);
    puts("EXT2_OK special"); return 0;
}

static int verify_writes(const char *point,int mapped)
{
    struct stat st;
    int fd;
    CHECK(chdir(point) == 0);
    CHECK((fd=open("mutation-proof",O_RDONLY)) >= 0);
    CHECK(fstat(fd,&st) == 0 && st.st_size == 9 && st.st_uid == 123 && st.st_gid == 456 && (st.st_mode&07777) == 0641);
    CHECK(read_at(fd,0,"persisted",9) == 0 && close(fd) == 0);
    if(mapped) {
        CHECK((fd=open("mmap-proof",O_RDONLY)) >= 0);
        CHECK(read_at(fd,16,"buffered",8) == 0 && read_at(fd,32,"late",4) == 0 && read_at(fd,4093,"mapped",6) == 0 && close(fd) == 0);
    }
    puts(mapped ? "EXT2_OK verify-writes" : "EXT2_OK verify-core"); return 0;
}


static int rejected_inode(const char *device,const char *point,int root)
{
    struct ext2fs_args args;
    struct statfs before,after;
    struct stat st;
    int fd,result,saved;
    args.fspec=(char *)device;
    if(root) {
        errno=0;result=mount("ext2fs",point,0,&args);saved=errno;
        printf("rejected root mount=%d errno=%d\n",result,saved);
        CHECK(result == 0 || (result == -1 && saved == EIO));
        if(result == 0) {
            errno=0;result=stat(point,&st);saved=errno;
            printf("rejected root stat=%d errno=%d\n",result,saved);
            CHECK(result == -1 && saved == EIO);
            errno=0;result=unmount(point,0);saved=errno;
            printf("rejected root unmount=%d errno=%d\n",result,saved);
            CHECK(result == -1 && saved == EIO);
        }
    } else {
        CHECK(mount("ext2fs",point,0,&args) == 0);
        CHECK(chdir(point) == 0 && statfs(".",&before) == 0);
        errno=0;fd=open("rejected",O_RDONLY);saved=errno;
        printf("rejected target open=%d errno=%d\n",fd,saved);
        CHECK(fd == -1 && saved == EIO);
        CHECK(statfs(".",&after) == 0);
        printf("rejected counts blocks=%ld/%ld inodes=%ld/%ld\n",(long)before.f_bfree,(long)after.f_bfree,(long)before.f_ffree,(long)after.f_ffree);
        CHECK(chdir("/") == 0 && unmount(point,0) == 0);
        CHECK(before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    }
    puts(root ? "EXT2_OK rejected-root" : "EXT2_OK rejected-inode");return 0;
}



static int mapped_readonly(const char *point)
{
    struct statfs before,after;
    char *shared,*private;
    int fd;
    CHECK(chdir(point) == 0 && statfs(".",&before) == 0 && (before.f_flags&MNT_RDONLY));
    CHECK((fd=open("hello.txt",O_RDONLY)) >= 0);
    shared=mmap(0,4096,PROT_READ,MAP_SHARED,fd,0);
    CHECK(shared != (char *)-1 && !memcmp(shared,"hello from ext2\n",16));
    CHECK(read_at(fd,0,"hello from ext2\n",16) == 0);
    private=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE,fd,0);
    CHECK(private != (char *)-1);private[0]='P';
    CHECK(shared[0]=='h' && read_at(fd,0,"hello from ext2\n",16) == 0);
    CHECK(fsync(fd) == 0 && munmap(private,4096) == 0 && munmap(shared,4096) == 0 && close(fd) == 0);
    CHECK(statfs(".",&after) == 0 && before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    puts("EXT2_OK mmap-readonly");return 0;
}

static int fresh_control(const char *point)
{
    struct statfs before,after;
    struct stat st;
    char zero[4096],*pages;
    int fd,mode,result,saved,failures=0;
    ssize_t count;
    memset(zero,0,sizeof(zero));CHECK(chdir(point) == 0 && statfs(".",&before) == 0);
    CHECK((fd=open("fresh-unlinked",O_CREAT|O_EXCL|O_RDWR,0600)) >= 0);
    CHECK(write(fd,zero,sizeof(zero)) == sizeof(zero));
    pages=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(pages != (char *)-1 && pages[0] == 0 && unlink("fresh-unlinked") == 0);
    pages[16]='U';CHECK(read_at(fd,16,"U",1) == 0);
    CHECK(lseek(fd,32,SEEK_SET) == 32 && write(fd,"V",1) == 1 && pages[32]=='V');
    CHECK(fsync(fd) == 0 && close(fd) == 0 && pages[16]=='U' && pages[32]=='V');
    CHECK(munmap(pages,4096) == 0);sync();CHECK(statfs(".",&after) == 0);
    CHECK(before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    puts("EXT2_OK fresh-unlinked");
    for(mode=0;mode<2;mode++) {
        CHECK((fd=open("fresh-limit",O_CREAT|O_EXCL|O_RDWR,0600)) >= 0);
        CHECK(write(fd,zero,sizeof(zero)) == sizeof(zero));
        if(mode) CHECK(ftruncate(fd,2147483646) == 0);
        pages=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        CHECK(pages != (char *)-1 && pages[0] == 0);pages[16]='A';
        if(mode) CHECK(fcntl(fd,F_SETFL,O_APPEND) == 0 && lseek(fd,0,SEEK_SET) == 0);
        else CHECK(lseek(fd,2147483646,SEEK_SET) == (off_t)2147483646);
        errno=0;count=write(fd,"XY",2);saved=errno;
        CHECK(fstat(fd,&st) == 0);
        printf("fresh limit append=%d count=%ld errno=%d size=%lu\n",mode,(long)count,saved,(unsigned long)st.st_size);
        CHECK(count == -1 && saved == EFBIG && st.st_size == (mode ? (off_t)2147483646 : (off_t)4096));
        errno=0;result=fsync(fd);saved=errno;
        printf("fresh limit immediate fsync=%d errno=%d\n",result,saved);
        if(result) failures++;
        CHECK(fcntl(fd,F_SETFL,0) == 0 && lseek(fd,32,SEEK_SET) == 32 && write(fd,"B",1) == 1);
        CHECK(read_at(fd,16,"A",1) == 0 && read_at(fd,32,"B",1) == 0 && pages[32]=='B');
        errno=0;result=fsync(fd);saved=errno;
        printf("fresh limit valid-I/O fsync=%d errno=%d\n",result,saved);
        CHECK(result == 0);
        CHECK(munmap(pages,4096) == 0 && close(fd) == 0 && unlink("fresh-limit") == 0);
        sync();CHECK(statfs(".",&after) == 0);
        CHECK(before.f_bfree == after.f_bfree && before.f_ffree == after.f_ffree);
    }
    CHECK(!failures);puts("EXT2_OK mmap-fresh-control");return 0;
}

static int fresh_mapping(const char *point,int verify)
{
    char name[32],zero[4096],got[2];
    char *shared,*private;
    volatile char fault;
    int fd,order,failures=0;
    memset(zero,0,sizeof(zero));CHECK(chdir(point) == 0);
    for(order=0;order<2;order++) {
        sprintf(name,"fresh-map-%d",order);
        if(verify) {
            CHECK((fd=open(name,O_RDONLY)) >= 0);
            CHECK(read_at(fd,16,"A",1) == 0 && read_at(fd,32,"B",1) == 0);
            CHECK(read_at(fd,48,zero,1) == 0 && close(fd) == 0);
            continue;
        }
        CHECK((fd=open(name,O_CREAT|O_EXCL|O_RDWR,0600)) >= 0);
        CHECK(write(fd,zero,sizeof(zero)) == sizeof(zero));
        shared=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        CHECK(shared != (char *)-1);fault=shared[0];CHECK(fault == 0);
        private=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE,fd,0);
        CHECK(private != (char *)-1);private[48]='P';
        if(order == 0) {
            shared[16]='A';
            CHECK(lseek(fd,16,SEEK_SET) == 16 && read(fd,got,1) == 1);
            printf("fresh mapped-first immediate read A=%d\n",got[0]);
            if(got[0]!='A') failures++;
        }
        CHECK(lseek(fd,32,SEEK_SET) == 32 && write(fd,"B",1) == 1);
        if(order == 1) shared[16]='A';
        CHECK(lseek(fd,16,SEEK_SET) == 16 && read(fd,got,1) == 1);
        printf("fresh order=%d immediate mapped-A=%d ordinary-A=%d mapped-B=%d private=%d shared-private=%d\n",order,shared[16],got[0],shared[32],private[48],shared[48]);
        if(got[0]!='A' || shared[32]!='B' || private[48]!='P' || shared[48]!=0) failures++;
        CHECK(fsync(fd) == 0 && munmap(private,4096) == 0 && munmap(shared,4096) == 0);
        CHECK(lseek(fd,16,SEEK_SET) == 16 && read(fd,got,1) == 1);
        if(got[0]!='A') failures++;
        CHECK(lseek(fd,32,SEEK_SET) == 32 && read(fd,got+1,1) == 1);
        printf("fresh order=%d persisted A=%d B=%d\n",order,got[0],got[1]);
        if(got[1]!='B') failures++;
        CHECK(close(fd) == 0);
    }
    CHECK(!failures);
    puts(verify ? "EXT2_OK verify-fresh" : "EXT2_OK mmap-fresh");return 0;
}

#ifdef EXT2FS_TEST_IO
static int fault_arm(int ctl,dev_t dev,int kind,unsigned long ino,long block,int after)
{
    struct ext2_fault_control c;
    memset(&c,0,sizeof(c)); c.op=EXT2_FAULT_ARM; c.target=dev;
    c.kind=kind; c.ino=ino; c.block=block; c.after=after; c.error=EIO;
    CHECK(ioctl(ctl,EXT2_FAULT_CTL,&c) == 0); return 0;
}
static int fault_query(int ctl,struct ext2_fault_control *c)
{
    memset(c,0,sizeof(*c)); c->op=EXT2_FAULT_QUERY;
    CHECK(ioctl(ctl,EXT2_FAULT_CTL,c) == 0);
    printf("fault query kind=%d target=%x matched=%d failed=%d block=%ld phase=%d reads=%d resid=%d releases=%d\n",
        c->kind,c->target,c->matched,c->failed,c->block,c->phase,c->reads,c->resid,c->releases);
    printf("fault reconciliation dirty-writes=%d successful-flushes=%d invalidated=%d release-resid=%d\n",c->dirty_writes,c->flushes,c->invalidated,c->release_resid);
    return 0;
}
static int fault_truncate_read(const char *scenario,const char *point,
    struct ext2fs_args *args,int ctl,dev_t dev)
{
    struct ext2_fault_control c;
    struct stat st;
    struct statfs before,after;
    char bytes[1024],retry;
    int fd,other,indirect,shortread,kind,result,saved,retryok,invalidated;
    indirect=strstr(scenario,"indirect") != NULL;
    shortread=strstr(scenario,"short") != NULL;
    kind=indirect ? (shortread ? EXT2_FAULT_INDIR_SHORT : EXT2_FAULT_INDIR_ERROR) :
        (shortread ? EXT2_FAULT_TAIL_SHORT : EXT2_FAULT_TAIL_ERROR);
    memset(bytes,'U',sizeof(bytes));
    CHECK(mount("ext2fs",point,0,args) == 0 && chdir(point) == 0);
    CHECK((fd=open("fault-file",O_RDWR)) >= 0 && fstat(fd,&st) == 0);
    CHECK((other=open("read-unrelated",O_CREAT|O_EXCL|O_RDWR,0600)) >= 0);
    CHECK(write(other,bytes,sizeof(bytes)) == sizeof(bytes));
    if(indirect) {
        CHECK(lseek(fd,12288,SEEK_SET) == 12288 && write(fd,"I",1) == 1);
        CHECK(lseek(fd,13312,SEEK_SET) == 13312 && write(fd,"J",1) == 1);
        CHECK(lseek(other,12288,SEEK_SET) == 12288 && write(other,"U",1) == 1);
        CHECK(lseek(other,13312,SEEK_SET) == 13312 && write(other,"V",1) == 1);
    }
    CHECK(fsync(fd) == 0 && fsync(other) == 0 && close(fd) == 0 && close(other) == 0);
    CHECK(chdir("/") == 0 && unmount(point,0) == 0);
    CHECK(mount("ext2fs",point,0,args) == 0 && chdir(point) == 0);
    CHECK(fault_arm(ctl,dev,kind,st.st_ino,0,1) == 0);
    CHECK((other=open("read-unrelated",O_RDWR)) >= 0);
    CHECK(ftruncate(other,indirect ? 13312 : 500) == 0 && fsync(other) == 0 && close(other) == 0);
    CHECK(fault_query(ctl,&c) == 0 && !c.matched && !c.reads && !c.releases);
    CHECK((fd=open("fault-file",O_RDWR)) >= 0 && statfs(".",&before) == 0);
    errno=0;result=ftruncate(fd,indirect ? 13312 : 500);saved=errno;
    CHECK(statfs(".",&after) == 0);
    printf("truncate-read result=%d errno=%d free-before=%ld free-after=%ld\n",
        result,saved,(long)before.f_bfree,(long)after.f_bfree);
    CHECK(result == -1 && saved == EIO);
    CHECK(fault_query(ctl,&c) == 0 && c.matched == 1 && c.failed == 1 &&
        c.reads == 1 && c.releases == 1 && c.resid == shortread && c.phase == (indirect ? 4 : 5));
    CHECK(c.block > 0 && (indirect || c.block == 40));
    CHECK(after.f_bfree == before.f_bfree);
    CHECK(fstat(fd,&st) == 0 && st.st_size == (indirect ? 13312 : 4096));
    CHECK(c.release_resid == shortread); invalidated=c.invalidated;
    CHECK(lseek(fd,indirect ? 12288 : 1023,SEEK_SET) == (indirect ? 12288 : 1023));
    errno=0;result=read(fd,&retry,1);saved=errno;
    retryok=result == 1 && retry == (indirect ? 'I' : 0);
    printf("truncate-read cached retry count=%d errno=%d payload-ok=%d invalidated=%d\n",result,saved,retryok,invalidated);
    CHECK(fault_arm(ctl,dev,EXT2_FAULT_CLEAN,0,0,1) == 0);
    errno=0;result=fsync(fd);saved=errno;
    printf("truncate-read later fsync=%d errno=%d\n",result,saved);
    CHECK(result == -1 && saved == EIO && retryok && invalidated);
    CHECK(close(fd) == 0 && chdir("/") == 0);
    errno=0;CHECK(unmount(point,0) == -1 && errno == EIO);
    CHECK(fault_query(ctl,&c) == 0 && !c.matched);
    return 0;
}
static int fault_case(const char *scenario,const char *device,const char *point,const char *control)
{
    struct ext2fs_args args;
    struct ext2_fault_control c;
    struct stat ds,st;
    struct statfs before,after;
    char *shared;
    int ctl,fd=-1,i,result,saved,guardstatus,remounting;
    pid_t child;
    args.fspec=(char *)device;
    remounting=!strcmp(scenario,"remount-clean") || !strcmp(scenario,"remount-rewrite");
    fprintf(stderr,"fault scenario=%s device=%s point=%s\n",scenario,device,point);
    CHECK(stat(device,&ds) == 0 && (ctl=open(control,O_RDONLY|O_NONBLOCK)) >= 0);
    CHECK(statfs(point,&before) == 0);
    if(!strcmp(scenario,"admission")) {
        memset(&c,0,sizeof(c)); c.op=EXT2_FAULT_ARM; c.after=1; c.error=EIO;
        errno=0; CHECK(ioctl(ctl,EXT2_FAULT_CTL,&c) == -1 && errno == EINVAL);
        CHECK(stat(control,&st) == 0); c.target=st.st_dev;
        errno=0; CHECK(ioctl(ctl,EXT2_FAULT_CTL,&c) == -1 && errno == EINVAL);
        c.target=ds.st_rdev;
        CHECK((child=fork()) >= 0);
        if(!child) {
            if(setgid(456) || setuid(123)) _exit(3);
            errno=0; result=ioctl(ctl,EXT2_FAULT_CTL,&c);
            _exit(result == -1 && errno == EPERM ? 0 : 4);
        }
        CHECK(waitpid(child,&guardstatus,0) == child && WIFEXITED(guardstatus) && WEXITSTATUS(guardstatus) == 0);
        puts("fault control invalid-target/self-target/nonroot refused");
        for(i=0;i<5;i++) {
            CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_DIRTY,0,0,1) == 0);
            errno=0; result=mount("ext2fs",point,0,&args); saved=errno;
            printf("admission cycle=%d result=%d errno=%d\n",i,result,saved);
            CHECK(result == -1 && saved == EIO);
            CHECK(statfs(point,&after) == 0 && !memcmp(&before.f_fsid,&after.f_fsid,sizeof(before.f_fsid)));
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1 && c.block == 2);
            CHECK(mount("ext2fs",point,0,&args) == 0 && unmount(point,0) == 0);
        }
    } else if(!strncmp(scenario,"read-",5)) {
        CHECK(fault_truncate_read(scenario,point,&args,ctl,ds.st_rdev) == 0);
    } else if(!strcmp(scenario,"short-inode")) {
        CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_SHORT,12,0,1) == 0);
        CHECK(mount("ext2fs",point,MNT_RDONLY,&args) == 0 && chdir(point) == 0);
        errno=0; fd=open("fault-file",O_RDONLY); saved=errno;
        printf("short inode open=%d errno=%d\n",fd,saved);
        CHECK(fd == -1 && saved == EIO);
        CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.reads == 1 && c.resid == 1 && c.releases == 1);
        CHECK((fd=open("fault-file",O_RDONLY)) >= 0 && close(fd) == 0);
        CHECK(chdir("/") == 0 && unmount(point,0) == 0);
    } else {
        CHECK(mount("ext2fs",point,0,&args) == 0 && chdir(point) == 0);
        CHECK((fd=open("fault-file",O_RDWR)) >= 0 && fstat(fd,&st) == 0);
        CHECK(fsync(fd) == 0);
        if(!strcmp(scenario,"first-push")) {
            shared=mmap(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
            CHECK(shared != (void *)-1 && shared[0] == 'F');
            /* An open after mmap owns a MapFS reference. Temporary enrollment
             * alone close-flushes the range before generic fsync can see it. */
            CHECK((i=open("fault-file",O_RDWR)) >= 0);
            CHECK(lseek(fd,32,SEEK_SET) == 32 && write(fd,"B",1) == 1);
            shared[16]='A';
            CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_DATA,st.st_ino,0,1) == 0);
            errno=0; result=fsync(fd); saved=errno;
            printf("generic first push fsync=%d errno=%d\n",result,saved);
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1 && c.phase == 0);
            CHECK(result == -1 && saved == EIO);
            errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
            CHECK(munmap(shared,4096) == 0 && close(i) == 0);
        } else if(!strcmp(scenario,"metadata")) {
            CHECK(lseek(fd,32,SEEK_SET) == 32 && write(fd,"M",1) == 1);
            /* Fixture inode12 sits in inode table sector12 (blocksize1024). */
            CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_INODE,st.st_ino,12,1) == 0);
            errno=0; result=fsync(fd); saved=errno;
            printf("metadata fsync=%d errno=%d\n",result,saved);
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1);
            CHECK(result == -1 && saved == EIO);
            errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
        } else if(!strcmp(scenario,"truncate") || !strcmp(scenario,"truncate-bitmap")) {
            CHECK(statfs(point,&before) == 0);
            CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_INODE,st.st_ino,!strcmp(scenario,"truncate-bitmap") ? 6 : 12,1) == 0);
            errno=0; result=ftruncate(fd,0); saved=errno;
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1);
            CHECK(statfs(point,&after) == 0);
            printf("truncate error=%d errno=%d free-before=%ld free-after=%ld\n",result,saved,before.f_bfree,after.f_bfree);
            CHECK(result == -1 && saved == EIO && before.f_bfree == after.f_bfree);
            errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
        } else if(!strcmp(scenario,"allocation") || !strcmp(scenario,"allocation-bitmap")) {
            CHECK(statfs(point,&before) == 0);
            CHECK(fault_arm(ctl,ds.st_rdev,!strcmp(scenario,"allocation-bitmap") ? EXT2_FAULT_INODE : EXT2_FAULT_DATA,st.st_ino,!strcmp(scenario,"allocation-bitmap") ? 6 : 0,1) == 0);
            CHECK(lseek(fd,12*1024,SEEK_SET) == 12*1024);
            errno=0; result=write(fd,"I",1); saved=errno;
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1);
            CHECK(statfs(point,&after) == 0);
            printf("allocation error=%d errno=%d free-before=%ld free-after=%ld\n",result,saved,before.f_bfree,after.f_bfree);
            CHECK(result == -1 && saved == EIO && before.f_bfree == after.f_bfree);
            errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
        } else if(!strcmp(scenario,"first-errno")) {
            CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_DATA,st.st_ino,0,1) == 0);
            CHECK(lseek(fd,16,SEEK_SET) == 16);
            errno=0; CHECK(write(fd,"E",1) == -1 && errno == EIO);
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1);
            memset(&c,0,sizeof(c)); c.op=EXT2_FAULT_ARM; c.target=ds.st_rdev;
            c.kind=EXT2_FAULT_DATA; c.ino=st.st_ino; c.after=1; c.error=ENXIO;
            CHECK(ioctl(ctl,EXT2_FAULT_CTL,&c) == 0 && lseek(fd,32,SEEK_SET) == 32);
            errno=0; CHECK(write(fd,"N",1) == -1 && errno == ENXIO);
            CHECK(fault_query(ctl,&c) == 0 && c.failed == 1 && c.matched == 1);
            errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
            puts("first error EIO retained after subsequent ENXIO");
        } else if(strcmp(scenario,"clean") && strcmp(scenario,"close") && strcmp(scenario,"rewrite") && !remounting) return 1;
        CHECK(close(fd) == 0 && chdir("/") == 0);
        CHECK(fault_arm(ctl,ds.st_rdev,!strcmp(scenario,"close") ? EXT2_FAULT_CLOSE : ((!strcmp(scenario,"rewrite") || !strcmp(scenario,"remount-rewrite")) ? EXT2_FAULT_REWRITE : EXT2_FAULT_CLEAN),0,0,1) == 0);
        errno=0;
        if(remounting) { args.fspec=NULL; result=mount("ext2fs",point,MNT_UPDATE|MNT_RDONLY,&args); }
        else result=unmount(point,0);
        saved=errno;
        printf("fault transition scenario=%s result=%d errno=%d\n",scenario,result,saved);
        CHECK(result == -1 && saved == EIO);
        CHECK(fault_query(ctl,&c) == 0);
        if(!strcmp(scenario,"clean") || !strcmp(scenario,"close") || !strcmp(scenario,"remount-clean")) {
            CHECK(c.failed == 1 && c.matched == 1);
            CHECK(c.dirty_writes == 1 && c.flushes >= 1);
        } else if(!strcmp(scenario,"rewrite") || !strcmp(scenario,"remount-rewrite")) {
            CHECK(c.failed == 2 && c.matched == 2 && c.dirty_writes == 1);
        }
        else CHECK(c.failed == 0 && c.matched == 0);
        CHECK(statfs(point,&after) == 0 && !strcmp(after.f_fstypename,"ext2fs") && !(after.f_flags&MNT_RDONLY));
        CHECK(chdir(point) == 0 && (fd=open("fault-file",O_RDONLY)) >= 0);
        if(!strcmp(scenario,"rewrite") || !strcmp(scenario,"remount-rewrite")) {
            int wr;
            CHECK(read_at(fd,0,"F",1) == 0);
            errno=0; wr=open("fault-file",O_WRONLY); CHECK(wr == -1 && errno == EIO);
            errno=0; CHECK(chmod("fault-file",0600) == -1 && errno == EIO);
            errno=0; CHECK(unlink("fault-file") == -1 && errno == EIO);
        }
        errno=0; CHECK(fsync(fd) == -1 && errno == EIO);
        CHECK(close(fd) == 0 && chdir("/") == 0);
        CHECK(fault_arm(ctl,ds.st_rdev,EXT2_FAULT_CLEAN,0,0,1) == 0);
        errno=0; CHECK(unmount(point,0) == -1 && errno == EIO);
        CHECK(fault_query(ctl,&c) == 0 && !c.failed && !c.matched);
        /* Leave the errored target mounted for dirty-marker offline evidence. */
    }
    CHECK(close(ctl) == 0);
    printf("EXT2_OK ioerror-%s\n",scenario); return 0;
}
#endif

int main(int argc,char **argv)
{
    struct stat st;
    struct statfs fs;
    struct dirent *entry;
    DIR *dir;
    int fd, saw_dot = 0, saw_parent = 0;
    char data[32];
    ssize_t count;
    if (argc == 4 && !strcmp(argv[1],"rejected-inode")) return rejected_inode(argv[2],argv[3],0);
    if (argc == 4 && !strcmp(argv[1],"rejected-root")) return rejected_inode(argv[2],argv[3],1);
    if (argc == 3 && !strcmp(argv[1],"mmap-readonly")) return mapped_readonly(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"mmap-fresh-control")) return fresh_control(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"mmap-fresh")) return fresh_mapping(argv[2],0);
    if (argc == 3 && !strcmp(argv[1],"verify-fresh")) return fresh_mapping(argv[2],1);
#ifdef EXT2FS_TEST_IO
    if (argc == 6 && !strcmp(argv[1],"ioerror")) return fault_case(argv[2],argv[3],argv[4],argv[5]);
#endif
    if (argc == 4 && !strcmp(argv[1],"dirty-refusal")) return dirty_refusal(argv[2],argv[3]);
    if (argc == 3 && !strcmp(argv[1],"remount-busy")) return remount_references(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"remount-cycle-null")) return remount_cycle(argv[2],NULL);
    if (argc == 4 && !strcmp(argv[1],"remount-cycle-device")) return remount_cycle(argv[2],argv[3]);
    if (argc == 3 && !strcmp(argv[1],"busy")) return busy_unmount(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"persistence-write")) return persistence(argv[2],0);
    if (argc == 3 && !strcmp(argv[1],"persistence-read")) return persistence(argv[2],1);
    if (argc == 3 && !strcmp(argv[1],"remount-null")) return remount_cycle(argv[2],NULL);
    if (argc == 4 && !strcmp(argv[1],"remount-device")) return remount_cycle(argv[2],argv[3]);
    if (argc == 3 && !strcmp(argv[1],"mutation")) return mutation(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"limits")) return limits(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"ufs-append-control")) return ufs_append_control(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"mmap-limits")) return mapped_limits(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"mmap-size")) return mapped_size(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"mmap")) return mapped(argv[2],1);
    if (argc == 3 && !strcmp(argv[1],"mmap-fsync")) return mapped(argv[2],0);
    if (argc == 3 && !strcmp(argv[1],"permissions")) return permissions(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"special")) return special(argv[2]);
    if (argc == 3 && !strcmp(argv[1],"verify-writes")) return verify_writes(argv[2],1);
    if (argc == 3 && !strcmp(argv[1],"verify-core")) return verify_writes(argv[2],0);
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
