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
#ifdef SHLIB
#include "shlib.h"
#undef abort
#endif SHLIB

/*
 * NXSoundParameters.m
 *
 * Copyright (c) 1993, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundParameters.h"
#import "Sound.h"
#import <Foundation/Foundation.h>
#import <stdlib.h>

@implementation NXSoundParameters

typedef struct param {
    BOOL	boolVal;
    int		intVal;
    float	floatVal;
} param_t;

/*
 * Get parameter value - create new table entry if needed.
 */
static param_t *getParam(HashTable *ptable, NXSoundParameterTag ptag)
{
    void *param;

    if (!(param = (param_t *)[ptable valueForKey:(const void *)ptag])) {
	param = calloc(1, sizeof(param_t));
	[ptable insertKey:(const void *)ptag value:param];
    }
    return (param_t *)param;
}

/*
 * Localizable strings.
 */
NSBundle * _NSSKBundle = nil;

#define S_BUFFER_SIZE [_NSSKBundle localizedStringForKey:@"Buffer size" value:nil table:@"SoundKit"]
#define S_BUFFER_COUNT [_NSSKBundle localizedStringForKey:@"Buffer count" value:nil table:@"SoundKit"]
#define S_DETECT_PEAKS [_NSSKBundle localizedStringForKey:@"Detect peaks" value:nil table:@"SoundKit"]
#define S_RAMP_UP [_NSSKBundle localizedStringForKey:@"Ramp up" value:nil table:@"SoundKit"]
#define S_RAMP_DOWN [_NSSKBundle localizedStringForKey:@"Ramp down" value:nil table:@"SoundKit"]
#define S_INSERT_ZEROS [_NSSKBundle localizedStringForKey:@"Insert zeros" value:nil table:@"SoundKit"]
#define S_DEEMPHASIZE [_NSSKBundle localizedStringForKey:@"Deemphasize" value:nil table:@"SoundKit"]
#define S_MUTE_SPEAKER [_NSSKBundle localizedStringForKey:@"Mute speaker" value:nil table:@"SoundKit"]
#define S_MUTE_HEADPHONE [_NSSKBundle localizedStringForKey:@"Mute headphone" value:nil table:@"SoundKit"]
#define S_MUTE_LINEOUT [_NSSKBundle localizedStringForKey:@"Mute line out" value:nil table:@"SoundKit"]
#define S_OUTPUT_LOUDNESS [_NSSKBundle localizedStringForKey:@"Output loudness" value:nil table:@"SoundKit"]
#define S_OUTPUT_ATTEN_STEREO [_NSSKBundle localizedStringForKey:@"Output attenuation stereo" value:nil table:@"SoundKit"]
#define S_OUTPUT_ATTEN_LEFT [_NSSKBundle localizedStringForKey:@"Output attenuation left" value:nil table:@"SoundKit"]
#define S_OUTPUT_ATTEN_RIGHT [_NSSKBundle localizedStringForKey:@"Output attenuation right" value:nil table:@"SoundKit"]
#define S_ANALOG_INPUT_SOURCE [_NSSKBundle localizedStringForKey:@"Analog input source" value:nil table:@"SoundKit"]
#define S_ANALOG_INPUT_SOURCE_MIC [_NSSKBundle localizedStringForKey:@"Analog input source micropone" value:nil table:@"SoundKit"]
#define S_ANALOG_INPUT_SOURCE_LINE_IN [_NSSKBundle localizedStringForKey:@"Analog input source line in" value:nil table:@"SoundKit"]
#define S_MONITOR_ATTEN [_NSSKBundle localizedStringForKey:@"Monitor attenuation" value:nil table:@"SoundKit"]
#define S_INPUT_GAIN_STEREO [_NSSKBundle localizedStringForKey:@"Input gain stereo" value:nil table:@"SoundKit"]
#define S_INPUT_GAIN_LEFT [_NSSKBundle localizedStringForKey:@"Input gain left" value:nil table:@"SoundKit"]
#define S_INPUT_GAIN_RIGHT [_NSSKBundle localizedStringForKey:@"Input gain right" value:nil table:@"SoundKit"]
#define S_DATA_ENCODING [_NSSKBundle localizedStringForKey:@"Data encoding" value:nil table:@"SoundKit"]
#define S_LINEAR16 [_NSSKBundle localizedStringForKey:@"Linear 16-bit" value:nil table:@"SoundKit"]
#define S_LINEAR8 [_NSSKBundle localizedStringForKey:@"Linear 8-bit" value:nil table:@"SoundKit"]
#define S_MULAW8 [_NSSKBundle localizedStringForKey:@"mu-law 8-bit" value:nil table:@"SoundKit"]
#define S_ALAW8 [_NSSKBundle localizedStringForKey:@"a-law 8-bit" value:nil table:@"SoundKit"]
#define S_AES [_NSSKBundle localizedStringForKey:@"AES" value:nil table:@"SoundKit"]
#define S_SAMPLING_RATE [_NSSKBundle localizedStringForKey:@"Sampling rate" value:nil table:@"SoundKit"]
#define S_CHANNEL_COUNT [_NSSKBundle localizedStringForKey:@"Channel count" value:nil table:@"SoundKit"]
#define S_HIGH_WATER [_NSSKBundle localizedStringForKey:@"High water mark" value:nil table:@"SoundKit"]
#define S_LOW_WATER [_NSSKBundle localizedStringForKey:@"Low water mark" value:nil table:@"SoundKit"]
#define S_SOURCE [_NSSKBundle localizedStringForKey:@"Source" value:nil table:@"SoundKit"]
#define S_ANALOG [_NSSKBundle localizedStringForKey:@"Analog" value:nil table:@"SoundKit"]
#define S_SINK [_NSSKBundle localizedStringForKey:@"Sink" value:nil table:@"SoundKit"]
#define S_GAIN_STEREO [_NSSKBundle localizedStringForKey:@"Gain stereo" value:nil table:@"SoundKit"]
#define S_GAIN_LEFT [_NSSKBundle localizedStringForKey:@"Gain left" value:nil table:@"SoundKit"]
#define S_GAIN_RIGHT [_NSSKBundle localizedStringForKey:@"Gain right" value:nil table:@"SoundKit"]
#define S_UNKNOWN_PARAM [_NSSKBundle localizedStringForKey:@"Unknown parameter" value:nil table:@"SoundKit"]

