/* Exercise production ismounted.c with a controlled mount table and real
 * native stat/realpath calls. Never open, mount or format a device. Compile
 * ismounted.c with -Dgetmntinfo=task6_getmntinfo; not installed.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <ext2fs/ext2fs.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

static struct statfs table;
static int table_error, failures, cases;

int task6_getmntinfo(struct statfs **result, int flags)
{
    (void)flags;
    *result = &table;
    errno = table_error;
    return table_error ? 0 : 1;
}

static void check(const char *name, const char *source, const char *target,
                  const char *mountpoint, int readonly, int expected,
                  int error, int length)
{
    struct statfs saved;
    char output[16];
    int flags = -1;
    errcode_t result;
    memset(&table, 0, sizeof(table));
    strncpy(table.f_mntfromname, source, sizeof(table.f_mntfromname) - 1);
    strncpy(table.f_mntonname, mountpoint, sizeof(table.f_mntonname) - 1);
    table.f_flags = readonly ? MNT_RDONLY : 0;
    saved = table;
    memset(output, 'X', sizeof(output));
    alarm(5);
    result = ext2fs_check_mount_point(target, &flags, output, length);
    alarm(0);
    cases++;
    if (result != error || flags != expected ||
        memcmp(&table, &saved, sizeof(table)) ||
        (length > 0 && ((!expected && output[0]) ||
          (expected && strncmp(output, mountpoint, length - 1)) ||
          (expected && output[length - 1]))) ||
        output[length] != 'X') {
        printf("FAIL %s result=%ld flags=%x expected=%x error=%d\n",
               name, (long)result, flags, expected, error);
        failures++;
    } else printf("PASS %s\n", name);
}

int main(int argc, char **argv)
{
    char block_alias[MAXPATHLEN], raw_alias[MAXPATHLEN];
    char broken[MAXPATHLEN], loop[MAXPATHLEN], regular[MAXPATHLEN];
    char resolved[MAXPATHLEN];
    int mounted = EXT2_MF_MOUNTED;
    setbuf(stdout, NULL);
    if (argc != 6 || strlen(argv[1]) + 16 >= MAXPATHLEN) return 2;
    sprintf(block_alias, "%s/block", argv[1]);
    sprintf(raw_alias, "%s/raw", argv[1]);
    sprintf(broken, "%s/broken", argv[1]);
    sprintf(loop, "%s/loop", argv[1]);
    sprintf(regular, "%s/regular", argv[1]);
    if (!realpath(argv[3], resolved)) return 2;
    printf("canonical block=%s raw=%s dev-source=%s\n", resolved, argv[4], argv[2]);
    check("direct block", argv[3], argv[3], "/mnt", 0, mounted, 0, 8);
    check("block target alias", argv[3], block_alias, "/mnt", 0, mounted, 0, 8);
    check("canonical raw", argv[3], argv[4], "/mnt", 0, mounted, 0, 8);
    check("raw target alias", argv[3], raw_alias, "/mnt", 0, mounted, 0, 8);
    check("outside source to raw", block_alias, argv[4], "/mnt", 0, mounted, 0, 8);
    check("outside source to raw alias", block_alias, raw_alias, "/mnt", 0, mounted, 0, 8);
    check("device source to raw", argv[2], argv[4], "/mnt", 0, mounted, 0, 8);
    check("device source to raw alias", argv[2], raw_alias, "/mnt", 0, mounted, 0, 8);
    check("private source to raw", argv[5], argv[4], "/mnt", 0, mounted, 0, 8);
    check("raw source identity", raw_alias, argv[4], "/mnt", 0, mounted, 0, 8);
    check("readonly root source alias", block_alias, raw_alias, "/", 1,
          mounted | EXT2_MF_READONLY | EXT2_MF_ISROOT, 0, 8);
    check("bounded mountpoint", block_alias, argv[4], "/long/mount", 0, mounted, 0, 4);
    check("zero mountpoint length", block_alias, argv[4], "/mnt", 0, mounted, 0, 0);
    check("safe unmounted regular", argv[3], regular, "/mnt", 0, 0, 0, 8);
    check("regular identity", regular, regular, "/mnt", 0, mounted, 0, 8);
    check("broken source", broken, argv[4], "/mnt", 0, 0, EIO, 8);
    check("loop source", loop, argv[4], "/mnt", 0, 0, EIO, 8);
    check("missing target", argv[3], broken, "/mnt", 0, 0, ENOENT, 8);
    check("relative source from another cwd", "disk0a", argv[4], "/mnt", 0, 0, EIO, 8);
    table_error = EIO;
    check("mount table failure", argv[3], argv[4], "/mnt", 0, 0, EIO, 8);
    printf("ismounted cases=%d failures=%d\n", cases, failures);
    return failures ? 1 : 0;
}
