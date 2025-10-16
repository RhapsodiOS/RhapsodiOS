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
	Sound.h
	Sound Kit, Release 2.0
	Copyright (c) 1988, 1989, 1990, NeXT, Inc.  All rights reserved. 
*/

#import <Foundation/Foundation.h>
#import <SoundKit/sound.h>
#import <streams/streams.h>

@class NSPasteboard;

/* Define this for compatibility */
#define NXSoundPboard NXSoundPboardType

extern NSString *NXSoundPboardType;
/*
 * This is the sound pasteboard type.
 */

@interface Sound : NSObject
/*
 * The Sound object encapsulates a SNDSoundStruct, which represents a sound.
 * It supports reading and writing to a soundfile, playback of sound,
 * recording of sampled sound, conversion among various sampled formats, 
 * basic editing of the sound, and name and storage management for sounds.
 */
{
    SNDSoundStruct *soundStruct; /* the sound data structure */
    int soundStructSize;	 /* the length of the structure in bytes */
    int priority;		 /* the priority of the sound */
    id delegate;		 /* the target of notification messages */
    int status;			 /* what the object is currently doing */
    NSString *name;		 /* The name of the sound */
    SNDSoundStruct *_scratchSound;
    int _scratchSize;
}

/*
 * Status codes
 */
typedef enum {
    NX_SoundStopped = 0,
    NX_SoundRecording,
    NX_SoundPlaying,
    NX_SoundInitialized,
    NX_SoundRecordingPaused,
    NX_SoundPlayingPaused,
    NX_SoundRecordingPending,
    NX_SoundPlayingPending,
    NX_SoundFreed = -1,
} NXSoundStatus;

/*
 * OBSOLETE status codes - use the NX ones above.
 */
typedef enum {
    SK_STATUS_STOPPED = NX_SoundStopped,
    SK_STATUS_RECORDING = NX_SoundRecording,
    SK_STATUS_PLAYING = NX_SoundPlaying,
    SK_STATUS_INITIALIZED = NX_SoundInitialized,
    SK_STATUS_RECORDING_PAUSED = NX_SoundRecordingPaused,
    SK_STATUS_PLAYING_PAUSED = NX_SoundPlayingPaused,
    SK_STATUS_RECORDING_PENDING = NX_SoundRecordingPending,
    SK_STATUS_PLAYING_PENDING = NX_SoundPlayingPending,
    SK_STATUS_FREED = NX_SoundFreed,
} SKStatus;

/*
 * Macho segment name where sounds may be.
 */
#define NX_SOUND_SEGMENT_NAME @"__SND"

/*
 * OBSOLETE macho segment name - use the NX one above.
 */
#define SK_SEGMENT_NAME @"__SND"


/*
 * --------------- Factory Methods
 */

+ (id)findSoundFor:(NSString *)aName;

+ (Sound *)addName:(NSString *)name sound:(id)aSound;
+ (Sound *)addName:(NSString *)name fromSoundfile:(NSString *)filename;
+ (Sound *)addName:(NSString *)name fromSection:(NSString *)sectionName;
+ (Sound *)addName:(NSString *)aName fromBundle:(NSBundle *)aBundle;

+ (Sound *)removeSoundForName:(NSString *)name;

+ getVolume:(float *)left :(float *)right;
+ setVolume:(float)left :(float)right;
+ (BOOL)isMuted;
+ setMute:(BOOL)aFlag;

- (id)initFromSoundfile:(NSString *)filename;
- (id)initFromSection:(NSString *)sectionName;
- (id)initFromPasteboard:(NSPasteboard *)thePboard;

- (void)dealloc;
- (BOOL)readSoundFromStream:(NXStream *)stream;
- (void)writeSoundToStream:(NXStream *)stream;
- (void)encodeWithCoder:(NSCoder *)stream;
- (id)initWithCoder:(NSCoder *)stream;
- (id)awakeAfterUsingCoder:(NSCoder *)coder;
- (NSString *)name;
- (BOOL)setName:(NSString *)theName;
- (id)delegate;
- (void)setDelegate:(id)anObject;
- (double)samplingRate;
- (int)sampleCount;
- (double)duration;
- (int)channelCount;
- (char *)info;
- (int)infoSize;
- (void)play:sender;
- (int)play;
- (void)record:sender;
- (int)record;
- (int)samplesProcessed;
- (int)status;
- (int)waitUntilStopped;
- (void)stop:(id)sender;
- (int)stop;
- (void)pause:sender;
- (int)pause;
- (void)resume:sender;
- (int)resume;
- (int)readSoundfile:(NSString *)filename;
- (int)writeSoundfile:(NSString *)filename;
- (int)writeToPasteboard:(NSPasteboard *)thePboard;
- (BOOL)isEmpty;
- (BOOL)isEditable;
- (BOOL)compatibleWith:aSound;
- (BOOL)isPlayable;
- (int)convertToFormat:(int)aFormat
	   samplingRate:(double)aRate
	   channelCount:(int)aChannelCount;
- (int)convertToFormat:(int)aFormat;
- (int)deleteSamples;
- (int)deleteSamplesAt:(int)startSample count:(int)sampleCount;
- (int)insertSamples:aSound at:(int)startSample;
- (int)copySound:aSound;
- (int)copySamples:aSound at:(int)startSample count:(int)sampleCount;
- (int)compactSamples;
- (BOOL)needsCompacting;
- (unsigned char *)data;
- (int)dataSize;
- (int)dataFormat;
- (int)setDataSize:(int)newDataSize
     dataFormat:(int)newDataFormat
     samplingRate:(double)newSamplingRate
     channelCount:(int)newChannelCount
     infoSize:(int)newInfoSize;
- (SNDSoundStruct *)soundStruct;
- (int)soundStructSize;
- (void)setSoundStruct:(SNDSoundStruct *)aStruct soundStructSize:(int)aSize;
- (SNDSoundStruct *)soundStructBeingProcessed;
- (int)processingError;
- soundBeingProcessed;
- (void)tellDelegate:(SEL)theMessage;

@end

@interface SoundDelegate : NSObject
- (void)willRecord:sender;
- (void)didRecord:sender;
- (void)willPlay:sender;
- (void)didPlay:sender;
- (void)hadError:sender;
@end

