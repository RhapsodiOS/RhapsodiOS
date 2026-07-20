/*
 * IOVGADisplay.m
 * VGA Display Driver Implementation
 *
 * Generic VGA display driver for VESA modes
 */

#import "IOVGADisplay.h"
#import "vidBIOS.h"
#import <driverkit/i386/IOVGAShared.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <objc/List.h>
#import <mach/mach_interface.h>
#import <string.h>
#import <ctype.h>

// External declarations
extern id EventDriver;
extern id __kmId;  // Kernel module ID
extern void *VGAAllocateConsole(void *displayInfo);
extern int ev_try_lock(int lock);
extern void ev_unlock(int lock);

// Global variables
static unsigned int nextVGAUnit = 0;
static char nameBuf[32];
char svga_bios_mode = 0;
unsigned int vesaMode = 0x6A;  // Default VESA mode (106 decimal)
unsigned int _vesaBiosMagic = VESA_MAGIC;

// VGA plane and segment tracking
unsigned int colr_mode = 1;
unsigned int curr_read_plane = 0;
unsigned int curr_write_plane = 0;
unsigned int curr_read_segment = 0;
unsigned int curr_write_segment = 0;

// Mask array for cursor operations (used by _VGARemoveCursor)
const unsigned int mask_array[16] = {
    0xFFFFFFFF, 0xFFFFFCFF, 0xFFFFF0FF, 0xFFFFC0FF,
    0xFFFF00FF, 0xFFFC00FF, 0xFFF000FF, 0xFFC000FF,
    0xFF0000FF, 0xFC0000FF, 0xF00000FF, 0xC00000FF,
    0x000000FF, 0x000000FC, 0x000000F0, 0x000000C0
};

// EMU486 related globals
unsigned int DAT_00006060 = 0;      // Base pointer
unsigned int DAT_00006064 = 0;      // Page table pointer
unsigned int DAT_00006068 = 0;      // I/O permission bitmap pointer
unsigned int DAT_0000606c = 0;      // Reserved
unsigned int DAT_00006070 = 0;      // EAX
unsigned int DAT_00006074 = 0;      // ECX
unsigned int DAT_00006078 = 0;      // EDX
unsigned int DAT_0000607c = 0;      // EBX
unsigned int DAT_00006080 = 0;      // ESP
unsigned int DAT_00006084 = 0;      // EBP
unsigned int DAT_00006088 = 0;      // ESI
unsigned int DAT_0000608c = 0;      // EDI
unsigned int DAT_00006090 = 0;      // IP
unsigned char DAT_00006094 = 0;     // FLAGS (low byte)
unsigned int DAT_00006098 = 0;      // CS
unsigned int DAT_0000609c = 0;      // SS
unsigned int DAT_000060a0 = 0;      // DS
unsigned int DAT_000060a4 = 0;      // ES
unsigned int DAT_000060a8 = 0;      // FS
unsigned int DAT_000060ac = 0;      // GS
unsigned char DAT_000060b4 = 0;     // Reserved
unsigned char DAT_000060b5 = 0;     // Reserved
unsigned char DAT_000060b6 = 0;     // Reserved
unsigned char DAT_000060b7 = 0;     // Opcode dispatch flags
unsigned char DAT_000060b8 = 0;     // FLAGS (high byte)

// VESA BIOS magic value check
#define VESA_MAGIC 0xA7A7A7A7
#define VGA_SHMEM_SIZE 0x1449  // Maximum shared memory size

@implementation IOVGADisplay

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    id instance;
    const char *name;
    unsigned int unit;

    // Allocate and initialize instance
    instance = [[self alloc] initFromDeviceDescription:devDesc];
    if (!instance)
        return NO;

    // Generate name and unit
    name = [instance generateNameAndUnit:&unit];

    // Set device properties
    [instance setUnit:unit];
    [instance setName:name];
    [instance setDeviceKind:"frame buffer"];

    // Register the device
    [instance registerDevice];

    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    id configTable;
    const char *svgaMode;
    const char *vesaBiosMode;

    if (![super initFromDeviceDescription:devDesc])
        return nil;

    // Check for SVGA Mode configuration
    configTable = [devDesc configTable];
    svgaMode = [[configTable valueForStringKey:"SVGA Mode"] stringValue];

    if (svgaMode != NULL && strcmp(svgaMode, "Yes") == 0) {
        svga_bios_mode = 1;
    } else {
        svga_bios_mode = 0;
    }

    // Check if we booted with default config
    if ([self _didBootWithDefaultConfig]) {
        svga_bios_mode = 0;
    }

    // Initialize VESA BIOS emulator if in SVGA mode
    if (svga_bios_mode == 1) {
        bios = [[vidBIOS alloc] init];
        if (bios == nil) {
            IOLog("VGADisplay: vidBIOS failed\n");
            svga_bios_mode = 0;
        }
    }

    // Log selected mode
    if (svga_bios_mode == 0) {
        IOLog("VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)\n");
    } else {
        IOLog("VGADisplay: Mode Selected: 800 x 600 @ 60 Hz (BW:2)\n");

        // Check for custom VESA mode
        vesaBiosMode = [[configTable valueForStringKey:"SVGA VESA BIOS Mode"] stringValue];
        if (vesaBiosMode != NULL) {
            vesaMode = strtol(vesaBiosMode, NULL, 16);
            IOLog("VGADisplay: VESA mode selected: 0x%x\n", vesaMode);
        }
    }

    return self;
}

