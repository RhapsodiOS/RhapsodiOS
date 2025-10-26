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
 * eisa.c
 * EISA Utility Functions Implementation
 */

#include "eisa.h"
#include <driverkit/generalFuncs.h>
#include <stdlib.h>
#include <string.h>

/* EISA configuration data structures - memory mapped to fixed addresses */
/* These point to data cached by the boot loader or firmware */
#define EISA_CONFIG_DATA_ADDR   0x00020000  /* EISA config data location */
#define EISA_SLOT_DATA_ADDR     0x000130FC  /* EISA slot data location */

unsigned char *eisaConfigData = (unsigned char *)EISA_CONFIG_DATA_ADDR;
int eisaFunctionCount = 0;              /* Number of EISA functions in cache */
unsigned int *eisaSlotData = (unsigned int *)EISA_SLOT_DATA_ADDR;

/*
 * Parse EISA ID from string
 *
 * This function parses an EISA ID from a string. The ID can be in two formats:
 * 1. Numeric: A hex or decimal number (e.g., "0x12345678" or "305419896")
 * 2. EISA format: Three uppercase letters followed by 4 hex digits (e.g., "ABC1234")
 *
 * EISA Format Details:
 * - The three letters represent a compressed manufacturer code
 * - Each letter is encoded as a 5-bit value (A=1, B=2, ... Z=26)
 * - The 4 hex digits represent the product code
 * - The final ID is a 32-bit value with manufacturer code in upper bits
 *
 * Example: "ABC1234"
 * - A=1, B=2, C=3
 * - Compressed: (1<<10) | (2<<5) | 3 = 0x0443
 * - Product: 0x1234
 * - Final ID: 0x04431234
 */
unsigned long EISAParseID(unsigned char **param_1)
{
    unsigned char byte1, byte2, byte3;
    unsigned char *ptr;
    unsigned char *startPtr;
    unsigned long result;
    long productCode;
    unsigned int len;
    int isWhitespace;
    unsigned short manufacturerCode;

    /* Check for NULL pointer */
    if (param_1 == NULL || *param_1 == NULL) {
        return 0;
    }

    /* Skip leading whitespace (space or tab) */
    while (**param_1 == ' ' || **param_1 == '\t') {
        (*param_1)++;
    }

    startPtr = *param_1;

    /* Try to parse as a numeric value first */
    result = strtoul((char *)startPtr, (char **)param_1, 0);

    if (result == 0) {
        /* Numeric parsing failed or returned 0, try EISA string format */

        /* Skip whitespace */
        ptr = startPtr;
        while (1) {
            byte1 = *ptr;
            isWhitespace = 0;

            /* Check if character is whitespace: space, tab, newline */
            if (byte1 == ' ' || (byte1 >= '\t' && byte1 <= '\n')) {
                isWhitespace = 1;
            }

            if (!isWhitespace) {
                break;
            }
            ptr++;
        }

        /* Calculate string length */
        len = 0xFFFFFFFF;
        startPtr = ptr;
        do {
            if (len == 0) break;
            len--;
            byte1 = *ptr;
            ptr++;
        } while (byte1 != '\0');

        len = ~len - 1;

        /* Check if we have at least 7 characters (3 letters + 4 hex digits) */
        /* and if the first 3 characters are uppercase letters (0x40-0x5F range) */
        if (len > 6 &&
            (startPtr[0] & 0xC0) == 0x40 &&
            (startPtr[1] & 0xC0) == 0x40 &&
            (startPtr[2] & 0xC0) == 0x40) {

            /* Extract the three letter codes */
            byte1 = startPtr[0];
            byte2 = startPtr[1];
            byte3 = startPtr[2];

            /* Update pointer to skip the 3 letters */
            if (param_1 != NULL) {
                *param_1 = *param_1 + 3;
            }

            /* Parse the hex product code (4 digits after the letters) */
            productCode = strtol((char *)(startPtr + 3), (char **)param_1, 16);

            /* Construct the EISA ID:
             * - Upper 16 bits: Compressed manufacturer code from 3 letters
             * - Lower 16 bits: Product code
             *
             * Each letter is 5 bits (0x1F mask):
             * - Letter 1: bits 26-30 (shifted left by 26, then right by 16 for upper word)
             * - Letter 2: bits 21-25 (shifted left by 21, then right by 16 for upper word)
             * - Letter 3: bits 16-20 (masked with 0x1F)
             */
            manufacturerCode =
                (unsigned short)(((byte1 & 0x1F) << 0x1A) >> 0x10) |  /* Letter 1 */
                (unsigned short)(((byte2 & 0x1F) << 0x15) >> 0x10) |  /* Letter 2 */
                (byte3 & 0x1F);                                        /* Letter 3 */

            /* Combine manufacturer code (upper 16 bits) and product code (lower 16 bits) */
            result = ((unsigned long)manufacturerCode << 16) | (unsigned short)productCode;
        }
    }

    return result;
}

