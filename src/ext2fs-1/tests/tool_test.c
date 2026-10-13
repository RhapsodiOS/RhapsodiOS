/* Execute production wrappers/helper and common codec; no source-text tests. */
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <kernserv/loadable_fs.h>
#include <ext2fs/ext2_disk.h>
#include "../common/ext2_tool.h"
#ifndef TEST_DIR
#error private TEST_DIR required
#endif
static int cases,failures;
extern int tool_read_calls;
#define CHECK(x) do {cases++; if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);failures++;}}while(0)
static char image[1024],logpath[1024];
static int run(const char *name,char **args) {char path[1024];sprintf(path,"%s/%s",TEST_DIR,name);unlink(logpath);return ext2_run_tool(path,args);}
static int logged(const char *text) {char b[4096];FILE *f=fopen(logpath,"rb");size_t n,i;if(!f)return 0;n=fread(b,1,sizeof(b),f);fclose(f);for(i=0;i<n;i+=strlen(b+i)+1)if(!strcmp(b+i,text))return 1;return 0;}
static void fixture(const char *label,int feature,int state) {
 struct ext2fs s;unsigned char raw[1024];int fd;
 memset(&s,0,sizeof(s));s.e2fs_magic=E2FS_MAGIC;s.e2fs_rev=1;s.e2fs_inode_size=128;s.e2fs_first_ino=11;
 s.e2fs_bcount=8192;s.e2fs_icount=1024;s.e2fs_first_dblock=1;s.e2fs_bpg=8192;s.e2fs_fpg=8192;s.e2fs_ipg=1024;
 s.e2fs_state=state;s.e2fs_features_incompat=feature;s.e2fs_features_rocompat=1;
 memcpy(s.e2fs_vname,label,strlen(label)>16?16:strlen(label));ext2_super_encode(&s,raw);
 fd=open(image,O_CREAT|O_TRUNC|O_RDWR,0600);lseek(fd,8192*1024-1,SEEK_SET);write(fd,"",1);lseek(fd,1024,SEEK_SET);write(fd,raw,1024);close(fd);
}
int main(void) {
 char label[17],huge[2048],rawpath[1024];int i,fd,statuses[]={0,1,2,3,4,5,7,8,16,32,128,12,255};char val[16];
 char *format[]={"newfs_ext2fs","-L","space ; \" label",image,NULL};
 char *aliasformat[]={"newfs_ext2fs","/outside/raw-node",NULL};
 char *aliascheck[]={"fsck_ext2fs","-n","/outside/raw-node",NULL};
 char *deviceformat[]={"newfs_ext2fs","/private/dev/rhd1a","8192",NULL};
 char *deviceblock[]={"newfs_ext2fs","/private/dev/hd1a","16384",NULL};
 char *rawformat[]={"newfs_ext2fs","/dev/null",NULL};
 char *block[]={"newfs_ext2fs","-b","2048",image,"8192",NULL};
 char *bad[]={"newfs_ext2fs","-b","8192",image,NULL};
 char *check[]={"fsck_ext2fs","-n","-f","-v",image,NULL};
 char *conflict[]={"fsck_ext2fs","-n","-y",image,NULL};
 char *probe[]={"ext2fs.util","-p","hd1","fixed","readonly",NULL};
 char *repair[]={"ext2fs.util","-r","hd1","fixed",NULL};
 char *init[]={"ext2fs.util","-i","hd1","fixed",NULL};
 char *mount[]={"ext2fs.util","-m","hd1","/mount space ; \"","fixed","readonly",NULL};
 char *unmount[]={"ext2fs.util","-u","hd1","/mount space ; \"",NULL};
 char *force[]={"ext2fs.util","-M","hd1","/mnt","fixed","writable",NULL};
 char *dummy[]={"fake",NULL};
 sprintf(image,"%s/image",TEST_DIR);sprintf(logpath,"%s/argv",TEST_DIR);setenv("TOOL_LOG",logpath,1);setenv("TOOL_MOUNT","safe",1);
 sprintf(rawpath,"%s/rhd1a",TEST_DIR);unlink(rawpath);CHECK(symlink(image,rawpath)==0);
 fixture("1234567890123456",2,1);
 CHECK(ext2_probe(image,label)==FSUR_RECOGNIZED);CHECK(strlen(label)==16);CHECK(!strcmp(label,"1234567890123456"));
 setenv("TOOL_SHORT","1",1);CHECK(ext2_probe(image,label)==FSUR_RECOGNIZED);CHECK(tool_read_calls>=148);unsetenv("TOOL_SHORT");
 fixture("",2,1);CHECK(ext2_probe(image,label)==FSUR_RECOGNIZED && label[0]==0);
 fixture("label ; \"",2,1);CHECK(ext2_probe(image,label)==FSUR_RECOGNIZED && !strcmp(label,"label ; \""));
 fixture("bad",6,1);CHECK(ext2_probe(image,label)==FSUR_UNRECOGNIZED);
 fd=open(image,O_TRUNC|O_WRONLY);close(fd);CHECK(ext2_probe(image,label)==FSUR_IO_FAIL);
 fixture("clean",2,1);
 CHECK(run("newfs_ext2fs",format)==0);CHECK(logged("-r") && logged("1") && logged("-I") && logged("128") && logged("1024") && logged("5") && logged("filetype,sparse_super"));CHECK(logged(format[2]));
 CHECK(sizeof(off_t)==8);setenv("TOOL_BIG_REG","1",1);CHECK(run("newfs_ext2fs",format)==0 && logged("-F"));unsetenv("TOOL_BIG_REG");
 CHECK(run("newfs_ext2fs",rawformat)==0 && logged("-F"));
 setenv("TOOL_CAP","sector1024",1);setenv("TOOL_DEVICE_IMAGE",image,1);
 i=tool_read_calls;CHECK(ext2_probe("/private/dev/rhd1a",label)==FSUR_RECOGNIZED && tool_read_calls>i);
 i=tool_read_calls;CHECK(ext2_probe("/private/dev/hd1a",label)==FSUR_RECOGNIZED && tool_read_calls>i);
 fixture("bad1024",6,1);CHECK(ext2_probe("/private/dev/rhd1a",label)==FSUR_UNRECOGNIZED);
 fixture("clean",2,1);unsetenv("TOOL_DEVICE_IMAGE");
 CHECK(ext2_format_size("/private/dev/rhd1a",1024,16384)==0);
 deviceformat[2]="16384";CHECK(run("newfs_ext2fs",deviceformat)==0 && logged("-F"));deviceformat[2]="8192";
 CHECK(run("newfs_ext2fs",deviceblock)==0 && !logged("-F"));
 deviceformat[2]="16385";CHECK(run("newfs_ext2fs",deviceformat)==8 && access(logpath,F_OK)!=0);deviceformat[2]="8192";
 unsetenv("TOOL_CAP");
 {const char *badcaps[]={"old","whole","missing","zero-size","zero-count","bad-count","unsupported-sector","small"};
 for(i=0;i<sizeof(badcaps)/sizeof(badcaps[0]);i++){setenv("TOOL_CAP",badcaps[i],1);CHECK(run("newfs_ext2fs",deviceformat)==8 && access(logpath,F_OK)!=0);}unsetenv("TOOL_CAP");}
 deviceformat[2]="32769";CHECK(run("newfs_ext2fs",deviceformat)==8 && access(logpath,F_OK)!=0);deviceformat[2]="8192";
 CHECK(run("newfs_ext2fs",block)==0 && logged("2048"));block[2]="4096";CHECK(run("newfs_ext2fs",block)==0 && logged("4096"));
 CHECK(run("newfs_ext2fs",bad)==16 && access(logpath,F_OK)!=0);CHECK(run("fsck_ext2fs",conflict)==16 && access(logpath,F_OK)!=0);
 for(i=0;i<sizeof(statuses)/sizeof(statuses[0]);i++){sprintf(val,"%d",statuses[i]);setenv("TOOL_EXIT",val,1);CHECK(run("fsck_ext2fs",check)==statuses[i]);CHECK(logged("-n")&&logged("-f")&&logged("-v"));}
 unsetenv("TOOL_EXIT");
 setenv("TOOL_SIGNAL","1",1);CHECK(run("fsck_ext2fs",check)==8);unsetenv("TOOL_SIGNAL");CHECK(ext2_run_tool("/missing/child",dummy)==8);
 setenv("TOOL_MOUNT","/dev/hd1a",1);CHECK(ext2_device_is_mounted("/private/dev/rhd1a")==1);CHECK(ext2_device_is_mounted("/dev/hd1a")==1);
 setenv("TOOL_MOUNT","/private/dev/rhd1a",1);CHECK(ext2_device_is_mounted("/dev/hd1a")==1);
 setenv("TOOL_MOUNT","link",1);CHECK(ext2_device_is_mounted("/dev/rhd1a")==1);
 setenv("TOOL_MOUNT","/outside/source-node",1);CHECK(ext2_device_is_mounted("/private/dev/rhd1a")==1);CHECK(run("newfs_ext2fs",deviceformat)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT","/dev/hd1a",1);CHECK(ext2_device_is_mounted("/outside/raw-node")==1);CHECK(run("newfs_ext2fs",aliasformat)==8 && access(logpath,F_OK)!=0);CHECK(run("fsck_ext2fs",aliascheck)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT","/outside/source-node",1);CHECK(ext2_device_is_mounted("/outside/raw-node")==-1);CHECK(run("newfs_ext2fs",aliasformat)==8 && access(logpath,F_OK)!=0);CHECK(run("fsck_ext2fs",aliascheck)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT",image,1);CHECK(run("newfs_ext2fs",format)==8 && access(logpath,F_OK)!=0);CHECK(run("fsck_ext2fs",check)==8 && access(logpath,F_OK)!=0);
 for(i=0;i<3;i++){setenv("TOOL_MOUNT",i==0?"fail":i==1?"broken":"relative",1);CHECK(ext2_device_is_mounted("/private/dev/hd1a")==-1);CHECK(run("newfs_ext2fs",format)==8 && access(logpath,F_OK)!=0);CHECK(run("fsck_ext2fs",check)==8 && access(logpath,F_OK)!=0);CHECK(run("ext2fs.util",repair)==(FSUR_IO_FAIL&255) && access(logpath,F_OK)!=0);CHECK(run("ext2fs.util",init)==(FSUR_IO_FAIL&255) && access(logpath,F_OK)!=0);}
 {const char *pseudo[]={"pseudo-volfs","pseudo-fdesc","pseudo-kernfs"};
 for(i=0;i<3;i++){setenv("TOOL_MOUNT",pseudo[i],1);CHECK(ext2_device_is_mounted(image)==0);CHECK(run("newfs_ext2fs",format)==0 && logged("-F"));CHECK(run("fsck_ext2fs",check)==0 && logged("-n"));}}
 setenv("TOOL_MOUNT","pseudo-unknown",1);CHECK(ext2_device_is_mounted(image)==-1);CHECK(run("newfs_ext2fs",format)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT","pseudo-mismatch",1);CHECK(ext2_device_is_mounted(image)==-1);CHECK(run("fsck_ext2fs",check)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT","pseudo-absolute",1);CHECK(ext2_device_is_mounted("/private/dev/rhd1a")==1);CHECK(run("newfs_ext2fs",deviceformat)==8 && access(logpath,F_OK)!=0);
 setenv("TOOL_MOUNT","safe",1);
 for(i=0;i<sizeof(statuses)/sizeof(statuses[0]);i++){int s=statuses[i],expected=(s & ~7)?FSUR_IO_FAIL:(s&4)?FSUR_IO_UNCLEAN:FSUR_IO_SUCCESS;sprintf(val,"%d",s);setenv("TOOL_EXIT",val,1);CHECK(run("ext2fs.util",repair)==(expected&255));CHECK(logged("-p")&&logged(rawpath));}
 unsetenv("TOOL_EXIT");CHECK(run("ext2fs.util",init)==(FSUR_IO_SUCCESS&255) && logged(rawpath));
 CHECK(run("ext2fs.util",mount)==(FSUR_IO_SUCCESS&255) && logged("ro") && logged(mount[3]) && logged("ext2fs"));
 CHECK(run("ext2fs.util",unmount)==(FSUR_IO_SUCCESS&255) && logged(unmount[3]));CHECK(run("ext2fs.util",force)==(FSUR_INVAL&255) && access(logpath,F_OK)!=0);
 CHECK(run("ext2fs.util",probe)==(FSUR_RECOGNIZED&255));
 probe[1]="-P";probe[4]=NULL;CHECK(run("ext2fs.util",probe)==(FSUR_INITRECOGNIZED&255));probe[1]="-p";probe[4]="readonly";
 fixture("dirty",2,0);mount[5]="writable";CHECK(run("ext2fs.util",mount)==(FSUR_IO_UNCLEAN&255) && access(logpath,F_OK)!=0);mount[5]="readonly";CHECK(run("ext2fs.util",mount)==(FSUR_IO_SUCCESS&255) && logged("ro"));
 CHECK(ext2_mount_probe(image,0)==FSUR_IO_UNCLEAN);CHECK(ext2_mount_probe(image,1)==FSUR_RECOGNIZED);
 setenv("TOOL_SIGNAL","1",1);CHECK(run("ext2fs.util",repair)==(FSUR_IO_FAIL&255));unsetenv("TOOL_SIGNAL");
 setenv("TOOL_MOUNT",image,1);CHECK(run("ext2fs.util",repair)==(FSUR_IO_FAIL&255) && access(logpath,F_OK)!=0);CHECK(run("ext2fs.util",init)==(FSUR_IO_FAIL&255) && access(logpath,F_OK)!=0);setenv("TOOL_MOUNT","safe",1);
 memset(huge,'x',sizeof(huge)-1);huge[sizeof(huge)-1]=0;probe[2]=huge;CHECK(run("ext2fs.util",probe)==(FSUR_INVAL&255));
 printf("tool cases=%d failures=%d\n",cases,failures);return failures?1:0;
}
