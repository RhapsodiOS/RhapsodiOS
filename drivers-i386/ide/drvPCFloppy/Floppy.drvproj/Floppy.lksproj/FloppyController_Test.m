/*
 * FloppyController_Test.m
 * Test and diagnostic implementation for FloppyController
 */

#import "FloppyController_Test.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

// FDC I/O port offsets
#define FDC_DOR     0  // Digital Output Register
#define FDC_MSR     4  // Main Status Register
#define FDC_DATA    5  // Data Register

// MSR bits
#define MSR_RQM     0x80  // Request for Master
#define MSR_DIO     0x40  // Data Input/Output

// FDC Commands
#define FDC_CMD_VERSION     0x10  // Get controller version
#define FDC_CMD_SENSE_INT   0x08  // Sense interrupt status

// Density codes (for 3.5" drives)
#define DENSITY_DD      0   // Double Density (720KB)
#define DENSITY_HD      1   // High Density (1.44MB)
#define DENSITY_ED      2   // Extra Density (2.88MB)

@implementation FloppyController(Test)

- (IOReturn)fcReset
{
    return [self resetController];
}

- (IOReturn)test
{
    IOReturn status;
    unsigned char version;
    int drive;

    IOLog("FloppyController_Test: Starting controller diagnostics\n");

    // Test 1: Reset controller
    IOLog("FloppyController_Test: Test 1 - Controller reset\n");
    status = [self resetController];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Test: FAILED - Controller reset error (0x%x)\n", status);
        return status;
    }
    IOLog("FloppyController_Test: PASSED - Controller reset\n");

    // Test 2: Get controller version
    IOLog("FloppyController_Test: Test 2 - Get controller version\n");
    status = [self doControllerVersion:&version];
    if (status == IO_R_SUCCESS) {
        IOLog("FloppyController_Test: PASSED - Controller version: 0x%02x\n", version);
    } else {
        IOLog("FloppyController_Test: WARNING - Version command failed (0x%x)\n", status);
        // Not critical, continue testing
    }

    // Test 3: Configure controller
    IOLog("FloppyController_Test: Test 3 - Configure controller\n");
    status = [self doConfigure];
    if (status == IO_R_SUCCESS) {
        IOLog("FloppyController_Test: PASSED - Controller configured\n");
    } else {
        IOLog("FloppyController_Test: WARNING - Configure failed (0x%x)\n", status);
    }

    // Test 4: Try recalibrate on each drive
    for (drive = 0; drive < 2; drive++) {  // Test drives 0 and 1
        IOLog("FloppyController_Test: Test 4.%d - Recalibrate drive %d\n", drive, drive);
        status = [self doRecalibrate:drive];
        if (status == IO_R_SUCCESS) {
            IOLog("FloppyController_Test: PASSED - Drive %d recalibrated\n", drive);
        } else {
            IOLog("FloppyController_Test: INFO - Drive %d recalibrate failed (0x%x) - may be no disk\n",
                  drive, status);
        }

        // Turn off motor
        [self doMotorOff:drive];
    }

    // Test 5: Check drive status
    IOLog("FloppyController_Test: Test 5 - Drive status\n");
    for (drive = 0; drive < 2; drive++) {
        status = [self getDriveStatus:drive];
        if (status == IO_R_SUCCESS) {
            IOLog("FloppyController_Test: Drive %d status: ready\n", drive);
        } else if (status == IO_R_NO_MEDIA) {
            IOLog("FloppyController_Test: Drive %d status: no media\n", drive);
        } else {
            IOLog("FloppyController_Test: Drive %d status: error (0x%x)\n", drive, status);
        }
    }

    IOLog("FloppyController_Test: All tests completed\n");
    return IO_R_SUCCESS;
}

- (IOReturn)thappyTest
{
    // Alternative test method name (compatibility)
    IOLog("FloppyController_Test: Running thappyTest (alias for test)\n");
    return [self test];
}

- (IOReturn)densityValues:(unsigned int *)density
{
    if (density == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Return density based on current drive geometry
    // Standard 1.44MB floppy = HD (High Density)
    if (_sectorsPerTrack == 18 && _heads == 2 && _cylinders == 80) {
        *density = DENSITY_HD;  // 1.44MB High Density
        IOLog("FloppyController_Test: Density = HD (1.44MB)\n");
    } else if (_sectorsPerTrack == 9 && _heads == 2 && _cylinders == 80) {
        *density = DENSITY_DD;  // 720KB Double Density
        IOLog("FloppyController_Test: Density = DD (720KB)\n");
    } else if (_sectorsPerTrack == 36 && _heads == 2 && _cylinders == 80) {
        *density = DENSITY_ED;  // 2.88MB Extra Density
        IOLog("FloppyController_Test: Density = ED (2.88MB)\n");
    } else {
        *density = DENSITY_HD;  // Default to HD
        IOLog("FloppyController_Test: Unknown geometry, defaulting to HD\n");
    }

    return IO_R_SUCCESS;
}

- (IOReturn)doControllerVersion:(unsigned char *)version
{
    IOReturn status;
    int i;

    if (version == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Wait for controller ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
        IOLog("FloppyController_Test: Timeout waiting for ready before VERSION\n");
        return IO_R_TIMEOUT;
    }

    // Send VERSION command
    status = [self fdSendByte:FDC_CMD_VERSION];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Test: Failed to send VERSION command\n");
        return status;
    }

    // Get version byte
    status = [self fdGetByte:version];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Test: Failed to read VERSION result\n");
        return status;
    }

    // Version interpretations:
    // 0x80 = NEC 765 (original)
    // 0x81 = Intel 82077 (enhanced)
    // 0x90 = National Semiconductor PC8477
    return IO_R_SUCCESS;
}

@end
