/*
 * pdservd.m
 * Port Server Daemon - Main Implementation
 *
 * The Port Server's Post-Load program.  It makes the /dev nodes for the
 * PortServer pseudo device and for every tty the driver registered, and
 * records each tty's paths in PortServer.config/Instance0.table.
 *
 * Reconstructed against Apple's DR2 pdservd (PortServer.config/pdservd,
 * drvPortServer-14).  See reconstruction/pdservd.md.
 */

#import "pdservd.h"
#import "IODeviceMaster.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <syslog.h>
#import <errno.h>
#import <libc.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <objc/NXStringTable.h>
#import <objc/hashtable.h>

#define INSTANCE_TABLE	"/usr/Devices/PortServer.config/Instance0.table"

/*
 * The four nodes made for each tty.  The minor number is the tty's unit
 * or'ed with the node's bits: 0x20 selects the call-out (cu) side and
 * 0x40 the initial-state device.
 */
typedef struct {
    const char *nameFormat;	/* node name, given the port letter */
    const char *keyFormat;	/* Instance0.table key, given the port index */
    int minorBits;
    mode_t mode;
} NodeEntry;

static NodeEntry nodeList[] = {
    { "ttyd%c",  "Path %d IN",       0x00, S_IFCHR | 0666 },
    { "ttyid%c", "Path %d IN Init",  0x40, S_IFCHR | 0666 },
    { "cua%c",   "Path %d OUT",      0x20, S_IFCHR | 0666 },
    { "cuia%c",  "Path %d OUT Init", 0x60, S_IFCHR | 0666 },
    { NULL,      NULL,               0,    0 }
};

/* Highest port letter seen; one below 'a' until a tty is found */
static char lastPort = 0x60;

static IODeviceMaster *devMaster;
static char *cmdName;
static id instanceTable;

static void init(int argc, char **argv)
{
    cmdName = strrchr(argv[0], '/');
    if (cmdName != NULL)
        cmdName++;
    else
        cmdName = argv[0];

    openlog(cmdName, LOG_CONS, LOG_DAEMON);
}

/*
 * Make /dev/pdservd and the /dev/rpskiNN session nodes that follow it.
 */
static void serverPostLoad(IOObjectNumber objectNumber, const char *deviceName)
{
    char path[128];
    int doPost;
    unsigned int count;
    int major;
    int unit;
    int maxSessions;
    IOReturn ret;

    count = 1;
    doPost = 0;
    ret = [devMaster getIntValues:(unsigned int *)&doPost
                     forParameter:"PortServerPLGandS"
                     objectNumber:objectNumber
                            count:&count];
    if (ret != IO_R_SUCCESS || doPost != 0)
        return;

    count = 1;
    major = -1;
    ret = [devMaster getIntValues:(unsigned int *)&major
                     forParameter:"IOCharacterMajor"
                     objectNumber:objectNumber
                            count:&count];
    if (ret != IO_R_SUCCESS || major == -1) {
        syslog(LOG_ERR, "Couldn't get major number: returned %d", ret);
        exit(1);
    }

    ret = [devMaster getIntValues:(unsigned int *)&unit
                     forParameter:"IOUnit"
                     objectNumber:objectNumber
                            count:&count];
    if (ret != IO_R_SUCCESS || count != 1) {
        syslog(LOG_ERR, "Couldn't get unit number for %s", deviceName);
        return;
    }

    unlink("/dev/pdservd");
    if (mknod("/dev/pdservd", S_IFCHR | 0666, makedev(major, unit)) != 0) {
        syslog(LOG_ERR, "Could not create %s - %s", "/dev/pdservd",
               strerror(errno));
        exit(1);
    }

    /* The session nodes take the minors after the server's own */
    unit++;
    count = 1;
    maxSessions = -1;
    ret = [devMaster getIntValues:(unsigned int *)&maxSessions
                     forParameter:"Maximum Sessions"
                     objectNumber:objectNumber
                            count:&count];
    if (ret != IO_R_SUCCESS || maxSessions == -1) {
        syslog(LOG_NOTICE, "Bad number of sessions, default 16");
        maxSessions = 16;
    }
    maxSessions += unit;
    if (maxSessions > 255) {
        syslog(LOG_NOTICE, "Too many IOPortSessions:  Setting maximum to %d",
               255);
        maxSessions = 255;
    }

    /* Clear every stale session node, and make the ones in range */
    for (; unit < 255; unit++) {
        sprintf(path, "/dev/rpski%02d", unit & 0x3f);
        unlink(path);
        if (unit < maxSessions
        &&  mknod(path, S_IFCHR | 0666, makedev(major, unit)) != 0)
            syslog(LOG_NOTICE, "Could not create %s - %s", path,
                   strerror(errno));
    }
}

/*
 * Return the port letter that follows a "ttyd" prefix, or 0 if the name
 * has neither recognised prefix.
 */
char genSuffix(const char *deviceName)
{
    static const char *prefixList[] = { "ttyd", "/dev/ttyd", NULL };
    const char *prefix;
    int i;

    for (i = 0; i < sizeof(prefixList) / sizeof(prefixList[0]) - 1; i++) {
        prefix = prefixList[i];
        if (strncmp(deviceName, prefix, strlen(prefix)) == 0)
            return deviceName[strlen(prefix)];
    }
    return 0;
}

