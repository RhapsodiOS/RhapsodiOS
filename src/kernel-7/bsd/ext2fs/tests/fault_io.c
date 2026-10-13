/* Private native fault kernel only. Never compiled or installed by normal
 * kernel/tool targets. The selected target is a disposable data partition;
 * a different mounted partition supplies the root-only control descriptor. */
#ifndef EXT2FS_TEST_IO
#error fault_io.c requires the private EXT2FS_TEST_IO build
#endif
#include <sys/ioctl.h>
#define EXT2_FAULT_ARM 1
#define EXT2_FAULT_QUERY 2
#define EXT2_FAULT_ANY 0
#define EXT2_FAULT_DIRTY 1
#define EXT2_FAULT_CLEAN 2
#define EXT2_FAULT_INODE 3
#define EXT2_FAULT_DATA 4
#define EXT2_FAULT_SHORT 5
#define EXT2_FAULT_CLOSE 6
#define EXT2_FAULT_REWRITE 7
#define EXT2_FAULT_INDIR_ERROR 8
#define EXT2_FAULT_INDIR_SHORT 9
#define EXT2_FAULT_TAIL_ERROR 10
#define EXT2_FAULT_TAIL_SHORT 11
struct ext2_fault_control {
    int op,kind,after,error;
    dev_t target;
    unsigned long ino;
    long block;
    int matched,failed,phase,reads,resid,releases,dirty_writes,flushes,invalidated,release_resid;
};
#define EXT2_FAULT_CTL _IOWR('E',201,struct ext2_fault_control)

#ifdef KERNEL
#undef bwrite
#undef bawrite
#undef brelse
static struct ext2_fault_control ext2_fault;
static struct buf *ext2_short_bp;
static int ext2_fault_phase;

int
ext2_test_ioctl(struct vop_ioctl_args *ap)
{
    struct ext2_fault_control *ctl=(struct ext2_fault_control *)ap->a_data;
    if (ap->a_command != EXT2_FAULT_CTL) return EOPNOTSUPP;
    if (ap->a_cred->cr_uid != 0) return EPERM;
    if (ctl->op == EXT2_FAULT_QUERY) { *ctl=ext2_fault; return 0; }
    if (ctl->op != EXT2_FAULT_ARM || ctl->after < 1 || ctl->error < 1 ||
        ctl->kind < EXT2_FAULT_ANY || ctl->kind > EXT2_FAULT_TAIL_SHORT ||
        major(ctl->target) != 3 || minor(ctl->target) < 8 ||
        minor(ctl->target) > 13 || ctl->target == VTOI(ap->a_vp)->i_dev)
        return EINVAL;
    ext2_fault=*ctl;
    ext2_fault.matched=ext2_fault.failed=ext2_fault.reads=0;
    ext2_fault.resid=ext2_fault.releases=0;
    ext2_fault.invalidated=ext2_fault.release_resid=0;
    ext2_fault.dirty_writes=ext2_fault.flushes=0; ext2_short_bp=NULL;
    printf("EXT2_FAULT arm target=%x kind=%d after=%d errno=%d ino=%lu block=%ld\n",
        ctl->target,ctl->kind,ctl->after,ctl->error,ctl->ino,ctl->block);
    return 0;
}

static int
ext2_test_match(dev_t dev,long block,int kind)
{
    if (dev != ext2_fault.target ||
        (ext2_fault.failed && ext2_fault.kind != EXT2_FAULT_REWRITE) ||
        kind != ext2_fault.kind) return 0;
    ext2_fault.matched++;
    if (ext2_fault.matched < ext2_fault.after) return 0;
    ext2_fault.failed++; ext2_fault.block=block;
    ext2_fault.phase=ext2_fault_phase;
    printf("EXT2_FAULT fired target=%x kind=%d matched=%d block=%ld phase=%d errno=%d no-write=1\n",
        dev,kind,ext2_fault.matched,block,ext2_fault.phase,ext2_fault.error);
    return ext2_fault.error;
}

int
ext2_test_write_error(struct buf *bp)
{
    int kind=EXT2_FAULT_ANY;
    dev_t dev;
    struct vnode *vp=bp->b_vp;
    if (!vp) return 0;
    dev=vp->v_type == VBLK ? vp->v_rdev : VTOI(vp)->i_dev;
    if (dev != ext2_fault.target) return 0;
    if (ext2_fault.failed && vp->v_type == VBLK && bp->b_blkno == 2 &&
        bp->b_bcount == 1024 && ext2_get_le16((u_char *)bp->b_data+56) == E2FS_MAGIC &&
        !(ext2_get_le16((u_char *)bp->b_data+58)&E2FS_ISCLEAN))
        ext2_fault.dirty_writes++;
    if (ext2_fault.kind == EXT2_FAULT_DATA) {
        if (vp->v_tag != VT_EXT2FS || vp->v_type != VREG ||
            VTOI(vp)->i_number != ext2_fault.ino) return 0;
        kind=EXT2_FAULT_DATA;
    } else if (ext2_fault.kind == EXT2_FAULT_INODE) {
        if (vp->v_type != VBLK || bp->b_blkno != ext2_fault.block) return 0;
        kind=EXT2_FAULT_INODE;
    } else if (ext2_fault.kind == EXT2_FAULT_DIRTY || ext2_fault.kind == EXT2_FAULT_CLEAN || ext2_fault.kind == EXT2_FAULT_REWRITE) {
        if (vp->v_type != VBLK || bp->b_blkno != 2 || bp->b_bcount != 1024 ||
            ext2_get_le16((u_char *)bp->b_data+56) != E2FS_MAGIC) return 0;
        kind=(ext2_get_le16((u_char *)bp->b_data+58)&E2FS_ISCLEAN) ? EXT2_FAULT_CLEAN : EXT2_FAULT_DIRTY;
        if (ext2_fault.kind == EXT2_FAULT_REWRITE) {
            if (kind == EXT2_FAULT_DIRTY && !ext2_fault.failed) return 0;
            kind=EXT2_FAULT_REWRITE;
        }
    } else if (ext2_fault.kind != EXT2_FAULT_ANY) return 0;
    return ext2_test_match(dev,bp->b_blkno,kind);
}