/*
 * Look up localized name for parameter or value.
 */
+ (NSString *)localizedNameForParameter:(NXSoundParameterTag)ptag
{
    /*
     * Create bundle if [NXApp new] not run.
     * ??? We should just have a _NSSKBundle() function in the kit... -aozer
     */
    if (!_NSSKBundle) {
	_NSSKBundle = [NSBundle bundleForClass:[Sound class]];
    }

    switch (ptag) {
      case NX_SoundDeviceBufferSize:
	return(S_BUFFER_SIZE);
      case NX_SoundDeviceBufferCount:
	return(S_BUFFER_COUNT);
      case NX_SoundDeviceDetectPeaks:
	return(S_DETECT_PEAKS);
      case NX_SoundDeviceRampUp:
	return(S_RAMP_UP);
      case NX_SoundDeviceRampDown:
	return(S_RAMP_DOWN);
      case NX_SoundDeviceInsertZeros:
	return(S_INSERT_ZEROS);
      case NX_SoundDeviceDeemphasize:
	return(S_DEEMPHASIZE);
      case NX_SoundDeviceMuteSpeaker:
	return(S_MUTE_SPEAKER);
      case NX_SoundDeviceMuteHeadphone:
	return(S_MUTE_HEADPHONE);
      case NX_SoundDeviceMuteLineOut:
	return(S_MUTE_LINEOUT);
      case NX_SoundDeviceOutputLoudness:
	return(S_OUTPUT_LOUDNESS);
      case NX_SoundDeviceOutputAttenuationStereo:
	return(S_OUTPUT_ATTEN_STEREO);
      case NX_SoundDeviceOutputAttenuationLeft:
	return(S_OUTPUT_ATTEN_LEFT);
      case NX_SoundDeviceOutputAttenuationRight:
	return(S_OUTPUT_ATTEN_RIGHT);

      case NX_SoundDeviceAnalogInputSource:
	return(S_ANALOG_INPUT_SOURCE);
      case NX_SoundDeviceAnalogInputSource_Microphone:
	return(S_ANALOG_INPUT_SOURCE_MIC);
      case NX_SoundDeviceAnalogInputSource_LineIn:
	return(S_ANALOG_INPUT_SOURCE_LINE_IN);

      case NX_SoundDeviceMonitorAttenuation:
	return(S_MONITOR_ATTEN);
      case NX_SoundDeviceInputGainStereo:
	return(S_INPUT_GAIN_STEREO);
      case NX_SoundDeviceInputGainLeft:
	return(S_INPUT_GAIN_LEFT);
      case NX_SoundDeviceInputGainRight:
	return(S_INPUT_GAIN_LEFT);

      case NX_SoundStreamDataEncoding:
	return(S_DATA_ENCODING);
      case NX_SoundStreamDataEncoding_Linear16:
	return(S_LINEAR16);
      case NX_SoundStreamDataEncoding_Linear8:
	return(S_LINEAR8);
      case NX_SoundStreamDataEncoding_Mulaw8:
	return(S_MULAW8);
      case NX_SoundStreamDataEncoding_Alaw8:
	return(S_ALAW8);
      case NX_SoundStreamDataEncoding_AES:
	return(S_AES);

      case NX_SoundStreamSamplingRate:
	return(S_SAMPLING_RATE);
      case NX_SoundStreamChannelCount:
	return(S_CHANNEL_COUNT);
      case NX_SoundStreamHighWaterMark:
	return(S_HIGH_WATER);
      case NX_SoundStreamLowWaterMark:
	return(S_LOW_WATER);

      case NX_SoundStreamSource:
	return(S_SOURCE);
      case NX_SoundStreamSource_Analog:
	return(S_ANALOG);
      case NX_SoundStreamSource_AES:
	return(S_AES);

      case NX_SoundStreamSink:
	return(S_SINK);
      case NX_SoundStreamSink_Analog:
	return(S_ANALOG);
      case NX_SoundStreamSink_AES:
	return(S_AES);

      case NX_SoundStreamDetectPeaks:
	return(S_DETECT_PEAKS);
      case NX_SoundStreamGainStereo:
	return(S_GAIN_STEREO);
      case NX_SoundStreamGainLeft:
	return(S_GAIN_LEFT);
      case NX_SoundStreamGainRight:
	return(S_GAIN_RIGHT);
      default:
	return(S_UNKNOWN_PARAM);
    }
}