- free
{
    return [super free];
}

- (IOReturn)map
{
    // Map returns 0 (success)
    return 0;
}

- (void)unmap
{
    id devDesc;
    unsigned int numPortRanges;
    unsigned int i;

    // Get device description and number of port ranges
    devDesc = [self deviceDescription];
    numPortRanges = [devDesc numPortRanges];

    // Release all port ranges
    for (i = 0; i < numPortRanges; i++) {
        [self releasePortRange:i];
    }
}

- (void *)allocateConsoleInfo
{
    void *displayInfo;

    // Get display info structure
    displayInfo = [self displayInfo];

    // Allocate console using VGA-specific allocator
    return VGAAllocateConsole(displayInfo);
}

- (const char *)generateNameAndUnit:(unsigned int *)unit
{
    *unit = nextVGAUnit;
    nextVGAUnit++;
    sprintf(nameBuf, "VGADisplay%d", *unit);
    return nameBuf;
}

- (IOReturn)getIntValues:(unsigned int *)values
              forParameter:(IOParameterName)parameterName
                     count:(unsigned int *)count
{
    unsigned int requestedCount = *count;
    IOReturn result;

    // Handle "IO_Framebuffer_Map" parameter
    if (strcmp(parameterName, "IO_Framebuffer_Map") == 0) {
        *values = [self map];
        *count = 1;
        return IO_R_SUCCESS;
    }

    // Handle "IO_Framebuffer_Dimensions" parameter
    if (strcmp(parameterName, "IO_Framebuffer_Dimensions") == 0) {
        unsigned int *displayInfo = (unsigned int *)[self displayInfo];
        unsigned int dims[3];

        dims[0] = displayInfo[0];  // width
        dims[1] = displayInfo[1];  // height
        dims[2] = displayInfo[3];  // totalWidth

        *count = 0;
        for (int i = 0; i < 3 && *count < requestedCount; i++) {
            values[i] = dims[i];
            (*count)++;
        }
        return IO_R_SUCCESS;
    }

    // Handle "IOGetDisplayInfo" parameter
    if (strcmp(parameterName, "IOGetDisplayInfo") == 0) {
        if (*count != 3) {
            return IO_R_NO_DEVICE;
        }

        if (svga_bios_mode == 0) {
            // 640x480 mode
            values[0] = 0x280;  // 640
            values[1] = 0x1e0;  // 480
            values[2] = 0xa0;   // 160 (totalWidth in bytes for 2bpp)
        } else {
            // 800x600 mode
            values[0] = 800;
            values[1] = 600;
            values[2] = 200;    // totalWidth in bytes for 2bpp
        }
        return IO_R_SUCCESS;
    }

    // Handle "IO_Framebuffer_Register" parameter
    if (strcmp(parameterName, "IO_Framebuffer_Register") == 0) {
        result = [self _registerWithED];
        [__kmId registerDisplay:self];

        *count = 0;
        if (requestedCount != 0) {
            *count = 1;
            *values = [self token];
        }
        return result;
    }

    // Fall back to superclass implementation
    return [super getIntValues:values
                  forParameter:parameterName
                         count:count];
}

