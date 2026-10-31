/* Exact truncation bodies, native ABI, observable strategy/write/free boundary. */
#include "ext2fs_extern.h"
#undef MACH_NBC
#define MACH_NBC 0
#define SINGLE 0
#define DOUBLE 1
#define TRIPLE 2
extern void exit(int);
volatile void panic(const char *m,...){printf("PANIC %s\n",m);exit(90);}
static int cases,failures,reads,writes,frees,unsafe,gets,copy_count,scenario;
static struct proc process;static struct pstats stats;
static struct m_ext2fs fs;
static struct buf wave_buffers[8];static u_int32_t contents[8][1024],copies[8][1024];
#define CHECK(x) do{cases++;if(!(x)){failures++;printf("FAIL %d: %s\n",__LINE__,#x);}}while(0)
static struct proc *wave_proc(void){return &process;}
#define current_proc() wave_proc()
static void *wave_copy(int size){return copies[copy_count++];}
#undef MALLOC
#undef FREE
#define MALLOC(p,t,n,k,f) ((p)=(t)wave_copy(n))
#define FREE(p,k) ((void)0)
static struct buf *wave_getblk(struct vnode *v,daddr_t lbn,int size,int x,int y){struct buf *b=&wave_buffers[gets];bzero(b,sizeof(*b));b->b_data=(caddr_t)contents[gets++];b->b_bcount=b->b_bufsize=size;b->b_lblkno=lbn;return b;}
static int wave_strategy(struct buf *b){
 u_int32_t block=(u_int32_t)b->b_blkno>>fs.e2fs_fsbtodb;
 u_int32_t *p=(u_int32_t *)b->b_data;
 reads++;if(block>=fs.e2fs.e2fs_bcount || block==0)unsafe++;
 bzero(p,fs.e2fs_bsize);
 if(scenario==2)p[1]=h2fs32(100);
 else if(scenario==3)p[1]=h2fs32(0xffffffffU);
 else if((scenario==8 || scenario==9) && block==30)p[1]=h2fs32(100);
 else if(scenario>=6 && block==20)p[0]=h2fs32(30);
 else if(scenario>=12 && block==30)p[0]=h2fs32(40);
 else{p[0]=h2fs32(21);p[1]=h2fs32(22);}
 return 0;
}
static int wave_wait(struct buf *b){return 0;}
static void wave_release(struct buf *b){}
static int wave_write(struct buf *b,int wait){writes++;return 0;}
static void wave_free(struct inode *ip,daddr_t b){frees++;if((u_int32_t)b>=fs.e2fs.e2fs_bcount || b==0)unsafe++;}
static int wave_update(struct vnode *v,struct timeval *a,struct timeval *m,int wait){return 0;}
static void wave_setsize(struct vnode *v,u_long n){}
static int wave_inval(struct vnode *v,int f,struct ucred *c,struct proc *p,int a,int b){return 0;}
static int wave_bmap(struct vnode *v,daddr_t b,struct vnode **out,daddr_t *physical,int *r){*physical=-1;return 0;}
static int wave_bread(struct vnode *v,daddr_t b,int n,struct ucred *c,struct buf **out){unsafe++;return EIO;}
#define getblk wave_getblk
#define biowait wave_wait
#define brelse wave_release
#define ext2_buf_write wave_write
#define ext2fs_blkfree wave_free
#define vnode_pager_setsize wave_setsize
#define vinvalbuf wave_inval
#define bread wave_bread
#undef VOP_STRATEGY
#undef VOP_UPDATE
#undef VOP_BMAP
#define VOP_STRATEGY(b) wave_strategy(b)
#define VOP_UPDATE(v,a,m,w) wave_update(v,a,m,w)
#define VOP_BMAP(v,b,o,p,r) wave_bmap(v,b,o,p,r)
#define splbio() 0
#define splx(s) ((void)(s))
/* BODY ext2fs_io_error */
static int ext2fs_indirtrunc(struct inode *,daddr_t,daddr_t,daddr_t,int,long *);
/* BODY ext2fs_truncate */
/* BODY ext2fs_indirtrunc */
int main(void){struct ext2fs_node node;struct vnode vp;struct mount mp;struct vop_truncate_args a;int device,status,full;u_int32_t root;
 process.p_stats=&stats;
 for(device=9;device<=10;device++)for(scenario=0;scenario<14;scenario++){
 bzero(&node,sizeof(node));bzero(&vp,sizeof(vp));bzero(&mp,sizeof(mp));bzero(&fs,sizeof(fs));bzero(&a,sizeof(a));
 reads=writes=frees=unsafe=gets=copy_count=0;vp.v_tag=VT_EXT2FS;vp.v_type=VREG;vp.v_data=&node;vp.v_mount=&mp;node.inode.i_vnode=&vp;node.inode.i_e2fs=&fs;
 fs.e2fs_bsize=1024;fs.e2fs_bshift=10;fs.e2fs_qbmask=1023;fs.e2fs_fsbtodb=10-device;fs.e2fs.e2fs_bcount=100;node.inode.i_blocks=100;
 full=scenario==5 || scenario==7 || scenario==9 || scenario==10 || scenario==11 || scenario==13;
 node.inode.i_size=(scenario>=12?12+256+65536+2:scenario>=6 && scenario<10?12+256+2:14)*1024;
 a.a_length=full?0:(scenario>=12?12+256+65536+1:scenario>=6 && scenario<10?12+256+1:13)*1024;a.a_vp=&vp;
 root=scenario==0 || scenario==10 || scenario==11?100:scenario==1?0x80000000U:20;
 node.dinode.e2di_blocks[scenario==11?1:scenario>=12?14:scenario>=6 && scenario<10?13:12]=h2fs32(root);
 status=ext2fs_truncate(&a);
 if(scenario<4 || scenario==10 || scenario==11){CHECK(status==EIO);CHECK(unsafe==0 && writes==0 && frees==0);CHECK(reads==(scenario<2 || scenario>=10?0:1));CHECK(fs.e2fs_ioerror==EIO);}
 else if(scenario==8 || scenario==9){CHECK(status==EIO && fs.e2fs_ioerror==EIO);CHECK(unsafe==0 && frees==0);CHECK(reads==2 && writes==(scenario==8?1:0));CHECK(node.inode.i_size==a.a_length);}
 else{CHECK(status==0 && unsafe==0);CHECK(reads==(scenario>=12?3:scenario>=6?2:1));CHECK(frees==(full?(scenario==5?3:scenario==7?4:5):1));CHECK(node.inode.i_size==a.a_length);}
 printf("TRUNC_CASE logical=%d scenario=%d status=%d read=%d write=%d free=%d unsafe=%d\n",1<<device,scenario,status,reads,writes,frees,unsafe);
 }
 printf("REVIEW_TRUNCATE cases=%d failures=%d\n",cases,failures);return failures?1:0;}
