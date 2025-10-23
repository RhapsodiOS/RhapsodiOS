/*
 * IOPortSessionKern.m
 * Kernel-level parameter access for IOPortSession
 */

#import "IOPortSessionKern.h"
#import <objc/objc-runtime.h>

/* External global arrays for kernel port session management */
extern id _nsPortKernIdMap[];      /* Array of port kernel session objects */
extern char _nsPortKernStateMap[]; /* Array of session state flags */

/* External global variables for session management */
extern int _numSessions;           /* Number of sessions (-1 if not initialized) */
extern id _mapLock;                /* AppleIOPSSafeCondLock for map access */

/* External kernel functions */
extern int copyout(const void *kaddr, void *uaddr, size_t len);
extern int copyin(const void *uaddr, void *kaddr, size_t len);
extern void bzero(void *s, size_t n);
extern long strtol(const char *str, char **endptr, int base);
extern void strcpy(char *dest, const char *src);
extern int sprintf(char *str, const char *format, ...);
extern void IOLog(const char *format, ...);

/* External protocol - objc_protocol_000068d4 */
extern Protocol *objc_protocol_PortDevices;  /* @protocol(PortDevices) */

@implementation IOPortSession (IOPortSessionKern)

/*
 * _getCharValues:forParameter:count: - Get character parameter values
 * values: Buffer to receive character values (output parameter)
 * parameter: Parameter identifier
 * count: Number of values to retrieve
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)_getCharValues:(unsigned char *)values forParameter:(int)parameter count:(int)count
{
    int result;

    /* Check if device object pointer at offset +4 exists */
    if ((*(int *)((char *)self + 4) != 0) && (**(int **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object
         * Device object is at: **(int **)((char *)self + 4)
         */
        result = objc_msgSend(**(int **)((char *)self + 4),
                             @selector(getCharValues:forParameter:count:),
                             values, parameter, count);
        return result;
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * _getIntValues:forParameter:count: - Get integer parameter values
 * values: Buffer to receive integer values (output parameter)
 * parameter: Parameter identifier
 * count: Number of values to retrieve
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)_getIntValues:(unsigned int *)values forParameter:(int)parameter count:(int)count
{
    int result;

    /* Check if device object pointer at offset +4 exists */
    if ((*(int *)((char *)self + 4) != 0) && (**(int **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object
         * Device object is at: **(int **)((char *)self + 4)
         */
        result = objc_msgSend(**(int **)((char *)self + 4),
                             @selector(getIntValues:forParameter:count:),
                             values, parameter, count);
        return result;
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * _setCharValues:forParameter:count: - Set character parameter values
 * values: Buffer containing character values to set
 * parameter: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)_setCharValues:(unsigned char *)values forParameter:(int)parameter count:(int)count
{
    int result;

    /* Check if device object pointer at offset +4 exists */
    if ((*(int *)((char *)self + 4) != 0) && (**(int **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object
         * Device object is at: **(int **)((char *)self + 4)
         * Note: count is passed directly as unsigned int, not pointer
         */
        result = objc_msgSend(**(int **)((char *)self + 4),
                             @selector(setCharValues:forParameter:count:),
                             values, parameter, count);
        return result;
    }

    /* No device object - return error code */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * _setIntValues:forParameter:count: - Set integer parameter values
 * values: Buffer containing integer values to set
 * parameter: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if no device)
 *
 * Forwards the call to the underlying device object at offset +4
 */
- (int)_setIntValues:(unsigned int *)values forParameter:(int)parameter count:(int)count
{
    int result;

    /* Check if device object pointer at offset +4 exists */
    if ((*(int *)((char *)self + 4) != 0) && (**(int **)((char *)self + 4) != 0)) {
        /* Forward the call to the device object
         * Device object is at: **(int **)((char *)self + 4)
         * Note: count is passed directly as unsigned int, not pointer
         */
        result = objc_msgSend(**(int **)((char *)self + 4),
                             @selector(setIntValues:forParameter:count:),
                             values, parameter, count);
        return result;
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
 * 1. Checking if session state flag is set
 * 2. Freeing the port object if it exists
 * 3. Clearing the session state flag
 *
 * Array indexing:
 * - _nsPortKernIdMap uses index * 8 (2 words per entry)
 * - _nsPortKernStateMap uses index * 2 (half-word per entry)
 */
- (int)iopsKernClose:(int)sessionId
{
    int arrayIndex;
    id portObject;
    
    /* Calculate array index for state map (sessionId * 2) */
    arrayIndex = sessionId * 8;  /* For _nsPortKernIdMap access */
    
    /* Check if session state flag is set at (sessionId * 2) offset */
    if (_nsPortKernStateMap[sessionId * 2] != 0) {
        /* Check if port object exists in _nsPortKernIdMap */
        portObject = *(id *)((char *)_nsPortKernIdMap + arrayIndex);
        
        if (portObject != NULL) {
            /* Free the port object and store result back (likely returns nil) */
            portObject = objc_msgSend(portObject, @selector(free));
            *(id *)((char *)_nsPortKernIdMap + arrayIndex) = portObject;
        }
        
        /* Clear the session state flag */
        _nsPortKernStateMap[sessionId * 2] = 0;
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
 * 2. Loop while data remains and no error:
 *    a. Dequeue up to 2048 bytes into kernel buffer
 *    b. Copy data to user space using copyout()
 *    c. Update pointers and counters
 *    d. Exit if error, copyout fails, or minCount satisfied
 */
- (int)iopsKernDequeue:(id)session msg:(void *)msg
{
    unsigned int transferCount;
    int result;
    int copyoutResult;
    unsigned int chunkSize;
    unsigned int minCount;
    unsigned char kernelBuffer[2048];  /* 0x800 bytes */
    
    /* Message structure field pointers */
    int *msgResult = (int *)((char *)msg + 0x4);           /* field1 */
    void **msgUserBuf = (void **)((char *)msg + 0x8);      /* field2 */
    unsigned int *msgRemaining = (unsigned int *)((char *)msg + 0xc);  /* field3 */
    unsigned int *msgTotalXfer = (unsigned int *)((char *)msg + 0x10); /* field4 */
    unsigned int *msgMinCount = (unsigned int *)((char *)msg + 0x14);  /* field5 */
    
    /* Initialize output fields */
    *msgResult = 0;
    transferCount = 0;
    *msgTotalXfer = 0;
    
    /* Check if there's data to transfer and no initial error */
    if ((*msgRemaining != 0) && (*msgResult == 0)) {
        /* Loop while no data was transferred (retry until we get something) */
        while (transferCount == 0) {
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
            result = objc_msgSend(session,
                                 @selector(dequeueData:bufferSize:transferCount:minCount:),
                                 kernelBuffer,
                                 chunkSize,
                                 &transferCount,
                                 minCount);
            
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
            
            /* Loop continues if transferCount == 0 (retry) */
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
 * 2. Loop while data remains and no error:
 *    a. Copy up to 2048 bytes from user space using copyin()
 *    b. Enqueue data from kernel buffer to session
 *    c. Update pointers and counters
 *    d. Exit if error, copyin fails, or all data transferred
 */
- (int)iopsKernEnqueue:(id)session msg:(void *)msg
{
    unsigned int transferCount;
    int result;
    int copyinResult;
    unsigned int chunkSize;
    unsigned int remainingInBuffer;
    unsigned char *kernelBufPtr;
    unsigned char kernelBuffer[2048];  /* 0x800 bytes */
    
    /* Message structure field pointers */
    int *msgResult = (int *)((char *)msg + 0x4);           /* field1 */
    void **msgUserBuf = (void **)((char *)msg + 0x8);      /* field2 */
    unsigned int *msgRemaining = (unsigned int *)((char *)msg + 0xc);  /* field3 */
    unsigned int *msgTotalXfer = (unsigned int *)((char *)msg + 0x10); /* field4 */
    char *msgSleepFlag = (char *)((char *)msg + 0x14);     /* field5 (byte) */
    
    /* Initialize local variables */
    kernelBufPtr = kernelBuffer;
    
    /* Initialize output fields */
    *msgResult = 0;
    transferCount = 0;
    remainingInBuffer = 0;
    *msgTotalXfer = 0;
    
    /* Check if there's data to transfer and no initial error */
    if ((*msgRemaining != 0) && (*msgResult == 0)) {
        /* Loop while no data was transferred (retry until we enqueue something) */
        while (transferCount == 0) {
            /* Check if we need to refill the kernel buffer */
            if (remainingInBuffer == 0) {
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
                
                /* Set remaining bytes in buffer */
                remainingInBuffer = chunkSize;
            } else {
                /* Adjust remaining buffer size after partial enqueue */
                remainingInBuffer = remainingInBuffer - transferCount;
            }
            
            /* Enqueue data from kernel buffer to session */
            result = objc_msgSend(session,
                                 @selector(enqueueData:bufferSize:transferCount:sleep:),
                                 kernelBufPtr,
                                 remainingInBuffer,
                                 &transferCount,
                                 (int)*msgSleepFlag);
            
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
            
            /* Loop continues if transferCount == 0 (retry) */
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
- (id)iopsKernFree
{
    int sessionIndex;
    
    /* Close all sessions from 0 to _numSessions */
    sessionIndex = 0;
    if (_numSessions >= 0) {
        do {
            /* Close this session */
            objc_msgSend(self, @selector(iopsKernClose:), sessionIndex);
            
            sessionIndex = sessionIndex + 1;
        } while (sessionIndex <= _numSessions);
    }
    
    /* Reset session count */
    _numSessions = 0;
    
    /* Free the map lock */
    _mapLock = objc_msgSend(_mapLock, @selector(free));
    
    /* Zero out the kernel ID map (0x200 = 512 bytes) */
    bzero(&_nsPortKernIdMap, 0x200);
    
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
- (void)iopsKernInit:(id)deviceDescription
{
    id configTable;
    char *maxSessionsStr;
    long maxSessions;
    id lockAlloc;
    
    /* Get config table from device description */
    configTable = objc_msgSend(deviceDescription, @selector(configTable));
    
    if (configTable == NULL) {
        /* No config table - log error and mark as invalid */
        IOLog("IOPortSessionKern: Invalid Config Table
");
        _numSessions = -1;
    } else {
        /* Read "Maximum Sessions" value from config */
        maxSessionsStr = (char *)objc_msgSend(configTable,
                                              @selector(valueForStringKey:),
                                              "Maximum Sessions");
        
        /* Convert string to long */
        maxSessions = strtol(maxSessionsStr, (char **)0, 0);
        
        /* Free the string returned by valueForStringKey */
        objc_msgSend(configTable, @selector(freeString:), maxSessionsStr);
        
        /* Limit to maximum of 64 (0x40) sessions */
        if (maxSessions > 0x3f) {
            maxSessions = 0x40;
        }
        
        /* Update _numSessions if this value is higher */
        if (_numSessions < maxSessions) {
            _numSessions = maxSessions;
        }
        
        /* Initialize map lock if not already created */
        if (_mapLock == NULL) {
            /* Zero out the kernel ID map (0x200 = 512 bytes) */
            bzero(&_nsPortKernIdMap, 0x200);
            
            /* Set initial state flag (at offset matching DAT_000081a8) */
            _nsPortKernStateMap[0] = 1;
            
            /* Create AppleIOPSSafeCondLock */
            lockAlloc = objc_msgSend(objc_getClass("AppleIOPSSafeCondLock"),
                                     @selector(alloc));
            _mapLock = objc_msgSend(lockAlloc, @selector(init));
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
- (int)iopsKernInitIoctl:(int)sessionId data:(char *)data
{
    int result;
    id sessionObject;
    id newSessionObject;
    const char *sessionName;
    int operation;
    
    /* Get session object from kernel ID map (sessionId * 8 offset) */
    sessionObject = *(id *)((char *)_nsPortKernIdMap + (sessionId * 8));
    
    result = 0;
    
    if (sessionObject == NULL) {
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
            newSessionObject = objc_msgSend(sessionObject,
                                           @selector(initForDevice:result:),
                                           data + 8,
                                           data + 4);
            
            /* Store new session object back in map */
            *(id *)((char *)_nsPortKernIdMap + (sessionId * 8)) = newSessionObject;
            
        } else if (operation == 1) {
            /* Operation 1: Get session name
             * data+8: output buffer for name
             */
            sessionName = (const char *)objc_msgSend(sessionObject, @selector(name));
            
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
- (int)iopsKernMsgIoctl:(int)sessionId data:(char *)data
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

    sessionObject = *(id *)((char *)_nsPortKernIdMap + (sessionId * 8));

    result = 0;

    if (sessionObject == NULL) {
        return 0x16;
    }

    operation = *(int *)data;

    switch (operation) {
    case 2:
        auditFlag = objc_msgSend(sessionObject, @selector(locked));
        *(int *)(data + 4) = (int)auditFlag;
        break;

    case 3:
        auditFlag = data[8];
        stateValue = objc_msgSend(sessionObject,
                                  @selector(acquireAudit:),
                                  (int)auditFlag);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 4:
        auditFlag = data[8];
        stateValue = objc_msgSend(sessionObject,
                                  @selector(acquire:),
                                  (int)auditFlag);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 5:
        stateValue = objc_msgSend(sessionObject, @selector(release));
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 6:
        stateValue = *(unsigned int *)(data + 8);
        maskValue = *(unsigned int *)(data + 0xc);
        stateValue = objc_msgSend(sessionObject,
                                  @selector(setState:mask:),
                                  stateValue,
                                  maskValue);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 7:
        stateValue = objc_msgSend(sessionObject, @selector(getState));
        *(unsigned int *)(data + 8) = stateValue;
        break;

    case 8:
        maskValue = *(unsigned int *)(data + 0xc);
        stateValue = objc_msgSend(sessionObject,
                                  @selector(watchState:mask:),
                                  data + 8,
                                  maskValue);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 9:
        stateValue = objc_msgSend(sessionObject, @selector(nextEvent));
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 10:
        eventValue = *(unsigned int *)(data + 8);
        eventData = *(unsigned int *)(data + 0xc);
        stateValue = objc_msgSend(sessionObject,
                                  @selector(executeEvent:data:),
                                  eventValue,
                                  eventData);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 11:
        eventValue = *(unsigned int *)(data + 8);
        stateValue = objc_msgSend(sessionObject,
                                  @selector(requestEvent:data:),
                                  eventValue,
                                  data + 0xc);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 12:
        sleepFlag = data[0x10];
        eventValue = *(unsigned int *)(data + 8);
        eventData = *(unsigned int *)(data + 0xc);
        stateValue = objc_msgSend(sessionObject,
                                  @selector(enqueueEvent:data:sleep:),
                                  eventValue,
                                  eventData,
                                  (int)sleepFlag);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 13:
        sleepFlag = data[0x10];
        stateValue = objc_msgSend(sessionObject,
                                  @selector(dequeueEvent:data:sleep:),
                                  data + 8,
                                  data + 0xc,
                                  (int)sleepFlag);
        *(unsigned int *)(data + 4) = stateValue;
        break;

    case 14:
        transferSize = *(unsigned int *)(data + 0xc);
        if (transferSize > 4) {
            result = objc_msgSend(objc_getClass("IOPortSession"),
                                 @selector(iopsKernEnqueue:msg:),
                                 sessionObject,
                                 data);
            return result;
        } else {
            sleepFlag = data[0x14];
            stateValue = objc_msgSend(sessionObject,
                                      @selector(enqueueData:bufferSize:transferCount:sleep:),
                                      data + 8,
                                      transferSize,
                                      data + 0x10,
                                      (int)sleepFlag);
            *(unsigned int *)(data + 4) = stateValue;
        }
        break;

    case 15:
        transferSize = *(unsigned int *)(data + 0xc);
        if (transferSize > 4) {
            result = objc_msgSend(objc_getClass("IOPortSession"),
                                 @selector(iopsKernDequeue:msg:),
                                 sessionObject,
                                 data);
            return result;
        } else {
            minCount = *(int *)(data + 0x14);
            stateValue = objc_msgSend(sessionObject,
                                      @selector(dequeueData:bufferSize:transferCount:minCount:),
                                      data + 8,
                                      transferSize,
                                      data + 0x10,
                                      minCount);
            *(unsigned int *)(data + 4) = stateValue;
        }
        break;

    default:
        result = 0x16;
        break;
    }

    return result;
}

- (int)iopsKernNumSess
{
    return _numSessions;
}

- (int)iopsKernOpen:(int)sessionId
{
    int result;
    id sessionAlloc;

    if (_nsPortKernStateMap[sessionId * 2] == 0) {
        result = 0x13;
    } else if (*(id *)((char *)_nsPortKernIdMap + (sessionId * 8)) == NULL) {
        sessionAlloc = objc_msgSend(objc_getClass("IOPortSession"),
                                    @selector(alloc));
        *(id *)((char *)_nsPortKernIdMap + (sessionId * 8)) = sessionAlloc;
        result = 0;
    } else {
        result = 0xd;
    }

    return result;
}

- (int)iopsServerIoctlCommand:(int)command data:(char *)data
{
    int result;
    int objectNumber;
    int lookupResult;
    id deviceObject;
    char conformsResult;
    int sessionIndex;

    result = 0;

    if (command == 0xc0047000) {
        objectNumber = *(int *)data;

        if (objectNumber < -1) {
            objectNumber = -1;
        }

        while (1) {
            objectNumber = objectNumber + 1;

            lookupResult = objc_msgSend(objc_getClass("IODevice"),
                                       @selector(lookupByObjectNumber:instance:),
                                       objectNumber,
                                       &deviceObject);

            if ((lookupResult == 0) &&
                (conformsResult = objc_msgSend(deviceObject,
                                              @selector(conformsTo:),
                                              objc_protocol_PortDevices),
                 conformsResult != 0)) {
                break;
            }

            if (lookupResult == -0x2c0) {
                /* No more devices to check */
                break;
            }
        }

        /* Update object number in data */
        *(int *)data = objectNumber;

        /* Check final result - LAB_00001c1a */
        if (lookupResult != -0x2c0) {
            return 0;  /* Found device */
        }
        return 6;  /* ENXIO - not found */

    } else if (command == 0x40547001) {
        result = objc_msgSend(_mapLock, @selector(lock));
        if (result != 0) {
            return 4;
        }

        sessionIndex = 0;
        if (_numSessions >= 0) {
            do {
                if (_nsPortKernStateMap[sessionIndex * 2] == 0) {
                    break;
                }
                sessionIndex = sessionIndex + 1;
            } while (sessionIndex <= _numSessions);

            if (sessionIndex <= _numSessions) {
                _nsPortKernStateMap[sessionIndex * 2] = 1;
                sprintf(data, "/dev/rpski%02d", sessionIndex);
                result = 0;
            } else {
                result = 6;
            }
        } else {
            result = 6;
        }

        objc_msgSend(_mapLock, @selector(unlock));

        return result;

    } else {
        return 0x16;
    }
}

@end
