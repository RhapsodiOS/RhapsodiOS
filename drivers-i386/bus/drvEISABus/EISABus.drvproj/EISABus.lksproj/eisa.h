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
 * eisa.h
 * EISA Utility Functions
 */

#ifndef _EISA_H_
#define _EISA_H_

#include <sys/types.h>

/*
 * Parse EISA ID from string
 *
 * Parses either a numeric ID (hex or decimal) or an EISA ID string format.
 * EISA ID format: 3 uppercase letters (A-Z) followed by 4 hex digits
 * Example: "ABC1234" where ABC is manufacturer code, 1234 is product code
 *
 * param_1: Pointer to pointer to string. Updated to point past parsed ID.
 * returns: Parsed EISA ID as 32-bit value, or 0 if parsing fails
 */
unsigned long EISAParseID(unsigned char **param_1);

/*
 * Parse prefix from string
 *
 * Checks if str starts with prefix followed by '('.
 * Example: prefix="GetValue", str="GetValue(123)" returns pointer to '('
 *
 * prefix: The prefix string to search for
 * str: The string to search in
 * returns: Pointer to '(' after prefix if found, NULL otherwise
 */
char *EISAParsePrefix(char *prefix, char *str);

/*
 * Match EISA ID against a list of IDs
 *
 * Checks if deviceID matches any ID in the idList string.
 * ID list format: Space-separated IDs, optionally with masks using '&'
 * Examples:
 *   "ABC1234 DEF5678" - Match either ID exactly
 *   "ABC1234&0xFFFF0000" - Match with mask (only compare upper 16 bits)
 *
 * deviceID: The EISA ID to match
 * idList: String containing list of IDs to match against
 * returns: 1 if match found, 0 otherwise
 */
int EISAMatchIDs(unsigned int deviceID, char *idList);

/*
 * Get EISA slot information
 *
 * Reads the EISA configuration information for a specific slot.
 * Reads 4 bytes of configuration data from EISA slot ports.
 *
 * slot: The EISA slot number (1-based)
 * buffer: Buffer to receive configuration data (minimum 4 bytes)
 * returns: 1 on success, 0 on failure
 */
int getEISASlotInfo(unsigned int slot, unsigned char *buffer);

/*
 * Get EISA function information
 *
 * Reads the EISA function configuration information for a specific slot and function.
 * Reads configuration data for one function within an EISA slot.
 *
 * slot: The EISA slot number (1-based)
 * function: The function number within the slot
 * buffer: Buffer to receive configuration data
 * returns: 1 on success, 0 on failure
 */
int getEISAFunctionInfo(unsigned int slot, unsigned int function, unsigned char *buffer);

/*
 * Look for EISA ID in system
 *
 * Searches all EISA slots for cards matching the specified ID list.
 * Returns information about the Nth matching instance.
 *
 * instance: Which matching instance to find (0-based)
 * ids: String containing list of IDs to match against
 * buffer: Buffer to receive slot/function configuration data
 * count: Pointer to receive function count
 * returns: Slot number if found (1-based), 0 if not found
 */
int LookForEISAID(unsigned long instance, const char *ids, unsigned char *buffer, unsigned int *count);

/*
 * Test slot for EISA ID match
 *
 * Reads the EISA ID from a slot and tests if it matches the ID list.
 * Returns 1 if the slot contains a matching card, 0 otherwise.
 *
 * slot: The EISA slot number to test
 * slotID: Pointer to receive the slot's EISA ID (can be NULL)
 * idList: String containing list of IDs to match against
 * returns: 1 if slot matches, 0 if not
 */
int testSlotForID(unsigned int slot, unsigned int *slotID, const char *idList);

#endif /* _EISA_H_ */
