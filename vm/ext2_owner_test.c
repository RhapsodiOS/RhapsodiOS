/* Native create/mkdir bodies. VALLOC stops at the first mutation boundary.
 * Import check is the exact post-load vget admission condition. */
#include "ext2fs_extern.h"
#include "ext2fs_dir.h"
enum vtype iftovt_tab[16]={VNON,VFIFO,VCHR,VNON,VDIR,VNON,VBLK,VNON,VREG,VNON,VLNK,VNON,VSOCK,VNON,VNON,VBAD};
extern void exit(int);
volatile void panic(const char *s,...){printf("PANIC %s\n",s);exit(90);}
static int cases,failures,allocated,released,freed;
#define CHECK(x) do{cases++;if(!(x)){failures++;printf("FAIL %d: %s\n",__LINE__,#x);}}while(0)
static int wave_valloc(struct vnode *v,int m,struct ucred *c,struct vnode **out){allocated++;return ENOSPC;}
static void wave_vput(struct vnode *v){released++;}
static int wave_group(gid_t g,struct ucred *c){return 1;}
static int wave_super(struct ucred *c,u_short *f){return 0;}
#undef VOP_VALLOC
#undef VOP_UPDATE
#undef _FREE_ZONE
#define VOP_VALLOC(v,m,c,o) wave_valloc(v,m,c,o)
#define VOP_UPDATE(v,a,m,w) 0
#define _FREE_ZONE(p,n,k) (freed++)
#define vput wave_vput
#define groupmember wave_group
#define suser wave_super
#define ext2fs_direnter(i,v,c) 0
#define vn_rdwr(r,v,b,l,o,s,f,c,x,p) 0
/* BODY ext2fs_makeinode */
/* BODY ext2fs_mkdir */
static int import_refused(struct inode *ip,int allocating){return /* IMPORT CONDITION */;}
int main(void){struct ext2fs_node parent,node;struct vnode vp,*out;struct componentname cn;struct ucred cr;struct vattr va;struct vop_mkdir_args a;struct ext2fs_dinode disk,saved;int kind,j,status;u_int32_t ids[]={65535,65536,65536+123};
 bzero(&parent,sizeof(parent));bzero(&vp,sizeof(vp));bzero(&cn,sizeof(cn));bzero(&cr,sizeof(cr));bzero(&va,sizeof(va));bzero(&a,sizeof(a));vp.v_tag=VT_EXT2FS;vp.v_data=&parent;cn.cn_cred=&cr;cn.cn_flags=HASBUF;parent.inode.i_vnode=&vp;parent.inode.i_gid=456;a.a_dvp=&vp;a.a_vpp=&out;a.a_cnp=&cn;a.a_vap=&va;
 for(kind=0;kind<2;kind++)for(j=0;j<3;j++){
 cr.cr_uid=ids[j];allocated=released=freed=0;out=NULL;
 status=kind?ext2fs_mkdir(&a):ext2fs_makeinode(IFREG|0644,&vp,&out,&cn);
 CHECK(status==(j?EINVAL:ENOSPC));CHECK(allocated==(j?0:1));CHECK(released==1 && freed==1 && out==NULL);CHECK(parent.inode.i_flag==0 && parent.inode.i_nlink==0);
 }
 cr.cr_uid=123;parent.inode.i_gid=65536;allocated=0;CHECK(ext2fs_makeinode(IFREG|0644,&vp,&out,&cn)==EINVAL && allocated==0);allocated=0;CHECK(ext2fs_mkdir(&a)==EINVAL && allocated==0);
 bzero(&node,sizeof(node));node.inode.i_vnode=&vp;vp.v_data=&node;bzero(&disk,sizeof(disk));disk.e2di_mode=h2fs16(IFREG|0644);disk.e2di_nlink=h2fs16(1);disk.e2di_uid=h2fs16(65535);disk.e2di_gid=h2fs16(65535);ext2fs_inode_load(&node.inode,&disk);CHECK(!import_refused(&node.inode,0));ext2fs_inode_save(&node.inode,&saved);CHECK(fs2h16(saved.e2di_uid)==65535 && fs2h16(saved.e2di_gid)==65535);
 disk.e2di_linux_reserved3[0]=h2fs32(1);ext2fs_inode_load(&node.inode,&disk);CHECK(import_refused(&node.inode,0));CHECK(!import_refused(&node.inode,1));
 disk.e2di_linux_reserved3[0]=h2fs32(1U<<16);ext2fs_inode_load(&node.inode,&disk);CHECK(import_refused(&node.inode,0));
 printf("REVIEW_OWNER cases=%d failures=%d\n",cases,failures);return failures?1:0;}
