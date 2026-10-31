/* Native regression for the logical-partition capacity ABI. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"line%d: %s errno%d\n",__LINE__,#x,errno); return 1; } } while (0)
int main(int argc,char **argv)
{
    struct disk_partition_info info;
    int fd,i,old_size,old_count;
    unsigned size,count,legacy_size,legacy_count;
    CHECK(sizeof(info)==8);
    CHECK(argc==11);
    size=strtoul(argv[7],NULL,10); count=strtoul(argv[8],NULL,10);
    legacy_size=strtoul(argv[9],NULL,10); legacy_count=strtoul(argv[10],NULL,10);
    for(i=1;i<=2;i++) {
        CHECK((fd=open(argv[i],O_RDONLY))>=0);
        CHECK(ioctl(fd,DKIOCBLKSIZE,&old_size)==0);
        CHECK(ioctl(fd,DKIOCNUMBLKS,&old_count)==0);
        CHECK(old_size==legacy_size && old_count==legacy_count);
        CHECK(ioctl(fd,DKIOCGPARTINFO,&info)==0);
        CHECK(info.block_size==size && info.block_count==count);
        printf("capacity %s %u*%u legacy%d*%d\n",argv[i],info.block_size,info.block_count,old_size,old_count);
        CHECK(close(fd)==0);
    }
    /* live, unavailable, equal-to-drive and oversized logical partitions */
    for(i=3;i<=6;i++) {
        fd=open(argv[i],O_RDONLY);
        if(fd>=0) {
            errno=0; CHECK(ioctl(fd,DKIOCGPARTINFO,&info)==-1);
            CHECK(errno==ENXIO || errno==EINVAL || errno==ENOTTY);
            CHECK(close(fd)==0);
        } else {
            CHECK(i==4); /* Only the deliberately unavailable node may fail open. */
            CHECK(errno==ENXIO || errno==ENOENT || errno==EIO);
        }
    }
    puts("EXT2_OK capacity");return 0;
}
