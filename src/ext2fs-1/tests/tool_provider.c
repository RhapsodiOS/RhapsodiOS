/* Test-only providers; production has no runtime inspection override. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
static struct statfs table;
int tool_getmntinfo(struct statfs **out,int flags) {
 const char *m=getenv("TOOL_MOUNT"); (void)flags;
 if(m && !strcmp(m,"fail")){errno=EIO;return 0;}
 memset(&table,0,sizeof(table));
 if(!m || !strcmp(m,"safe")){strcpy(table.f_mntfromname,"/private/dev/hd0a");}
 else if(!strncmp(m,"pseudo-",7)) {
  const char *kind=m+7;
  strcpy(table.f_fstypename,!strcmp(kind,"unknown")?"ufs":!strcmp(kind,"mismatch")||!strcmp(kind,"absolute")?"volfs":kind);
  strcpy(table.f_mntfromname,!strcmp(kind,"volfs")||!strcmp(kind,"unknown")?"<volfs>":!strcmp(kind,"absolute")?"/dev/hd1a":!strcmp(kind,"mismatch")?"fdesc":kind);
 }
 else if(!strcmp(m,"relative")) strcpy(table.f_mntfromname,"hd1a");
 else if(!strcmp(m,"broken")) strcpy(table.f_mntfromname,"/missing/source");
 else if(!strcmp(m,"link")) strcpy(table.f_mntfromname,"/outside/source-link");
 else strcpy(table.f_mntfromname,m);
 *out=&table;return 1;
}
int tool_stat(const char *p,struct stat *s) {
 if(!strcmp(p,"/outside/raw-node") || !strcmp(p,"/outside/source-node")) {
  memset(s,0,sizeof(*s));s->st_mode=!strcmp(p,"/outside/raw-node")?S_IFCHR:S_IFBLK;
  s->st_rdev=!strcmp(p,"/outside/raw-node")?0x901:0x301;return 0;
 }
 if(!strncmp(p,"/dev/",5)||!strncmp(p,"/private/dev/",13)||!strcmp(p,"/outside/source-link")) {
  memset(s,0,sizeof(*s));s->st_mode=strstr(p,"/r")?S_IFCHR:S_IFBLK;
  s->st_rdev=(strstr(p,"/r")?0x900:0x300)+(strstr(p,"hd0")?0:1);return 0;
 }
 return stat(p,s);
}
char *tool_realpath(const char *p,char *out) {
 if(!strcmp(p,"/outside/raw-node") || !strcmp(p,"/outside/source-node")){strcpy(out,p);return out;}
 if(!strcmp(p,"/outside/source-link"))p="/private/dev/hd1a";
 if(!strncmp(p,"/dev/",5)||!strncmp(p,"/private/dev/",13)){strcpy(out,p);return out;}
 return realpath(p,out);
}
int tool_read_calls;
ssize_t tool_read(int fd,void *p,size_t n) {
 static int interrupted;tool_read_calls++;
 if(getenv("TOOL_SHORT")) {if(!interrupted++){errno=EINTR;return -1;}if(n>7)n=7;}
 return read(fd,p,n);
}

int tool_open(const char *path,int flags) {
 if(!strcmp(path,"/outside/raw-node") || !strncmp(path,"/dev/",5)||!strncmp(path,"/private/dev/",13)) {
  const char *image=getenv("TOOL_DEVICE_IMAGE");path=image?image:"/dev/null";
 }
 return open(path,flags);
}
int tool_ioctl(int fd,unsigned long request,void *arg) {
 const char *mode=getenv("TOOL_CAP");struct disk_partition_info *p=arg;
 if(request!=DKIOCGPARTINFO)return ioctl(fd,request,arg);
 if(mode && (!strcmp(mode,"old")||!strcmp(mode,"whole")||!strcmp(mode,"missing"))){errno=!strcmp(mode,"old")?ENOTTY:EINVAL;return -1;}
 p->block_size=512;p->block_count=32768;
 if(mode && !strcmp(mode,"zero-size"))p->block_size=0;
 if(mode && !strcmp(mode,"zero-count"))p->block_count=0;
 if(mode && !strcmp(mode,"bad-count"))p->block_count=0x80000000U;
 if(mode && !strcmp(mode,"unsupported-sector"))p->block_size=2048;
 if(mode && !strcmp(mode,"sector1024")){p->block_size=1024;p->block_count=16384;}
 if(mode && !strcmp(mode,"small"))p->block_count=4;
 return 0;
}
int tool_fstat(int fd,struct stat *st) {
 int status=fstat(fd,st);
 if(status==0 && getenv("TOOL_DEVICE_IMAGE") && S_ISREG(st->st_mode))st->st_mode=(st->st_mode & ~S_IFMT)|S_IFCHR;
 if(status==0 && getenv("TOOL_BIG_REG") && S_ISREG(st->st_mode))st->st_size=(off_t)3*1024*1024*1024;
 return status;
}
