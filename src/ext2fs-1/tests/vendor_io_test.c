/* Exercise the actual patched vendor I/O module with private providers. */
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define NO_INLINE_FUNCS
#include <ext2fs/ext2fs.h>
ext2_loff_t observed_seek(int,ext2_loff_t,int);
static ssize_t observed_read(int,void *,size_t);
static ssize_t observed_write(int,const void *,size_t);
#define read observed_read
#define write observed_write
#define ext2fs_llseek observed_seek
#include VENDOR_UNIX_IO
#undef read
#undef write
#undef ext2fs_llseek
static int calls,write_calls,short_call,short_size,read_fail,seek_fail;
static size_t sizes[8];static off_t offsets[8];
static int callback_calls,callback_actual;static errcode_t callback_error;
static int cases,failures;
#define CHECK(x) do {cases++;if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);failures++;}}while(0)
errcode_t ext2fs_get_mem(unsigned long n,void *p) {*(void **)p=malloc(n);return *(void **)p?0:ENOMEM;}
errcode_t ext2fs_free_mem(void *p) {free(*(void **)p);*(void **)p=NULL;return 0;}
ext2_loff_t observed_seek(int fd,ext2_loff_t offset,int whence) {
 if(seek_fail){errno=EIO;return -1;}
 return (ext2_loff_t)lseek(fd,(off_t)offset,whence);
}
static ssize_t observed_read(int fd,void *p,size_t n) {
 ssize_t got;off_t offset=lseek(fd,0,SEEK_CUR);int seq=++calls;
 if(seq<=8){sizes[seq-1]=n;offsets[seq-1]=offset;}
 if(read_fail==seq){errno=EIO;got=-1;}
 else got=read(fd,p,seq==short_call && n>(size_t)short_size?(size_t)short_size:n);
 printf("IO_READ sequence=%d offset=%qd requested=%lu actual=%ld\n",seq,(long long)offset,(unsigned long)n,(long)got);
 return got;
}
static ssize_t observed_write(int fd,const void *p,size_t n) {
 write_calls++;printf("IO_WRITE offset=%qd requested=%lu\n",(long long)lseek(fd,0,SEEK_CUR),(unsigned long)n);
 return write(fd,p,n);
}
static errcode_t on_error(io_channel c,unsigned long block,int count,void *p,size_t n,int actual,errcode_t error) {
 (void)c;(void)p;callback_calls++;callback_actual=actual;callback_error=error;
 printf("READ_ERROR block=%lu count=%d logical=%lu actual=%d error=%ld\n",block,count,(unsigned long)n,actual,(long)error);
 return error;
}
static unsigned char pattern(unsigned n){return (unsigned char)(n*37+11);}
static void reset(void) {calls=write_calls=short_call=short_size=read_fail=seek_fail=callback_calls=callback_actual=callback_error=0;memset(sizes,0,sizeof(sizes));memset(offsets,0,sizeof(offsets));}
static void verify(unsigned char *buffer,int length,int actual) {
 int i,content=1,zero=1,guard=1;
 for(i=0;i<actual;i++)if(buffer[64+i]!=pattern(7168+i))content=0;
 for(i=actual;i<length;i++)if(buffer[64+i]!=0)zero=0;
 for(i=0;i<64;i++)if(buffer[i]!=0xa5 || buffer[64+length+i]!=0xa5)guard=0;
 CHECK(content);CHECK(zero);CHECK(guard);
}
static void prepare(unsigned char *b){memset(b,0xa5,2048);}
int main(int argc,char **argv) {
 unsigned char b[2048],fixture[16384];int i,fd;io_channel c;errcode_t result;
 CHECK(argc==2);if(argc!=2)return 2;
 for(i=0;i<sizeof(fixture);i++)fixture[i]=pattern(i);
 fd=open(argv[1],O_WRONLY|O_CREAT|O_EXCL,0600);CHECK(fd>=0);if(fd<0)return 2;
 CHECK(write(fd,fixture,sizeof(fixture))==sizeof(fixture));CHECK(close(fd)==0);
 CHECK(unix_io_manager->open(argv[1],IO_FLAG_RW,&c)==0);
 CHECK(io_channel_set_blksize(c,1024)==0);c->read_error=on_error;
 reset();prepare(b);result=io_channel_read_blk(c,7,-256,b+64);
 CHECK(result==0);CHECK(calls==1 && offsets[0]==7168 && sizes[0]==512);verify(b,256,256);
 reset();prepare(b);result=io_channel_read_blk(c,7,-768,b+64);
 CHECK(result==0);CHECK(calls==2 && offsets[0]==7168 && offsets[1]==7680 && sizes[0]==512 && sizes[1]==512);verify(b,768,768);
 reset();short_call=1;short_size=129;prepare(b);result=io_channel_read_blk(c,7,-256,b+64);
 CHECK(result==EXT2_ET_SHORT_READ);CHECK(callback_calls==1 && callback_actual==129 && callback_error==result);verify(b,256,129);
 reset();short_call=2;short_size=129;prepare(b);result=io_channel_read_blk(c,7,-768,b+64);
 CHECK(result==EXT2_ET_SHORT_READ);CHECK(callback_calls==1 && callback_actual==641 && callback_error==result);verify(b,768,641);
 reset();short_call=1;short_size=300;prepare(b);result=io_channel_read_blk(c,7,-256,b+64);
 CHECK(result==EXT2_ET_SHORT_READ);CHECK(callback_calls==1 && callback_actual==256 && callback_error==result);verify(b,256,256);
 reset();read_fail=1;prepare(b);result=io_channel_read_blk(c,7,-256,b+64);
 CHECK(result==EXT2_ET_SHORT_READ);CHECK(callback_calls==1 && callback_actual==0);verify(b,256,0);
 reset();read_fail=2;prepare(b);result=io_channel_read_blk(c,7,-768,b+64);
 CHECK(result==EXT2_ET_SHORT_READ);CHECK(callback_calls==1 && callback_actual==512);verify(b,768,512);
 reset();seek_fail=1;prepare(b);result=io_channel_read_blk(c,7,-256,b+64);
 CHECK(result==EIO && calls==0);CHECK(callback_calls==1 && callback_actual==0);verify(b,256,0);
 /* Changed-word superblock writes must use the full-super fallback. */
 reset();CHECK(unix_io_manager->write_byte==NULL);
 if(unix_io_manager->write_byte) {CHECK(io_channel_write_byte(c,1082,2,"XY")==0);CHECK(write_calls==1);}
 CHECK(io_channel_close(c)==0);
 printf("RAW_IO cases=%d failures=%d\n",cases,failures);return failures?1:0;
}