/*
 * Init methods.
 */

- (id)init
{
    [super init];
    _paramTable = [[HashTable alloc] initKeyDesc:"i" valueDesc:"!"];
    return self;
}

static void setFromSound(NXSoundParameters *self, float rate, int chans,
			 int format)
{
    [self setParameter:NX_SoundStreamSamplingRate toFloat:rate];
    [self setParameter:NX_SoundStreamChannelCount toInt:chans];
    switch (format) {
      case SND_FORMAT_MULAW_8:
	[self setParameter:NX_SoundStreamDataEncoding
            toInt:NX_SoundStreamDataEncoding_Mulaw8];
	break;
      case SND_FORMAT_LINEAR_8:
	[self setParameter:NX_SoundStreamDataEncoding
            toInt:NX_SoundStreamDataEncoding_Linear8];
	break;
      case SND_FORMAT_LINEAR_16:
	[self setParameter:NX_SoundStreamDataEncoding
            toInt:NX_SoundStreamDataEncoding_Linear16];
	break;
      case SND_FORMAT_ALAW_8:
	[self setParameter:NX_SoundStreamDataEncoding
            toInt:NX_SoundStreamDataEncoding_Alaw8];
	break;
      case SND_FORMAT_AES:
	[self setParameter:NX_SoundStreamDataEncoding
            toInt:NX_SoundStreamDataEncoding_AES];
	break;
      default:
	break;
    }
}

