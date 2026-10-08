/* Native command safety and the kernel's portable admission codec. */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <kernserv/loadable_fs.h>
#include <ext2fs/ext2_disk.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "ext2_tool.h"

/* Raw and block nodes have distinct st_rdev values on Rhapsody. Resolve
 * source symlinks first, then compare their device-namespace partition names.
 * stat must succeed before realpath: legacy libc loops on self links. */
static int
identity(const char *path,struct stat *st,char resolved[MAXPATHLEN],char **key)
{
    char *name;
    *key=NULL;
    if(path==NULL || strlen(path)>=MAXPATHLEN ||
        stat(path,st)<0 || realpath(path,resolved)==NULL)
        return -1;
    if(!strncmp(resolved,"/private/dev/",13)) name=resolved+13;
    else if(!strncmp(resolved,"/dev/",5)) name=resolved+5;
    else return 0;
    if(!S_ISCHR(st->st_mode) && !S_ISBLK(st->st_mode)) return 0;
    if(S_ISCHR(st->st_mode) && name[0]=='r') name++;
    if(!*name || strchr(name,'/')) return -1;
    *key=name;
    return 0;
}

/* Compare the other node in the actual raw/block namespace by same-type
 * identity; no relationship between character and block major numbers is
 * assumed. Unknown cross-type aliases are inspection failures. */
static int
counterpart(const struct stat *one,const char *key,const struct stat *other)
{
    struct stat paired;
    char path[MAXPATHLEN];
    const char *raw=S_ISBLK(one->st_mode)?"r":"";
    if(key==NULL || strlen(key)+strlen(raw)+14>=sizeof(path)) return -1;
    sprintf(path,"/private/dev/%s%s",raw,key);
    if(stat(path,&paired)<0 ||
        (S_ISBLK(other->st_mode)?!S_ISBLK(paired.st_mode):!S_ISCHR(paired.st_mode))) return -1;
    return paired.st_rdev==other->st_rdev;
}

int
ext2_device_is_mounted(const char *path)
{
    struct stat target,source;
    struct statfs *mounts;
    char a[MAXPATHLEN],b[MAXPATHLEN],*ak,*bk;
    int count,i,match;
    /* Regular image callers may supply relative paths; mount source names
     * cannot be recovered relative to this process's unrelated directory. */
    if(identity(path,&target,a,&ak)<0) return -1;
    count=getmntinfo(&mounts,MNT_NOWAIT);
    if(count<=0 || mounts==NULL) return -1;
    for(i=0;i<count;i++) {
        if(memchr(mounts[i].f_mntfromname,0,sizeof(mounts[i].f_mntfromname))==NULL ||
            memchr(mounts[i].f_fstypename,0,sizeof(mounts[i].f_fstypename))==NULL) return -1;
        /* These registered pseudo filesystems have no backing device. Only
         * their documented source/type pairs are safe to omit. */
        if((!strcmp(mounts[i].f_fstypename,"volfs") && !strcmp(mounts[i].f_mntfromname,"<volfs>")) ||
            (!strcmp(mounts[i].f_fstypename,"fdesc") && !strcmp(mounts[i].f_mntfromname,"fdesc")) ||
            (!strcmp(mounts[i].f_fstypename,"kernfs") && !strcmp(mounts[i].f_mntfromname,"kernfs"))) continue;
        if(mounts[i].f_mntfromname[0]!='/' ||
            identity(mounts[i].f_mntfromname,&source,b,&bk)<0) return -1;
        if(ak && bk && !strcmp(ak,bk)) return 1;
        if((S_ISBLK(target.st_mode) && S_ISBLK(source.st_mode)) ||
            (S_ISCHR(target.st_mode) && S_ISCHR(source.st_mode))) {
            if(target.st_rdev==source.st_rdev) return 1;
        } else if((S_ISBLK(target.st_mode) && S_ISCHR(source.st_mode)) ||
            (S_ISCHR(target.st_mode) && S_ISBLK(source.st_mode))) {
            match=counterpart(&target,ak,&source);
            if(match<0) match=counterpart(&source,bk,&target);
            if(match<0) return -1;
            if(match) return 1;
        } else if(S_ISREG(target.st_mode) && S_ISREG(source.st_mode) &&
            target.st_dev==source.st_dev && target.st_ino==source.st_ino) return 1;
    }
    return 0;
}

