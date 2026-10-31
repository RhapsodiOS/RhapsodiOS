/* Workspace/autodiskmount protocol; kernserv/loadable_fs.h is authoritative. */
#include <sys/param.h>
#include <kernserv/loadable_fs.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "ext2_tool.h"
#ifndef EXT2_DEVICE_DIRECTORY
#define EXT2_DEVICE_DIRECTORY "/private/dev"
#endif
#ifndef EXT2_FS_DIRECTORY
#define EXT2_FS_DIRECTORY "/usr/filesystems/ext2fs.fs"
#endif
static int save(const char *suffix,const char *text) {
    char path[MAXPATHLEN];size_t left=strlen(text);ssize_t n;int fd;
    if(strlen(EXT2_FS_DIRECTORY)+strlen(suffix)+9>=sizeof(path))return -1;
    sprintf(path,"%s/ext2fs%s",EXT2_FS_DIRECTORY,suffix);
    if(unlink(path)<0 && errno!=ENOENT)return -1;
    fd=open(path,O_WRONLY|O_CREAT|O_EXCL,0644);if(fd<0)return -1;
    while(left) {n=write(fd,text,left);if(n<0 && errno==EINTR)continue;if(n<=0){close(fd);return -1;}text+=n;left-=n;}
    return close(fd);
}
int main(int argc,char **argv) {
    char block[MAXPATHLEN],raw[MAXPATHLEN],label[17],*args[10];
    const char *device,*flags=NULL;int action,readonly=0,result,status,i;
    if(argc<3 || argv[1][0]!='-' || !argv[1][1] || argv[1][2])return FSUR_INVAL;
    action=argv[1][1];device=argv[2];
    if(!*device || strlen(device)+strlen(EXT2_DEVICE_DIRECTORY)+4>=sizeof(raw))return FSUR_INVAL;
    for(i=0;device[i];i++)if(!isalnum((unsigned char)device[i]) && device[i]!='_')return FSUR_INVAL;
    switch(action) {
    case FSUC_PROBE: if(argc!=5)return FSUR_INVAL;flags=argv[3];break;
    case FSUC_PROBEFORINIT: case FSUC_REPAIR: case FSUC_INITIALIZE:
        if(argc!=4)return FSUR_INVAL;flags=argv[3];break;
    case FSUC_MOUNT:
        if(argc!=6 || argv[3][0]!='/' || strlen(argv[3])>=MAXPATHLEN)return FSUR_INVAL;
        flags=argv[4];break;
    case FSUC_UNMOUNT:
        if(argc!=4 || argv[3][0]!='/' || strlen(argv[3])>=MAXPATHLEN)return FSUR_INVAL;break;
    default:return FSUR_INVAL;
    }
    if(flags && strcmp(flags,DEVICE_FIXED) && strcmp(flags,DEVICE_REMOVABLE))return FSUR_INVAL;
    if(action==FSUC_PROBE || action==FSUC_MOUNT) {
        const char *mode=argv[action==FSUC_PROBE?4:5];
        if(!strcmp(mode,DEVICE_READONLY))readonly=1;
        else if(strcmp(mode,DEVICE_WRITABLE))return FSUR_INVAL;
    }
    sprintf(block,"%s/%sa",EXT2_DEVICE_DIRECTORY,device);
    sprintf(raw,"%s/r%sa",EXT2_DEVICE_DIRECTORY,device);
    if(action==FSUC_PROBE || action==FSUC_PROBEFORINIT) {
        result=ext2_probe(raw,label);
        if(result==FSUR_RECOGNIZED && (save(FS_NAME_SUFFIX,"ext2")<0 || save(FS_LABEL_SUFFIX,label)<0))return FSUR_IO_FAIL;
        return action==FSUC_PROBEFORINIT && result==FSUR_RECOGNIZED?FSUR_INITRECOGNIZED:result;
    }
    if(action==FSUC_REPAIR || action==FSUC_INITIALIZE) {
        if(ext2_device_is_mounted(raw)!=0)return FSUR_IO_FAIL;
        args[0]=action==FSUC_REPAIR?EXT2_FSCK:EXT2_NEWFS;
        if(action==FSUC_REPAIR) {args[1]="-p";args[2]=raw;args[3]=NULL;}
        else {args[1]=raw;args[2]=NULL;}
        status=ext2_run_tool(args[0],args);
        if(action==FSUC_INITIALIZE)return status==0?FSUR_IO_SUCCESS:FSUR_IO_FAIL;
        if(status & ~7)return FSUR_IO_FAIL;
        if(status & 4)return FSUR_IO_UNCLEAN;
        if(status & 2)fprintf(stderr,"ext2fs.util: repair advises reboot\n");
        return FSUR_IO_SUCCESS;
    }
    if(action==FSUC_UNMOUNT) {args[0]=EXT2_UMOUNT;args[1]=argv[3];args[2]=NULL;}
    else {
        result=ext2_mount_probe(raw,readonly);
        if(result!=FSUR_RECOGNIZED)return result;
        args[0]=EXT2_MOUNT;args[1]="-t";args[2]="ext2fs";args[3]="-o";
        args[4]=readonly?"ro":"rw";args[5]=block;args[6]=argv[3];args[7]=NULL;
    }
    return ext2_run_tool(args[0],args)==0?FSUR_IO_SUCCESS:FSUR_IO_FAIL;
}
