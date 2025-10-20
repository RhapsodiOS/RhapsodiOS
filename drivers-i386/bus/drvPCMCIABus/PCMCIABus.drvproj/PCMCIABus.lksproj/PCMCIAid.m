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
 * PCMCIA Card ID Implementation
 */

#import "PCMCIAid.h"
#import <string.h>
#import <libkern/libkern.h>

/* PCMCIA ID field keys for description dictionary (no colon) */
static const char *PCMCIAidDescriptionKeys[] = {
    "PCMCIA_TPLFID_FUNCTION",
    "PCMCIA_TPLMID_MANF",
    "PCMCIA_TPLMID_CARD",
    "PCMCIA_TPLVERS_1",
    "PCMCIA_TPLVERS_2"
};

/* PCMCIA ID field keys for string parsing (with colon) */
static const char *PCMCIAidStringKeys[] = {
    "PCMCIA_TPLFID_FUNCTION:",
    "PCMCIA_TPLMID_MANF:",
    "PCMCIA_TPLMID_CARD:",
    "PCMCIA_TPLVERS_1:",
    "PCMCIA_TPLVERS_2:"
};

static const int PCMCIAidStringKeyLengths[] = {
    24,  /* strlen("PCMCIA_TPLFID_FUNCTION:") */
    19,  /* strlen("PCMCIA_TPLMID_MANF:") */
    19,  /* strlen("PCMCIA_TPLMID_CARD:") */
    17,  /* strlen("PCMCIA_TPLVERS_1:") */
    17   /* strlen("PCMCIA_TPLVERS_2:") */
};

/* Field labels for logging */
static const char *PCMCIAidFieldLabels[] = {
    "Function Type:",
    "Manufacturer:",
    "Product:",
    "Version 1:",
    "Version 2:"
};

/* Helper function to free a string field */
static void _freeString(char **stringPtr)
{
    if (*stringPtr != NULL) {
        IOFree(*stringPtr, strlen(*stringPtr) + 1);
        *stringPtr = NULL;
    }
}

/*
 * Check if character is valid for PCMCIA ID strings
 * Valid characters: A-Z, a-z, 0-9, '-', '+', '.', and ':' and ';'
 */
static char isValidPCMCIA_IDChar(char c)
{
    /* Check if character is invalid by testing all exclusion conditions */
    if ((((0x19 < (unsigned char)(c + 0xBF)) && (0x19 < (unsigned char)(c + 0x9F))) &&
        (9 < (unsigned char)(c - 0x30))) &&
        (((c != '-' && (c != '+')) && ((c != '.' && (1 < (unsigned char)(c - 0x3A))))))) {
        return 0;  /* Invalid character */
    }
    return 1;  /* Valid character */
}

/*
 * Sanitize and copy a string, filtering out invalid characters
 * Returns NULL if input is NULL or contains no valid characters
 */
static char *_sanitizeStringCopy(char *str)
{
    char c;
    char *scanPtr;
    unsigned int strLen;
    int originalLength;
    int validCount;
    int i;
    char *result;
    char *destPtr;

    if (str == NULL) {
        return NULL;
    }

    /* Calculate string length manually */
    strLen = 0xFFFFFFFF;
    scanPtr = str;
    do {
        if (strLen == 0) break;
        strLen--;
        c = *scanPtr;
        scanPtr++;
    } while (c != '\0');
    originalLength = ~strLen - 1;

    /* Count valid characters */
    validCount = 0;
    i = 0;
    if (0 < originalLength) {
        do {
            c = isValidPCMCIA_IDChar((int)str[i]);
            if (c != '\0') {
                validCount++;
            }
            i++;
        } while (i < originalLength);
    }

    /* Check if any valid characters found */
    if (validCount == 0) {
        IOLog("PCMCIA: sanitizeStringCopy: no valid characters in '%s'\n", str);
        return NULL;
    }

    /* Allocate memory for valid characters + null terminator */
    result = (char *)IOMalloc(validCount + 1);
    if (result == NULL) {
        IOLog("PCMCIA: sanitizeStringCopy: IOMalloc failed\n");
        return NULL;
    }

    /* Copy only valid characters */
    i = 0;
    destPtr = result;
    if (0 < originalLength) {
        do {
            c = isValidPCMCIA_IDChar((int)str[i]);
            if (c != '\0') {
                *destPtr = str[i];
                destPtr++;
            }
            i++;
        } while (i < originalLength);
    }

    /* Null-terminate */
    result[validCount] = '\0';

    return result;
}

@implementation PCMCIAid

- initFromDescription:description
{
    int i;
    const char *str;
    char **fields;

    [super init];

    /* Array of pointers to the 5 string fields */
    fields = (char **)&_function;

    /* Loop through all 5 ID fields */
    for (i = 0; i < 5; i++) {
        /* Get string for this key from description */
        str = [description stringForKey:PCMCIAidDescriptionKeys[i]];

        /* Sanitize and copy the string */
        fields[i] = _sanitizeStringCopy(str);
    }

    return self;
}