/*
 * Parse prefix from string
 *
 * This function checks if a string (str) starts with a given prefix followed
 * by an opening parenthesis '('.
 *
 * Example:
 * - prefix = "GetValue"
 * - str = "GetValue(123)"
 * - Returns pointer to '(' in str
 *
 * This is useful for parsing function-like command strings in driver configuration.
 */
char *EISAParsePrefix(char *prefix, char *str)
{
    size_t prefixLen;
    unsigned int len;
    char *ptr;
    char c;
    int compareResult;

    /* Check for NULL pointers */
    if (prefix == NULL || str == NULL) {
        return NULL;
    }

    /* Calculate length of prefix string manually */
    len = 0xFFFFFFFF;
    ptr = prefix;
    do {
        if (len == 0) break;
        len--;
        c = *ptr;
        ptr++;
    } while (c != '\0');

    /* Convert to actual length: ~len - 1 */
    prefixLen = ~len - 1;

    /* Compare prefix with the beginning of str */
    compareResult = strncmp(prefix, str, prefixLen);

    /* Check if prefix matches and is followed by '(' */
    if (compareResult == 0 && str[prefixLen] == '(') {
        /* Return pointer to the position after prefix (pointing at '(') */
        return str + ~len;
    }

    return NULL;
}

/*
 * Match EISA ID against a list of IDs
 *
 * This function checks if a device ID matches any ID in a list string.
 * The list can contain multiple IDs separated by whitespace.
 * Each ID can optionally have a mask specified with '&'.
 *
 * Format Examples:
 * - "ABC1234" - Match exactly
 * - "ABC1234 DEF5678" - Match either ID
 * - "ABC1234&0xFFFF0000" - Match with mask (only upper 16 bits)
 * - "ABC1234&0xFFFF0000 DEF5678" - Match first with mask or second exactly
 *
 * This is useful for matching device IDs where some bits are don't-care,
 * or for matching multiple compatible device IDs.
 */
int EISAMatchIDs(unsigned int deviceID, char *idList)
{
    char *currentPos;
    char *previousPos;
    unsigned int parsedID;
    unsigned long mask;

    currentPos = idList;

    /* Check for NULL pointer */
    if (idList == NULL) {
        return 0;
    }

    /* Parse through the ID list */
    do {
        previousPos = currentPos;

        /* Check for end of string */
        if (*currentPos == '\0') {
            return 0;
        }

        /* Parse an ID from the list */
        parsedID = EISAParseID((unsigned char **)&currentPos);

        /* Default mask is all bits (exact match) */
        mask = 0xFFFFFFFF;

        /* Check if a mask is specified with '&' */
        if (*currentPos == '&') {
            currentPos++;
            /* Parse the mask value */
            mask = strtoul(currentPos, &currentPos, 0);
        }

        /* Compare masked IDs */
        if ((parsedID & mask) == (deviceID & mask)) {
            /* Match found */
            return 1;
        }

        /* Continue loop if EISAParseID advanced the pointer */
        /* If pointer didn't advance, we're stuck and should exit */
    } while (currentPos != previousPos);

    /* No match found */
    return 0;
}

/*
 * Get EISA slot information
 *
 * Reads the EISA slot configuration information from the cached slot data table.
 * Each slot has 16 bytes (4 DWORDs) of configuration data.
 *
 * The slot data is stored at eisaSlotData (memory address 0x130fc).
 * Maximum of 64 slots (0-63) are supported.
 */
int getEISASlotInfo(unsigned int slot, unsigned char *buffer)
{
    unsigned int offset;
    unsigned int *dwordBuffer;

    /* Validate slot number (must be < 0x40 = 64) */
    if (slot >= 0x40) {
        return 0;
    }

    /* Calculate offset into slot data table */
    /* Each slot has 16 bytes (0x10), so offset = slot * 0x10 / 4 DWORDs = slot * 4 */
    offset = slot * 0x10;

    /* Cast buffer to DWORD pointer for 32-bit copies */
    dwordBuffer = (unsigned int *)buffer;

    /* Copy 4 DWORDs (16 bytes) from the cached slot data */
    dwordBuffer[0] = eisaSlotData[offset / 4 + 0];
    dwordBuffer[1] = eisaSlotData[offset / 4 + 1];
    dwordBuffer[2] = eisaSlotData[offset / 4 + 2];
    dwordBuffer[3] = eisaSlotData[offset / 4 + 3];

    return 1;
}

/*
 * Get EISA function information
 *
 * Reads the EISA function configuration information for a specific slot and function
 * from the cached EISA configuration data structure.
 *
 * The configuration data is organized as an array of structures:
 * - Offset 0x00: Slot number (1 byte)
 * - Offset 0x01: Function number (1 byte)
 * - Offset 0x02-0x03: Reserved (2 bytes)
 * - Offset 0x04-0x143: Function configuration data (0x140 = 320 bytes)
 * Total entry size: 0x144 = 324 bytes
 */
