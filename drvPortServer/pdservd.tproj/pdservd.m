/*
 * pdservd.m
 * Port Server Daemon - Main Implementation
 */

#import "pdservd.h"
#import "IODeviceMaster.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <syslog.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>
#import <mach/mach.h>

/*
 * Initialize the daemon
 * Extracts command name from argv[0] and opens syslog
 * argc: Argument count
 * argv: Argument vector
 */
void init(int argc, char **argv)
{
    char *lastSlash;

    // Extract command name from full path
    // Find last '/' in argv[0]
    lastSlash = strrchr(argv[0], '/');

    if (lastSlash == NULL) {
        // No path separator, use argv[0] as-is
        cmdName = argv[0];
    } else {
        // Use everything after the last '/'
        cmdName = lastSlash + 1;
    }

    // Open syslog with the command name
    // LOG_NDELAY = 2, LOG_DAEMON = 0x18 (24)
    openlog(cmdName, LOG_NDELAY, LOG_DAEMON);
}

/*
 * Get the device master port from the kernel
 * Returns: Mach port to the device master
 */
mach_port_t device_master_self(void)
{
    mach_port_t masterPort = MACH_PORT_NULL;
    kern_return_t kr;

    // TODO: Implement device_master_self - get the device master port from bootstrap
    kr = task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &masterPort);
    if (kr != KERN_SUCCESS) {
        syslog(LOG_ERR, "device_master_self: Failed to get device master port: %s",
               mach_error_string(kr));
        return MACH_PORT_NULL;
    }

    return masterPort;
}

// Prefix list for suffix generation
static const char *prefixList[] = {
    "tty",
    "cu",
    NULL
};

// Device node entry structure
typedef struct {
    const char *devNameFormat;   // Format string for device name (e.g., "tty%c")
    const char *tableKeyFormat;  // Format string for instance table key (e.g., "Path_%d_IN")
    unsigned int minorOffset;    // Offset to add to minor number
    mode_t mode;                 // File mode/permissions for device node
} DeviceNodeEntry;

// Node list for device creation
static DeviceNodeEntry nodeList[] = {
    { "tty%c", "Path_%d_IN",  0, 0020666 },  // Character device, rw-rw-rw-
    { "cu%c",  "Path_%d_OUT", 128, 0020666 }, // Character device with offset, rw-rw-rw-
    { NULL, NULL, 0, 0 }
};

// Global device master
static id devMaster = nil;

// Instance table global
static id instanceTable = nil;

// Last port number (starts at 0x60 = 96)
static int lastPort = 0x60;

// Command name for logging
static const char *cmdName = NULL;

/*
 * Generate suffix by stripping known prefixes from device name
 * deviceName: Device name to extract suffix from
 * Returns: First character of suffix, or 0 if no match
 */
int genSuffix(char *deviceName)
{
    const char *prefix;
    size_t prefixLen;
    int result;
    unsigned int i;

    if (deviceName == NULL) {
        return 0;
    }

    // Try each prefix in the list
    for (i = 0; i < 2; i++) {
        prefix = prefixList[i];

        // Calculate prefix length
        prefixLen = strlen(prefix);

        // Compare device name with this prefix
        result = strncmp(deviceName, prefix, prefixLen);
        if (result == 0) {
            // Found matching prefix - return first character after prefix
            return (int)deviceName[prefixLen];
        }
    }

    // No matching prefix found
    return 0;
}

/*
 * Process TTY devices
 * Enumerates all devices and calls appropriate post-load handlers
 * Returns: 0 on success, -1 on failure
 */
int process_ttys(void)
{
    int result;
    int objectNumber;
    const char *deviceKind;
    const char *deviceName;

    // Get the IODeviceMaster singleton instance
    devMaster = [IODeviceMaster new];

    // Enumerate all devices starting from object number 0
    objectNumber = 0;

    while (1) {
        // Look up device by object number
        result = [devMaster lookUpByObjectNumber:objectNumber
                                      deviceKind:&deviceKind
                                      deviceName:&deviceName];

        // Error codes:
        // 0 = success
        // -0x2C0 = -704 = no more devices (end of enumeration)
        // -0x2D7 = -727 = device not found/skip

        if (result == -0x2C0) {
            // End of device enumeration
            break;
        }

        if (result == -0x2D7) {
            // Device not found at this index, skip to next
            objectNumber++;
            continue;
        }

        if (result != 0) {
            // Other error, stop enumeration
            break;
        }

        // Check if this is a "Port Server" device
        if (strncmp(deviceKind, "Port Server", 12) == 0) {
            // Call serverPostLoad for Port Server devices
            serverPostLoad(objectNumber, deviceName);
        }
        // Check if this is a "Port Device tty" device
        else if (strncmp(deviceKind, "Port Device tty", 16) == 0) {
            // Call ttyPostLoad for TTY devices
            ttyPostLoad(objectNumber, deviceName);
        }

        // Move to next device
        objectNumber++;
    }

    // Free the device master (no-op for singleton, but follows convention)
    [devMaster free];

    return 0;
}

