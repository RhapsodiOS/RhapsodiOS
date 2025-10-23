/*
 * SCSIServer.m
 * Main SCSIServer driver implementation
 */

#import "SCSIServer.h"
#import "IOSCSISession.h"
#import <objc/objc-runtime.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IODevice.h>
#import <string.h>
#import <mach/mach.h>

/* Global SCSI server structures */
static id _scsiServerLock = NULL;           /* Lock for SCSI server operations */
static id _scsiControllerList = NULL;       /* List of registered SCSI controllers */
static int _scsiServerMajor = 0;            /* Major device number for SCSI server */
static id _server = NULL;                   /* Global SCSIServer instance */

/* Protocol array for SCSIServer */
extern Protocol *objc_protocol_IOSCSIController;  /* @protocol(IOSCSIController) */
static Protocol *_scsiServerProtocols[] = {
    &objc_protocol_IOSCSIController,
    NULL
};

@implementation SCSIServer

/*
 * deviceStyle - Get device style
 * Returns: 1 (IO_DirectDevice style)
 *
 * This class method returns the device style for SCSIServer.
 * The value 1 corresponds to IO_DirectDevice, indicating this is
 * a direct (not indirect) device driver.
 */
+ (int)deviceStyle
{
    return 1;
}

/*
 * probe: - Probe for SCSI server device
 * deviceDescription: Device description to probe
 * Returns: YES (1) if probe successful, NO (0) otherwise
 *
 * Initializes the SCSI server subsystem and creates a SCSIServer instance.
 *
 * The decompiled code shows this behavior:
 * 1. If _server is NULL (first probe):
 *    - Allocate and initialize a new SCSIServer instance
 *    - Return YES if successful, NO if failed
 * 2. If _server exists (subsequent probe):
 *    - Register the deviceDescription as a SCSI controller
 *    - Always return NO (only one SCSIServer instance allowed)
 *
 * This ensures only one SCSIServer instance exists, with subsequent
 * probes registering additional controllers.
 */
+ (BOOL)probe:(id)deviceDescription
{
    id allocatedServer;
    BOOL result;

    result = NO;

    /* Check if server instance already exists */
    if (_server == NULL) {
        /* First probe - create the SCSIServer instance */

        /* Allocate SCSIServer: [[self class] alloc]
         * uVar1 = FUN_000000d4(param_1, s_class_000059dc)
         * uVar1 = FUN_000000d4(uVar1, s_alloc_000059e4)
         */
        allocatedServer = objc_msgSend(objc_msgSend(self, @selector(class)),
                                       @selector(alloc));

        /* Initialize with device description
         * _server = FUN_000000d4(uVar1, s_initFromDeviceDescription:_000059c0, param_3)
         */
        _server = objc_msgSend(allocatedServer,
                               @selector(initFromDeviceDescription:),
                               deviceDescription);

        /* Calculate return value: cVar2 = '\x01' - (_server == 0)
         * If _server != NULL (success): return = 1 - 0 = 1 (YES)
         * If _server == NULL (failure): return = 1 - 1 = 0 (NO)
         */
        result = (_server != NULL);

        if (result) {
            IOLog("SCSIServer: probe successful - server instance created\n");
        } else {
            IOLog("SCSIServer: probe failed - initialization failed\n");
        }
    }
    else {
        /* Server already exists - register this as a SCSI controller
         * FUN_000000d4(_server, s_registerSCSIController:_000059a8, param_3)
         */
        objc_msgSend(_server, @selector(registerSCSIController:), deviceDescription);

        /* Always return NO for subsequent probes (result already = NO)
         * This prevents multiple SCSIServer instances
         */
        IOLog("SCSIServer: probe - registering additional controller\n");
    }

    return result;
}

/*
 * requiredProtocols - Get required protocols
 * Returns: Pointer to protocols array
 *
 * Returns the array of protocols that SCSI devices must conform to.
 */
+ (Protocol **)requiredProtocols
{
    return _scsiServerProtocols;
}

/*
 * initFromDeviceDescription: - Initialize SCSIServer from device description
 * deviceDescription: Device description structure
 * Returns: initialized object or result of [self free] on failure
 *
 * Sets up the SCSI server instance and registers it as a device.
 *
 * The decompiled code shows this sequence:
 * 1. Call [self registerSCSIController:] with self as argument - if fails, return [self free]
 * 2. Set name to "SCSI Server"
 * 3. Set device kind to "SCSI Server"
 * 4. Call [super initFromDeviceDescription:]
 * 5. If successful, call [self registerDevice] and set global _server
 * 6. Return the result
 */
