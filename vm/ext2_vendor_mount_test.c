/* Actual vendor helper and both destructive callers; native ABI providers.
 * No filesystem or device I/O: all inspection results are deterministic. */
#include "e2fsck.h"
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <setjmp.h>
#include <errno.h>
static struct statfs mounts;
static int scenario,table_error,forced_error,failures,cases;
static jmp_buf escape;
#define CHECK(x) do{cases++;if(!(x)){failures++;printf("FAIL %d scenario=%d: %s\n",__LINE__,scenario,#x);}}while(0)
static int wave_stat(const char *p,struct stat *s){memset(s,0,sizeof(*s));if(strstr(p,"removed")||strstr(p,"loop")){errno=ENOENT;return -1;}s->st_mode=strstr(p,"regular")?S_IFREG:strstr(p,"rdisk")?S_IFCHR:S_IFBLK;s->st_rdev=S_ISCHR(s->st_mode)?900:100;if(strstr(p,"other"))s->st_rdev++;s->st_dev=7;s->st_ino=8;return 0;}
static char *wave_realpath(const char *p,char *r){strcpy(r,p);return r;}
static int wave_getmntinfo(struct statfs **p,int f){*p=&mounts;errno=EIO;return table_error?0:1;}
#define stat(p,s) wave_stat(p,s)
#define realpath wave_realpath
#define getmntinfo wave_getmntinfo
/* HELPER */
static errcode_t wave_check(const char *p,int *flags){*flags=0;return forced_error?EIO:check_getmntinfo(p,flags,NULL,0);}
static void wave_com_err(const char *who,errcode_t error,const char *fmt,...){}
static void wave_fatal(e2fsck_t ctx,const char *message){longjmp(escape,1);}
static void wave_exit(int status){longjmp(escape,status?1:2);}
static int wave_ask(const char *s,int d){return 1;}
#define ext2fs_check_if_mounted wave_check
#define com_err wave_com_err
#define fatal_error wave_fatal
#define exit wave_exit
#define ask_yn wave_ask
/* CHECKER */
/* FORMATTER */
int main(void){struct e2fsck_struct ctx;int flags,result,stopped;const char *source[]={"/dev/disk0a","/tmp/removed","disk0a","/tmp/blocknode","/tmp/loop","/dev/other","/dev/disk0a","/dev/disk0a"};
 for(scenario=0;scenario<8;scenario++){
 memset(&mounts,0,sizeof(mounts));strcpy(mounts.f_mntfromname,source[scenario]);strcpy(mounts.f_mntonname,"/mnt");strcpy(mounts.f_fstypename,"ext2");table_error=scenario==6;forced_error=scenario==7;
 result=wave_check("/dev/rdisk0a",&flags);
 CHECK(scenario==5 ? (!result && !flags) : scenario==0||scenario==3 ? (!result && (flags&EXT2_MF_MOUNTED)) : result!=0);
 memset(&ctx,0,sizeof(ctx));ctx.filesystem_name="/dev/rdisk0a";
 stopped=setjmp(escape);if(!stopped)checker_decision(&ctx);CHECK(!!stopped==(scenario!=5));
 ctx.options=E2F_OPT_READONLY;stopped=setjmp(escape);if(!stopped)checker_decision(&ctx);CHECK(!stopped);
 stopped=setjmp(escape);if(!stopped)formatter_decision("/dev/rdisk0a",0,"ext2");CHECK(!!stopped==(scenario!=5));
 stopped=setjmp(escape);if(!stopped)formatter_decision("/dev/rdisk0a",1,"ext2");CHECK(!stopped);
 }
 scenario=0;table_error=forced_error=0;strcpy(mounts.f_mntfromname,"/dev/disk0a");memset(&ctx,0,sizeof(ctx));ctx.filesystem_name="/dev/rdisk0a";ctx.interactive=1;stopped=setjmp(escape);if(!stopped)checker_decision(&ctx);CHECK(!stopped);
 printf("REVIEW_VENDOR_MOUNT cases=%d failures=%d\n",cases,failures);return failures?1:0;}
