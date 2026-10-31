/* Native headers are authoritative. Only allocation and buffer I/O are providers. */
#include "ext2fs_extern.h"
#include <string.h>
extern void exit(int);
volatile void panic(const char *message,...){printf("unexpected panic: %s\n",message);exit(90);}
#undef MACH_NBC
#define MACH_NBC 0
static int cases,failures,allocations;
#define CHECK(x) do { cases++;if(!(x)){failures++;printf("FAIL %d: %s\n",__LINE__,#x);} }while(0)
static daddr_t wave_alloccg(struct inode *ip,int cg,daddr_t pref,int size){return 42;}
static u_long wave_hashalloc(struct inode *ip,int cg,long pref,int size,daddr_t (*fn)(struct inode *,int,daddr_t,int)) {allocations++;ip->i_e2fs->e2fs.e2fs_fbcount--;return 42;}
static void wave_fserr(struct m_ext2fs *fs,u_int uid,char *message){}
#define ext2fs_alloccg wave_alloccg
#define ext2fs_hashalloc wave_hashalloc
#define ext2fs_fserr wave_fserr
/* BODY ext2fs_alloc */
static int wave_suser(struct ucred *cr,u_short *flags){return cr->cr_uid?EPERM:0;}
static int wave_groupmember(gid_t gid,struct ucred *cr){return gid==cr->cr_gid;}
#define suser wave_suser
#define groupmember wave_groupmember
/* BODY ext2fs_chown */
static struct buf buffer;
static char bytes[4096];
static int wave_bread(struct vnode *v,daddr_t b,int n,struct ucred *c,struct buf **out){buffer.b_un.b_addr=bytes;buffer.b_resid=0;*out=&buffer;return 0;}
static int wave_breadn(struct vnode *v,daddr_t b,int n,daddr_t *r,int *sizes,int nr,struct ucred *c,struct buf **out){return wave_bread(v,b,n,c,out);}
static void wave_brelse(struct buf *b){}
static int wave_uiomove(caddr_t p,int n,struct uio *u){if(n>u->uio_resid)n=u->uio_resid;u->uio_resid-=n;u->uio_offset+=n;return 0;}
#define bread wave_bread
#define breadn wave_breadn
#define brelse wave_brelse
#define uiomove wave_uiomove
/* BODY ext2fs_read */
static int wave_read(struct vnode *v,struct uio *u,int flags,struct ucred *cr){struct vop_read_args a;memset(&a,0,sizeof(a));a.a_vp=v;a.a_uio=u;a.a_cred=cr;return ext2fs_read(&a);}
#undef VOP_READ
#define VOP_READ(v,u,f,c) wave_read(v,u,f,c)
/* BODY ext2fs_readlink */
int main(void){
 struct ext2fs_node node;struct vnode vp;struct mount mp;struct m_ext2fs fs;struct ucred cr;struct proc proc;
 struct uio u;struct vop_read_args readargs;struct vop_readlink_args linkargs;
 daddr_t block;unsigned free_count;int root,expect,status,readonly;
 memset(&node,0,sizeof(node));memset(&vp,0,sizeof(vp));memset(&mp,0,sizeof(mp));memset(&fs,0,sizeof(fs));memset(&cr,0,sizeof(cr));memset(&proc,0,sizeof(proc));
 vp.v_data=&node;vp.v_tag=VT_EXT2FS;vp.v_mount=&mp;node.inode.i_vnode=&vp;node.inode.i_e2fs=&fs;node.inode.i_number=1;
 fs.e2fs_bsize=1024;fs.e2fs_bshift=10;fs.e2fs_qbmask=1023;fs.e2fs.e2fs_bcount=100;fs.e2fs.e2fs_ipg=16;fs.e2fs.e2fs_rbcount=2;
 CHECK(sizeof(uid_t)==4 && sizeof(gid_t)==4);
 for(root=0;root<=1;root++)for(free_count=0;free_count<=3;free_count++){
  cr.cr_uid=root?0:501;fs.e2fs.e2fs_fbcount=free_count;allocations=0;block=-1;expect=free_count && (root || free_count>2);
  status=ext2fs_alloc(&node.inode,0,0,&cr,&block);
  CHECK(status==(expect?0:ENOSPC));CHECK(allocations==(expect?1:0));CHECK(block==(expect?42:0));
 }
 fs.e2fs.e2fs_fbcount=2;cr.cr_uid=0;CHECK(ext2fs_alloc(&node.inode,0,0,&cr,&block)==0);
 cr.cr_uid=501;allocations=0;CHECK(ext2fs_alloc(&node.inode,1,0,&cr,&block)==ENOSPC && allocations==0);
 cr.cr_uid=0;node.inode.i_uid=123;node.inode.i_gid=456;
 CHECK(ext2fs_chown(&vp,65535,65535,&cr,&proc)==0 && node.inode.i_uid==65535 && node.inode.i_gid==65535);
 node.inode.i_uid=123;node.inode.i_gid=456;node.inode.i_flag=0;
 CHECK(ext2fs_chown(&vp,65536,(gid_t)VNOVAL,&cr,&proc)==EINVAL && node.inode.i_uid==123 && node.inode.i_gid==456 && node.inode.i_flag==0);
 node.inode.i_uid=123;node.inode.i_gid=456;node.inode.i_flag=0;
 CHECK(ext2fs_chown(&vp,(uid_t)VNOVAL,65536+456,&cr,&proc)==EINVAL && node.inode.i_uid==123 && node.inode.i_gid==456 && node.inode.i_flag==0);
 CHECK(ext2fs_chown(&vp,(uid_t)VNOVAL,(gid_t)VNOVAL,&cr,&proc)==0);
 memset(&readargs,0,sizeof(readargs));memset(&linkargs,0,sizeof(linkargs));readargs.a_vp=linkargs.a_vp=&vp;readargs.a_uio=linkargs.a_uio=&u;
 for(readonly=0;readonly<=1;readonly++){
  mp.mnt_flag=readonly?MNT_RDONLY:0;fs.e2fs_ronly=readonly;vp.v_type=VREG;node.inode.i_size=4;node.inode.i_flag=0;
  memset(&u,0,sizeof(u));u.uio_resid=4;u.uio_rw=UIO_READ;
  CHECK(ext2fs_read(&readargs)==0 && u.uio_resid==0);CHECK(!!(node.inode.i_flag&IN_ACCESS)==!readonly);
  vp.v_type=VLNK;node.inode.i_blocks=0;node.inode.i_flag=0;memset(&u,0,sizeof(u));u.uio_resid=4;u.uio_rw=UIO_READ;
  CHECK(ext2fs_readlink(&linkargs)==0 && u.uio_resid==0);CHECK(!!(node.inode.i_flag&IN_ACCESS)==!readonly);
 }
 printf("REVIEW_KERNEL cases=%d failures=%d\n",cases,failures);return failures?1:0;
}