- (IOReturn)setIntValues:(unsigned int *)values
              forParameter:(IOParameterName)parameterName
                     count:(unsigned int)count
{
    unsigned int *displayInfo;

    // Handle "IO_Framebuffer_Unmap" parameter
    if (strcmp(parameterName, "IO_Framebuffer_Unmap") == 0) {
        [self unmap];
        return IO_R_SUCCESS;
    }

    // Handle "IO_Framebuffer_SetDimensions" parameter
    if (strcmp(parameterName, "IO_Framebuffer_SetDimensions") == 0) {
        displayInfo = (unsigned int *)[self displayInfo];
        displayInfo[0] = values[0];  // width
        displayInfo[1] = values[1];  // height
        displayInfo[3] = values[2];  // totalWidth
        displayInfo[6] = 5;          // flags
        return IO_R_SUCCESS;
    }

    // Handle "IO_Framebuffer_Unregister" parameter
    if (strcmp(parameterName, "IO_Framebuffer_Unregister") == 0) {
        id result;
        if (count != 1) {
            return IO_R_NO_DEVICE;
        }
        result = [EventDriver instance];
        [result unregisterScreen:values[0]];
        return IO_R_SUCCESS;
    }

    // Handle "Set VGA VESA Mode" parameter
    if (strcmp(parameterName, "Set VGA VESA Mode") == 0) {
        if (count != 1) {
            return IO_R_NO_DEVICE;
        }
        [self _enterSVGAMode:vesaMode];
        return IO_R_SUCCESS;
    }

    // Fall back to superclass implementation
    return [super setIntValues:values
                  forParameter:parameterName
                         count:count];
}

- (void)hideCursor:(int)token
{
    void *displayInfo;
    void *shmem;
    char hideCount;

    // Try to lock shared memory
    shmem = consoleInfo;
    if (ev_try_lock((int)shmem + 4) != 0) {
        displayInfo = [self displayInfo];

        // Increment hide count
        hideCount = *((char *)shmem + 8);
        *((char *)shmem + 8) = hideCount + 1;

        // If cursor was visible (hideCount == 0), remove it
        if (hideCount == 0) {
            _VGARemoveCursor(displayInfo, (int)shmem);
        }

        ev_unlock((int)shmem + 4);
    }
}

- (void)showCursor:(IOGPoint *)cursorLoc
             frame:(IOGBounds *)bounds
             token:(int)token
{
    int *shmem;
    void *displayInfo;
    short cursorX, cursorY;
    short frameX, frameY;
    char inFrame;
    char oldHideCount;
    int frameOffset;

    shmem = (int *)consoleInfo;
    if (ev_try_lock((int)shmem + 4) == 0) {
        return;
    }

    // Store token and cursor location
    shmem[0] = token;
    *((IOGPoint *)(shmem + 7)) = *cursorLoc;

    // Check if cursor frame checking is enabled
    if (*((char *)shmem + 10) != 0) {
        displayInfo = [self displayInfo];

        // Get frame offset for this token
        frameOffset = shmem[shmem[0] + 0xe];
        cursorX = (short)shmem[7] - (short)frameOffset;
        cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);

        // Check if cursor is within frame bounds
        inFrame = 0;
        if (cursorX < *((short *)shmem + 0xb) &&
            (short)shmem[5] < (short)(cursorX + 16) &&
            cursorY < *((short *)shmem + 0xd) &&
            (short)shmem[6] < (short)(cursorY + 16)) {
            inFrame = 1;
        }

        // Update frame state if changed
        if (inFrame != *((char *)shmem + 0xb)) {
            *((char *)shmem + 0xb) = inFrame;
            if (inFrame == 0) {
                // Cursor moved out of frame - decrement hide count
                if ((char)shmem[2] != 0) {
                    *((char *)(shmem + 2)) = (char)shmem[2] - 1;
                    if ((char)shmem[2] == 0) {
                        // Display cursor
                        frameOffset = shmem[shmem[0] + 0xe];
                        cursorX = (short)shmem[7] - (short)frameOffset;
                        *((short *)(shmem + 8)) = cursorX;
                        *((short *)shmem + 0x11) = cursorX + 16;
                        cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);
                        *((short *)(shmem + 9)) = cursorY;
                        *((short *)shmem + 0x13) = cursorY + 16;
                        _VGADisplayCursor(displayInfo, shmem);
                        shmem[10] = shmem[8];
                        shmem[0xb] = shmem[9];
                    }
                }
            } else {
                // Cursor moved into frame - increment hide count
                oldHideCount = (char)shmem[2];
                *((char *)(shmem + 2)) = oldHideCount + 1;
                if (oldHideCount == 0) {
                    _VGARemoveCursor(displayInfo, (int)shmem);
                }
            }
        }
    }

    // Decrement hide count and show cursor if now visible
    displayInfo = [self displayInfo];
    if ((char)shmem[2] != 0) {
        *((char *)(shmem + 2)) = (char)shmem[2] - 1;
        if ((char)shmem[2] == 0) {
            frameOffset = shmem[shmem[0] + 0xe];
            cursorX = (short)shmem[7] - (short)frameOffset;
            *((short *)(shmem + 8)) = cursorX;
            *((short *)shmem + 0x11) = cursorX + 16;
            cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);
            *((short *)(shmem + 9)) = cursorY;
            *((short *)shmem + 0x13) = cursorY + 16;
            _VGADisplayCursor(displayInfo, shmem);
            shmem[10] = shmem[8];
            shmem[0xb] = shmem[9];
        }
    }

    ev_unlock((int)shmem + 4);
}

