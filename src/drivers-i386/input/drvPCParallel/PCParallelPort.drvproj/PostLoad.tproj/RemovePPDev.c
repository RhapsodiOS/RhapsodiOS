/*
 * RemovePPDev.c - Pre-Load tool: remove /dev/ppN
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#define PROGRAM_NAME "Parallel Port Pre-Load"

char path[20];

int
main(int argc, char **argv)
{
    int i;
    char *instanceArg;
    unsigned int instanceNum;

    instanceArg = NULL;
    if (argc > 1) {
        for (i = 1; i < argc; i++) {
            if (argv[i] != NULL) {
                if (strncmp(argv[i], "Instance=", 9) == 0) {
                    instanceArg = argv[i];
                    break;
                }
            }
        }
    }
    if (instanceArg == NULL) {
        printf("%s: invoked without '%s' argument\n", PROGRAM_NAME, "Instance=");
        return -1;
    }

    sscanf(instanceArg, "Instance=%d", &instanceNum);
    if (instanceNum > 9) {
        printf("%s: invalid instance number\n", PROGRAM_NAME);
        return -1;
    }

    bzero(path, 20);
    sprintf(path, "%s%s%d", "/dev/", "pp", instanceNum);
    if (unlink(path) != 0) {
        if (errno != ENOENT) {
            printf("%s: could not delete old %s - %s\n",
                PROGRAM_NAME, path, strerror(errno));
            return -1;
        }
    }
    return 0;
}
