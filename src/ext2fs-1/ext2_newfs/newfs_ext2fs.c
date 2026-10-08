/* Supported-profile formatter; labels are argv data, never shell text. */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "ext2_tool.h"
static int number(const char *s,unsigned long maximum,int nonzero) {
    unsigned long n=0;
    if(!s || !*s)return 0;
    while(*s) {if(*s<'0'||*s>'9'||n>(maximum-(*s-'0'))/10)return 0;n=n*10+*s++-'0';}
    return !nonzero || n!=0;
}
int main(int argc,char **argv) {
    char *block="1024",*label=NULL,*reserved="5",*args[24];
    struct stat st;
    int c,n=0,mounted;
    while((c=getopt(argc,argv,"b:L:m:"))!=-1) {
        if(c=='b')block=optarg;
        else if(c=='L')label=optarg;
        else if(c=='m')reserved=optarg;
        else goto usage;
    }
    if((argc-optind!=1 && argc-optind!=2) ||
        (strcmp(block,"1024") && strcmp(block,"2048") && strcmp(block,"4096")) ||
        (label && strlen(label)>16) || !number(reserved,50,0) ||
        strlen(argv[optind])>=MAXPATHLEN ||
        (argc-optind==2 && !number(argv[optind+1],2147483647UL,1))) goto usage;
    mounted=ext2_device_is_mounted(argv[optind]);
    if(mounted!=0) {fprintf(stderr,"newfs_ext2fs: target mounted or inspection failed: %s\n",argv[optind]);return 8;}
    if(ext2_format_size(argv[optind],(unsigned int)strtoul(block,NULL,10),argc-optind==2?strtoul(argv[optind+1],NULL,10):0)!=0) {fprintf(stderr,"newfs_ext2fs: unsupported or insufficient target capacity: %s\n",argv[optind]);return 8;}
    args[n++]=EXT2_MKE2FS;args[n++]="-r";args[n++]="1";args[n++]="-I";args[n++]="128";
    args[n++]="-b";args[n++]=block;args[n++]="-m";args[n++]=reserved;
    args[n++]="-O";args[n++]="filetype,sparse_super";
    if(label) {args[n++]="-L";args[n++]=label;}
    if(stat(argv[optind],&st)==0 && (S_ISREG(st.st_mode) || S_ISCHR(st.st_mode)))args[n++]="-F";
    args[n++]="--";args[n++]=argv[optind];
    if(argc-optind==2)args[n++]=argv[optind+1];
    args[n]=NULL;return ext2_run_tool(EXT2_MKE2FS,args);
usage:
    fprintf(stderr,"usage: newfs_ext2fs [-b 1024|2048|4096] [-L label] [-m percent] special [blocks]\n");return 16;
}