- (void)moveCursor:(IOGPoint *)cursorLoc
             frame:(IOGBounds *)bounds
             token:(int)token
{
    int *shmem;
    void *displayInfo;
    short cursorX, cursorY;
    short frameX, frameY;
    char inFrame;
    char oldHideCount;
    int frameOffset;

    shmem = (int *)consoleInfo;
    if (ev_try_lock((int)shmem + 4) == 0) {
        return;
    }

    // Store token and cursor location
    shmem[0] = token;
    *((IOGPoint *)(shmem + 7)) = *cursorLoc;

    // Increment hide count temporarily
    oldHideCount = (char)shmem[2];
    *((char *)(shmem + 2)) = oldHideCount + 1;
    if (oldHideCount == 0) {
        displayInfo = [self displayInfo];
        _VGARemoveCursor(displayInfo, (int)shmem);
    }

    // Check if should update frame hide flag
    if (*((char *)shmem + 9) != 0) {
        *((char *)shmem + 9) = 0;
        if ((char)shmem[2] != 0) {
            *((char *)(shmem + 2)) = (char)shmem[2] - 1;
        }
    }

    // Check if cursor frame checking is enabled
    if (*((char *)shmem + 10) == 0) {
        goto move_cursor_final;
    }

    displayInfo = [self displayInfo];

    // Get frame offset for this token
    frameOffset = shmem[shmem[0] + 0xe];
    cursorX = (short)shmem[7] - (short)frameOffset;
    cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);

    // Check if cursor is within frame bounds
    inFrame = 0;
    if (cursorX < *((short *)shmem + 0xb) &&
        (short)shmem[5] < (short)(cursorX + 16) &&
        cursorY < *((short *)shmem + 0xd) &&
        (short)shmem[6] < (short)(cursorY + 16)) {
        inFrame = 1;
    }

    if (inFrame == *((char *)shmem + 0xb)) {
        goto move_cursor_final;
    }

    *((char *)shmem + 0xb) = inFrame;

    if (inFrame != 0) {
        // Cursor is in frame - hide it
        oldHideCount = (char)shmem[2];
        *((char *)(shmem + 2)) = oldHideCount + 1;
        if (oldHideCount == 0) {
            _VGARemoveCursor(displayInfo, (int)shmem);
        }
        goto move_cursor_final;
    }

    // Cursor is out of frame - show it if not hidden
    if ((char)shmem[2] == 0) {
        goto move_cursor_final;
    }

    *((char *)(shmem + 2)) = (char)shmem[2] - 1;
    if ((char)shmem[2] == 0) {
        frameOffset = shmem[shmem[0] + 0xe];
        cursorX = (short)shmem[7] - (short)frameOffset;
        *((short *)(shmem + 8)) = cursorX;
        *((short *)shmem + 0x11) = cursorX + 16;
        cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);
        *((short *)(shmem + 9)) = cursorY;
        *((short *)shmem + 0x13) = cursorY + 16;
        _VGADisplayCursor(displayInfo, shmem);
        shmem[10] = shmem[8];
        shmem[0xb] = shmem[9];
        goto move_cursor_final;
    }

move_cursor_final:
    // Restore hide count
    *((char *)(shmem + 2)) = (char)shmem[2] - 1;
    if ((char)shmem[2] == 0) {
        displayInfo = [self displayInfo];
        frameOffset = shmem[shmem[0] + 0xe];
        cursorX = (short)shmem[7] - (short)frameOffset;
        *((short *)(shmem + 8)) = cursorX;
        *((short *)shmem + 0x11) = cursorX + 16;
        cursorY = *((short *)shmem + 0xf) - (short)(frameOffset >> 16);
        *((short *)(shmem + 9)) = cursorY;
        *((short *)shmem + 0x13) = cursorY + 16;
        _VGADisplayCursor(displayInfo, shmem);
        shmem[10] = shmem[8];
        shmem[0xb] = shmem[9];
    }

    ev_unlock((int)shmem + 4);
}

- (void)setBrightness:(int)level
                token:(int)token
{
    const char *name;

    // Validate brightness level (0-64)
    if (level > 0x40) {
        name = [self name];
        IOLog("%s: Invalid arg to setBrightness:%d\n", name, level);
    }

    // Set ET4000 chipset brightness
    _SetET4000Brightness(level);
}

