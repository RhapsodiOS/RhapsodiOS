#import <streams/streams.h>
#import <errno.h>
#import <libc.h>
#import <sys/stat.h>

#define PATH_NAME_SIZE 16
#define DEV_STRING "/dev/"
#define AHCI_INIT_ERR_STRING "Error initializing AHCI driver"

#define DEV_MOD_CHAR 020640
#define DEV_MOD_BLOCK 060640
#define DEV_UMASK 0

#define N_AHCI_PARTITIONS 8
#define N_AHCI_DEVICES 32
#define AHCI_BLOCK_MAJOR 3
#define AHCI_CHARACTER_MAJOR 15

/*
 * PostLoad is invoked as root and uses its current group for new nodes.
 * umask(0) and the mknod modes below establish the final permissions.
 */
static int makeNode(char *deviceName, int unit, int major, int partition,
                    unsigned short mode);

int main(int argc, char **argv)
{
    int unit;
    int partition;
    int result;

    result = 0;
    for (unit = 0; unit < N_AHCI_DEVICES; ++unit) {
        for (partition = 0; partition < N_AHCI_PARTITIONS; ++partition) {
            if (makeNode("hd", unit, AHCI_BLOCK_MAJOR, partition,
                         DEV_MOD_BLOCK) != 0)
                result = -1;
            if (makeNode("rhd", unit, AHCI_CHARACTER_MAJOR, partition,
                         DEV_MOD_CHAR) != 0)
                result = -1;
        }
    }
    exit(result);
}

static int makeNode(char *deviceName, int unit, int major, int partition,
                    unsigned short mode)
{
    struct stat status;
    dev_t device;
    int minor;
    char path[PATH_NAME_SIZE];

    bzero(path, PATH_NAME_SIZE);
    sprintf(path, "%s%s%d%c", DEV_STRING, deviceName, unit,
            partition + 'a');
    minor = unit * N_AHCI_PARTITIONS + partition;
    device = (major << 8) | minor;
    if (lstat(path, &status) == 0) {
        if ((status.st_mode & S_IFMT) == (mode & S_IFMT) &&
            (status.st_mode & 07777) == (mode & 07777) &&
            status.st_rdev == device)
            return 0;
        if (unlink(path)) {
            printf("%s: could not delete old %s. Errno is %d\n",
                   AHCI_INIT_ERR_STRING, path, errno);
            return -1;
        }
    } else if (errno != ENOENT) {
        printf("%s: could not inspect %s. Errno is %d\n",
               AHCI_INIT_ERR_STRING, path, errno);
        return -1;
    }
    umask(DEV_UMASK);
    if (mknod(path, mode, device)) {
        printf("%s: could not create %s. Errno is %d\n",
               AHCI_INIT_ERR_STRING, path, errno);
        return -1;
    }
    return 0;
}