int
ext2_run_tool(const char *path,char *const argv[])
{
    pid_t child,result;
    int status;
    child=fork();
    if(child<0) return 8;
    if(child==0) {execv(path,argv);_exit(8);}
    do {result=waitpid(child,&status,0);} while(result<0 && errno==EINTR);
    if(result!=child || !WIFEXITED(status)) return 8;
    return WEXITSTATUS(status);
}

static int
read_at(void *cookie,u_int32_t offset,void *buffer,size_t length)
{
    int fd=*(int *)cookie;
    char *p=buffer;
    ssize_t n;
    if(lseek(fd,(off_t)offset,SEEK_SET)!=(off_t)offset) return EIO;
    while(length) {
        n=read(fd,p,length);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return EIO;
        p+=n;length-=n;
    }
    return 0;
}

static int
capacity(int fd,u_int64_t *bytes,int *regular)
{
    struct stat st;
    struct disk_partition_info part;
    if(fstat(fd,&st)<0) return -1;
    *regular=S_ISREG(st.st_mode);
    if(*regular) {
        if(st.st_size<0) return -1;
        *bytes=(u_int64_t)st.st_size;
    } else {
        if((!S_ISCHR(st.st_mode) && !S_ISBLK(st.st_mode)) ||
            ioctl(fd,DKIOCGPARTINFO,&part)<0 ||
            (part.block_size!=512 && part.block_size!=1024) ||
            part.block_count<4 || part.block_count>0x7fffffffU) return -1;
        *bytes=(u_int64_t)part.block_count*part.block_size;
    }
    return 0;
}

/* A raw formatter needs -F to avoid upstream's block-only plausibility
 * prompt. -F also suppresses its oversized-count warning, so establish
 * selected-partition bounds ourselves before launching any formatter. */
int
ext2_format_size(const char *path,unsigned int blocksize,unsigned long requested)
{
    u_int64_t bytes,blocks;
    int fd,regular,error;
    if(path==NULL || strlen(path)>=MAXPATHLEN || blocksize<512 || blocksize%512) return 8;
    fd=open(path,O_RDONLY);
    if(fd<0) return 8;
    error=capacity(fd,&bytes,&regular);
    if(close(fd)<0 || error) return 8;
    blocks=requested?requested:bytes/blocksize;
    if(!blocks || blocks>0x80000000U/(blocksize/512)) return 8;
    /* off_t is signed64 in the exported ABI; backing files may exceed the
     * ext2 per-file ceiling. Keep the volume's sector addresses bounded. */
    if((off_t)(blocks*blocksize)<0 || (u_int64_t)(off_t)(blocks*blocksize)!=blocks*blocksize) return 8;
    if(!regular && blocks>bytes/blocksize) return 8;
    return 0;
}

static int
load_volume(const char *path,struct ext2fs *super)
{
    u_int64_t bytes;
    u_int32_t count;
    int fd,error,regular;
    if(path==NULL || strlen(path)>=MAXPATHLEN) return FSUR_IO_FAIL;
    fd=open(path,O_RDONLY);
    if(fd<0) return FSUR_IO_FAIL;
    error=FSUR_IO_FAIL;
    /* Convert selected capacity to bounded 512-byte address units. */
    if(capacity(fd,&bytes,&regular)<0 || bytes/512<4 || bytes/512>0x7fffffffU) goto done;
    count=(u_int32_t)(bytes/512);
    if(ext2_read_super(512,count,read_at,&fd,super)!=0) goto done;
    error=ext2_validate_super(super,bytes,0)==0?FSUR_RECOGNIZED:FSUR_UNRECOGNIZED;
done:
    if(close(fd)<0) return FSUR_IO_FAIL;
    return error;
}

int
ext2_probe(const char *path,char label[17])
{
    struct ext2fs super;
    int result;
    label[0]=0;
    result=load_volume(path,&super);
    if(result==FSUR_RECOGNIZED) {memcpy(label,super.e2fs_vname,16);label[16]=0;}
    return result;
}

int
ext2_mount_probe(const char *path,int readonly)
{
    struct ext2fs super;
    int result=load_volume(path,&super);
    if(result==FSUR_RECOGNIZED && !readonly && super.e2fs_state!=E2FS_ISCLEAN)
        return FSUR_IO_UNCLEAN;
    return result;
}
