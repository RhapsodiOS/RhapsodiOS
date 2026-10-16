/* Compile with the extracted msdosfs_pageout body, using a write boundary
 * that records the size actually submitted to the filesystem. */
#include <stdio.h>
#include <string.h>
#define MACH_NBC 1
#define EINVAL 22
#define VREG 1
#define off_t fixture_off_t
typedef long long off_t;
struct vm_info { unsigned long vnode_size; int mapped; };
struct denode { unsigned long de_FileSize; };
struct vnode { struct vm_info *v_vm_info; struct denode *v_data; int v_type; };
struct uio { off_t uio_offset; int uio_resid; };
struct ucred { int unused; };
struct vop_pageout_args {
    struct vnode *a_vp;
    struct uio *a_uio;
    int a_ioflag;
    struct ucred *a_cred;
};
#define VTODE(vp) ((vp)->v_data)
static int calls, submitted, write_error;
static void vnode_pager_setsize(struct vnode *vp, unsigned long size)
{
    if (vp->v_vm_info) vp->v_vm_info->vnode_size = size;
}
static int test_write(struct vnode *vp, struct uio *uio, int flags,
    struct ucred *cred)
{
    struct denode *dep = vp->v_data;
    int n = uio->uio_resid;
    calls++;
    submitted = uio->uio_resid;
    if (write_error) return write_error;
    /* BODY write growth */
    uio->uio_offset += uio->uio_resid;
    uio->uio_resid = 0;
    return 0;
}
#define VOP_WRITE test_write
/* BODY msdosfs_pageout */
static int failures;
#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s\n", __LINE__, #x); failures++; } } while (0)
static void run(unsigned long disk, unsigned long cached, off_t offset,
    int count, int expected_calls, int expected_count, unsigned long size)
{
    struct denode de = { disk };
    struct vm_info vm = { cached, 1 };
    struct vnode vp = { &vm, &de, VREG };
    struct uio uio = { offset, count };
    struct vop_pageout_args args = { &vp, &uio, 0, 0 };
    calls = submitted = 0;
    CHECK(msdosfs_pageout(&args) == write_error);
    CHECK(calls == expected_calls);
    CHECK(submitted == expected_count);
    CHECK(de.de_FileSize == size);
    CHECK(vm.vnode_size == cached);
}
int main(void)
{
    /* Pager selected these pages before ftruncate acquired the vnode. */
    run(20480, 20480, 28672, 4096, 0, 0, 20480);
    run(20480, 20480, 20480, 4096, 0, 0, 20480);
    run(20517, 20517, 20480, 4096, 1, 37, 20517);
    /* MapFS can legitimately have grown ahead of the on-disk denode. */
    run(8192, 65536, 32768, 4096, 1, 4096, 36864);
    run(65536, 65536, 0, 4096, 1, 4096, 65536);
    write_error = 5;
    run(20517, 20517, 20480, 4096, 1, 37, 20517);
    printf("msdosfs pageout failures=%d\n", failures);
    return failures != 0;
}
