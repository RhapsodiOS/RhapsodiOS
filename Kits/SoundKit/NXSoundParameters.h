/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * NXSoundParameters.h
 *
 * Copyright (c) 1993, NeXT Computer, Inc.  All rights reserved. 
 */

#import <objc/HashTable.h>
#import <Foundation/Foundation.h>
#import <SoundKit/soundstruct.h>
#import <driverkit/NXSoundParameterTags.h>

@protocol NXSoundParameters
- (BOOL)boolValueForParameter:(NXSoundParameterTag)ptag;
- (int)intValueForParameter:(NXSoundParameterTag)ptag;
- (float)floatValueForParameter:(NXSoundParameterTag)ptag;
- (void)setParameter:(NXSoundParameterTag)ptag toBool:(BOOL)flag;
- (void)setParameter:(NXSoundParameterTag)ptag toInt:(int)value;
- (void)setParameter:(NXSoundParameterTag)ptag toFloat:(float)value;
- (void)removeParameter:(NXSoundParameterTag)ptag;
- (BOOL)isParameterPresent:(NXSoundParameterTag)ptag;
- (void)getParameters:(const NXSoundParameterTag **)list
    count:(unsigned int *)numParameters;
- (void)getValues:(const NXSoundParameterTag **)list
     count:(unsigned int *)numValues forParameter:(NXSoundParameterTag)ptag;
@end

@interface NXSoundParameters : NSObject <NXSoundParameters>
{
    HashTable		*_paramTable;
    NXSoundParameterTag *_paramList;
    int			_reserved;
}

+ (NSString *)localizedNameForParameter:(NXSoundParameterTag)ptag;
- (id)init;
- (id)initFromSound:(id)aSound;
- (id)initFromSoundStruct:(SNDSoundStruct *)soundStruct;
- (void)configureSoundStruct:(SNDSoundStruct *)soundStruct;
- (void)encodeWithCoder:(NSCoder *)stream;
- (id)initWithCoder:(NSCoder *)stream;
- (void)dealloc;

@end