- initFromIDString:(char **)idStringPtr
{
    char *str;
    char *originalStr;
    char *endOfString;
    char *endOfToken;
    char *comma;
    int offset;
    int fieldIndex;
    int i;
    int matchIndex;
    size_t valueLen;
    char *value;
    char **fields;

    [super init];

    /* Initialize all fields to NULL */
    _function = NULL;
    _manufacturer = NULL;
    _product = NULL;
    _version1 = NULL;
    _version2 = NULL;

    /* Get the string from the pointer */
    str = *idStringPtr;
    originalStr = str;

    /* Calculate string length */
    endOfString = str + strlen(str);
    offset = 0;

    /* Skip leading whitespace (spaces and tabs) */
    while (*str == ' ' || *str == '\t') {
        str++;
        offset++;
    }

    /* Find the end of the current token (up to space or end of string) */
    endOfToken = strchr(str, ' ');
    if (endOfToken == NULL) {
        endOfToken = endOfString;
    }

    /* Array of pointers to the 5 string fields */
    fields = (char **)&_function;

    /* Parse fields until we reach the end of the token */
    while (endOfToken > str) {
        /* Try to match one of the 5 field prefixes */
        matchIndex = -1;
        for (i = 0; i < 5; i++) {
            if (strncmp(PCMCIAidStringKeys[i], str, PCMCIAidStringKeyLengths[i]) == 0) {
                matchIndex = i;
                break;
            }
        }

        /* If no match found, error */
        if (matchIndex == -1) {
            IOLog("PCMCIA: error parsing '%s' at offset %d\n", originalStr, offset);
            *idStringPtr = NULL;
            [self free];
            return nil;
        }

        /* Move past the prefix */
        fieldIndex = matchIndex;
        str += PCMCIAidStringKeyLengths[matchIndex];
        offset += PCMCIAidStringKeyLengths[matchIndex];

        /* Find the end of the value (comma or end of token) */
        comma = strchr(str, ',');
        if (comma == NULL || endOfToken < comma) {
            comma = endOfToken;
        }

        /* Extract the value */
        valueLen = comma - str;
        value = (char *)IOMalloc(valueLen + 1);
        strncpy(value, str, valueLen);
        value[valueLen] = '\0';

        /* Store in the appropriate field */
        fields[fieldIndex] = value;

        /* Move to next field */
        offset += valueLen;
        str = comma;

        /* Skip comma if present */
        if (*str == ',') {
            str++;
            offset++;
        }

        /* Update the pointer to indicate where we stopped parsing */
        *idStringPtr = endOfToken;
    }

    return self;
}

- free
{
    int i;
    char **fields;

    /* Array of pointers to the 5 string fields */
    fields = (char **)&_function;

    /* Free all 5 string fields */
    for (i = 0; i < 5; i++) {
        _freeString(&fields[i]);
    }

    return [super free];
}

- (BOOL)matchesID:otherID
{
    PCMCIAid *other = (PCMCIAid *)otherID;
    int i;
    char **selfFields;
    char **otherFields;

    /* Array of pointers to the 5 string fields */
    selfFields = (char **)&_function;
    otherFields = (char **)&(other->_function);

    /* Check all 5 fields */
    for (i = 0; i < 5; i++) {
        /* If self's field is NULL, it matches anything (wildcard) */
        if (selfFields[i] == NULL) {
            continue;
        }

        /* If self's field is non-NULL, other's field must also be non-NULL and equal */
        if (otherFields[i] != NULL && strcmp(selfFields[i], otherFields[i]) == 0) {
            continue;
        }

        /* Fields don't match */
        return NO;
    }

    /* All fields matched */
    return YES;
}

- (void)IOLog
{
    int i;
    char **fields;

    /* Array of pointers to the 5 string fields */
    fields = (char **)&_function;

    /* Log each non-NULL field with its label */
    for (i = 0; i < 5; i++) {
        if (fields[i] != NULL) {
            ::IOLog("PCMCIAid: %s %s\n", PCMCIAidFieldLabels[i], fields[i]);
        }
    }
}

/*
 * Class method to log card information from device description
 */
+ (void)IOLogCardInformation:deviceDesc
{
    int i;
    const char *value;
    const char *functionName;
    extern const char *_stringForFunctionID(const char *funcID);

    /* Loop through all 5 ID fields */
    for (i = 0; i < 5; i++) {
        /* Get string value for this key from device description */
        value = [deviceDesc stringForKey:PCMCIAidDescriptionKeys[i]];

        if (value != NULL) {
            if (i == 0) {
                /* Field 0 is function type - convert to human-readable string */
                functionName = _stringForFunctionID(value);
                ::IOLog("PCMCIABus: %s %s (%s)\n",
                       PCMCIAidFieldLabels[i], functionName, value);
            } else {
                /* Other fields - just log the value */
                ::IOLog("PCMCIABus: %s %s\n",
                       PCMCIAidFieldLabels[i], value);
            }
        }
    }
}

@end
