/* Native arithmetic test of production getsize.c; not installed.
 * The existing /dev/null supplies a real character fd. Only the partition
 * query is substituted, so no driver/device node or production hook is added.
 */
#include <sys/types.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <ext2fs/ext2fs.h>
#include <stdarg.h>
#include <stdio.h>
#include <errno.h>

static struct disk_partition_info answer;
static int query_error, failures;

int ioctl(int fd, unsigned long request, ...)
{
    va_list ap;
    struct disk_partition_info *result;
    (void)fd;
    if (request != DKIOCGPARTINFO || query_error) {
        errno = query_error ? query_error : EINVAL;
        return -1;
    }
    va_start(ap, request);
    result = va_arg(ap, struct disk_partition_info *);
    *result = answer;
    va_end(ap);
    return 0;
}

static void check(const char *name, unsigned size, unsigned count,
                  int quantum, int expected_error, blk_t expected_blocks)
{
    blk_t blocks = 123;
    errcode_t error;
    answer.block_size = size;
    answer.block_count = count;
    error = ext2fs_get_device_size("/dev/null", quantum, &blocks);
    if ((expected_error && (!error || blocks != 123)) ||
        (!expected_error && (error || blocks != expected_blocks))) {
        printf("FAIL %s: error=%ld blocks=%lu\n", name, error,
               (unsigned long)blocks);
        failures++;
    } else
        printf("PASS %s\n", name);
}

int main(void)
{
    check("512-byte partition", 512, 10000, 1024, 0, 5000);
    check("1024-byte partition", 1024, 10000, 1024, 0, 10000);
    check("zero sector size refused", 0, 10000, 1024, 1, 0);
    check("zero sector count refused", 512, 0, 1024, 1, 0);
    check("sector size sign bit refused", 0x80000000U, 1, 1024, 1, 0);
    check("sector count sign bit refused", 1024, 0x80000000U, 1024, 1, 0);
    check("blk_t overflow refused", 1024, 0x7fffffffU, 1, 1, 0);
    check("invalid quantum refused", 512, 10000, 0, 1, 0);
    query_error = ENOTTY;
    check("unsupported query refused", 512, 10000, 1024, 1, 0);
    return failures ? 1 : 0;
}