int getEISAFunctionInfo(unsigned int slot, unsigned int function, unsigned char *buffer)
{
    unsigned char *entry;
    int index;

    /* Point to base of EISA configuration data */
    entry = eisaConfigData;
    index = 0;

    /* Search through cached configuration entries */
    if (eisaFunctionCount > 0) {
        do {
            /* Check if this entry matches the requested slot and function */
            if ((entry[0] == slot) && (entry[1] == function)) {
                /* Found matching entry - copy function data to buffer */
                /* Data starts at offset 4, length is 0x140 (320) bytes */
                bcopy(entry + 4, buffer, 0x140);
                return 1;
            }

            /* Move to next entry (each entry is 0x144 bytes) */
            index++;
            entry = entry + 0x144;
        } while (index < eisaFunctionCount);
    }

    /* Not found */
    return 0;
}

/*
 * Look for EISA ID in system
 *
 * Searches all EISA slots for cards matching the specified ID list.
 * Returns information about the Nth matching instance.
 */
int LookForEISAID(unsigned long instance, const char *ids, unsigned char *buffer, unsigned int *count)
{
    unsigned int slot;
    unsigned char slotInfo[4];
    unsigned int slotID;
    unsigned long instanceCounter;
    int result;
    unsigned int functionCount;

    /* Validate parameters */
    if (ids == NULL || buffer == NULL || count == NULL) {
        return 0;
    }

    instanceCounter = 0;

    /* Search through all EISA slots (1-15) */
    for (slot = 1; slot <= 15; slot++) {
        /* Read slot information */
        result = getEISASlotInfo(slot, slotInfo);
        if (!result) {
            continue;
        }

        /* Construct slot ID from the 4 bytes */
        /* EISA ID format: bytes are in little-endian order */
        slotID = (slotInfo[3] << 24) | (slotInfo[2] << 16) | (slotInfo[1] << 8) | slotInfo[0];

        /* Check if this slot is empty (ID = 0xFFFFFFFF or 0x00000000) */
        if (slotID == 0xFFFFFFFF || slotID == 0x00000000) {
            continue;
        }

        /* Check if this slot matches the ID list */
        if (EISAMatchIDs(slotID, (char *)ids)) {
            /* Found a matching slot */
            if (instanceCounter == instance) {
                /* This is the instance we're looking for */
                /* Read full slot configuration into buffer */
                getEISASlotInfo(slot, buffer);

                /* Read function count (typically from slot configuration) */
                /* For now, assume 1 function - actual implementation would read from config */
                *count = 1;

                return slot;
            }
            instanceCounter++;
        }
    }

    /* Not found */
    return 0;
}

/*
 * Read EISA ID from a slot
 * Helper function to read the 4-byte EISA ID from a slot's configuration registers
 * Returns 1 on success, 0 if slot is empty or invalid
 */
static int eisa_id(unsigned int slot, unsigned int *slotID)
{
    unsigned char idBytes[4];
    unsigned char slotData[16];
    unsigned int id;
    int i;
    int result;

    /* Validate slot number (must be < 64) */
    if (slot >= 0x40) {
        return 0;
    }

    /* Read from cached slot data instead of I/O ports */
    /* Use getEISASlotInfo to read the 16-byte slot data */
    result = getEISASlotInfo(slot, slotData);

    if (!result) {
        return 0;
    }

    /* Extract the 4-byte EISA ID from slot data */
    /* The ID is typically in the first 4 bytes */
    id = (slotData[0] << 0) | (slotData[1] << 8) |
         (slotData[2] << 16) | (slotData[3] << 24);

    /* Check if slot is empty (ID = 0xFFFFFFFF or 0x00000000) */
    if (id == 0xFFFFFFFF || id == 0x00000000) {
        return 0;
    }

    /* Store the ID */
    if (slotID != NULL) {
        *slotID = id;
    }

    return 1;
}

/*
 * Test slot for EISA ID match
 *
 * Reads the EISA ID from a slot and tests if it matches the ID list.
 * Returns 1 if the slot contains a matching card, 0 otherwise.
 */
int testSlotForID(unsigned int slot, unsigned int *slotID, const char *idList)
{
    unsigned int localID;
    int result;
    int matches;

    /* Try to read EISA ID from slot */
    result = eisa_id(slot, &localID);

    if (result == 0) {
        /* Slot is empty or invalid */
        return 0;
    }

    /* Store the ID if caller wants it */
    if (slotID != NULL) {
        *slotID = localID;
    }

    /* Check if the ID matches the list */
    matches = EISAMatchIDs(localID, (char *)idList);

    return matches;
}