/*
 * Make the four nodes for one tty and record their paths.
 */
static void ttyPostLoad(IOObjectNumber objectNumber, const char *deviceName)
{
    char path[88];
    char nodeName[64];
    int doPost;
    unsigned int count = 1;
    int major;
    int unit;
    char suffix;
    NodeEntry *entry;
    IOReturn ret;

    suffix = genSuffix(deviceName);
    if (suffix == 0) {
        syslog(LOG_ERR, "Could not recognize name format %s", deviceName);
        return;
    }

    count = 1;
    ret = [devMaster getIntValues:(unsigned int *)&doPost
                     forParameter:"PortServerPLGandS"
                     objectNumber:objectNumber
                            count:&count];
    if (ret != IO_R_SUCCESS) {
        syslog(LOG_NOTICE, "Couldn't get do-post flag: returned %d", ret);
        doPost = 0;
    }

    if (doPost == 0) {
        count = 1;
        major = -1;
        ret = [devMaster getIntValues:(unsigned int *)&major
                         forParameter:"IOCharacterMajor"
                         objectNumber:objectNumber
                                count:&count];
        if (ret != IO_R_SUCCESS || major == -1) {
            syslog(LOG_ERR, "Couldn't get major number: returned %d", ret);
            exit(1);
        }

        ret = [devMaster getIntValues:(unsigned int *)&unit
                         forParameter:"IOUnit"
                         objectNumber:objectNumber
                                count:&count];
        if (ret != IO_R_SUCCESS || count != 1) {
            syslog(LOG_ERR, "Couldn't get unit number for %s", deviceName);
            return;
        }
    }

    for (entry = nodeList; entry->nameFormat != NULL; entry++) {
        sprintf(nodeName, entry->nameFormat, suffix);
        sprintf(path, "%s%s", "/dev/", nodeName);

        if (doPost == 0) {
            unlink(path);
            if (mknod(path, entry->mode,
                      makedev(major, entry->minorBits | unit)) != 0)
                syslog(LOG_NOTICE, "Could not create %s - %s", path,
                       strerror(errno));
        }

        if (instanceTable != nil && entry->keyFormat != NULL) {
            sprintf(nodeName, entry->keyFormat, suffix - 'a');
            [instanceTable insertKey:NXCopyStringBuffer(nodeName)
                               value:NXCopyStringBuffer(path)];
        }
    }

    if (lastPort < suffix)
        lastPort = suffix;

    syslog(LOG_NOTICE, "Post Load for %s complete", deviceName);
}

/*
 * Walk every driver object and post-load the Port Server's.
 */
static void process_ttys(void)
{
    IOString deviceKind;
    IOString deviceName;
    IOObjectNumber objectNumber;
    IOReturn ret;

    devMaster = [IODeviceMaster new];

    for (objectNumber = 0; ; objectNumber++) {
        ret = [devMaster lookUpByObjectNumber:objectNumber
                                   deviceKind:&deviceKind
                                   deviceName:&deviceName];
        switch (ret) {
        case IO_R_NO_DEVICE:	/* past the last object */
        default:
            [devMaster free];
            return;

        case IO_R_SUCCESS:
            if (strcmp(deviceKind, "Port Server") == 0)
                serverPostLoad(objectNumber, deviceName);
            else if (strcmp(deviceKind, "Port Device tty") == 0)
                ttyPostLoad(objectNumber, deviceName);
            break;

        case IO_R_OFFLINE:
            break;
        }
    }
}

/*
 * Load Instance0.table and drop the keys this run is about to rewrite.
 */
void readInstanceTable(void)
{
    char key[32];
    const char *portCount;
    int ports;
    int i, j;

    instanceTable = [[NXStringTable alloc] init];
    if ([instanceTable readFromFile:INSTANCE_TABLE] == nil) {
        syslog(LOG_ERR, "Unable to read %s", "Instance0.table");
        instanceTable = [instanceTable free];
        return;
    }

    /* The reference converts the count here and then again on every
     * test of the loop below, discarding this result. */
    portCount = [instanceTable valueForKey:"Port Count"];
    ports = atoi(portCount);
    for (i = 0; i < atoi(portCount); i++) {
        for (j = 0; nodeList[j].nameFormat != NULL; j++) {
            if (nodeList[j].keyFormat != NULL) {
                sprintf(key, nodeList[j].keyFormat, i);
                [instanceTable removeKey:key];
            }
        }
    }
    [instanceTable removeKey:"Port Count"];
}

void writeInstanceTable(void)
{
    char count[8];

    if (instanceTable != nil) {
        sprintf(count, "%d", lastPort - 0x60);
        [instanceTable insertKey:"Port Count" value:count];
        if ([instanceTable writeToFile:INSTANCE_TABLE] == nil)
            syslog(LOG_ERR, "Unable to write %s", "Instance0.table");
    }
}

int main(int argc, char **argv)
{
    int mask;

    init(argc, argv);

    mask = umask(0);
    readInstanceTable();
    process_ttys();
    writeInstanceTable();
    umask(mask);

    return 1;
}
