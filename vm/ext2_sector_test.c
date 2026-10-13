/* Test providers preserve logical-device block units and buffer outcomes. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stddef.h>
#ifdef _WIN32
typedef unsigned int u_int32_t;
#else
#include <sys/types.h>
#endif
#define NOCRED 0
#define SBOFF 1024
struct vnode { unsigned v_specsize; };
struct ext2fs { unsigned unused; };
struct m_ext2fs { int e2fs_suspended,e2fs_ioerror,e2fs_bshift,e2fs_fsbtodb; struct ext2fs e2fs; };
struct ufsmount { struct vnode *um_devvp; struct m_ext2fs *um_e2fs; };
struct buf { int b_resid; union { void *b_addr; } b_un; void *b_data; };
static struct buf buffer;
static unsigned char bytes[1024];
static int calls,failures,checks,releases,encodes,writes,read_error,residual,write_error,wait_seen;
static unsigned block_seen,length_seen;
static struct vnode *vnode_seen;
#define CHECK(x) do { checks++; if (!(x)) { failures++; printf("FAIL %d: %s\n",__LINE__,#x); } } while(0)
static int bread(struct vnode *vp,unsigned block,size_t length,int cred,struct buf **out) {
 calls++;vnode_seen=vp;block_seen=block;length_seen=length;buffer.b_resid=residual;*out=&buffer;return read_error;
}
static struct buf *getblk(struct vnode *vp,unsigned block,size_t length,int a,int b) {
 calls++;vnode_seen=vp;block_seen=block;length_seen=length;return &buffer;
}
static void brelse(struct buf *bp) { CHECK(bp==&buffer);releases++; }
#ifdef _WIN32
static void bcopy(const void *src,void *out,size_t n) { memcpy(out,src,n); }
#endif
static void ext2_super_encode(const struct ext2fs *fs,void *out) { CHECK(out==bytes);encodes++; }
static int ext2_buf_write(struct buf *bp,int waitfor) { CHECK(bp==&buffer);writes++;wait_seen=waitfor;return write_error; }
static int ext2fs_io_error(struct m_ext2fs *fs,int error) { return error; }
/* PRODUCTION_BODIES */
static void reset(void) { calls=releases=encodes=writes=read_error=residual=write_error=wait_seen=0;block_seen=length_seen=0; }
int main(void) {
 struct vnode vp;struct m_ext2fs fs;struct ufsmount ump;
 unsigned size;int mode,error;unsigned char out[1024];
 unsigned bad_sizes[]={0,256,2048};
 memset(&fs,0,sizeof(fs));memset(bytes,0x5a,sizeof(bytes));buffer.b_un.b_addr=bytes;buffer.b_data=bytes;
 ump.um_devvp=&vp;ump.um_e2fs=&fs;
 for(mode=0;mode<3;mode++) {
  reset();vp.v_specsize=bad_sizes[mode];
  CHECK(ext2fs_device_bshift(&vp,vp.v_specsize)==-1 && calls==0);
  CHECK(ext2fs_read_super_bytes(&vp,1024,out,sizeof(out))==EINVAL && calls==0 && releases==0);
 }
 for(size=512;size<=1024;size*=2) {
  vp.v_specsize=size;fs.e2fs_bshift=10;fs.e2fs_fsbtodb=size==512?1:0;
  reset();CHECK(ext2fs_device_bshift(&vp,size)==(size==512?9:10) && calls==0);
  CHECK(ext2fs_device_bshift(&vp,size==512?1024:512)==-1 && calls==0);
  CHECK(ext2fs_device_bshift(&vp,0)==-1 && calls==0);
  CHECK(ext2fs_device_bshift(&vp,2048)==-1 && calls==0);
  for(mode=0;mode<3;mode++) {
   reset();memset(out,0xa5,sizeof(out));read_error=mode==1?EIO:0;residual=mode==2?1:0;
   error=ext2fs_read_super_bytes(&vp,1024,out,sizeof(out));
   CHECK(error==(mode==1?EIO:mode==2?EINVAL:0));CHECK(calls==1 && releases==1 && vnode_seen==&vp);
   CHECK(block_seen*size==1024 && length_seen==1024);
   CHECK(out[0]==(mode?0xa5:0x5a));
  }
  for(mode=0;mode<2;mode++) {
   reset();write_error=mode?EIO:0;error=ext2fs_sbupdate(&ump,7);
   CHECK(error==write_error);CHECK(calls==1 && encodes==1 && writes==1 && wait_seen==7);
   CHECK(vnode_seen==&vp && block_seen*size==1024 && length_seen==1024);
  }
  reset();fs.e2fs_suspended=1;fs.e2fs_ioerror=EIO;
  CHECK(ext2fs_sbupdate(&ump,7)==EIO && calls==0 && writes==0);fs.e2fs_suspended=0;
 }
 printf("SECTOR_IO_CONTROLS %d FAILURES %d\n",checks,failures);return failures?1:0;
}
