/*
 * PortServer.m
 * Main PortServer driver implementation
 */

#import "PortServer.h"
#import "IOPortSession.h"
#import "IOPortSessionKern.h"
#import "AppleIOPSSafeCondLock.h"
#import "ttyiops.h"
#import <string.h>
#import <sys/conf.h>
#import <sys/systm.h>
#import <driverkit/kernelDriver.h>
/* Global ttyiops map and lock - defined here */
static id _ttyiopsMapLock = NULL;       /* AppleIOPSSafeCondLock for ttyiops map access */
id _ttyiopsMap[26] = { NULL };          /* Array of 26 PortServer instances (one per letter a-z) */
static id _pseudoUnit = NULL;           /* PDPseudo unit instance */

/* Global port server major device number */
int _portServerMajor = 0;      /* read by ttyiops.m through ttyiops.h */

/*
 * The character device switch entry this driver installs is defined in
 * ttyiops.m (see ttyiops.h) - the seven ttyiops_* entry points it names are
 * static to that file, so only that file can take their addresses.
 * serverMajor: hands the same entry points to addToCdevswFromDescription:,
 * and the three wrappers below dispatch through this table rather than
 * naming ttyiops_* directly.
 */

/* ========================================================================
 * Character Device Switch Wrappers
 *
 * Minor numbers with both bits 6 and 7 set (0xC0) are the pseudo device the
 * kernel session layer hands out; everything else is a real tty and goes
 * through ttyiops_devsw.  Every exit reports through IOSetUNIXError().
 * ======================================================================== */

/*
 * portServeropen - Character device open
 */
static int portServeropen(unsigned int dev, int flag, int mode, struct proc *p)
{
    int rtn = 0;

    if ((dev & 0xc0) != 0xc0) {
        rtn = (*ttyiops_devsw.d_open)(dev, flag, mode, p);
    } else if ((dev & 0x3f) != 0) {
        rtn = [IOPortSession iopsKernOpen:(dev & 0x3f)];
    }

    IOSetUNIXError(rtn);
    return rtn;
}

/*
 * portServerclose - Character device close
 */
static int portServerclose(unsigned int dev, int flag, int mode, struct proc *p)
{
    int rtn = 0;

    if ((dev & 0xc0) != 0xc0) {
        rtn = (*ttyiops_devsw.d_close)(dev, flag, mode, p);
    } else if ((dev & 0x3f) != 0) {
        rtn = [IOPortSession iopsKernClose:(dev & 0x3f)];
    }

    IOSetUNIXError(rtn);
    return rtn;
}

/*
 * portServerioctl - Character device ioctl
 *
 * On the pseudo device, minor 0 answers the name lookup (0xC0547004) and the
 * server commands; the other minors carry the per-session init and message
 * ioctls.
 */
static int portServerioctl(unsigned int dev, unsigned int cmd, void *data,
                           int flag, struct proc *p)
{
    int rtn = 0;
    unsigned int target;
    ttyiops_state *st;

    if ((dev & 0xc0) != 0xc0) {
        rtn = (*ttyiops_devsw.d_ioctl)(dev, cmd, data, flag, p);
    } else if ((dev & 0x3f) == 0) {
        if (cmd == 0xc0547004) {
            /* Return the IOPortSession name of the tty named in the request */
            target = *(unsigned int *)((char *)data + 0x50);
            st = NULL;

            if (_portServerMajor == *(unsigned char *)((char *)data + 0x51) &&
                (target & 0xc0) != 0xc0 &&
                _ttyiopsMap[target & 0x1f] != NULL) {
                st = (ttyiops_state *)((char *)_ttyiopsMap[target & 0x1f] + 0x108);
            }

            if (st == NULL) {
                rtn = 6;    /* ENXIO */
            } else {
                strcpy((char *)data, (char *)[st->iops name]);
            }
        } else {
            rtn = [IOPortSession iopsServerIoctlCommand:cmd data:(char *)data];
        }
    } else if (cmd == 0xc0587003) {
        rtn = [IOPortSession iopsKernInitIoctl:(dev & 0x3f) data:(char *)data];
    } else if (cmd == 0xc0187002) {
        rtn = [IOPortSession iopsKernMsgIoctl:(dev & 0x3f) data:(char *)data];
    } else {
        rtn = 0x16;         /* EINVAL */
    }

    IOSetUNIXError(rtn);
    return rtn;
}

/* Protocol array for PortServer - _protocols.102 in the reference */
Protocol *_protocols_102[] = {
    @protocol(PortDevices),
    0
};


/* External IOLog function */
extern void IOLog(const char *format, ...);


@implementation PortServer

/*
 * deviceStyle - Return device style
 * Returns: 1 (device style constant)
 */
+ (int)deviceStyle
{
    return 1;
}

/*
 * requiredProtocols - Get required protocols
 * Returns: Pointer to protocols array
 */
