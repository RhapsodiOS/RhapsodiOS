/* 	Copyright (c) 1997 Apple Computer, Inc.  All rights reserved.
 *
 * InterceptorGlobals.h - Global constants for use with Interceptor framework
 *
 * HISTORY
 * 13 October 1997    Mike Paquette at Apple
 *      Created. 
 */
#import <Foundation/NSString.h>
#import "Interceptor_types.h"
/*
 * Tokens representing some of the more common pixel formats found
 * in currently supported framebuffers.  This list is by no means all-inclusive.
 * Other formats, limited only by the ingenuity of hardware designers, will be
 * encountered from time to time.
 */
extern NSString * NSInterceptorEightBitPseudoColor;
extern NSString * NSInterceptorEightBitGrey;
extern NSString * NSInterceptorTwoBitGrey;
extern NSString * NSInterceptorFifteenBitRGBColor;
extern NSString * NSInterceptorSixteenBitRGBColor;
extern NSString * NSInterceptorTwelveBitRGBColor;
extern NSString * NSInterceptorThirtyTwoBitRGBColor;
