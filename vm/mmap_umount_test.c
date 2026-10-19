/* mmap_umount_test w FILE : write a pattern through MAP_SHARED, no msync, munmap, close
 * mmap_umount_test r FILE : read() the file back and check the pattern (after umount and mount: #60) */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>

#define LEN (64*1024)

static unsigned char pat(long i) { return (unsigned char)((i * 7 + (i >> 9)) | 1); }

int main(int argc, char **argv)
{
	static unsigned char buf[LEN];
	unsigned char *p;
	long i;
	int fd;

	if (argc != 3) { fprintf(stderr, "usage: mmap_umount_test w|r file\n"); return 2; }
	if (argv[1][0] == 'w') {
		fd = open(argv[2], O_RDWR|O_CREAT|O_TRUNC, 0644);
		if (fd < 0 || ftruncate(fd, LEN) < 0) { perror("open/ftruncate"); return 1; }
		p = (unsigned char *)mmap(0, LEN, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
		if (p == (unsigned char *)-1) { perror("mmap"); return 1; }
		for (i = 0; i < LEN; i++) p[i] = pat(i);
		if (munmap((caddr_t)p, LEN) < 0) { perror("munmap"); return 1; }
		close(fd);
		printf("UMSYNC wrote %s\n", argv[2]);
		return 0;
	}
	fd = open(argv[2], O_RDONLY);
	if (fd < 0 || read(fd, buf, LEN) != LEN) { perror("read"); printf("UMSYNC FAIL short %s\n", argv[2]); return 1; }
	for (i = 0; i < LEN; i++)
		if (buf[i] != pat(i)) {
			printf("UMSYNC FAIL %s mismatch at %ld: %02x != %02x\n", argv[2], i, buf[i], pat(i));
			return 1;
		}
	printf("UMSYNC PASS %s\n", argv[2]);
	return 0;
}
