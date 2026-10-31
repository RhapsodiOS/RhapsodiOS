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
 * pci.c
 * PCI Helper Functions
 */

#include "pci.h"
#include <string.h>
#include <stdlib.h>

/*
 * Helper function to check if string starts with a prefix followed by '('
 * Returns pointer after the prefix if match, NULL otherwise
 * Example: PCIParsePrefix("PCI", "PCI(something)") returns pointer to "(something)"
 */
char *PCIParsePrefix(char *prefix, char *str)
{
    unsigned int prefixLen;
    char ch;
    char *ptr;

    if (prefix == NULL || str == NULL) {
        return NULL;
    }

    /* Calculate length of prefix string manually */
    prefixLen = 0xFFFFFFFF;
    ptr = prefix;
    do {
        if (prefixLen == 0) break;
        prefixLen--;
        ch = *ptr++;
    } while (ch != '\0');
    prefixLen = ~prefixLen - 1;  /* Convert to actual length */

    /* Compare prefix with start of str */
    if (strncmp(prefix, str, prefixLen) == 0) {
        /* Check if character after prefix is '(' */
        if (str[prefixLen] == '(') {
            /* Return pointer to character after '(' (prefix length + 1) */
            return str + prefixLen + 1;
        }
    }

    return NULL;
}

/*
 * Helper function to parse PCI location strings
 * Format: Supports keywords like "DEV:1 FUNC:0 BUS:0 REG:10"
 * Returns 1 if parsing successful, 0 otherwise
 */
unsigned int PCIParseKeys(char *locationStr,
                         unsigned long *device,
                         unsigned int *function,
                         unsigned int *bus,
                         unsigned int *reg)
{
    char *ptr = locationStr;
    char ch, prevCh = ' ';
    int currentIndex = -1;
    unsigned long values[4] = {0, 0, 0, 0};
    unsigned int valueSet[4] = {0, 0, 0, 0}; /* Track which values were parsed */
    unsigned long parsedValue;

    if (locationStr == NULL) {
        return 0;
    }

    while (1) {
        ch = *ptr++;

        /* Convert lowercase to uppercase */
        if (ch >= 'a' && ch <= 'z') {
            ch = ch - 0x20;
        }

        switch (prevCh) {
        case ' ':  /* Initial/whitespace state */
            if (ch == 'D') {
                prevCh = 'D';
                currentIndex = 0; /* DEV */
            } else if (ch == 'F') {
                prevCh = 'F';
                currentIndex = 1; /* FUNC */
            } else if (ch == 'B') {
                prevCh = 'B';
                currentIndex = 2; /* BUS */
            } else if (ch == 'R') {
                prevCh = 'R';
                currentIndex = 3; /* REG */
            } else if (ch != ' ' && ch != '\t') {
                prevCh = '!'; /* Error state */
            }
            /* Check if this field was already set */
            if (currentIndex != -1 && valueSet[currentIndex]) {
                return 0; /* Duplicate field */
            }
            break;

        case 'D':  /* Expecting 'E' */
            if (ch != 'E') return 0;
            prevCh = 'E';
            break;

        case 'E':  /* Expecting 'V' */
            if (ch != 'V') return 0;
            prevCh = 'V';
            break;

        case 'V':  /* Expecting ':' */
        case 'C':  /* From FUNC, expecting ':' */
        case 'S':  /* From BUS, expecting ':' */
        case 'G':  /* From REG, expecting ':' */
            if (ch != ':') return 0;
            prevCh = ':';
            break;

        case 'F':  /* Expecting 'U' */
            if (ch != 'U') return 0;
            prevCh = 'U';
            break;

        case 'U':  /* Expecting 'N' */
            if (ch != 'N') return 0;
            prevCh = 'N';
            break;

        case 'N':  /* Expecting 'C' */
            if (ch != 'C') return 0;
            prevCh = 'C';
            break;

        case 'B':  /* Expecting 'U' */
            if (ch != 'U') return 0;
            prevCh = 'u'; /* lowercase u state */
            break;

        case 'u':  /* Expecting 'S' */
            if (ch != 'S') return 0;
            prevCh = 'S';
            break;

        case 'R':  /* Expecting 'E' */
            if (ch != 'E') return 0;
            prevCh = 'e'; /* lowercase e state */
            break;

        case 'e':  /* Expecting 'G' */
            if (ch != 'G') return 0;
            prevCh = 'G';
            break;

        case ':':  /* After colon, expecting number */
            if (ch != ' ' && ch != '\t') {
                if (ch >= '0' && ch <= '9') {
                    if (currentIndex == -1) return 0;
                    /* Parse the number */
                    parsedValue = strtoul(ptr - 1, &ptr, 0);
                    values[currentIndex] = parsedValue;
                    valueSet[currentIndex] = 1;
                    currentIndex = -1;
                    prevCh = ' ';
                } else {
                    prevCh = '!'; /* Error */
                }
            }
            break;

        case '!':  /* End/success state */
            /* Fill in the output parameters */
            if (device != NULL) {
                if (!valueSet[0]) return 0;
                *device = values[0];
            }
            if (function != NULL) {
                if (!valueSet[1]) return 0;
                *function = values[1];
            }
            if (bus != NULL) {
                if (!valueSet[2]) return 0;
                *bus = values[2];
            }
            if (reg != NULL) {
                if (!valueSet[3]) return 0;
                *reg = values[3];
            }
            return 1;

        default:
            /* Unknown state */
            return 0;
        }

        /* Check for end of string - transition to success state */
        if (ch == '\0') {
            prevCh = '!';
        }
    }
}
