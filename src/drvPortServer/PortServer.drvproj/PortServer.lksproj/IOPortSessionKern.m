/*
 * IOPortSessionKern.m
 * Kernel-level parameter access for IOPortSession
 */

#import "IOPortSessionKern.h"
#import "AppleIOPSSafeCondLock.h"
#import <driverkit/IODeviceParams.h>

/* One slot per session, 64 slots of 8 bytes = 0x200, matching the reference's
 * single _nsPortKernIdMap in __bss. */
typedef struct {
    id  session;                        /* IOPortSession for this slot, nil if none */
    int inUse;                          /* non-zero once the slot has been handed out */
} nsPortKernSlot;

/* Global kernel port session map - defined here */
static nsPortKernSlot _nsPortKernIdMap[64];

/* Global kernel session state */
static int _numSessions;                /* Number of sessions, 0 until iopsKernInit: */
static id _mapLock = NULL;              /* AppleIOPSSafeCondLock for map access */

/* External kernel functions */
extern int copyout(const void *kaddr, void *uaddr, size_t len);
extern int copyin(const void *uaddr, void *kaddr, size_t len);
extern void bzero(void *s, size_t n);
extern long strtol(const char *str, char **endptr, int base);
extern void strcpy(char *dest, const char *src);
extern int sprintf(char *str, const char *format, ...);
extern void IOLog(const char *format, ...);

@implementation IOPortSession (IOPortSessionKern)