+ (id *)requiredProtocols
{
    return (id *)_protocols_102;
}

/*
 * serverMajor: - Get or allocate server major number
 * deviceDescription: Device description
 * Returns: Major device number, -1 on failure
 *
 * Allocates character device switch entry if not already done.
 * Creates ttyiops map lock.
 */
+ (int)serverMajor:(id)deviceDescription
{
    if (_portServerMajor == 0) {
        /* Add to character device switch table */
        [[self class] addToCdevswFromDescription:deviceDescription
                                            open:(IOSwitchFunc)portServeropen
                                           close:(IOSwitchFunc)portServerclose
                                            read:(IOSwitchFunc)ttyiops_read
                                           write:(IOSwitchFunc)ttyiops_write
                                           ioctl:(IOSwitchFunc)portServerioctl
                                            stop:(IOSwitchFunc)ttyiops_stop
                                           reset:(IOSwitchFunc)nulldev
                                          select:(IOSwitchFunc)ttyiops_select
                                            mmap:(IOSwitchFunc)enodev
                                            getc:(IOSwitchFunc)enodev
                                            putc:(IOSwitchFunc)enodev];

        /* Get character major number */
        _portServerMajor = [[self class] characterMajor];

        if (_portServerMajor == 0xffffffff) {
            IOLog("Port Server: Can't find space in devsw\n");
        }

        /* Create AppleIOPSSafeCondLock for ttyiops map */
        _ttyiopsMapLock = [[AppleIOPSSafeCondLock alloc] init];
    }

    return _portServerMajor;
}

/*
 * probe: - Probe for port server device
 * deviceDescription: Device description to probe
 * Returns: 1 if probe successful, 0 otherwise
 *
 * Initializes the port server subsystem and creates a PortServer instance.
 */
+ (char)probe:(id)deviceDescription
{
    int majorNumber;
    int lockResult;
    id portServerInit;

    /* Get/allocate server major number */
    majorNumber = [self serverMajor:deviceDescription];

    if (majorNumber != -1) {
        /* Initialize kernel port session subsystem */
        [IOPortSession iopsKernInit:deviceDescription];

        /* Lock the ttyiops map (spin-wait) */
        do {
            lockResult = [_ttyiopsMapLock lock];
        } while (lockResult != 0);

        /* Allocate and initialize PortServer */
        portServerInit = [[[self class] alloc]
                              initFromDeviceDescription:deviceDescription];

        /* Unlock the ttyiops map */
        [_ttyiopsMapLock unlock];

        if (portServerInit != nil) {
            return 1;  /* Probe succeeded */
        }
    }

    return 0;  /* Probe failed */
}

/*
 * initFromDeviceDescription: - Initialize PortServer from device description
 * deviceDescription: Device description structure
 * Returns: initialized object or nil on failure
 *
 * Handles two types of devices:
 * 1. PDPseudo: Creates pseudo serial device named "pdservd"
 * 2. Regular TTY: Creates ttydX devices (a-z) with IOPortSession
 */
- initFromDeviceDescription:(id)deviceDescription
{
    id direct_device;
    const char *device_name;
    unsigned int unit_index;
    char name_buffer[8];
    int result_code;
    id port_session;
    id init_result;
    const char *existing_name;

    /* Get direct device from device description */
    direct_device = [deviceDescription directDevice];
    device_name = (const char *)[direct_device name];

    /* Check if device name exists and is not empty */
    if (device_name == NULL || *device_name == '\0') {
        goto init_failed;
    }

    /* Check if this is a PDPseudo device */
    if (strcmp(device_name, "PDPseudo") == 0) {
        /* PDPseudo device */
        [self setDeviceKind:"Port Server"];

        /* Set name to "pdservd" */
        name_buffer[0] = 'p';
        name_buffer[1] = 'd';
        name_buffer[2] = 's';
        name_buffer[3] = 'e';
        name_buffer[4] = 'r';
        name_buffer[5] = 'v';
        name_buffer[6] = 'd';
        name_buffer[7] = '\0';

        unit_index = 0xc0;  /* Special unit index for pseudo device */
    } else {
        /* Regular TTY device - find available slot in _ttyiopsMap */
        unit_index = 0;

        while (unit_index < 0x1a) {  /* 0x1a = 26 slots (a-z) */
            if (_ttyiopsMap[unit_index] == NULL) {
                break;  /* Found empty slot */
            }

            /* Check if device name already exists */
            existing_name = (const char *)[_ttyiopsMap[unit_index] iopsName];
            if (strcmp(existing_name, device_name) == 0) {
                /* Device already registered */
                goto init_failed;
            }

            unit_index++;
        }

        /* Check if we exceeded maximum units (26) */
        if (unit_index > 0x19) {  /* 0x19 = 25 (last valid index) */
            IOLog("ttyiops: Couldn't create any more tty instances\n");
            goto init_failed;
        }

        /* Set device kind */
        [self setDeviceKind:"Port Device tty"];

        /* Create name "ttydX" where X is a-z */
        sprintf(name_buffer, "ttyd%c", unit_index + 0x61);  /* 0x61 = 'a' */

        /* Create IOPortSession for this device */
        port_session = [[IOPortSession alloc] initForDevice:(char *)device_name
                                                     result:&result_code];

        /* Store IOPortSession in the state block */
        state.iops = port_session;

        /* Attach device to ttyiops system - the reference passes &self->state */
        ttyiops_attachDevice(&state);
    }

    /* Set unit number */
    [self setUnit:unit_index];

    /* Set device name */
    [self setName:name_buffer];

    init_result = [super initFromDeviceDescription:deviceDescription];

    if (init_result == nil) {
        goto init_failed;
    }

    /* Store this instance in appropriate global */
    if (unit_index == 0xc0) {
        /* PDPseudo device */
        _pseudoUnit = self;
    } else {
        /* Regular TTY device */
        _ttyiopsMap[unit_index] = self;
    }

    /* Register the device */
    [self registerDevice];

    return init_result;

init_failed:
    /* Initialization failed - free self and return nil */
    return [self free];
}

