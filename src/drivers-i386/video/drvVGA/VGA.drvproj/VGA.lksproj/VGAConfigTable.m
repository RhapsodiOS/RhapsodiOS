/* Copyright (c) 1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * VGAConfigTable.m -- VGA configuration table access
 *
 * Created for RhapsodiOS VGA support
 */

#import "VGA.h"
#import <driverkit/configTablePrivate.h>

@implementation VGA (ConfigTable)

/* Get a string value from the configuration table */
- (const char *)valueForStringKey:(const char *)key
{
    IOConfigTable *configTable;
    const char *value;

    configTable = [[self deviceDescription] configTable];
    value = configTable != 0 ?
        [configTable valueForStringKey:key] : 0;

    return value;
}

/* Get parameters for a specific mode */
- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count
{
    int paramCount = 0;
    IOConfigTable *configTable;
    const char *value;

    configTable = [[self deviceDescription] configTable];
    if (configTable == 0)
        return 0;

    value = [configTable valueForStringKey:key];
    if (value != 0) {
        /* Parse the value string and extract parameters */
        /* This is a simplified implementation */
        if (count > 0) {
            strncpy(parameters, value, count - 1);
            parameters[count - 1] = '\0';
            paramCount = 1;
        }
    }

    return paramCount;
}

/* Get a boolean value from the configuration table */
- (BOOL)booleanForStringKey:(const char *)key withDefault:(BOOL)defaultValue
{
    IOConfigTable *configTable;
    const char *value;

    configTable = [[self deviceDescription] configTable];
    if (configTable == 0)
        return defaultValue;

    value = [configTable valueForStringKey:key];
    if (value == 0)
        return defaultValue;

    if (strcmp(value, "YES") == 0 || strcmp(value, "Yes") == 0 ||
        strcmp(value, "yes") == 0 || strcmp(value, "1") == 0)
        return YES;

    if (strcmp(value, "NO") == 0 || strcmp(value, "No") == 0 ||
        strcmp(value, "no") == 0 || strcmp(value, "0") == 0)
        return NO;

    return defaultValue;
}

@end