/*
 * getCharValues:forParameter:count: - Get character parameter values
 * values: Buffer to receive character values (output parameter)
 * parameterName: Parameter identifier
 * count: Pointer to the number of values to retrieve (in/out)
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)getCharValues:(char *)values
        forParameter:(IOParameterName)parameterName
               count:(unsigned int *)count
{
    id device;

    /* Check if device object pointer at offset +4 exists */
    if ((*(id **)((char *)self + 4) != 0) && (**(id **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object at *_priv */
        device = **(id **)((char *)self + 4);
        return [device getCharValues:values forParameter:parameterName count:count];
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * getIntValues:forParameter:count: - Get integer parameter values
 * values: Buffer to receive integer values (output parameter)
 * parameterName: Parameter identifier
 * count: Pointer to the number of values to retrieve (in/out)
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)getIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int *)count
{
    id device;

    /* Check if device object pointer at offset +4 exists */
    if ((*(id **)((char *)self + 4) != 0) && (**(id **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object at *_priv */
        device = **(id **)((char *)self + 4);
        return [device getIntValues:values forParameter:parameterName count:count];
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * setCharValues:forParameter:count: - Set character parameter values
 * values: Buffer containing character values to set
 * parameterName: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)setCharValues:(char *)values
        forParameter:(IOParameterName)parameterName
               count:(unsigned int)count
{
    id device;

    /* Check if device object pointer at offset +4 exists */
    if ((*(id **)((char *)self + 4) != 0) && (**(id **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object at *_priv */
        device = **(id **)((char *)self + 4);
        return [device setCharValues:values forParameter:parameterName count:count];
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * setIntValues:forParameter:count: - Set integer parameter values
 * values: Buffer containing integer values to set
 * parameterName: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)setIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int)count
{
    id device;

    /* Check if device object pointer at offset +4 exists */
    if ((*(id **)((char *)self + 4) != 0) && (**(id **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object at *_priv */
        device = **(id **)((char *)self + 4);
        return [device setIntValues:values forParameter:parameterName count:count];
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * iopsKernClose: - Close kernel port session
 * sessionId: Session identifier/index
 * Returns: 0 on success
 *
 * Cleans up and closes a kernel port session by:
 * 1. Checking if the slot is in use
 * 2. Freeing the port object if it exists
 * 3. Clearing the in-use flag
 */
+ (int)iopsKernClose:(int)sessionId
{
    id portObject;

    /* Check if the slot is in use */
    if (_nsPortKernIdMap[sessionId].inUse != 0) {
        /* Check if port object exists in _nsPortKernIdMap */
        portObject = _nsPortKernIdMap[sessionId].session;

        if (portObject != nil) {
            /* Free the port object and store result back (returns nil) */
            _nsPortKernIdMap[sessionId].session = [portObject free];
        }

        /* Clear the in-use flag */
        _nsPortKernIdMap[sessionId].inUse = 0;
    }

    return 0;
}

/*
 * iopsKernDequeue:msg: - Dequeue data from kernel port session
 * session: IOPortSession object to dequeue from
 * msg: Message structure containing buffer and transfer parameters
 * Returns: 0 on success, 0x16 (22) on copyout error
 *
 * Message structure layout (based on decompiled offsets):
 *   +0x0: (unused/padding)
 *   +0x4: field1 - result/error code (int) - output
 *   +0x8: field2 - user buffer pointer (void *) - updated as data copied
 *   +0xc: field3 - bytes remaining to transfer (uint) - updated
 *   +0x10: field4 - total bytes transferred (uint) - output
 *   +0x14: field5 - minimum bytes before return (uint) - updated
 *
 * Algorithm:
 * 1. Initialize result and transfer count to 0
 * 2. Loop while the session handed back everything it was asked for:
 *    a. Dequeue up to 2048 bytes into kernel buffer
 *    b. Copy data to user space using copyout()
 *    c. Update pointers and counters
 *    d. Exit if error, copyout fails, or minCount satisfied
 */
+ (int)iopsKernDequeue:(id)session msg:(void *)msg
{
    unsigned int transferCount;
    int result;
    int copyoutResult;
    unsigned int chunkSize;
    unsigned int minCount;
    char kernelBuffer[2048];  /* 0x800 bytes */

    /* Message structure field pointers */
    int *msgResult = (int *)((char *)msg + 0x4);           /* field1 */
    void **msgUserBuf = (void **)((char *)msg + 0x8);      /* field2 */
    unsigned int *msgRemaining = (unsigned int *)((char *)msg + 0xc);  /* field3 */
    unsigned int *msgTotalXfer = (unsigned int *)((char *)msg + 0x10); /* field4 */
    unsigned int *msgMinCount = (unsigned int *)((char *)msg + 0x14);  /* field5 */

    /* Initialize output fields */
    *msgResult = 0;
    transferCount = 0;
    chunkSize = 0;
    *msgTotalXfer = 0;

    /* Check if there's data to transfer and no initial error */
    if ((*msgRemaining != 0) && (*msgResult == 0)) {
        /* Loop while the session handed back everything it was asked for.
         * Both counters start at 0, so the first pass always runs. */
        while (transferCount == chunkSize) {
            /* Determine chunk size - min of remaining and buffer size (0x800) */
            chunkSize = *msgRemaining;
            if (chunkSize > 0x800) {
                chunkSize = 0x800;
            }

            /* Further limit by minCount if smaller */
            minCount = *msgMinCount;
            if (chunkSize < *msgMinCount) {
                minCount = chunkSize;
            }

            /* Dequeue data from session into kernel buffer */
            result = [session dequeueData:kernelBuffer
                               bufferSize:chunkSize
                            transferCount:&transferCount
                                 minCount:minCount];

            /* Store result code */
            *msgResult = result;

            /* Copy data from kernel buffer to user space */
            copyoutResult = copyout(kernelBuffer, *msgUserBuf, transferCount);
            
            /* Update total bytes transferred */
            *msgTotalXfer = *msgTotalXfer + transferCount;
            
            /* Update user buffer pointer */
            *msgUserBuf = (void *)((char *)*msgUserBuf + transferCount);
            
            /* Update remaining byte count */
            *msgRemaining = *msgRemaining - transferCount;
            
            /* Check for copyout error */
            if (copyoutResult != 0) {
                return 0x16;  /* 22 decimal - EINVAL */
            }
            
            /* Update minimum count */
            if (transferCount < *msgMinCount) {
                *msgMinCount = *msgMinCount - transferCount;
            } else {
                *msgMinCount = 0;
            }
            
            /* Exit conditions */
            if (*msgRemaining == 0) {
                return 0;  /* All data transferred */
            }
            
            if (*msgResult != 0) {
                return 0;  /* Error occurred */
            }

            /* Loop continues while transferCount == chunkSize */
        }
    }

    return 0;
}

/*
 * iopsKernEnqueue:msg: - Enqueue data to kernel port session
 * session: IOPortSession object to enqueue to
 * msg: Message structure containing buffer and transfer parameters
 * Returns: 0 on success, 0x16 (22) on copyin error
 *
 * Message structure layout (based on decompiled offsets):
 *   +0x0: (unused/padding)
 *   +0x4: field1 - result/error code (int) - output
 *   +0x8: field2 - user buffer pointer (void *) - updated as data copied
 *   +0xc: field3 - bytes remaining to transfer (uint) - updated
 *   +0x10: field4 - total bytes transferred (uint) - output
 *   +0x14: field5 - sleep flag (byte) - input
 *
 * Algorithm:
 * 1. Initialize result and transfer count to 0
 * 2. Loop while the session took everything it was offered:
 *    a. Copy up to 2048 bytes from user space using copyin()
 *    b. Enqueue data from kernel buffer to session
 *    c. Update pointers and counters
 *    d. Exit if error, copyin fails, or all data transferred
 */
+ (int)iopsKernEnqueue:(id)session msg:(void *)msg
{
    unsigned int transferCount;
    int result;
    int copyinResult;
    unsigned int chunkSize;
    char *kernelBufPtr;
    char kernelBuffer[2048];  /* 0x800 bytes */

    /* Message structure field pointers */
    int *msgResult = (int *)((char *)msg + 0x4);           /* field1 */
    void **msgUserBuf = (void **)((char *)msg + 0x8);      /* field2 */
    unsigned int *msgRemaining = (unsigned int *)((char *)msg + 0xc);  /* field3 */
    unsigned int *msgTotalXfer = (unsigned int *)((char *)msg + 0x10); /* field4 */
    char *msgSleepFlag = (char *)((char *)msg + 0x14);     /* field5 (byte) */

    /* Start one past the end of the buffer so the first pass refills it */
    kernelBufPtr = kernelBuffer + sizeof kernelBuffer;

    /* Initialize output fields */
    *msgResult = 0;
    transferCount = 0;
    chunkSize = 0;
    *msgTotalXfer = 0;

    /* Check if there's data to transfer and no initial error */
    if ((*msgRemaining != 0) && (*msgResult == 0)) {
        /* Loop while the session took everything it was offered.
         * Both counters start at 0, so the first pass always runs. */
        while (transferCount == chunkSize) {
            /* Check if we need to refill the kernel buffer */
            if (kernelBufPtr >= kernelBuffer + sizeof kernelBuffer) {
                /* Reset buffer pointer to start */
                kernelBufPtr = kernelBuffer;

                /* Determine chunk size - min of remaining and buffer size (0x800) */
                chunkSize = *msgRemaining;
                if (chunkSize > 0x800) {
                    chunkSize = 0x800;
                }

                /* Copy data from user space to kernel buffer */
                copyinResult = copyin(*msgUserBuf, kernelBufPtr, chunkSize);

                /* Check for copyin error */
                if (copyinResult != 0) {
                    return 0x16;  /* 22 decimal - EINVAL */
                }

                /* Update user buffer pointer */
                *msgUserBuf = (void *)((char *)*msgUserBuf + chunkSize);
            } else {
                /* Offer what is left of the chunk already copied in */
                chunkSize = chunkSize - transferCount;
            }

            /* Enqueue data from kernel buffer to session */
            result = [session enqueueData:kernelBufPtr
                               bufferSize:chunkSize
                            transferCount:&transferCount
                                    sleep:*msgSleepFlag];

            /* Store result code */
            *msgResult = result;

            /* Update kernel buffer pointer */
            kernelBufPtr = kernelBufPtr + transferCount;

            /* Update total bytes transferred */
            *msgTotalXfer = *msgTotalXfer + transferCount;

            /* Update remaining byte count */
            *msgRemaining = *msgRemaining - transferCount;

            /* Exit conditions */
            if (*msgRemaining == 0) {
                return 0;  /* All data transferred */
            }

            if (*msgResult != 0) {
                return 0;  /* Error occurred */
            }

            /* Loop continues while transferCount == chunkSize */
        }
    }

    return 0;
}

/*
 * iopsKernFree - Free kernel port session resources
 * Returns: 0 always
 *
 * Cleanup procedure:
 * 1. Close all active sessions (0 to _numSessions)
 * 2. Reset _numSessions to 0
 * 3. Free the map lock
 * 4. Zero out the kernel ID map (0x200 = 512 bytes)
 */
+ (id)iopsKernFree
{
    int sessionIndex;

    /* Close all sessions from 0 to _numSessions */
    sessionIndex = 0;
    if (_numSessions >= 0) {
        do {
            /* Close this session */
            [self iopsKernClose:sessionIndex];

            sessionIndex = sessionIndex + 1;
        } while (sessionIndex <= _numSessions);
    }

    /* Reset session count */
    _numSessions = 0;

    /* Free the map lock */
    _mapLock = [_mapLock free];

    /* Zero out the kernel ID map (0x200 = 512 bytes) */
    bzero(_nsPortKernIdMap, sizeof _nsPortKernIdMap);

    return 0;
}

/*
 * iopsKernInit: - Initialize kernel port session subsystem
 * deviceDescription: Device description object containing configuration
 *
 * Initialization steps:
 * 1. Get config table from device description
 * 2. Read "Maximum Sessions" from config (max 64/0x40)
 * 3. Initialize _numSessions if higher than current
 * 4. Create map lock if not already created
 * 5. Zero out kernel ID map and set initial state
 */
+ (void)iopsKernInit:(id)deviceDescription
{
    id configTable;
    char *maxSessionsStr;
    long maxSessions;

    /* Get config table from device description */
    configTable = [deviceDescription configTable];

    if (configTable == nil) {
        /* No config table - log error and mark as invalid */
        IOLog("IOPortSessionKern: Invalid Config Table\n");
        _numSessions = -1;
    } else {
        /* Read "Maximum Sessions" value from config */
        maxSessionsStr = (char *)[configTable valueForStringKey:"Maximum Sessions"];

        /* Convert string to long */
        maxSessions = strtol(maxSessionsStr, (char **)0, 0);

        /* Free the string returned by valueForStringKey */
        [configTable freeString:maxSessionsStr];

        /* Limit to maximum of 64 (0x40) sessions */
        if (maxSessions > 0x3f) {
            maxSessions = 0x40;
        }

        /* Update _numSessions if this value is higher */
        if (_numSessions < maxSessions) {
            _numSessions = maxSessions;
        }

        /* Initialize map lock if not already created */
        if (_mapLock == nil) {
            /* Zero out the kernel ID map (0x200 = 512 bytes) */
            bzero(_nsPortKernIdMap, sizeof _nsPortKernIdMap);

            /* Reserve slot 0 so minor 0 never enters the pool */
            _nsPortKernIdMap[0].inUse = 1;

            /* Create AppleIOPSSafeCondLock */
            _mapLock = [[AppleIOPSSafeCondLock alloc] init];
        }
    }
}

/*
 * iopsKernInitIoctl:data: - Handle kernel port session ioctl initialization
 * sessionId: Session identifier/index
 * data: Ioctl data buffer
 * Returns: 0 on success, 0x16 (22) on error
 *
 * Data buffer layout:
 *   +0x0 (int): Operation code
 *   +0x4 (int): Result field (for op 0)
 *   +0x8 (char[]): Device name (op 0) or output buffer (op 1)
 *
 * Operations:
 *   0: Initialize session for device - calls initForDevice:result:
 *   1: Get session name - copies name to data+8
 *   Other: Return error 0x16
 */
+ (int)iopsKernInitIoctl:(int)sessionId data:(char *)data
{
    int result;
    id sessionObject;
    id newSessionObject;
    const char *sessionName;
    int operation;

    /* Get session object from kernel ID map */
    sessionObject = _nsPortKernIdMap[sessionId].session;

    result = 0;

    if (sessionObject == nil) {
        /* No session object - return error */
        result = 0x16;  /* 22 decimal - EINVAL */
    } else {
        /* Get operation code from data[0] */
        operation = *(int *)data;

        if (operation == 0) {
            /* Operation 0: Initialize session for device
             * data+8: device name (input)
             * data+4: result code (output)
             */
            newSessionObject = [sessionObject initForDevice:data + 8
                                                     result:(int *)(data + 4)];

            /* Store new session object back in map */
            _nsPortKernIdMap[sessionId].session = newSessionObject;

        } else if (operation == 1) {
            /* Operation 1: Get session name
             * data+8: output buffer for name
             */
            sessionName = [sessionObject name];

            /* Copy name to output buffer */
            strcpy(data + 8, sessionName);

        } else {
            /* Unknown operation - return error */
            result = 0x16;  /* 22 decimal - EINVAL */
        }
    }
    
    return result;
}

/*
 * iopsKernMsgIoctl:data: - Handle kernel port session message ioctl
 */
+ (int)iopsKernMsgIoctl:(int)sessionId data:(char *)data
{
    int result;
    id sessionObject;
    int operation;
    char auditFlag;
    unsigned int stateValue;
    unsigned int maskValue;
    unsigned int eventValue;
    unsigned int eventData;
    char sleepFlag;
    unsigned int transferSize;
    int minCount;

    sessionObject = _nsPortKernIdMap[sessionId].session;

    result = 0;

    if (sessionObject == nil) {
        return 0x16;
    }

    operation = *(int *)data;

    switch (operation) {
    case 2:
        auditFlag = [sessionObject locked];
        *(int *)(data + 4) = (int)auditFlag;
        break;

    case 3:
        auditFlag = data[8];
        stateValue = [sessionObject acquireAudit:auditFlag];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 4:
        auditFlag = data[8];
        stateValue = [sessionObject acquire:auditFlag];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 5:
        stateValue = [sessionObject release];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 6:
        stateValue = *(unsigned int *)(data + 8);
        maskValue = *(unsigned int *)(data + 0xc);
        stateValue = [sessionObject setState:stateValue mask:maskValue];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 7:
        stateValue = [sessionObject getState];
        *(unsigned int *)(data + 8) = stateValue;
        break;

    case 8:
        maskValue = *(unsigned int *)(data + 0xc);
        stateValue = [sessionObject watchState:(unsigned long *)(data + 8)
                                          mask:maskValue];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 9:
        stateValue = [sessionObject nextEvent];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 10:
        eventValue = *(unsigned int *)(data + 8);
        eventData = *(unsigned int *)(data + 0xc);
        stateValue = [sessionObject executeEvent:eventValue data:eventData];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 11:
        eventValue = *(unsigned int *)(data + 8);
        stateValue = [sessionObject requestEvent:eventValue
                                            data:(unsigned long *)(data + 0xc)];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 12:
        sleepFlag = data[0x10];
        eventValue = *(unsigned int *)(data + 8);
        eventData = *(unsigned int *)(data + 0xc);
        stateValue = [sessionObject enqueueEvent:eventValue
                                            data:eventData
                                           sleep:sleepFlag];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 13:
        sleepFlag = data[0x10];
        stateValue = [sessionObject dequeueEvent:(unsigned long *)(data + 8)
                                            data:(unsigned long *)(data + 0xc)
                                           sleep:sleepFlag];
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 14:
        transferSize = *(unsigned int *)(data + 0xc);
        if (transferSize > 4) {
            return [IOPortSession iopsKernEnqueue:sessionObject msg:data];
        } else {
            sleepFlag = data[0x14];
            stateValue = [sessionObject enqueueData:data + 8
                                         bufferSize:transferSize
                                      transferCount:(unsigned int *)(data + 0x10)
                                              sleep:sleepFlag];
            *(unsigned int *)(data + 4) = stateValue;
        }
        break;

    case 15:
        transferSize = *(unsigned int *)(data + 0xc);
        if (transferSize > 4) {
            return [IOPortSession iopsKernDequeue:sessionObject msg:data];
        } else {
            minCount = *(int *)(data + 0x14);
            stateValue = [sessionObject dequeueData:data + 8
                                         bufferSize:transferSize
                                      transferCount:(unsigned int *)(data + 0x10)
                                           minCount:minCount];
            *(unsigned int *)(data + 4) = stateValue;
        }
        break;

    default:
        result = 0x16;
        break;
    }

    return result;
}

+ (int)iopsKernNumSess
{
    return _numSessions;
}

+ (int)iopsKernOpen:(int)sessionId
{
    int result;

    if (_nsPortKernIdMap[sessionId].inUse == 0) {
        result = 0x13;
    } else if (_nsPortKernIdMap[sessionId].session == nil) {
        _nsPortKernIdMap[sessionId].session = [IOPortSession alloc];
        result = 0;
    } else {
        result = 0xd;
    }

    return result;
}

+ (int)iopsServerIoctlCommand:(int)command data:(char *)data
{
    int result;
    int objectNumber;
    int lookupResult;
    id deviceObject;
    int sessionIndex;

    result = 0;

    if (command == 0xc0047000) {
        objectNumber = *(int *)data;

        if (objectNumber < -1) {
            objectNumber = -1;
        }

        while (1) {
            objectNumber = objectNumber + 1;

            lookupResult = [IODevice lookupByObjectNumber:objectNumber
                                                 instance:&deviceObject];

            if ((lookupResult == 0) &&
                [deviceObject conformsTo:@protocol(PortDevices)]) {
                /* Found a conforming device - hand its number back */
                *(int *)data = objectNumber;
                return 0;
            }

            if (lookupResult == -0x2c0) {
                /* No more devices to check - data is left untouched */
                return 6;  /* ENXIO - not found */
            }
        }

    } else if (command == 0x40547001) {
        result = [_mapLock lock];
        if (result != 0) {
            return 4;
        }

        sessionIndex = 0;
        if (_numSessions >= 0) {
            do {
                if (_nsPortKernIdMap[sessionIndex].inUse == 0) {
                    break;
                }
                sessionIndex = sessionIndex + 1;
            } while (sessionIndex <= _numSessions);

            if (sessionIndex <= _numSessions) {
                _nsPortKernIdMap[sessionIndex].inUse = 1;
                sprintf(data, "/dev/rpski%02d", sessionIndex);
                result = 0;
            } else {
                result = 6;
            }
        } else {
            result = 6;
        }

        [_mapLock unlock];

        return result;

    } else {
        return 0x16;
    }
}

@end
