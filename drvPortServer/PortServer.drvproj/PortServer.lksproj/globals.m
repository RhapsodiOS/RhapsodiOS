/*
 * globals.m
 * Global variables for PortServer driver
 */

#import <objc/objc.h>

/* Global ttyiops map and lock */
id _ttyiopsMapLock = NULL;              /* AppleIOPSSafeCondLock for ttyiops map access */
id _ttyiopsMap[26] = { NULL };          /* Array of 26 PortServer instances (one per letter a-z) */
id _pseudoUnit = NULL;                  /* PDPseudo unit instance */

/* Global kernel port session maps */
id _nsPortKernIdMap[64] = { NULL };     /* Array of port kernel session objects (64 * 8 bytes = 0x200) */
char _nsPortKernStateMap[128] = { 0 };  /* Array of session state flags (64 * 2 bytes = 128) */

/* Global kernel session state */
int _numSessions = -1;                  /* Number of sessions (-1 if not initialized) */
id _mapLock = NULL;                     /* AppleIOPSSafeCondLock for map access */

/* Protocol array - defined in assembly */
/* This will be provided by the linker from the protocol section */
extern Protocol *objc_protocol_PortDevices;

/* Protocol array for PortServer */
Protocol *_protocols_102[] = {
    &objc_protocol_PortDevices,
    NULL
};
