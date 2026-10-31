/* Native checker wrapper; preserve every upstream exit bit. */
#include <sys/param.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "ext2_tool.h"
int main(int argc,char **argv) {
    char *mode=NULL,*args[9];int c,n=0,force=0,verbose=0;
    while((c=getopt(argc,argv,"nypfv"))!=-1) {
        if(c=='f')force=1;
        else if(c=='v')verbose=1;
        else if(c=='n'||c=='y'||c=='p') {
            char *selected=c=='n'?"-n":c=='y'?"-y":"-p";
            if(mode && strcmp(mode,selected))goto usage;
            mode=selected;
        } else goto usage;
    }
    if(argc-optind!=1 || strlen(argv[optind])>=MAXPATHLEN)goto usage;
    if(ext2_device_is_mounted(argv[optind])!=0) {
        fprintf(stderr,"fsck_ext2fs: target mounted or inspection failed: %s\n",argv[optind]);return 8;
    }
    args[n++]=EXT2_E2FSCK;if(mode)args[n++]=mode;if(force)args[n++]="-f";if(verbose)args[n++]="-v";
    args[n++]="--";args[n++]=argv[optind];args[n]=NULL;return ext2_run_tool(EXT2_E2FSCK,args);
usage:
    fprintf(stderr,"usage: fsck_ext2fs [-n|-y|-p] [-f] [-v] special\n");return 16;
}