/*
 * Read the instance table from persistent storage
 * Returns: 0 on success, -1 on failure
 */
int readInstanceTable(void)
{
    id stringTableClass;
    const char *portCountStr;
    int portCount;
    int i, j;
    int result;
    char key[32];

    // Get NXStringTable class and create new instance
    stringTableClass = objc_getClass("NXStringTable");
    instanceTable = [stringTableClass new];

    // Try to read the instance table file
    result = [instanceTable readFromFile:"/usr/Devices/PortServer.config/Instance0.table"];

    if (result == 0) {
        syslog(LOG_ERR, "Unable to read %s", "Instance0.table");
        // Free the instance table and set to nil
        [instanceTable free];
        instanceTable = nil;
    } else {
        // Get the port count from the table
        portCountStr = [instanceTable valueForStringKey:"Port Count"];
        portCount = atoi(portCountStr);

        // Process each port
        for (i = 0; i < portCount; i++) {
            j = 0;
            // Process each node type (Path_IN, Path_OUT, etc.)
            while (nodeList[j] != NULL) {
                if (nodeList[j] != NULL) {
                    // Format the key (e.g., "Path_0_IN", "Path_0_OUT")
                    sprintf(key, nodeList[j], i);
                    // Remove this key from the table
                    [instanceTable removeStringKey:key];
                }
                j++;
            }
        }

        // Remove the "Port Count" key
        [instanceTable removeStringKey:"Port Count"];
    }

    return 0;
}

/*
 * Post-load initialization for the server
 * Creates the main /dev/pdservd device and session devices (/dev/rpski*)
 * objectNumber: Device object number
 * deviceName: Name of the device
 * Returns: 0 on success, -1 on failure
 */
int serverPostLoad(int objectNumber, const char *deviceName)
{
    int result;
    int count;
    int doPost = 0;
    int majorNumber = -1;
    unsigned int unitNumber;
    int maxSessions = -1;
    int maxMinor;
    char sessionDevPath[128];
    const char *errorStr;

    // Get the "PortServerPLGandS" (Post-Load-Get-and-Set) flag
    count = 1;
    result = [devMaster getIntValues:&doPost
                        forParameter:"PortServerPLGandS"
                        objectNumber:objectNumber
                               count:&count];

    // Only create device nodes if doPost flag is not set
    if (result != 0 || doPost != 0) {
        return 0;
    }

    // Get the major device number
    count = 1;
    result = [devMaster getIntValues:&majorNumber
                        forParameter:"IOCharacterMajor"
                        objectNumber:objectNumber
                               count:&count];

    if (result != 0 || majorNumber == -1) {
        syslog(LOG_ERR, "Couldn't get major number: returned %d", result);
        exit(1);
    }

    // Get the unit number
    count = 1;
    result = [devMaster getIntValues:(int *)&unitNumber
                        forParameter:"IOUnit"
                        objectNumber:objectNumber
                               count:&count];

    if (result != 0 || count != 1) {
        syslog(LOG_ERR, "Couldn't get unit number for %s", deviceName);
        return -1;
    }

    // Create the main /dev/pdservd device node
    unlink("/dev/pdservd");
    result = mknod("/dev/pdservd", 0021666, (majorNumber << 8) | unitNumber);

    if (result != 0) {
        errorStr = strerror(errno);
        syslog(LOG_ERR, "Could not create %s - %s", "/dev/pdservd", errorStr);
        exit(1);
    }

    // Move to next minor number for session devices
    unitNumber++;

    // Get the maximum number of sessions
    count = 1;
    result = [devMaster getIntValues:&maxSessions
                        forParameter:"Maximum Sessions"
                        objectNumber:objectNumber
                               count:&count];

    if (result != 0 || maxSessions == -1) {
        syslog(LOG_NOTICE, "Bad number of sessions, default 16");
        maxSessions = 16;
    }

    // Calculate maximum minor number
    maxMinor = maxSessions + unitNumber;
    if (maxMinor > 0xFF) {
        syslog(LOG_NOTICE, "Too many IOPortSessions:  Setting maximum to %d", 0xFF);
        maxMinor = 0xFF;
    }

    // Create session device nodes /dev/rpski00 through /dev/rpskiXX
    while ((int)unitNumber < 0xFF) {
        // Format: /dev/rpski%02d (using only lower 6 bits for formatting)
        sprintf(sessionDevPath, "/dev/rpski%02d", unitNumber & 0x3F);

        // Always unlink the old device
        unlink(sessionDevPath);

        // Only create if within session limit
        if ((int)unitNumber < maxMinor) {
            result = mknod(sessionDevPath, 0021666, (majorNumber << 8) | unitNumber);

            if (result != 0) {
                errorStr = strerror(errno);
                syslog(LOG_NOTICE, "Could not create %s - %s", sessionDevPath, errorStr);
            }
        }

        unitNumber++;
    }

    return 0;
}

