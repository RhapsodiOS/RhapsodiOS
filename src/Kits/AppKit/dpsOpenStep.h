/*
    dpsOpenStep.h
    
    DPS routines specific to the OpenStep implementation of DPSClient.
    This API is part of OpenStep.
    
    Copyright (c) 1994-1997, Apple Computer, Inc.
    All rights reserved.
*/

#ifndef DPS_OPENSTEP_H
#define DPS_OPENSTEP_H

#import <AppKit/dpsclient.h>
#import <AppKit/AppKitDefines.h>
#import <Foundation/Foundation.h>

/* === Exception names === */

APPKIT_EXTERN NSString *DPSPostscriptErrorException;
APPKIT_EXTERN NSString *DPSNameTooLongException;
APPKIT_EXTERN NSString *DPSResultTagCheckException;
APPKIT_EXTERN NSString *DPSResultTypeCheckException;
APPKIT_EXTERN NSString *DPSInvalidContextException;
APPKIT_EXTERN NSString *DPSSelectException;
APPKIT_EXTERN NSString *DPSConnectionClosedException;
APPKIT_EXTERN NSString *DPSReadException;
APPKIT_EXTERN NSString *DPSWriteException;
APPKIT_EXTERN NSString *DPSInvalidFDException;
APPKIT_EXTERN NSString *DPSInvalidTEException;
APPKIT_EXTERN NSString *DPSInvalidPortException;
APPKIT_EXTERN NSString *DPSOutOfMemoryException;
APPKIT_EXTERN NSString *DPSCantConnectException;

// DPS exceptions may have two keys in their user info:
// 	@"DPSContextExceptionInfo" = An NSValue holding a nonretained 
//			NSDPSContext object for the context involved.
//	@"DPSArg1ExceptionUserInfo" = An NSValue holding a pointer
//			which is actually whatever the first argument 
//			to the dps error proc is for the specific type 
//			of error.


/*=== CONSTANTS ===*/

/* operation types for composite operators */
typedef enum _NSCompositingOperation {
    NSCompositeClear		= 0,
    NSCompositeCopy		= 1,
    NSCompositeSourceOver	= 2,
    NSCompositeSourceIn		= 3,
    NSCompositeSourceOut	= 4,
    NSCompositeSourceAtop	= 5,
    NSCompositeDestinationOver	= 6,
    NSCompositeDestinationIn	= 7,
    NSCompositeDestinationOut	= 8,
    NSCompositeDestinationAtop	= 9,
    NSCompositeXOR		= 10,
    NSCompositePlusDarker	= 11,
    NSCompositeHighlight	= 12,
    NSCompositePlusLighter	= 13
} NSCompositingOperation;

/* special values for alpha */
enum {
    NSAlphaEqualToData		= 1,
    NSAlphaAlwaysOne		= 2
};

/* types of window backing store */
typedef enum _NSBackingStoreType {
    NSBackingStoreRetained	 = 0,
    NSBackingStoreNonretained	 = 1,
    NSBackingStoreBuffered	 = 2
} NSBackingStoreType;

/* ways to order windows */
typedef enum _NSWindowOrderingMode {
    NSWindowAbove		 =  1,
    NSWindowBelow		 = -1,
    NSWindowOut			 =  0
} NSWindowOrderingMode;


typedef enum _DPSNumberFormat {
#ifdef __BIG_ENDIAN__
    dps_float = 48,
    dps_long = 0,
    dps_short = 32
#else
    dps_float = 48+128,
    dps_long = 0+128,
    dps_short = 32+128
#endif
} DPSNumberFormat;
  /* Constants for DPSDoUserPath describing what type of coordinates are
     being used.  Other legal values are:

     For 32-bit fixed point numbers, use dps_long plus the number of bits
     in the fractional part.

     For 16-bit fixed point numbers, use dps_short plus the number of bits
     in the fractional part.
  */

typedef unsigned char DPSUserPathOp;
enum {
    dps_setbbox = 0,
    dps_moveto,
    dps_rmoveto,
    dps_lineto,
    dps_rlineto,
    dps_curveto,
    dps_rcurveto,
    dps_arc,
    dps_arcn,
    dps_arct,
    dps_closepath,
    dps_ucache
};
  /* Constants for constructing operator array parameter of DPSDoUserPath. */

typedef enum _DPSUserPathAction {
    dps_uappend = 176,
    dps_ufill = 179,
    dps_ueofill = 178,
    dps_ustroke = 183,
    dps_ustrokepath = 364,
    dps_inufill = 93,
    dps_inueofill = 92,
    dps_inustroke = 312,
    dps_def = 51,
    dps_put = 120
} DPSUserPathAction;
  /* Constants for the action of DPSDoUserPath.  In addition to these, any
     other system name index may be used.
   */

/* a userobject that can be used to pass a PostScript "null" */
enum {
    DPSNullObject = 1
};

/*=== PROCEDURES ===*/

APPKIT_EXTERN void PSFlush(void);
  /* Flushes the current connection */

APPKIT_EXTERN void PSWait(void);
  /* Flushes the current connection, waits for acknowledgement */

APPKIT_EXTERN void PSDoUserPath(  
    const void *coords,
    int numCoords,
    DPSNumberFormat numType,
    const DPSUserPathOp *ops,
    int numOps,
    const void *bbox,
    DPSUserPathAction action);
APPKIT_EXTERN void DPSDoUserPath(
    DPSContext context,
    const void *coords,
    int numCoords,
    DPSNumberFormat numType,
    const DPSUserPathOp *ops,
    int numOps,
    const void *bbox,
    DPSUserPathAction action);
APPKIT_EXTERN void PSDoUserPathWithMatrix(  
    const void *coords,
    int numCoords,
    DPSNumberFormat numType,
    const DPSUserPathOp *ops,
    int numOps,
    const void *bbox,
    DPSUserPathAction action,
    float matrix[6]);
APPKIT_EXTERN void DPSDoUserPathWithMatrix(
    DPSContext context,
    const void *coords,
    int numCoords,
    DPSNumberFormat numType,
    const DPSUserPathOp *ops,
    int numOps,
    const void *bbox,
    DPSUserPathAction action,
    float matrix[6]);
  /* Sends a user path to the window server and one other operator.  See DPS
     extensions documentation on encoded user paths.
     Matrix represents the optional matrix argument used by the ustroke,
     inustroke and ustrokepath operators. If matrix is NULL, it is ignored.
   */

#endif DPS_OPENSTEP_H

