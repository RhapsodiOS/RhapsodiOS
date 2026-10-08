/* Native ABI test: real ext2 traversal and real shared UFS path geometry.
 * Only the buffer/device boundary is supplied here, including short I/O. */
#include "../ext2fs_extern.h"
extern void exit(int);
volatile void panic(const char *message,...) { printf("unexpected panic: %s\n",message); exit(90); }
#define CHECK(x) do { if (!(x)) { printf("bmap_test:%d: %s\n",__LINE__,#x); exit(1); } } while (0)

static struct proc process;
static struct pstats stats;
struct proc *ext2_test_proc(void) { return &process; }

struct vnodeop_desc vop_strategy_desc;
static struct buf buffer;
static u_int32_t pointers[1024];
static int reads, releases, residual;
static daddr_t expected_sector;

struct buf *incore(struct vnode *vp,daddr_t bn) { return NULL; }
struct buf *getblk(struct vnode *vp,daddr_t bn,int size,int slp,int timeo)
{
    memset(&buffer,0,sizeof(buffer));
    buffer.b_vp=vp; buffer.b_un.b_addr=(caddr_t)pointers;
    buffer.b_bcount=size;
    return &buffer;
}
void brelse(struct buf *bp) { CHECK(bp == &buffer); releases++; }
int biowait(struct buf *bp) { return 0; }
static int strategy(void *v)
{
    struct buf *bp=((struct vop_strategy_args *)v)->a_bp;
    CHECK(bp->b_blkno == expected_sector);
    reads++; bp->b_resid=residual; bp->b_flags |= B_DONE;
    return 0;
}

int main(void)
{
    struct ext2fs_node node;
    struct m_ext2fs fs;
    struct vnode vnode;
    struct mount mount;
    struct ufsmount ump;
    struct vop_bmap_args args;
    struct indir path[4];
    int (*ops[1])();
    int levels,run,shift,devshift;
    daddr_t sector;
    memset(&node,0,sizeof(node)); memset(&vnode,0,sizeof(vnode));
    memset(&fs,0,sizeof(fs)); memset(&mount,0,sizeof(mount));
    memset(&ump,0,sizeof(ump)); memset(&args,0,sizeof(args));
    memset(&process,0,sizeof(process)); memset(&stats,0,sizeof(stats));
    process.p_stats=&stats;
    vnode.v_data=&node; vnode.v_tag=VT_EXT2FS; vnode.v_mount=&mount;
    node.inode.i_vnode=&vnode; node.inode.i_e2fs=&fs;
    mount.mnt_data=(qaddr_t)&ump; ump.um_e2fs=&fs; ump.um_mountp=&mount;
    ops[0]=strategy; vnode.v_op=ops; vop_strategy_desc.vdesc_offset=0;
    args.a_vp=&vnode; args.a_bnp=&sector; args.a_runp=&run;
    fs.e2fs.e2fs_bcount=1000;
    for(devshift=9;devshift<=10;devshift++) {
      for(shift=0;shift<3;shift++) {
        fs.e2fs_bsize=1024<<shift; mount.mnt_stat.f_iosize=fs.e2fs_bsize;
        ump.um_nindir=fs.e2fs_bsize/4; ump.um_bptrtodb=shift+10-devshift; ump.um_seqinc=1;
        fs.e2fs_fsbtodb=ump.um_bptrtodb;
        CHECK(ufs_getlbns(&vnode,12,path,&levels) == 0);
        CHECK(levels == 2 && path[0].in_off == 0 && path[1].in_off == 0 && path[1].in_lbn == -12);
        CHECK(ufs_getlbns(&vnode,12+ump.um_nindir,path,&levels) == 0);
        CHECK(levels == 3 && path[0].in_off == 1 && path[1].in_off == 0 && path[2].in_off == 0);
        if(shift == 0) {
            CHECK(ufs_getlbns(&vnode,65804,path,&levels) == 0);
            CHECK(levels == 4 && path[0].in_off == 2 && path[1].in_off == 0 && path[2].in_off == 0 && path[3].in_off == 0);
        }
        args.a_bn=0; CHECK(ext2fs_bmap(&args) == 0 && sector == -1 && reads == 0);
        node.dinode.e2di_blocks[0]=h2fs32(999);
        node.dinode.e2di_blocks[1]=h2fs32(1000);
        CHECK(ext2fs_bmap(&args) == 0 && sector == (999<<(shift+10-devshift)) && run == 0);
        node.dinode.e2di_blocks[1]=0;
        node.dinode.e2di_blocks[0]=h2fs32(1000);
        CHECK(ext2fs_bmap(&args) == EIO && reads == 0);
        node.dinode.e2di_blocks[0]=0;
        args.a_bn=12; node.dinode.e2di_blocks[12]=h2fs32(1000);
        CHECK(ext2fs_bmap(&args) == EIO && reads == 0);
        node.dinode.e2di_blocks[12]=h2fs32(20); expected_sector=20<<(shift+10-devshift);
        memset(pointers,0,sizeof(pointers)); ext2_put_le32(pointers,1000);
        CHECK(ext2fs_bmap(&args) == EIO && reads == 1 && releases == 1);
        reads=releases=0; ext2_put_le32(pointers,21);
        CHECK(ext2fs_bmap(&args) == 0 && sector == (21<<(shift+10-devshift)) && reads == 1 && releases == 1);
        reads=releases=0; ext2_put_le32(pointers,999); ext2_put_le32(pointers+1,1000);
        CHECK(ext2fs_bmap(&args) == 0 && sector == (999<<(shift+10-devshift)) && run == 0 && reads == 1 && releases == 1);
        ext2_put_le32(pointers,21); ext2_put_le32(pointers+1,0);
        reads=releases=0; residual=fs.e2fs_bsize;
        CHECK(ext2fs_bmap(&args) == EIO && reads == 1 && releases == 1);
        reads=releases=residual=0;
        printf("EXT2_OK bmap logical=%d filesystem=%d\n",1<<devshift,fs.e2fs_bsize);
      }
    }
    printf("EXT2_OK bmap bounds, geometry and short I/O\n");
    return 0;
}