/*
 * Post-load initialization for TTY devices
 * objectNumber: Device object number
 * deviceName: Name of the device (e.g., "ttyS0")
 * Returns: 0 on success, -1 on failure
 */
int ttyPostLoad(int objectNumber, const char *deviceName)
{
    char suffix;
    int result;
    int doPost = 0;
    int majorNumber = -1;
    unsigned int unitNumber;
    int count;
    DeviceNodeEntry *entry;
    char nodeName[64];
    char devicePath[88];
    char tableKey[64];
    const char *errorStr;

    // Get the suffix character from the device name
    suffix = (char)genSuffix((char *)deviceName);

    if (suffix == '\0') {
        syslog(LOG_ERR, "Could not recognize name format %s", deviceName);
        return -1;
    }

    // Get the "PortServerPLGandS" (Post-Load-Get-and-Set) flag
    count = 1;
    result = [devMaster getIntValues:&doPost
                        forParameter:"PortServerPLGandS"
                        objectNumber:objectNumber
                               count:&count];

    if (result != 0) {
        syslog(LOG_NOTICE, "Couldn't get do-post flag: returned %d", result);
        doPost = 0;
    }

    // Only create device nodes if doPost flag is not set
    if (doPost == 0) {
        // Get the major device number
        count = 1;
        result = [devMaster getIntValues:&majorNumber
                            forParameter:"IOCharacterMajor"
                            objectNumber:objectNumber
                                   count:&count];

        if (result != 0 || majorNumber == -1) {
            syslog(LOG_ERR, "Couldn't get major number: returned %d", result);
            exit(1);
        }

        // Get the unit number
        count = 1;
        result = [devMaster getIntValues:(int *)&unitNumber
                            forParameter:"IOUnit"
                            objectNumber:objectNumber
                                   count:&count];

        if (result != 0 || count != 1) {
            syslog(LOG_ERR, "Couldn't get unit number for %s", deviceName);
            return -1;
        }
    }

    // Process each device node type (tty, cu)
    entry = nodeList;
    while (entry->devNameFormat != NULL) {
        // Format the node name (e.g., "ttyS", "cuS")
        sprintf(nodeName, entry->devNameFormat, suffix);

        // Create full device path (e.g., "/dev/ttyS")
        sprintf(devicePath, "%s%s", "/dev/", nodeName);

        // Create device node if doPost is not set
        if (doPost == 0) {
            // Remove old device node if it exists
            unlink(devicePath);

            // Create new device node
            // dev_t = (major << 8) | minorOffset | unitNumber
            result = mknod(devicePath,
                          entry->mode,
                          (majorNumber << 8) | entry->minorOffset | unitNumber);

            if (result != 0) {
                errorStr = strerror(errno);
                syslog(LOG_NOTICE, "Could not create %s - %s", devicePath, errorStr);
            }
        }

        // Add entry to instance table if it exists and has a table key format
        if (instanceTable != nil && entry->tableKeyFormat != NULL) {
            // Format the table key (e.g., "Path_0_IN")
            // suffix - 0x61 converts 'a' to 0, 'b' to 1, etc.
            sprintf(tableKey, entry->tableKeyFormat, suffix - 0x61);

            // Insert the device path into the instance table
            [instanceTable insertKey:tableKey value:devicePath];
        }

        // Move to next entry
        entry++;
    }

    // Update lastPort if this suffix is higher
    if (lastPort < suffix) {
        lastPort = suffix;
    }

    syslog(LOG_NOTICE, "Post Load for %s complete", deviceName);

    return 0;
}

/*
 * Write the instance table to persistent storage
 * Returns: 0 on success, -1 on failure
 */
int writeInstanceTable(void)
{
    int result;
    char portCountStr[8];

    // Only write if instance table exists
    if (instanceTable != nil) {
        // Calculate port count (lastPort - 0x60)
        // 0x60 = 96, which is the starting port number
        sprintf(portCountStr, "%d", lastPort - 0x60);

        // Set the "Port Count" value in the table
        [instanceTable insertKey:"Port Count" value:portCountStr];

        // Write the instance table to file
        result = [instanceTable writeToFile:"/usr/Devices/PortServer.config/Instance0.table"];

        if (result == 0) {
            syslog(LOG_ERR, "Unable to write %s", "Instance0.table");
        }
    }

    return 0;
}

int main(int argc, char **argv)
{
    mode_t oldMask;

    // Initialize: extract command name and open syslog
    init(argc, argv);

    syslog(LOG_INFO, "Port Server Daemon starting...");

    // Save current umask and set to 0 for device node creation
    // This ensures device nodes are created with the exact permissions specified
    oldMask = umask(0);

    // Read the instance table from persistent storage
    readInstanceTable();

    // Process all TTY and Port Server devices
    // This enumerates devices and creates device nodes
    process_ttys();

    // Write the updated instance table back to storage
    writeInstanceTable();

    // Restore original umask
    umask(oldMask);

    syslog(LOG_INFO, "Port Server Daemon initialization complete");

    // Return 1 (success in this context)
    return 1;
}
