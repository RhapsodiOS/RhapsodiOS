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

#import <objc/Object.h>
#import <objc/objc-runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "IODeviceMaster.h"

static char *progname;
static char cmdBuffer[512];
static char valueBuffer[512];

void bail(const char *msg, int code)
{
    fprintf(stderr, "%s: %s %d\n", progname, msg, code);
    exit(1);
}

int main(int argc, char **argv)
{
    int dumpConfig;
    int dumpCards;
    id deviceMaster;
    int result;
    unsigned int objNum;
    const char *kind;
    Class pnpDevResClass;
    Class pnpResClass;
    unsigned int csn;
    char *argPtr;
    unsigned int valueSize;
    id deviceResources;
    int deviceCount;
    id deviceList;
    int deviceIndex;
    id currentConfig;

    progname = argv[0];

    if (argc == 1) {
        dumpConfig = 1;
        dumpCards = 1;
    } else {
        dumpConfig = 0;
        dumpCards = 0;

        while (argc = argc - 1, argc != 0) {
            argv = argv + 1;
            if (**argv == '-') {
                argPtr = *argv;
                while (argPtr = argPtr + 1, *argPtr != '\0') {
                    if (*argPtr == 'c') {
                        dumpCards = 1;
                    } else if (*argPtr == 'd') {
                        dumpConfig = 1;
                    } else {
                        bail("invalid option\n", 0);
                    }
                }
            }
        }
    }

    deviceMaster = objc_msgSend(objc_getClass("IODeviceMaster"), sel_getUid("new"));
    result = (int)objc_msgSend(deviceMaster, sel_getUid("lookUpByDeviceName:objectNumber:deviceKind:"),
                         "EISA0", &objNum, &kind);
    if (result != 0) {
        bail("lookup EISA0 failed", result);
    }

    pnpDevResClass = objc_getClass("PnPDeviceResources");
    pnpResClass = objc_getClass("PnPResources");

    objc_msgSend(pnpDevResClass, sel_getUid("setVerbose:"), 1);

    for (csn = 1; csn <= 254; csn++) {
        valueSize = 0x200;

        if (dumpCards) {
            sprintf(cmdBuffer, "%s( %d", "GetPnPInfo", csn);
            result = (int)objc_msgSend(deviceMaster,
                                sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                valueBuffer, cmdBuffer, objNum, &valueSize);

            if (result == 0) {
                printf("\n");
                printf("=========================================================\n");
                printf("csn %d:\n", csn);
                printf("=====================\n");
                printf("Resource Description:\n");
                printf("=====================\n");

                deviceResources = objc_msgSend(pnpDevResClass, sel_getUid("alloc"));
                deviceResources = objc_msgSend(deviceResources,
                                              sel_getUid("initForBuf:Length:CSN:"),
                                              valueBuffer, valueSize, csn);

                result = (int)objc_msgSend(deviceResources, sel_getUid("parseConfig"));
                if (result == 0) {
                    exit(1);
                }

                deviceList = objc_msgSend((id)result, sel_getUid("deviceList"));
                deviceCount = (int)objc_msgSend(deviceList, sel_getUid("count"));
                objc_msgSend((id)result, sel_getUid("free"));
            } else {
                continue;
            }
        } else {
            deviceCount = 10;
        }

        if (dumpConfig && deviceCount > 0) {
            for (deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++) {
                sprintf(cmdBuffer, "%s( %d %d", "GetPnPDeviceCfg", csn, deviceIndex);
                valueSize = 0x200;

                result = (int)objc_msgSend(deviceMaster,
                                    sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                    valueBuffer, cmdBuffer, objNum, &valueSize);

                if (result == 0) {
                    printf("\n");
                    printf("============================================\n");
                    printf("Current configuration for Logical Device %d:\n", deviceIndex);
                    printf("============================================\n");

                    currentConfig = objc_msgSend(pnpResClass, sel_getUid("alloc"));
                    currentConfig = objc_msgSend(currentConfig,
                                                sel_getUid("initFromRegisters:"),
                                                valueBuffer);

                    result = (int)objc_msgSend(currentConfig, sel_getUid("parseConfig"));
                    if (result == 0) {
                        printf("config is nil - continuing\n");
                    } else {
                        objc_msgSend((id)result, sel_getUid("free"));
                    }
                }
            }
        }
    }

    exit(0);
    return 0;
}