/* Baseline wrappers inject the same no-write error without adding a latch or
 * changing successful scheduling. A failed async submission has no caller
 * return value, exactly the old path whose loss is under test. */
int
ext2_test_bwrite(struct buf *bp)
{
    int error=ext2_test_write_error(bp);
    if (!error) return bwrite(bp);
    bp->b_flags |= B_ERROR; bp->b_error=error; brelse(bp); return error;
}
void
ext2_test_bawrite(struct buf *bp)
{
    int error=ext2_test_write_error(bp);
    if (!error) { bawrite(bp); return; }
    bp->b_flags |= B_ERROR; bp->b_error=error; brelse(bp);
}

/* Inject only after the real selected inode bread succeeded. */
void
ext2_test_inode_read(struct vnode *devvp,ino_t ino,struct buf *bp,int error)
{
    if (error || ino != ext2_fault.ino || ext2_fault.kind != EXT2_FAULT_SHORT ||
        devvp->v_rdev != ext2_fault.target) return;
    ext2_fault.reads++;
    if (ext2_test_match(devvp->v_rdev,bp->b_blkno,EXT2_FAULT_SHORT)) {
        bp->b_resid=1; ext2_fault.resid=1; ext2_short_bp=bp;
        printf("EXT2_FAULT successful inode bread ino=%lu resid=1\n",(u_long)ino);
    }
}
/* Private call sites follow real biowait/bread completion. Error mode models
 * a failed completion; short mode models a successful return with residual.
 * Selection occurs before counting, so unrelated inode/device reads are inert. */
int
ext2_test_truncate_read(struct vnode *vp,struct buf *bp,int error,int indirect)
{
    int kind=ext2_fault.kind, saved, injected;
    if (error || VTOI(vp)->i_dev != ext2_fault.target ||
        VTOI(vp)->i_number != ext2_fault.ino || ext2_fault.failed) return error;
    if (indirect ? (kind != EXT2_FAULT_INDIR_ERROR && kind != EXT2_FAULT_INDIR_SHORT) :
        (kind != EXT2_FAULT_TAIL_ERROR && kind != EXT2_FAULT_TAIL_SHORT)) return error;
    ext2_fault.reads++;
    saved=ext2_fault_phase; ext2_fault_phase=indirect ? 4 : 5;
    injected=ext2_test_match(VTOI(vp)->i_dev,bp->b_blkno,kind);
    ext2_fault_phase=saved;
    if (!injected) return error;
    ext2_short_bp=bp;
    if (kind == EXT2_FAULT_INDIR_SHORT || kind == EXT2_FAULT_TAIL_SHORT) {
        bp->b_resid=1; ext2_fault.resid=1;
    } else { bp->b_flags |= B_ERROR; bp->b_error=injected; error=injected; }
    printf("EXT2_FAULT truncate read site=%d ino=%lu block=%ld return=%d resid=%d\n",
        indirect,(u_long)VTOI(vp)->i_number,(long)bp->b_blkno,error,(int)bp->b_resid);
    return error;
}
void
ext2_test_brelse(struct buf *bp)
{
    if (bp == ext2_short_bp) {
        ext2_fault.releases++;
        ext2_fault.invalidated=!!(bp->b_flags&B_INVAL);
        ext2_fault.release_resid=bp->b_resid;
        ext2_short_bp=NULL;
    }
    brelse(bp);
}
int
ext2_test_close_error(struct vnode *devvp)
{
    return ext2_test_match(devvp->v_rdev,-1,EXT2_FAULT_CLOSE);
}
int
ext2_test_dev_fsync(struct vnode *vp,struct proc *p)
{
    int error=VOP_FSYNC(vp,p->p_ucred,MNT_WAIT,p);
    if (!error && vp->v_rdev == ext2_fault.target && ext2_fault.failed)
        ext2_fault.flushes++;
    return error;
}
int
ext2_test_fsync(struct vop_fsync_args *ap)
{
    int error;
    ext2_fault_phase=2;
    error=ext2fs_fsync(ap);
    ext2_fault_phase=0;
    return error;
}
#endif
