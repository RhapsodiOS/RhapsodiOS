/* Test-only full-superblock mutation on an explicitly disposable partition. */
#include <sys/types.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
int main(int argc,char **argv) {
    unsigned char super[1024];int fd,copy;
    if(argc!=4 || (strcmp(argv[1],"save") && strcmp(argv[1],"restore") &&
       strcmp(argv[1],"dirty") && strcmp(argv[1],"unsupported") && strcmp(argv[1],"malformed")))return 2;
    fd=open(argv[2],!strcmp(argv[1],"save")?O_RDONLY:O_RDWR);if(fd<0)return 1;
    if(lseek(fd,1024,SEEK_SET)!=1024 || read(fd,super,sizeof(super))!=sizeof(super))return 1;
    if(!strcmp(argv[1],"save")) {
        if(super[56]!=0x53 || super[57]!=0xef)return 1;
        copy=open(argv[3],O_WRONLY|O_CREAT|O_EXCL,0600);if(copy<0)return 1;
        if(write(copy,super,sizeof(super))!=sizeof(super) || close(copy)<0)return 1;
    } else {
        copy=open(argv[3],O_RDONLY);if(copy<0)return 1;
        if(read(copy,super,sizeof(super))!=sizeof(super) || close(copy)<0)return 1;
        if(!strcmp(argv[1],"dirty")) {super[58]=0;super[59]=0;}
        if(!strcmp(argv[1],"unsupported"))super[92]=0x20;
        if(!strcmp(argv[1],"malformed")) {super[56]=0;super[57]=0;}
        if(lseek(fd,1024,SEEK_SET)!=1024 || write(fd,super,sizeof(super))!=sizeof(super) || fsync(fd)<0)return 1;
    }
    return close(fd)<0?1:0;
}
