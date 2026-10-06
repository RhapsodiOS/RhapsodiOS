/* Native production allocator test. Only allocation and buffer I/O are
 * controlled boundaries; block traversal uses the actual UFS geometry. */
#include "../ext2fs_extern.h"
extern void exit(int);
volatile void panic(const char *message,...) { printf("unexpected panic: %s\n",message); exit(90); }
static struct proc process;
struct proc *ext2_test_proc(void) { return &process; }
struct vnodeop_desc vop_strategy_desc;
static struct buf indirect,data;
static u_int32_t pointers[1024];
static char bytes[4096];
static int reads,gets,releases,writes,allocs,frees,short_indirect,short_data,failures;
struct buf *incore(struct vnode *vp,daddr_t bn) { return NULL; }
int biowait(struct buf *bp) { return 0; }
struct buf *getblk(struct vnode *vp,daddr_t bn,int size,int slp,int timeo)
{
    gets++; memset(&data,0,sizeof(data)); data.b_vp=vp;
    data.b_un.b_addr=bytes; data.b_bcount=size; data.b_bufsize=size;
    return &data;
}
int bread(struct vnode *vp,daddr_t bn,int size,struct ucred *cred,struct buf **bpp)
{
    struct buf *bp=bn<0 ? &indirect : &data;
    reads++; memset(bp,0,sizeof(*bp)); bp->b_vp=vp;
    bp->b_un.b_addr=bn<0 ? (caddr_t)pointers : bytes;
    bp->b_bcount=bp->b_bufsize=size;
    bp->b_resid=(bn<0 ? short_indirect : short_data) ? 1 : 0;
    *bpp=bp; return 0;
}
void brelse(struct buf *bp) { releases++; }
int bwrite(struct buf *bp) { writes++; return 0; }
void bdwrite(struct buf *bp) { writes++; }
void bawrite(struct buf *bp) { writes++; }
int ext2fs_alloc(struct inode *ip,daddr_t lbn,daddr_t pref,struct ucred *cred,daddr_t *bn)
{ allocs++; return ENOSPC; }
daddr_t ext2fs_blkpref(struct inode *ip,daddr_t lbn,int index,int32_t *bap) { return 0; }
void ext2fs_blkfree(struct inode *ip,daddr_t bn) { frees++; }
static void check_case(const char *name,int blocksize,int error,struct buf *bp,int expected_reads,int expected_releases)
{
    int ok=error==EIO && bp==NULL && reads==expected_reads && releases==expected_releases && !gets && !writes && !allocs && !frees;
    printf("%s block=%d error=%d bp=%d reads=%d releases=%d getblk=%d writes=%d allocs=%d frees=%d %s\n",name,blocksize,error,bp!=NULL,reads,releases,gets,writes,allocs,frees,ok ? "PASS" : "FAIL");
    if(!ok) failures++;
    reads=gets=releases=writes=allocs=frees=0;
}
int main(void)
{
    struct ext2fs_node node;
    struct m_ext2fs fs;
    struct vnode vp;
    struct mount mp;
    struct ufsmount ump;
    struct ucred cred;
    struct buf *bp;
    int shift,bad,error;
    memset(&node,0,sizeof(node));memset(&fs,0,sizeof(fs));memset(&vp,0,sizeof(vp));
    memset(&mp,0,sizeof(mp));memset(&ump,0,sizeof(ump));memset(&cred,0,sizeof(cred));
    vp.v_data=&node;vp.v_tag=VT_EXT2FS;vp.v_mount=&mp;
    node.inode.i_vnode=&vp;node.inode.i_e2fs=&fs;
    mp.mnt_data=(qaddr_t)&ump;ump.um_e2fs=&fs;ump.um_mountp=&mp;
    fs.e2fs.e2fs_bcount=1000;
    for(shift=0;shift<3;shift++) {
        fs.e2fs_bsize=1024<<shift;fs.e2fs_bshift=10+shift;fs.e2fs_fsbtodb=1+shift;
        mp.mnt_stat.f_iosize=fs.e2fs_bsize;ump.um_nindir=fs.e2fs_bsize/4;
        ump.um_bptrtodb=shift+1;ump.um_seqinc=1;
        node.dinode.e2di_blocks[NDADDR]=h2fs32(20);
        for(bad=1000;bad<=1001;bad++) {
            memset(pointers,0,sizeof(pointers));ext2_put_le32(pointers,bad);
            error=ext2fs_balloc(&node.inode,12,fs.e2fs_bsize,&cred,&bp,0);
            check_case("invalid existing indirect data",fs.e2fs_bsize,error,bp,1,1);
        }
        ext2_put_le32(pointers,21);short_indirect=1;
        error=ext2fs_balloc(&node.inode,12,fs.e2fs_bsize,&cred,&bp,0);
        check_case("short indirect metadata",fs.e2fs_bsize,error,bp,1,1);short_indirect=0;
        short_data=1;node.dinode.e2di_blocks[0]=h2fs32(21);
        error=ext2fs_balloc(&node.inode,0,fs.e2fs_bsize,&cred,&bp,B_CLRBUF);
        check_case("short direct data",fs.e2fs_bsize,error,bp,1,1);
        error=ext2fs_balloc(&node.inode,12,fs.e2fs_bsize,&cred,&bp,B_CLRBUF);
        check_case("short indirect data",fs.e2fs_bsize,error,bp,2,2);short_data=0;
        error=ext2fs_balloc(&node.inode,12,fs.e2fs_bsize,&cred,&bp,0);
        if(error || bp!=&data || reads!=1 || releases!=1 || gets!=1 || writes || allocs || frees || bp->b_blkno!=(21<<(shift+1))) failures++;
        printf("valid existing indirect data block=%d error=%d sector=%ld\n",fs.e2fs_bsize,error,(long)(bp ? bp->b_blkno : -1));
        reads=gets=releases=writes=allocs=frees=0;
    }
    if(failures) return 1;
    printf("EXT2_OK balloc bounds and short I/O\n"); return 0;
}