- initFromDeviceDescription:(id)deviceDescription
{
    int registerResult;
    struct objc_super superStruct;
    id initResult;

    /* Register self as SCSI controller
     * iVar1 = FUN_000001d0(param_1, s_registerSCSIController:_000059a8)
     * This appears to be [self registerSCSIController:self] but that doesn't make sense.
     * Actually, looking at the decompiled code, this checks if registration is possible.
     * The return value check (iVar1 != 0) suggests this is a capability check.
     *
     * However, registerSCSIController: expects a controller object, not self.
     * This might be checking some capability or doing self-registration.
     * For now, let's interpret this as a registration capability check.
     */
    registerResult = (int)[self registerSCSIController:self];

    if (registerResult == 0) {
        /* Registration check failed - free and return */
        return [self free];
    }

    /* Set the device name to "SCSI Server"
     * FUN_000001d0(param_1, s_setName:_000059f4, "SCSI Server")
     */
    [self setName:"SCSI Server"];

    /* Set the device kind to "SCSI Server"
     * FUN_000001d0(param_1, s_setDeviceKind:_00005a00, "SCSI Server")
     */
    [self setDeviceKind:"SCSI Server"];

    /* Call [super initFromDeviceDescription:]
     * local_14 = PTR_s_IODevice_0000519c
     * local_18 = param_1
     * IVar2 = FUN_000001c0(&local_18, s_initFromDeviceDescription:_000059c0, param_3)
     */
    superStruct.receiver = self;
    superStruct.class = objc_getClass("IODevice");
    initResult = objc_msgSendSuper(&superStruct,
                                   @selector(initFromDeviceDescription:),
                                   deviceDescription);

    if (initResult == NULL) {
        /* Super initialization failed - free and return */
        return [self free];
    }

    /* Register the device
     * FUN_000001d0(param_1, s_registerDevice_00005a10)
     */
    [self registerDevice];

    /* Store this instance in global _server variable
     * _server = param_1
     */
    _server = self;

    IOLog("SCSIServer: Initialized successfully as 'SCSI Server'\n");

    return initResult;
}

/*
 * registerSCSIController: - Register a SCSI controller with the server
 * controller: SCSI controller object to register
 * Returns: self on success, nil on failure
 *
 * Adds a SCSI controller to the list of available controllers.
 * This function:
 * 1. Gets the controller's direct device and name
 * 2. Validates the name is non-empty
 * 3. Checks if the controller array is not full (max 8 controllers)
 * 4. Stores the controller name in the array and increments the counter
 *
 * The decompiled code shows this stores controller names in an array at
 * offset +0x108 with a counter at offset +0x128 (corresponds to _controllerNames
 * and _controllerCount instance variables).
 */
- (id)registerSCSIController:(id)controller
{
    id directDevice;
    const char *controllerName;
    int currentCount;

    /* Get the direct device from the controller
     * This is FUN_00000268(param_3, s_directDevice_00005a20)
     * which calls [controller directDevice]
     */
    directDevice = objc_msgSend(controller, @selector(directDevice));

    /* Get the name from the direct device
     * This is FUN_00000268(uVar1, s_name_00005a30)
     * which calls [directDevice name]
     */
    controllerName = objc_msgSend(directDevice, @selector(name));

    /* Validate controller name and check if array is not full
     * Conditions for failure:
     * 1. controllerName == NULL
     * 2. *controllerName == '\0' (empty string)
     * 3. _controllerCount > 7 (array is full, max 8 controllers)
     */
    if ((controllerName == NULL) || (*controllerName == '\0') ||
        (_controllerCount > 7)) {
        /* Return nil on failure */
        return nil;
    }

    /* Get current count and increment it */
    currentCount = _controllerCount;
    _controllerCount = currentCount + 1;

    /* Store controller name in array at index currentCount
     * Array is at offset +0x108, which corresponds to _controllerNames[0]
     * Formula: *(char **)(currentCount * 4 + param_1 + 0x108) = controllerName
     */
    _controllerNames[currentCount] = (char *)controllerName;

    IOLog("SCSIServer: Registered SCSI controller '%s' (count: %d)\n",
          controllerName, _controllerCount);

    /* Return self on success */
    return self;
}

/*
 * serverConnect:taskPort: - Handle server connection from client
 * connection: Pointer to connection port (output parameter)
 * taskPort: Task port for the connecting client
 * Returns: 0 on success, -702 (0xfffffd42) on failure
 *
 * Called when a client application wants to establish a session
 * with the SCSI server. Sets up the Mach messaging infrastructure.
 *
 * The decompiled code shows this:
 * 1. Initializes *connection to 0
 * 2. Allocates IOSCSISession via [IOSCSISession alloc]
 * 3. Initializes session via _initServerWithTask:sendPort:
 * 4. Returns -702 on failure (iVar2 == 0), 0 on success
 *
 * The error code calculation: -(uint)(iVar2 == 0) & 0xfffffd42
 * - If iVar2 == 0: result = -1 & 0xfffffd42 = 0xfffffd42 = -702
 * - If iVar2 != 0: result = 0 & 0xfffffd42 = 0
 */
