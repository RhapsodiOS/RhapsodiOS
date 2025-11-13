/*
 * DECchip21140VendorSpecific.m
 * Vendor-specific initialization for DEC 21140 Ethernet Controller
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import "DECchip21140.h"
#import "DECchip21140Private.h"
#import "DECchip21140Inline.h"

/*
 * Vendor-specific category implementation
 */
@implementation DECchip21140(VendorSpecific)

/*
 * Initialize GP Port Register for Cogent 100Mb
 */
- (void)initGPPortRegisterForCogent100Mb
{
    /* Write initial value to CSR12 */
    outl(_portBase + 0x60, 0x13f);
    IODelay(100);

    /* Write configuration for 100Mb operation */
    outl(_portBase + 0x60, 0x9);
}

/*
 * Initialize GP Port Register for Cogent 10Mb
 */
- (void)initGPPortRegisterForCogent10Mb
{
    /* Write initial value to CSR12 */
    outl(_portBase + 0x60, 0x13f);
    IODelay(100);

    /* Write configuration for 10Mb operation */
    outl(_portBase + 0x60, 0x3e);
}

/*
 * Initialize GP Port Register for Custom configuration
 */
- (void)initGPPortRegisterForCustom
{
    char *buffer;
    const char *configString;
    const char *keyName;
    id deviceDescription;
    id configTable;
    unsigned int value;

    /* Allocate buffer for config string (512 bytes) */
    buffer = (char *)IOMalloc(0x200);
    if (buffer == NULL) {
        return;
    }

    /* Determine which config key to look up based on media type */
    if (_mediaType < 2) {
        keyName = "CSR12 10";
    } else {
        keyName = "CSR12 100";
    }

    /* Get config string from device description */
    deviceDescription = [self deviceDescription];
    configTable = [deviceDescription configTable];
    configString = [[configTable valueForStringKey:keyName] cString];

    /* Try alternate key names if first lookup failed */
    if (configString == NULL) {
        if (_mediaType < 2) {
            keyName = "CSR12 10BASE-T";
        } else {
            keyName = "CSR12 100BASE-TX";
        }

        configString = [[configTable valueForStringKey:keyName] cString];
        if (configString == NULL) {
            IOFree(buffer, 0x200);
            return;
        }
    }

    /* Check string length fits in buffer */
    if (strlen(configString) >= 0x200) {
        IOLog("%s: CSR12 string too long.\n", [self name]);
        IOFree(buffer, 0x200);
        return;
    }

    /* Copy config string to buffer */
    strcpy(buffer, configString);

    /* Parse and write each value to CSR12 */
    while ([self getNextValue:&value fromString:&buffer]) {
        outl(_portBase + 0x60, value);
        IOSleep(10);
    }

    /* Free allocated buffer */
    IOFree(buffer, 0x200);
}

/*
 * Initialize GP Port Register for DE500 100Mb
 */
- (void)initGPPortRegisterForDE500100Mb
{
    /* Write sequence of values to CSR12 for DE500 100Mb initialization */
    outl(_portBase + 0x60, 0x10f);
    IODelay(100);
    outl(_portBase + 0x60, 0x8);
    IODelay(100);
    outl(_portBase + 0x60, 0x9);
}

/*
 * Get next value from string
 * Parse hexadecimal values from a string
 * Returns YES if a value was parsed, NO if end of string
 */
- (BOOL)getNextValue:(unsigned int *)value fromString:(char **)str
{
    char *current = *str;
    char ch;
    unsigned int parsedValue;

    /* Skip leading whitespace and tabs */
    ch = *current;
    while (ch != '\0' && (ch == ' ' || (unsigned char)(ch - 9) < 2)) {
        current++;
        ch = *current;
    }

    /* Initialize result */
    *value = 0;

    /* Check if end of string */
    if (*current == '\0') {
        return NO;
    }

    /* Parse hexadecimal value character by character */
    parsedValue = 0;
    while (*current != '\0') {
        /* Check for whitespace or tab - end of number */
        if (*current == ' ' || (unsigned char)(*current - 9) < 2) {
            break;
        }

        /* Parse hex digit */
        if ((unsigned char)(*current - '0') < 10) {
            /* Digit 0-9 */
            parsedValue = (*current - '0') + parsedValue * 16;
        } else if ((unsigned char)(*current - 'A') < 6) {
            /* Uppercase A-F */
            parsedValue = (*current - 'A' + 10) + parsedValue * 16;
        } else if ((unsigned char)(*current - 'a') < 6) {
            /* Lowercase a-f */
            parsedValue = (*current - 'a' + 10) + parsedValue * 16;
        }

        /* Mark character as processed by replacing with space */
        *current = ' ';
        current++;
    }

    /* Store parsed value */
    *value = parsedValue;

    /* Update string pointer */
    *str = current;

    return YES;
}

@end
