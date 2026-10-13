/* Compile the actual autodiskmount implementation with private device fixtures.
 * Driver enumeration/open/ioctl/getfsstat are providers; fork/execve/wait,
 * labels, DiskVolumes, DiskVolume and List are production implementations.
 */
#import <libc.h>
#import <stdlib.h>
#import <unistd.h>
#import <string.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IOProperties.h>
#import <sys/ioctl.h>
#import <bsd/dev/disk.h>
#import <errno.h>
#import <sys/wait.h>
#import <sys/param.h>
#import <sys/mount.h>
#import <grp.h>
#import <ufs/ufs/ufsmount.h>
#import <objc/Object.h>
#import <mach/boolean.h>
#import <objc/List.h>
#import <kernserv/loadable_fs.h>
#include <stdarg.h>

#ifndef DISCOVERY_SOURCE
#error Define DISCOVERY_SOURCE to the production DiskVolume.m
#endif
#ifndef DISCOVERY_DIRECTORY
#error Define DISCOVERY_DIRECTORY to a fresh private test directory
#endif
static int hfs_present, candidate_present=1, mounted_type, ufs_present;
static int checks, failures;
static const char literal_label[]="Data ; $() ' \"";
static void check(int ok,const char *name) {
    checks++; if(!ok) { failures++; printf("FAIL %s\n",name); }
    else printf("PASS %s\n",name);
}
@interface DiscoveryMaster : Object
- (IOReturn)lookUpByStringPropertyList:(const char *)query results:(char *)resultBuf maxLength:(unsigned)n;
- (IOReturn)lookUpByDeviceName:(const char *)name objectNumber:(IOObjectNumber *)number deviceKind:(IOString *)kind;
- (IOReturn)getStringPropertyList:(IOObjectNumber)number names:(const char *)names results:(char *)resultBuf maxLength:(unsigned)n;
@end
@implementation DiscoveryMaster
- (IOReturn)lookUpByStringPropertyList:(const char *)query results:(char *)resultBuf maxLength:(unsigned)n {
    strcpy(resultBuf,"hd1"); return IO_R_SUCCESS;
}
- (IOReturn)lookUpByDeviceName:(const char *)name objectNumber:(IOObjectNumber *)number deviceKind:(IOString *)kind {
    *number=1;return IO_R_SUCCESS;
}
- (IOReturn)getStringPropertyList:(IOObjectNumber)number names:(const char *)names results:(char *)resultBuf maxLength:(unsigned)n {
    strcpy(resultBuf,IOTypeIDE);return IO_R_SUCCESS;
}
@end
static int fixture_open(const char *path,int flags,...) {
    mode_t mode=0;va_list ap;
    if(flags&O_CREAT) {va_start(ap,flags);mode=va_arg(ap,int);va_end(ap);}
    if(!strncmp(path,"/dev/",5)) {
        if((candidate_present && !strcmp(path,"/dev/hd1a")) ||
           (hfs_present && !strcmp(path,"/dev/hd1_hfs_a")) ||
           (ufs_present && !strcmp(path,"/dev/rhd1h")))return open("/dev/null",O_RDONLY);
        errno=ENOENT;return -1;
    }
    return open(path,flags,mode);
}
static int fixture_ioctl(int fd,unsigned long request,...) {
    va_list ap;struct disk_label *label;
    if(ufs_present && request==DKIOCGLABEL) {
        va_start(ap,request);label=va_arg(ap,struct disk_label *);va_end(ap);
        memset(label,0,sizeof(*label));label->dl_dt.d_partitions[0].p_newfs=1;
        strcpy(label->dl_label,"UFS");return 0;
    }
    errno=ENOTTY;return -1;
}
static int fixture_getfsstat(struct statfs *fs,long bytes,int flags) {
    if(fs) {
        memset(fs,0,sizeof(*fs));
        strcpy(fs->f_fstypename,mounted_type==1?"ext2fs":mounted_type==2?"msdos":"ufs");
        strcpy(fs->f_mntfromname,mounted_type?"/private/dev/hd1a":"/dev/hd0a");
        strcpy(fs->f_mntonname,mounted_type?"/Already mounted":"/");
    }
    return 1;
}
#undef FS_DIR_LOCATION
#define FS_DIR_LOCATION DISCOVERY_DIRECTORY
#define IODeviceMaster DiscoveryMaster
#define open fixture_open
#define ioctl fixture_ioctl
#define getfsstat fixture_getfsstat
#include DISCOVERY_SOURCE
#undef getfsstat
#undef ioctl
#undef open
#undef IODeviceMaster