- (int)serverConnect:(mach_port_t *)connection taskPort:(mach_port_t)taskPort
{
    id sessionAlloc;
    int session_result;

    /* Initialize connection port to 0
     * *param_3 = 0
     */
    *connection = 0;

    /* Allocate a new SCSI session
     * uVar1 = FUN_000002f4(s_IOSCSISession_00005428, s_alloc_000059e4)
     * This is [IOSCSISession alloc]
     */
    sessionAlloc = objc_msgSend(objc_getClass("IOSCSISession"), @selector(alloc));

    /* Initialize the session with task and send port
     * iVar2 = FUN_000002f4(uVar1, s_initServerWithTask:sendPort:_00005a38, param_4, param_3)
     * This is [sessionAlloc _initServerWithTask:taskPort sendPort:connection]
     *
     * The connection pointer is passed as the sendPort output parameter.
     * On success, this returns the session object (non-zero).
     * On failure, this returns the result of [self free] (could be non-zero).
     */
    session_result = (int)objc_msgSend(sessionAlloc,
                                       @selector(_initServerWithTask:sendPort:),
                                       taskPort,
                                       connection);

    /* Calculate return value based on session_result
     * return -(uint)(iVar2 == 0) & 0xfffffd42
     *
     * If session_result == 0 (failure):
     *   -(uint)(1) & 0xfffffd42 = 0xFFFFFFFF & 0xfffffd42 = 0xfffffd42 = -702
     * If session_result != 0 (success):
     *   -(uint)(0) & 0xfffffd42 = 0x00000000 & 0xfffffd42 = 0
     */
    if (session_result == 0) {
        return -702;  /* 0xfffffd42 */
    }

    return 0;  /* Success */
}

/*
 * getCharValues:forParameter:count: - Get character string parameter values
 * values: Buffer to receive string values (output parameter)
 * parameter: Parameter identifier (string)
 * count: Pointer to count (input/output parameter)
 * Returns: Result code (0 on success)
 *
 * Handles SCSI-specific string parameters. Currently supports:
 * - "SCSI Controllers": Returns comma-separated list of controller names
 * Falls back to [super getCharValues:forParameter:count:] for other parameters
 *
 * The decompiled code shows this builds a comma-separated string of controller
 * names from the _controllerNames array, with the count stored in _controllerCount.
 */
- (int)getCharValues:(unsigned char *)values
        forParameter:(const char *)parameter
               count:(unsigned int *)count
{
    struct objc_super superStruct;
    int result;
    unsigned int bytesWritten;
    int i;
    int nameLen;
    unsigned int nextPos;
    const char *controllerName;

    /* Check for "SCSI Controllers" parameter
     * FUN_00000478(param_4, "SCSI Controllers") is strcmp()
     */
    result = strcmp(parameter, "SCSI Controllers");

    if (result != 0) {
        /* Not our parameter - call super implementation */
        superStruct.receiver = self;
        superStruct.class = objc_getClass("IODevice");
        return objc_msgSendSuper(&superStruct,
                                @selector(getCharValues:forParameter:count:),
                                values, parameter, count);
    }

    /* Handle "SCSI Controllers" parameter */

    /* Check if we have any controllers registered */
    if (_controllerCount == 0) {
        /* No controllers - return empty list */
        *count = 0;
        return 0;
    }

    /* Build comma-separated list of controller names */
    bytesWritten = 0;
    i = 0;

    /* Loop through all registered controllers */
    while (i < _controllerCount) {
        /* Get controller name from array
         * Formula: *(char **)(i * 4 + param_1 + 0x108)
         */
        controllerName = _controllerNames[i];

        /* Get length of controller name
         * FUN_00000468() is strlen()
         */
        nameLen = strlen(controllerName);

        /* Calculate position after adding this name + comma
         * nextPos = bytesWritten + nameLen + 1
         */
        nextPos = bytesWritten + nameLen + 1;

        /* Check if buffer has enough space
         * Break if nextPos > *count (buffer too small)
         */
        if (*count <= nextPos) {
            break;
        }

        /* Copy controller name to buffer
         * FUN_00000458(param_3 + bytesWritten, controllerName) is strcpy()
         */
        strcpy((char *)(values + bytesWritten), controllerName);

        /* Add comma separator after the name */
        values[bytesWritten + nameLen] = ',';

        /* Move to next controller */
        i = i + 1;
        bytesWritten = nextPos;
    }

    /* Replace last comma with null terminator
     * values[bytesWritten - 1] = '\0'
     */
    if (bytesWritten > 0) {
        values[bytesWritten - 1] = '\0';
    }

    /* Set the count to the number of bytes written */
    *count = bytesWritten;

    return 0;  /* Success */
}

@end
