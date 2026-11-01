/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright 1993 NeXT Computer, Inc.
 * All rights reserved.
 */

#import "libsaio.h"
#import "memory.h"
#import "kernBootStruct.h"
#import "load.h"
#import "sarld.h"
#import "language.h"
#import "drivers.h"
#import "stringConstants.h"

#import <mach-o/fat.h>

extern char *LoadableFamilies;
struct driver_info *loaded_drivers;	/* read by execKernel, as in 4.2 */
int num_loaded;
extern BOOL errors;

static inline int isspace(char c)
{
    return (c == ' ' || c == '\t');
}

/*
 * A flag to let us know that a driver specified in
 * the system configuration was not found.
 */
int driverMissing;
static struct _missingDriver {
    char *bundleName;
    char *longName;
    char *version;
    char *tableName;
    int   reason;
} missingDrivers[MAX_MISSING_DRIVERS];

/*
 * Record the fact that a driver is missing.
 * Assumes that all strings are malloced.
 */
void
driverIsMissing(
    char *bundleName,
    char *version,
    char *longName,
    char *tableName,
    int   reason
)
{
    struct _missingDriver *dp = &missingDrivers[driverMissing++];

    dp->bundleName = bundleName;
    dp->version = version;
    dp->longName = longName ? longName : newString(bundleName);
    dp->tableName = tableName ? tableName : newString("Default");
    dp->reason = reason;
}

/*
 * Name the boot drivers that are missing from the startup disk or have
 * the wrong version there.  No prompt: the screen this replaces offered
 * only to load them from a floppy.  As that screen did, it clears
 * errors, so missing drivers alone don't add the error pause.
 */
void
reportMissingDrivers(void)
{
    int i;

    if (driverMissing == 0)
	return;
    errors = 0;
    setMode(TEXT_MODE);
    localPrintf("These boot drivers are missing or the wrong version:\n");
    for (i = 0; i < driverMissing; i++)
	printf("  %s\n", missingDrivers[i].longName);
    sleep(2);
}

/*
 * You loaded a (possibly) missing driver.
 * If the name passed in matches one of the missing drivers,
 * it's removed from the list and the original string is freed.
 */
void
loadedPossiblyMissingDriver(char *name)
{
    int i;
    for (i=0; i < driverMissing; i++) {
	if (strcmp(name, missingDrivers[i].bundleName) == 0) {
	    free(missingDrivers[i].bundleName);
	    free(missingDrivers[i].longName);
	    free(missingDrivers[i].version);
	    free(missingDrivers[i].tableName);
	    driverMissing--;
	    for(; i < driverMissing; i++) {
		missingDrivers[i] = missingDrivers[i+1];
	    }
	    return;
	}
    }
}

void
addToLoadedDriverList(
    char *bundleName,
    char *longName,
    char *configTable,
    char *tableName,
    int flags
)
{
    if (loaded_drivers == 0) {
	loaded_drivers = (struct driver_info *)
	    malloc(sizeof(struct driver_info) * MAX_DRIVERS);
    }
    loaded_drivers[num_loaded].name = longName;
    loaded_drivers[num_loaded].bundle = bundleName;
    if ((loaded_drivers[num_loaded].version =
	newStringForStringTableKey(configTable, "Version")) == NULL)
	    loaded_drivers[num_loaded].version = "1.0";
    loaded_drivers[num_loaded].flags = flags;
    loaded_drivers[num_loaded].configTable = configTable;
    loaded_drivers[num_loaded].locationTag = 
        newStringForStringTableKey(configTable, "Location");
    num_loaded++;
}

BOOL
isInteresting(
    char *name,
    char *configTable,
    char *interestingFamilies
)
{
    char *familyVal, *listVal, *listElt;
    int familyLen, listLen;
    BOOL freeTable = NO, found = NO;
    
    if (interestingFamilies == 0)
	return YES;
	
    if (configTable == 0) {
	if (loadConfigDir(name, NO, &configTable, YES) < 0)
	    return NO;
	freeTable = YES;
    }
    if (getValueForStringTableKey(configTable, "Family",
				    &familyVal, &familyLen) == NO) {
	if (freeTable)
	    free(configTable);
	return NO;
    }
    listVal = interestingFamilies;
    listLen = strlen(listVal);
    while ((found == NO) &&
           (listElt = (char *)newStringFromList(&listVal, &listLen))) {
	if (strlen(listElt) == familyLen &&
	    strncmp(listElt, familyVal, familyLen) == 0) {
	    found = YES;
	}
	free(listElt);
    }
    if (freeTable)
	free(configTable);
    return found;
}

void
driverWasLoaded(char *name, char *configTable, char *tableName)
{
    loadedPossiblyMissingDriver(name);
    addToLoadedDriverList(newString(name),
	    (char *)bundleLongName(name, tableName), configTable,
	    tableName,
	    isInteresting(name, configTable, LoadableFamilies) ?
	    DRIVER_FLAG_INTERESTING : DRIVER_FLAG_NONE);
}



