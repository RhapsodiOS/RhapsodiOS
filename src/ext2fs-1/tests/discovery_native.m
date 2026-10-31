/* Native discovery against the actual driver-exposed candidate and helpers. */
#import <libc.h>
#import <objc/Object.h>
#import <objc/List.h>
#import <mach/boolean.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#ifndef DISCOVERY_HEADER
#error Define DISCOVERY_HEADER to the production DiskVolume.h
#endif
#include DISCOVERY_HEADER
@interface DiskVolumes (DiscoveryCount)
- (unsigned)count;
@end
int main(int argc,char **argv) {
    DiskVolumes *volumes;DiskVolume *disk=nil;unsigned i;int found=0,result=0;
    if(argc!=4) {fprintf(stderr,"usage: discovery-native expected-type mount-result label\n");return 2;}
    volumes=[[DiskVolumes alloc] init:TRUE Eject:FALSE];
    if(!volumes)return 1;
    for(i=0;i<[volumes count];i++) {
        DiskVolume *one=[volumes objectAt:i];
        if(!strcmp(one->dev_name,"hd1a")) {disk=one;found++;}
    }
    if(!strcmp(argv[1],"none"))result=found!=0;
    else {
        result=found!=1 || !disk || strcmp(disk->fs_type,argv[1]) || strcmp(disk->disk_name,argv[3]);
        if(!result && strcmp(argv[2],"skip")) {
            if(![volumes setVolumeMountPoint:disk])result=1;
            if(!result)result=[disk mount] != atoi(argv[2]);
            if(disk->mounted && unmount(disk->mount_point,0)<0)result=1;
            if(disk->mount_point && rmdir(disk->mount_point)<0)result=1;
        }
    }
    printf("DISCOVERY_NATIVE expected=%s found=%d mount=%s result=%d\n",argv[1],found,argv[2],result);
    [volumes free];return result;
}
