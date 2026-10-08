/* Exact mapfs_io successful-copy boundary; native vnode/inode/uio ABI.
 * The VFS already-mapped route enters this boundary without ext2fs_read. */
#include "ext2fs_extern.h"
static int failures,cases,partial;
#define CHECK(x) do{cases++;if(!(x)){failures++;printf("FAIL %d: %s\n",__LINE__,#x);}}while(0)
static int wave_uiomove(caddr_t p,int n,struct uio *u){if(partial==2)return EFAULT;u->uio_resid-=partial?1:n;return partial?EFAULT:0;}
#define uiomove wave_uiomove
static int copy_boundary(struct vnode *vp,struct uio *uio,int rw){int error,n=4;char bytes[4];caddr_t va=bytes;
/* COPY BOUNDARY */
 return error;}
int main(void){struct ext2fs_node node;struct vnode vp;struct mount mp;struct uio u;int ro,ext2,rw;
 bzero(&node,sizeof(node));bzero(&vp,sizeof(vp));bzero(&mp,sizeof(mp));vp.v_data=&node;vp.v_mount=&mp;
 for(ro=0;ro<=1;ro++)for(ext2=0;ext2<=1;ext2++)for(rw=0;rw<=1;rw++)for(partial=0;partial<3;partial++){
 mp.mnt_flag=ro?MNT_RDONLY:0;vp.v_tag=ext2?VT_EXT2FS:VT_UFS;node.inode.i_flag=0;bzero(&u,sizeof(u));u.uio_resid=4;
 CHECK(copy_boundary(&vp,&u,rw?UIO_WRITE:UIO_READ)==(partial?EFAULT:0));CHECK(!!(node.inode.i_flag&IN_ACCESS)==(EXT2FS&&!ro&&ext2&&!rw&&partial!=2));
 }
 printf("REVIEW_MAPFS_ATIME cases=%d failures=%d\n",cases,failures);return failures?1:0;}