static void helper(const char *fs,int result) {
    char dir[MAXPATHLEN],path[MAXPATHLEN];FILE *f;
    sprintf(dir,"%s/%s.fs",DISCOVERY_DIRECTORY,fs);mkdir(dir,0755);
    sprintf(path,"%s/%s.util",dir,fs);f=fopen(path,"w");
    fprintf(f,"#!/bin/sh\nprintf '%%s\\n' '%s' \"$@\" >> '%s/calls'\nexit %d\n",fs,DISCOVERY_DIRECTORY,result);
    fclose(f);chmod(path,0755);
    sprintf(path,"%s/%s.label",dir,fs);f=fopen(path,"w");fputs(literal_label,f);fclose(f);
}
static char *calls(void) {
    static char text[4096];char path[MAXPATHLEN];FILE *f;size_t n=0;
    sprintf(path,"%s/calls",DISCOVERY_DIRECTORY);f=fopen(path,"r");
    if(f) {n=fread(text,1,sizeof(text)-1,f);fclose(f);}text[n]=0;return text;
}
static void reset(void) {
    char path[MAXPATHLEN];sprintf(path,"%s/calls",DISCOVERY_DIRECTORY);unlink(path);
    hfs_present=mounted_type=ufs_present=0;candidate_present=1;
    helper("hfs",254);helper("cd9660",254);helper("msdos",254);helper("ext2fs",255);
}
static DiskVolumes *discover(void) {return [[DiskVolumes alloc] init:TRUE Eject:FALSE];}
static DiskVolume *only(DiskVolumes *v) {return [v count]==1?[v objectAt:0]:nil;}
int main(void) {
    DiskVolumes *volumes;DiskVolume *disk;char path[MAXPATHLEN];
    mkdir(DISCOVERY_DIRECTORY,0755);
    reset();volumes=discover();disk=only(volumes);
    check(disk && !strcmp(disk->fs_type,"ext2fs"),"supported ext2 classification");
    check(disk && !strcmp(disk->disk_name,literal_label),"ext2 bounded literal label");
    check(strstr(calls(),"ext2fs\n-p\nhd1\nfixed\nwritable\n")!=NULL,"ext2 probe protocol");
    if(disk) {
        [disk setMountPoint:"/Data ; $() ' \""];helper("ext2fs",253);
        check([disk mount],"ext2 foreign mount dispatch");
        check(strstr(calls(),"ext2fs\n-m\nhd1\n/Data ; $() ' \"\nfixed\nwritable\n")!=NULL,"literal mount argv");
    } else check(0,"ext2 foreign mount dispatch");
    [volumes free];
    reset();helper("msdos",255);volumes=discover();disk=only(volumes);
    check(disk && !strcmp(disk->fs_type,"msdos"),"FAT classification precedence");
    check(strstr(calls(),"ext2fs")==NULL,"FAT suppresses ext2 helper");[volumes free];
    reset();hfs_present=1;helper("hfs",255);helper("ext2fs",254);volumes=discover();
    check([volumes count]==1 && !strcmp(only(volumes)->fs_type,"hfs"),"HFS classification precedence");
    check([volumes count]==1,"HFS bank and partition-a are distinct candidates");[volumes free];
    reset();helper("cd9660",255);volumes=discover();
    check([volumes count]==1 && !strcmp(only(volumes)->fs_type,"cd9660"),"CD9660 classification precedence");
    check(strstr(calls(),"ext2fs")==NULL,"CD9660 suppresses ext2 helper");[volumes free];
    reset();ufs_present=1;mounted_type=3;volumes=discover();
    check([volumes count]==1 && !strcmp(only(volumes)->fs_type,"ufs"),"UFS label precedence");
    check(strstr(calls(),"ext2fs")==NULL,"UFS suppresses ext2 helper");[volumes free];
    reset();mounted_type=1;volumes=discover();disk=only(volumes);
    check(disk && disk->mounted && !strcmp(disk->mount_point,"/Already mounted"),"mounted ext2 reused");
    check(strstr(calls(),"ext2fs")==NULL,"mounted ext2 not reprobed");[volumes free];
    reset();mounted_type=2;volumes=discover();
    check([volumes count]==1 && !strcmp(only(volumes)->fs_type,"msdos"),"mounted FAT precedence");
    check(strstr(calls(),"ext2fs")==NULL,"mounted FAT not ext2 probed");[volumes free];
    reset();sprintf(path,"%s/ext2fs.fs/ext2fs.util",DISCOVERY_DIRECTORY);unlink(path);volumes=discover();
    check([volumes count]==0 && strstr(calls(),"ext2fs")==NULL,"missing helper no ext2 child");[volumes free];
    reset();candidate_present=0;volumes=discover();
    check([volumes count]==0 && !*calls(),"unexposed candidate no child");[volumes free];
    reset();helper("ext2fs",254);volumes=discover();
    check([volumes count]==0,"unsupported ext2 not classified");
    check(strstr(calls(),"\n-i\n")==NULL && strstr(calls(),"\n-r\n")==NULL,"no init or repair during discovery");[volumes free];
    reset();helper("ext2fs",252);volumes=discover();check([volumes count]==0,"malformed or I/O failure not classified");[volumes free];
    reset();volumes=discover();disk=only(volumes);helper("ext2fs",251);
    if(disk) {[disk setMountPoint:"/dirty"];check(![disk mount],"dirty writable mount refuses");}
    else check(0,"dirty writable mount refuses");
    check(strstr(calls(),"\n-i\n")==NULL && strstr(calls(),"\n-r\n")==NULL,"dirty mount no implicit repair");[volumes free];
    printf("DISCOVERY cases=%d failures=%d\n",checks,failures);return failures?1:0;
}
