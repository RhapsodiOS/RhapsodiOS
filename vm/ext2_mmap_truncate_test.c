/* Run on an ext2 scratch mount: ext2_mmap_truncate_test /mnt/e/test-file.
 * Do not sync before shrinking: retained mmap pages must allocate their
 * blocks before ext2fs_truncate snapshots the inode's block pointers. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define FILE_SIZE (64 * 1024)

static void
fail(const char *operation)
{
    perror(operation);
    exit(1);
}

static unsigned char
pattern(int offset)
{
    return (unsigned char)(1 + offset % 251);
}

int
main(int argc, char **argv)
{
    static const int lengths[] = {20 * 1024, 20 * 1024 + 37,
        5 * 1024 + 37, 0};
    unsigned char *mapping, buffer[4096];
    struct stat st;
    int fd, test, i, offset, n, length;

    if (argc != 2) {
        fprintf(stderr, "usage: %s scratch-file\n", argv[0]);
        return 2;
    }
    setbuf(stdout, NULL);
    for (test = 0; test < sizeof(lengths) / sizeof(lengths[0]); test++) {
        length = lengths[test];
        fd = open(argv[1], O_RDWR | O_CREAT | O_EXCL, 0600);
        if (fd < 0) fail("open scratch file");
        if (ftruncate(fd, FILE_SIZE)) fail("sparse growth");
        mapping = (unsigned char *)mmap(NULL, FILE_SIZE,
            PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (mapping == (unsigned char *)-1) fail("mmap");
        for (i = 0; i < FILE_SIZE; i++) mapping[i] = pattern(i);
        printf("TRUNCATE start length=%d\n", length);
        if (ftruncate(fd, length)) fail("mapped shrink");
        if (fstat(fd, &st)) fail("fstat");
        if (st.st_size != length) {
            fprintf(stderr, "wrong truncated size\n");
            return 1;
        }
        for (i = 0; i < length; i++) {
            if (mapping[i] != pattern(i)) {
                fprintf(stderr, "retained mapping mismatch at %d\n", i);
                return 1;
            }
        }
        if (munmap((caddr_t)mapping, FILE_SIZE)) fail("munmap");
        if (ftruncate(fd, FILE_SIZE)) fail("regrowth");
        if (fsync(fd)) fail("fsync");
        if (close(fd)) fail("close");
        fd = open(argv[1], O_RDONLY, 0);
        if (fd < 0) fail("reopen");
        for (offset = 0; offset < FILE_SIZE; offset += n) {
            n = read(fd, buffer, sizeof(buffer));
            if (n < 0) fail("read");
            if (!n) {
                fprintf(stderr, "unexpected EOF at %d\n", offset);
                return 1;
            }
            for (i = 0; i < n; i++) {
                if (buffer[i] != (offset + i < length ?
                    pattern(offset + i) : 0)) {
                    fprintf(stderr, "regrowth mismatch at %d, length=%d\n",
                        offset + i, length);
                    return 1;
                }
            }
        }
        if (close(fd)) fail("close reader");
        if (unlink(argv[1])) fail("unlink");
        printf("TRUNCATE pass length=%d\n", length);
    }
    puts("EXT2_MMAP_TRUNCATE PASS");
    return 0;
}
