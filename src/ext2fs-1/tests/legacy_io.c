/* Native UFS controls for the shared vnode/MapFS paths used by ext2fs.
 * Run only on a disposable writable UFS volume as root. */
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"line %d: %s errno=%d\n",__LINE__,#x,errno); return 1; } } while (0)

static int byte_at(int fd, off_t offset, char expected)
{
    char value;
    CHECK(lseek(fd,offset,SEEK_SET)==offset);
    CHECK(read(fd,&value,1)==1 && value==expected);
    return 0;
}

static int access_as(uid_t uid, int allowed)
{
    pid_t child;
    int fd,status;
    child=fork(); CHECK(child>=0);
    if (child==0) {
        if (setgid(uid)!=0 || setuid(uid)!=0) _exit(2);
        errno=0; fd=open("permissions",O_RDONLY);
        if (allowed) { if (fd<0) _exit(3); close(fd); }
        else if (fd>=0 || errno!=EACCES) _exit(4);
        _exit(0);
    }
    CHECK(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0);
    return 0;
}

int main(int argc,char **argv)
{
    struct statfs fs;
    struct stat st;
    off_t offsets[4],last;
    char *pages;
    int fd,i;
    CHECK(argc==2 && getuid()==0 && chdir(argv[1])==0);
    CHECK(statfs(".",&fs)==0 && !strcmp(fs.f_fstypename,"ufs"));
    CHECK(fs.f_iosize>=1024 && fs.f_iosize<=8192 && fs.f_iosize%4==0);
    printf("UFS geometry fragment=%ld block=%ld type=%ld\n",
        (long)fs.f_bsize,(long)fs.f_iosize,(long)fs.f_type);
    offsets[0]=(off_t)12*fs.f_iosize-1;
    offsets[1]=(off_t)12*fs.f_iosize;
    offsets[2]=((off_t)12+fs.f_iosize/4)*fs.f_iosize-1;
    offsets[3]=((off_t)12+fs.f_iosize/4)*fs.f_iosize;
    last=offsets[3]+1;
    CHECK((fd=open("sparse",O_CREAT|O_EXCL|O_RDWR,0600))>=0);
    CHECK(ftruncate(fd,last)==0 && byte_at(fd,last-1,0)==0);
    for (i=0;i<4;i++) {
        char value='A'+i;
        CHECK(lseek(fd,offsets[i],SEEK_SET)==offsets[i] && write(fd,&value,1)==1);
    }
    CHECK(fsync(fd)==0 && close(fd)==0);
    CHECK((fd=open("sparse",O_RDONLY))>=0 && fstat(fd,&st)==0 && st.st_size==last);
    CHECK(byte_at(fd,0,0)==0 && byte_at(fd,offsets[0]-1,0)==0);
    for (i=0;i<4;i++) CHECK(byte_at(fd,offsets[i],'A'+i)==0);
    CHECK(close(fd)==0 && unlink("sparse")==0);
    puts("UFS_OK sparse-direct-single-double");

    CHECK((fd=open("mapped",O_CREAT|O_EXCL|O_RDWR,0600))>=0);
    CHECK(ftruncate(fd,8192)==0);
    pages=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    CHECK(pages!=(void *)-1);
    memcpy(pages+4093,"mapfs",5);
    CHECK(fsync(fd)==0 && munmap(pages,8192)==0 && close(fd)==0);
    CHECK((fd=open("mapped",O_RDONLY))>=0);
    for (i=0;i<5;i++) CHECK(byte_at(fd,4093+i,"mapfs"[i])==0);
    CHECK(close(fd)==0 && unlink("mapped")==0);
    puts("UFS_OK mapped-fsync-readback");

    CHECK((fd=open("permissions",O_CREAT|O_EXCL|O_RDWR,0600))>=0);
    CHECK(write(fd,"owner",5)==5 && fsync(fd)==0 && close(fd)==0);
    CHECK(chown("permissions",501,501)==0 && chmod("permissions",0600)==0);
    CHECK(access_as(501,1)==0 && access_as(502,0)==0);
    CHECK(unlink("permissions")==0);
    puts("UFS_OK owner-and-other-permissions");
    return 0;
}
