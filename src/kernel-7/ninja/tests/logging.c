#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    char data[1024];
    int fd, i, count, zeros;
    if (argc != 4) return 2;
    if (!strcmp(argv[1], "write")) {
        memset(data, 'X', sizeof(data));
        data[1023] = '\n';
        fd = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) return 3;
        for (i = 0; i < 400; ++i) {
            if (write(fd, data, sizeof(data)) != sizeof(data)) return 4;
            usleep(5000);
        }
        close(fd);
        fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) return 5;
        close(fd);
        return 0;
    }
    fd = open(argv[2], O_RDONLY);
    if (fd < 0) return 6;
    zeros = 0;
    i = 0;
    while ((count = read(fd, data, sizeof(data))) > 0) {
        int n;
        i += count;
        for (n = 0; n < count; ++n) if (!data[n]) ++zeros;
    }
    close(fd);
    printf("bytes=%d zeros=%d\n", i, zeros);
    return i != 409600 || zeros != 0;
}