- initFromSound:aSound
{
    [self init];
    if (!aSound)
	return self;
    setFromSound(self, (float)[aSound samplingRate],
		 [aSound channelCount], [aSound dataFormat]);
    return self;
}

- initFromSoundStruct:(SNDSoundStruct *)soundStruct
{
    [self init];
    if (!soundStruct)
	return self;
    setFromSound(self, (float)soundStruct->samplingRate,
		 soundStruct->channelCount, soundStruct->dataFormat);
    return self;
}

/*
 * Configure a sound struct.
 */
- (void)configureSoundStruct:(SNDSoundStruct *)soundStruct
{
    int format;

    if (!soundStruct)
	return;
    if ([self isParameterPresent:NX_SoundStreamSamplingRate])
	soundStruct->samplingRate =
	    [self intValueForParameter:NX_SoundStreamSamplingRate];
    if ([self isParameterPresent:NX_SoundStreamChannelCount])
	soundStruct->channelCount =
	    [self intValueForParameter:NX_SoundStreamChannelCount];
    if ([self isParameterPresent:NX_SoundStreamDataEncoding]) {
	format = [self intValueForParameter:NX_SoundStreamDataEncoding];
	switch (format) {
	  case NX_SoundStreamDataEncoding_Mulaw8:
	    soundStruct->dataFormat = SND_FORMAT_MULAW_8;
	    break;
	  case NX_SoundStreamDataEncoding_Linear8:
	    soundStruct->dataFormat = SND_FORMAT_LINEAR_8;
	    break;
	  case NX_SoundStreamDataEncoding_Linear16:
	    soundStruct->dataFormat = SND_FORMAT_LINEAR_16;
	    break;
	  case NX_SoundStreamDataEncoding_Alaw8:
	    soundStruct->dataFormat = SND_FORMAT_ALAW_8;
	    break;
	  case NX_SoundStreamDataEncoding_AES:
	    soundStruct->dataFormat = SND_FORMAT_AES;
	    break;
	  default:
	    break;
	}
    }
}

static void freeParamList(NXSoundParameters *self)
{
    if (self->_paramList) {
	free(self->_paramList);
	self->_paramList = 0;
    }
}

/*
 * Free param table and self.
 */
- (void)dealloc
{
    NXHashState state = [_paramTable initState];
    const void *key;
    void *value;

    while ([_paramTable nextState:&state key:&key value:&value])
	if (value)
	    free(value);
     [_paramTable release];
    freeParamList(self);
    [super dealloc];
}

/*
 * Archive support.
 */

- (void)encodeWithCoder:(NSCoder *)stream
{
    NXHashState state;
    const void *key;
    void *value;
    unsigned int count = [_paramTable count];

    [stream encodeValueOfObjCType:"I" at:&count];
    state = [_paramTable initState];
    while ([_paramTable nextState:&state key:&key value:&value]) {
	[stream encodeValueOfObjCType:"i" at:&key];
	[stream encodeValueOfObjCType:"{cif}" at:value];
    }

}

- (id)initWithCoder:(NSCoder *)stream
{
    unsigned int count;
    int i, ptag;
    void *param;

    [stream decodeValueOfObjCType:"I" at:&count];
    _paramTable = [[HashTable alloc] initKeyDesc:"i" valueDesc:"!"];
    for (i = 0; i < count; i++) {
	[stream decodeValueOfObjCType:"i" at:&ptag];
	param = calloc(1, sizeof(param_t));
	[stream decodeValueOfObjCType:"{cif}" at:param];
	[_paramTable insertKey:(const void *)ptag value:param];
    }
    return self;

}

/*
 * Generic parameter get/set methods.
 */

- (BOOL)boolValueForParameter:(NXSoundParameterTag)ptag
{
    param_t *param;

    if (![self isParameterPresent:ptag])
	return NO;
    param = getParam(_paramTable, ptag);
    return param->boolVal;
}

- (int)intValueForParameter:(NXSoundParameterTag)ptag
{
    param_t *param;

    if (![self isParameterPresent:ptag])
	return 0;
    param = getParam(_paramTable, ptag);
    return param->intVal;
}

