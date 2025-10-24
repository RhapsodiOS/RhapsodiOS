/*
 * RemovePPDev.c - Remove parallel port device node
 *
 * This tool is called during driver unload to remove the device node
 * from /dev/
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#define PROGRAM_NAME "Parallel Port Post-Load"
#define MAX_INSTANCE 9

int main(int argc, char *argv[])
{
    char *instanceArg = NULL;
    unsigned int instanceNum;
    char devicePath[20];
    int i;
    int result;

    // Parse command line arguments looking for "Instance=N"
    if (argc > 1) {
        for (i = 1; i < argc; i++) {
            if (argv[i] != NULL && strncmp(argv[i], "Instance=", 9) == 0) {
                instanceArg = argv[i];
                break;
            }
        }
    }

    // Check if Instance= argument was found
    if (instanceArg == NULL) {
        printf("%s: invoked without '%s' argument\n", PROGRAM_NAME, "Instance=");
        return -1;
    }

    // Parse the instance number
    if (sscanf(instanceArg, "Instance=%u", &instanceNum) != 1) {
        printf("%s: invalid instance format\n", PROGRAM_NAME);
        return -1;
    }

    // Validate instance number
    if (instanceNum > MAX_INSTANCE) {
        printf("%s: invalid instance number\n", PROGRAM_NAME);
        return -1;
    }

    // Build device path
    bzero(devicePath, sizeof(devicePath));
    sprintf(devicePath, "%s%s%u", "/dev/", "pp", instanceNum);

    // Remove the device node
    result = unlink(devicePath);
    if (result != 0 && errno != ENOENT) {
        // Error other than "file doesn't exist"
        printf("%s: could not delete old %s - %s\n",
               PROGRAM_NAME, devicePath, strerror(errno));
        return -1;
    }

    return 0;
}
