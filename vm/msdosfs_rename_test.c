/* Run on a disposable mounted FAT volume: msdosfs_rename_test /mnt/m
 * Opposing cross-directory moves plus lookup exercise the lock inversion.
 * Use an external guest watchdog: a vnode deadlock cannot handle SIGALRM. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void fail(const char *op) { perror(op); exit(1); }
static void makefile(const char *name)
{
    int fd = open(name, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) fail(name);
    if (write(fd, "rename", 6) != 6 || close(fd)) fail("write");
}
int main(int argc, char **argv)
{
    char root[80], a[80], b[80];
    struct stat st;
    int i, worker, status, failed = 0;
    pid_t child;
    if (argc != 2) return 2;
    if (chdir(argv[1])) fail("chdir");
    sprintf(root, "r54-%ld", (long)getpid());
    if (mkdir(root, 0700) || chdir(root) || mkdir("left", 0700) ||
        mkdir("right", 0700)) fail("mkdir");
    makefile("left/keep");
    if (rename("left/keep", "right") != -1 ||
        (errno != EISDIR && errno != ENOTDIR))
        fail("file over directory");
    if (stat("left/keep", &st) || st.st_size != 6) fail("source retained");
    if (rename("left", "left/child") != -1) fail("ancestor move");
    if (rename("left/keep", "left/keep")) fail("same vnode");
    if (unlink("left/keep")) fail("unlink");
    for (worker = 0; worker < 4; worker++) {
        child = fork();
        if (child < 0) fail("fork");
        if (child) continue;
        sprintf(a, "%s/w%d", worker & 1 ? "right" : "left", worker);
        sprintf(b, "%s/w%d", worker & 1 ? "left" : "right", worker);
        if (worker < 2) makefile(a);
        else if (mkdir(a, 0700)) fail("worker mkdir");
        for (i = 0; i < 2000; i++) {
            if (rename(a, b) || stat(b, &st) || rename(b, a) || stat(a, &st))
                fail("opposing rename");
            if (stat("left", &st) || stat("right", &st)) fail("lookup");
        }
        if (worker < 2 ? unlink(a) : rmdir(a)) fail("worker cleanup");
        exit(0);
    }
    while (wait(&status) > 0)
        if (!WIFEXITED(status) || WEXITSTATUS(status)) failed = 1;
    if (rmdir("left") || rmdir("right") || chdir("..") || rmdir(root))
        fail("cleanup");
    printf("msdosfs rename: %s\n", failed ? "FAIL" : "PASS");
    return failed;
}