- (float)floatValueForParameter:(NXSoundParameterTag)ptag
{
    param_t *param;

    if (![self isParameterPresent:ptag])
	return 0.0;
    param = getParam(_paramTable, ptag);
    return param->floatVal;
}
	
- (void)setParameter:(NXSoundParameterTag)ptag toBool:(BOOL)flag
{
    param_t *param = getParam(_paramTable, ptag);

    param->boolVal = flag;
    param->intVal = (int)flag;
    param->floatVal = (float)flag;
    freeParamList(self);
}

- (void)setParameter:(NXSoundParameterTag)ptag toInt:(int)value
{
    param_t *param = getParam(_paramTable, ptag);

    param->boolVal = (BOOL)value;
    param->intVal = value;
    param->floatVal = (float)value;
    freeParamList(self);
}

- (void)setParameter:(NXSoundParameterTag)ptag toFloat:(float)value
{
    param_t *param = getParam(_paramTable, ptag);

    param->boolVal = (BOOL)value;
    param->intVal = (int)value;
    param->floatVal = value;
    freeParamList(self);
}

- (void)removeParameter:(NXSoundParameterTag)ptag
{
    [_paramTable removeKey:(const void *)ptag];
    freeParamList(self);
}

- (BOOL)isParameterPresent:(NXSoundParameterTag)ptag
{
    return [_paramTable isKey:(const void *)ptag];
}

- (void)getParameters:(const NXSoundParameterTag **)list
    count:(unsigned int *)numParameters
{
    NXHashState state;
    const void *key;
    void *value;
    int i = 0;

    /*
     * Lifetime of returned list is until object has been changed
     * (parameters have been added or deleted).
     */
    *numParameters = [_paramTable count];
    if (_paramList || (*numParameters == 0)) {
	*list = _paramList;
	return;
    }

    _paramList = (NXSoundParameterTag *)malloc((*numParameters) *
					       sizeof(NXSoundParameterTag));
    state = [_paramTable initState];
    while ([_paramTable nextState:&state key:&key value:&value])
	_paramList[i++] = (NXSoundParameterTag)key;
    *list = _paramList;
}

- (void)getValues:(const NXSoundParameterTag **)list
  count:(unsigned int *)numValues forParameter:(NXSoundParameterTag)ptag
{
    static const NXSoundParameterTag analogInputSource[] = {
	NX_SoundDeviceAnalogInputSource_Microphone,
	NX_SoundDeviceAnalogInputSource_LineIn
	};
    static const NXSoundParameterTag dataEncoding[] = {
	NX_SoundStreamDataEncoding_Linear16,
	NX_SoundStreamDataEncoding_Linear8,
	NX_SoundStreamDataEncoding_Mulaw8,
	NX_SoundStreamDataEncoding_Alaw8,
	NX_SoundStreamDataEncoding_AES
	};
    static const NXSoundParameterTag streamSource[] = {
	NX_SoundStreamSource_Analog,
	NX_SoundStreamSource_AES
	};
    static const NXSoundParameterTag streamSink[] = {
	NX_SoundStreamSink_Analog,
	NX_SoundStreamSink_AES
	};

    switch (ptag) {
      case NX_SoundDeviceAnalogInputSource:
	*list = analogInputSource;
	*numValues = sizeof(analogInputSource)/sizeof(NXSoundParameterTag);
	break;
      case NX_SoundStreamDataEncoding:
	*list = dataEncoding;
	*numValues = sizeof(dataEncoding)/sizeof(NXSoundParameterTag);
	break;
      case NX_SoundStreamSource:
	*list = streamSource;
	*numValues = sizeof(streamSource)/sizeof(NXSoundParameterTag);
	break;
      case NX_SoundStreamSink:
	*list = streamSink;
	*numValues = sizeof(streamSink)/sizeof(NXSoundParameterTag);
	break;
      default:
	*list = 0;
	*numValues = 0;
	break;
    }
    return;
}

@end

/*

Created by Mike Minnick 01/15/93.

Modification History:

 10/7/93 aozer	Changed to use NSString.

*/
