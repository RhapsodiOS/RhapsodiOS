/* Run on an HFS/HFS+ volume: hfs_rename_test /mnt/h */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void
fail(const char *what)
{
    perror(what);
    exit(1);
}

/* Use an external guest watchdog: a kernel vnode deadlock cannot be killed. */
static void
lock_test(void)
{
    pid_t mover;
    struct stat sb;
    int i, status;

    if (mkdir("a", 0700) < 0 || mkdir("a/b", 0700) < 0 ||
        mkdir("a/child", 0700) < 0)
        fail("create lock test directories");
    mover = fork();
    if (mover < 0)
        fail("fork");
    if (mover == 0) {
        for (i = 0; i < 2000; i++) {
            while (rename("a/child", "a/b/child") < 0)
                if (errno != EBUSY)
                    fail("move into descendant parent");
            while (rename("a/b/child", "a/child") < 0)
                if (errno != EBUSY)
                    fail("move into ancestor parent");
        }
        _exit(0);
    }
    for (i = 0; i < 10000; i++)
        if (stat("a/b", &sb) < 0)
            fail("lookup descendant parent");
    if (waitpid(mover, &status, 0) != mover ||
        !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "FAIL: rename worker\n");
        exit(1);
    }
    if (rmdir("a/child") < 0 || rmdir("a/b") < 0 || rmdir("a") < 0)
        fail("cleanup lock test");
    puts("PASS: concurrent rename and descendant lookup completed");
}

int
main(int argc, char **argv)
{
    char dir[1024];
    struct stat old_parent, new_parent, before, after;
    int failed = 0;
    int fd1 = -1, fd2 = -1;

    if (argc != 2 && !(argc == 3 && strcmp(argv[2], "locks") == 0)) {
        fprintf(stderr, "usage: %s hfs-mountpoint [locks]\n", argv[0]);
        return 2;
    }
    if (chdir(argv[1]) < 0)
        fail("chdir mountpoint");
    sprintf(dir, "hfs-rename-%ld", (long)getpid());
    if (mkdir(dir, 0700) < 0 || chdir(dir) < 0)
        fail("create test directory");
    if (argc == 3) {
        lock_test();
        if (chdir("..") < 0 || rmdir(dir) < 0)
            fail("cleanup test directory");
        return 0;
    }
    if (mkdir("old", 0700) < 0 || mkdir("new", 0700) < 0 ||
        mkdir("old/child", 0700) < 0)
        fail("create directories");
    if (stat("old", &old_parent) < 0 || stat("new", &new_parent) < 0 ||
        stat("old/CHILD", &before) < 0 || stat("old/child/..", &after) < 0)
        fail("warm name cache");
    if (after.st_ino != old_parent.st_ino)
        fail("initial parent inode");

    if (rename("old/child", "new/child") < 0)
        fail("rename directory");
    if (stat("old/CHILD", &after) == 0 || errno != ENOENT) {
        fprintf(stderr, "FAIL: old case alias survived directory rename\n");
        failed = 1;
    }
    if (stat("new/child", &after) < 0)
        fail("stat renamed directory");
    if (after.st_ino != before.st_ino) {
        fprintf(stderr, "FAIL: renamed directory inode changed\n");
        failed = 1;
    }
    if (stat("new/child/..", &after) < 0)
        fail("stat renamed parent");
    if (after.st_ino != new_parent.st_ino) {
        fprintf(stderr, "FAIL: cached dotdot survived directory rename\n");
        failed = 1;
    }
    if (mkdir("new/victim", 0700) < 0 ||
        stat("new/victim", &old_parent) < 0 ||
        (fd1 = open("new/victim", O_RDONLY)) < 0 ||
        (fd2 = open("new/victim", O_RDONLY)) < 0)
        fail("hold rename destination open");
    if (rename("new/child", "new/victim") == 0 || errno != EBUSY) {
        fprintf(stderr, "FAIL: replacement of busy directory\n");
        return 1;
    }
    if (stat("new/child", &after) < 0 || after.st_ino != before.st_ino)
        fail("source after busy rename");
    if (stat("new/victim", &after) < 0 || after.st_ino != old_parent.st_ino)
        fail("destination after busy rename");
    if (close(fd1) < 0 || close(fd2) < 0 ||
        rename("new/child", "new/victim") < 0)
        fail("replace directory after busy rename");
    if (stat("new/victim", &after) < 0 || after.st_ino != before.st_ino)
        fail("replacement directory inode");
    if (rmdir("new/victim") < 0 || rmdir("new") < 0 ||
        rmdir("old") < 0 || chdir("..") < 0 || rmdir(dir) < 0)
        fail("cleanup");
    if (!failed)
        puts("PASS: directory rename invalidates aliases and dotdot");
    return failed;
}
