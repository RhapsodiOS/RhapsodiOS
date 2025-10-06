/* Copyright (c) 1993-1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * S3GenericConfigTable.m -- Configuration table support for S3 Generic driver
 *
 * Created:
 *  7 July 1993		Derek B Clegg
 */
#import <string.h>
#import "S3Generic.h"

/* The `ConfigTable' category of `S3Generic'. */

@implementation S3Generic (ConfigTable)

- (const char *)valueForStringKey:(const char *)key
{
    IOConfigTable *configTable;
    configTable = [[self deviceDescription] configTable];
    if (configTable == nil)
	return 0;
    return [configTable valueForStringKey:key];
}

static inline int
isWhiteSpace(int c)
{
    return (c == ' ' || c == '\t' || c == '\n' || c == '\r');
}

static int
readHexValue(const char **s)
{
    int c, value;
    const char *string;

    string = *s;
    while ((c = *string) != '\0' && isWhiteSpace(c))
	string++;
    if (c == '\0') {
	*s = string;
	return -1;
    }
    value = 0;
    while ((c = *string) != '\0' && !isWhiteSpace(c)) {
	if (c >= '0' && c <= '9')
	    value = (value << 4) | (c - '0');
	else if (c >= 'A' && c <= 'F')
	    value = (value << 4) | (c - 'A' + 10);
	else if (c >= 'a' && c <= 'f')
	    value = (value << 4) | (c - 'a' + 10);
	else
	    break;
	string++;
    }
    *s = string;
    return (value & 0xFF);
}

- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count
{
    int k, value;
    const char *s;
    char modeKey[strlen(modeName) + 1 + strlen(key) + 1];

    strcpy(modeKey, modeName);
    strcat(modeKey, " ");
    strcat(modeKey, key);
    s = [self valueForStringKey:modeKey];
    if (s == 0)
	return -1;

    k = 0;
    for (k = 0; k < count; k++) {
	value = readHexValue(&s);
	if (value == -1)
	    break;
	parameters[k] = value;
    }
    return k;
}

- (BOOL)booleanForStringKey:(const char *)key withDefault:(BOOL)defaultValue
{
    const char *value;

    value = [self valueForStringKey:key];
    if (value == 0)
	return defaultValue;

    if (value[0] == 'Y' || value[0] == 'y') {
	if (value[1] == '\0'
	    || ((value[1] == 'E' || value[1] == 'e')
		&& (value[2] == 'S' || value[2] == 's')
		&& value[3] == '\0')) {
	    return YES;
	}
    } else if (value[0] == 'N' || value[0] == 'n') {
	if (value[1] == '\0'
	    || ((value[1] == 'O' || value[1] == 'o')
		&& value[2] == '\0')) {
	    return NO;
	}
    }
    IOLog("%s: Unrecognized value for key `%s': `%s'.\n",
	  [self name], key, value);
    return defaultValue;
}
@end