- (IOReturn)_registerWithED
{
    id result;
    int token;
    void *shmem;
    unsigned int shmemSize;
    unsigned int bounds_x, bounds_y;

    // Register screen with Event Driver
    result = [EventDriver instance];
    token = [result registerScreen:self
                            bounds:&bounds_x
                             shmem:&shmem
                              size:&shmemSize];

    if (token == -1) {
        // Registration failed
        return IO_R_NO_DEVICE;
    }

    // Validate shared memory size
    if (shmemSize >= VGA_SHMEM_SIZE) {
        const char *name = [self name];
        IOLog("%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)\n",
              name, shmemSize, VGA_SHMEM_SIZE);

        // Unregister and fail
        result = [EventDriver instance];
        [result unregisterScreen:token];
        return IO_R_NO_DEVICE;
    }

    // Initialize shared memory
    memset(shmem, 0, shmemSize);
    *((unsigned char *)shmem + 8) = 1;  // Set flags
    *((unsigned int *)((unsigned char *)shmem + 0x30)) = bounds_x;
    *((unsigned int *)((unsigned char *)shmem + 0x34)) = bounds_y;

    // Store token
    [self setToken:token];

    return IO_R_SUCCESS;
}

@end

// Category: VESAMode
@implementation IOVGADisplay(VESAMode)

- (BOOL)_didBootWithDefaultConfig
{
    char *config;
    char *p;

    // Check for VESA BIOS magic value
    extern unsigned int _vesaBiosMagic;  // At offset 0x110a4 in decompiled code
    if (_vesaBiosMagic != VESA_MAGIC) {
        return NO;
    }

    // Find "config" parameter
    config = (char *)_find_parameter("config");
    if (!config) {
        return NO;
    }

    // Skip leading whitespace
    while (*config && ((*config == ' ') || (*config == '\t') || (*config == '\n'))) {
        config++;
    }

    // Look for '=' sign
    if (!config || *config != '=') {
        return NO;
    }

    // Skip '=' and following whitespace
    do {
        p = config;
        config = p + 1;
        if (*config == '\0')
            break;
    } while ((*config == ' ') || (*config == '\t') || (*config == '\n'));

    // Compare with "Default"
    if (strncmp(config, "Default", 7) == 0) {
        p = p + 8;
        // Check that it ends properly (whitespace, newline, or null)
        if (*p == '\0' || *p == ' ' || *p == '\t' || *p == '\n') {
            return YES;
        }
    }

    return NO;
}

- (IOReturn)_enterSVGAMode:(unsigned int)mode
{
    unsigned char regs[0x40];
    unsigned short result;
    const char *name;

    // Zero out registers
    memset(regs, 0, 0x40);

    // Set up VESA BIOS mode change call
    // AX = 0x4F02, BX = mode number
    *(unsigned short *)&regs[0] = 0x4F02;
    *(unsigned int *)&regs[0x38] = mode;  // BX register

    // Execute INT 10h
    [self _int10:regs];

    // Check result (AX should be 0x004F for success)
    result = *(unsigned short *)&regs[0];
    if (result != 0x004F) {
        name = [self name];
        IOLog("%s: BIOS mode change returned %04x\n", name, result);
        IOSleep(5000);  // Sleep for 5 seconds on error
    }

    return IO_R_SUCCESS;
}

- (int)_int10:(void *)regs
{
    id devDesc;
    int numPortRanges;
    int i;
    IORange *portRanges;
    IORange *copiedRanges;
    int result;

    // Get device description
    devDesc = [self deviceDescription];

    // Get number of port ranges
    numPortRanges = [devDesc numPortRanges];

    // Allocate space for port ranges on stack
    // In the original: (numPortRanges + 1) * sizeof(IORange) on stack
    copiedRanges = (IORange *)IOMalloc((numPortRanges + 1) * sizeof(IORange));

    // Add VGA BIOS ROM range
    copiedRanges[0].start = 0;
    copiedRanges[0].size = 0x10000;  // 64KB for BIOS ROM
    copiedRanges[numPortRanges].start = 0x40;  // BIOS data area

    // Get port range list from device
    portRanges = (IORange *)[devDesc portRangeList];

    // Copy port ranges
    memcpy(&copiedRanges[1], portRanges, numPortRanges * sizeof(IORange));

    // Call BIOS emulator
    result = [bios int10:regs
                outregs:regs
                iorange:copiedRanges
                  ionum:(numPortRanges + 1)];

    // Free allocated memory
    IOFree(copiedRanges, (numPortRanges + 1) * sizeof(IORange));

    return result;
}

@end