/*
 * iopsName - Get IOPS (IOPortSession) name
 * Returns: Port session name string
 *
 * Returns the name from the IOPortSession object at offset +0x1f0
 */
- (const char *)iopsName
{
    const char *name;

    /* Get name from the IOPortSession this port was opened on */
    name = [state.iops name];

    return name;
}

/*
 * state - Get current driver state
 * Returns: Pointer to this instance's ttyiops state block
 */
- (ttyiops_state *)state
{
    return &state;
}

/*
 * getIntValues:forParameter:count: - Get integer parameter values
 * values: Buffer to receive integer values (output parameter)
 * parameterName: Parameter identifier (string)
 * count: Pointer to count (input/output parameter)
 * Returns: Result code (0 on success)
 *
 * Handles three special parameters:
 * - "PortServerPLGandS": Returns and sets flag at offset +0x264
 * - "Port Device tty": Returns pointer to offset +0x108
 * - "Maximum Sessions": Returns max sessions from IOPortSession
 * Falls back to [super getIntValues:forParameter:count:] for other parameters
 */
- (int)getIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int *)count
{
    int result;

    /* Check for "PortServerPLGandS" parameter */
    if (strcmp(parameterName, "PortServerPLGandS") == 0) {
        /* Lock the ttyiops map */
        do {
            result = [_ttyiopsMapLock lock];
        } while (result != 0);

        /* Set count to 1 */
        *count = 1;

        /* Get current flag value */
        *values = state.is_post_loaded;

        /* Set the flag */
        state.is_post_loaded = 1;

        /* Unlock the ttyiops map */
        [_ttyiopsMapLock unlock];

        return 0;
    }

    /* Check for "Port Device tty" parameter */
    if (strcmp(parameterName, "Port Device tty") == 0) {
        /* Set count to 1 */
        *count = 1;

        /* Return pointer to the state block */
        *values = (unsigned int)&state;

        return 0;
    }

    /* Check for "Maximum Sessions" parameter */
    if (strcmp(parameterName, "Maximum Sessions") == 0) {
        /* Get maximum sessions from IOPortSession class */
        *values = [IOPortSession iopsKernNumSess];
        *count = 1;

        return 0;
    }

    /* Unknown parameter - call super implementation */
    return [super getIntValues:values forParameter:parameterName count:count];
}

/*
 * setIntValues:forParameter:count: - Set integer parameter values
 * values: Buffer containing integer values to set
 * parameterName: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success)
 *
 * Handles one special parameter:
 * - "PortServerPLGandS": Sets flag at offset +0x264 based on *values (if count == 1)
 * Falls back to [super setIntValues:forParameter:count:] for other parameters
 */
- (int)setIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int)count
{
    int result;

    /* Check for "PortServerPLGandS" parameter */
    if (strcmp(parameterName, "PortServerPLGandS") == 0) {
        /* Check if count is 1 */
        if (count == 1) {
            /* Lock the ttyiops map */
            do {
                result = [_ttyiopsMapLock lock];
            } while (result != 0);

            /* Set the flag based on *values */
            if (*values == 0) {
                state.is_post_loaded = 0;
            } else {
                state.is_post_loaded = 1;
            }

            /* Unlock the ttyiops map */
            [_ttyiopsMapLock unlock];

            return 0;
        } else {
            /* Invalid count - return error */
            return 0xfffffd3e;  /* -706 decimal */
        }
    }

    /* Unknown parameter - call super implementation */
    return [super setIntValues:values forParameter:parameterName count:count];
}

@end
