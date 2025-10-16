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
#endif SHLIB

/*
 *	Sound.m
 *	Written by Lee Boynton
 *	Copyright 1988 NeXT, Inc.
 *
 */
#import <mach/mach.h>
#import <objc/zone.h>
#import <string.h>
#import <stdlib.h>
#import <pwd.h>
#import <sys/types.h>
#import <sys/file.h>
#import <sys/param.h>
#import <kern/time_stamp.h>
#import <objc/List.h>
#import <sound.h>
#import "obsolete.h"
#import "NXSoundThreshold_Private.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSPasteboard.h>
#import <defaults/defaults.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSDPSContextPrivate.h>

#import "Sound.h"

extern char *getsectdata();

#define HOME_SOUND_DIR @"/Library/Sounds/"
#define LOCAL_SOUND_DIR @"/Local/Library/Sounds/"
#define NETWORK_SOUND_DIR @"/Network/Library/Sounds/"
#define SYSTEM_SOUND_DIR @"/System/Library/Sounds/"

@implementation Sound

#define DEFAULT_DURATION_IN_MINUTES (10.0)
#define BIG_BUF_SIZE ((int)(SND_RATE_CODEC*60.0*DEFAULT_DURATION_IN_MINUTES))
#define DEFAULT_INFO_SIZE 128
#define NULL_SOUND ((SNDSoundStruct*)0)

/*
 * Support to provide asynchronous messages to the delegate
 */

typedef struct _sound_message_t {
	msg_header_t	header;
	msg_type_t	type;
	int		theSound;
} sound_message_t;

#define SOUND_MSG_P_BEGIN 0
#define SOUND_MSG_P_END 1
#define SOUND_MSG_R_BEGIN 2
#define SOUND_MSG_R_END 3
#define SOUND_MSG_ERR 4

static port_t listenPort=0;
static int lastError=0;

 static void trimTail(SNDSoundStruct *s, int *nbytes);
 static int calcSoundSize(SNDSoundStruct *s);
 static void clearScratchSound(Sound *self);

static void messageReceived(Sound *self, int ident)
{
    int i, err;
    if (!self) {
#ifdef DEBUG
	printf("Message received for null sound\n");
#endif
	return;
    }
    if (self->status == SK_STATUS_FREED) {
	return;
    } else switch (ident) {
	case SOUND_MSG_R_BEGIN:
	    [self tellDelegate:@selector(willRecord:)];
	    break;
	case SOUND_MSG_R_END:
	    if (self->status != SK_STATUS_RECORDING_PAUSED) {
		int last_status = self->status;
		if (self->soundStruct) {
		    SNDInsertSamples(self->soundStruct,self->_scratchSound,
						          [self sampleCount]);
		    clearScratchSound(self);
		} else {
		    i = self->_scratchSize;
		    trimTail(self->_scratchSound,&i);
		    self->soundStruct = self->_scratchSound;
		    self->soundStructSize = i +
                        self->soundStruct->dataLocation;
		}
		self->_scratchSound = 0;
		self->_scratchSize = 0;
		self->status = SK_STATUS_STOPPED;
		[self tellDelegate:@selector(didRecord:)];
		if (last_status == SK_STATUS_PLAYING_PENDING)
		    [self play:self];
	    } else if (self->soundStruct) {
		SNDInsertSamples(self->soundStruct,self->_scratchSound,
						          [self sampleCount]);
		self->_scratchSound->dataSize = self->_scratchSize;
		self->soundStructSize = calcSoundSize(self->soundStruct);
	    } else {
		err = SNDCopySound(&self->soundStruct,self->_scratchSound);
		self->soundStructSize = calcSoundSize(self->_scratchSound);
	    }
	    break;
	case SOUND_MSG_P_BEGIN:
	    [self tellDelegate:@selector(willPlay:)];
	    break;
	case SOUND_MSG_P_END:
	    if (self->status != SK_STATUS_PLAYING_PAUSED) { 
		int last_status = self->status;
		self->status = SK_STATUS_STOPPED;
		[self tellDelegate:@selector(didPlay:)];
		if (last_status == SK_STATUS_RECORDING_PENDING)
		    [self record:self];
	    }
	    break;
	case SOUND_MSG_ERR:
	    [self tellDelegate:@selector(hadError:)];
	    self->status = SK_STATUS_STOPPED;
	    break;
	default:
	    break;
    }
}

static void receive_message(msg_header_t *msg, void *data)
{
    Sound *self = (Sound *)(((sound_message_t *)msg)->theSound);
    messageReceived(self,msg->msg_id);
}

static void init_port(id self)
{
    if (!listenPort) {
	port_allocate(task_self(), &listenPort);
	_NSSKAddPort((port_t)listenPort, (_NSSKPortProc)&receive_message,
    			(int)sizeof(sound_message_t), (void *)0, 
			(int)NSModalResponseThreshold);
    }
}

extern int kern_timestamp();

static int usec_timestamp()
// wraps around at 40 seconds
{
    struct tsval foo;
    kern_timestamp(&foo);
    return foo.low_val;
}

static int post_message(int object_id, int msg_id)
{
    sound_message_t the_msg;
    static sound_message_t the_msg_template = {
	{
	    /* no name */		0,
	    /* msg_simple */		TRUE,
	    /* msg_size */		sizeof(sound_message_t),
	    /* msg_type */		MSG_TYPE_NORMAL,
	    /* msg_remote_port */	PORT_NULL,
	    /* msg_reply_port */	PORT_NULL,
	    /* msg_id */		0
	},
	{
	    /* msg_type_name = */	MSG_TYPE_INTEGER_32,
	    /* msg_type_size = */	32,
	    /* msg_type_number = */	1,
	    /* msg_type_inline = */	TRUE,
	    /* msg_type_longform = */	FALSE,
	    /* msg_type_deallocate = */	FALSE,
	}
    };
    the_msg = the_msg_template;
    the_msg.header.msg_remote_port = listenPort;
    the_msg.header.msg_id = msg_id;
    the_msg.theSound = object_id;
    return msg_send((msg_header_t *)&the_msg,MSG_OPTION_NONE,0);
}

static int play_begin_time = 0;

static double makeRateDouble(int val)
{
    double temp =(double)val;
    if (temp > 8012.0 && temp < 8013.0) temp = SND_RATE_CODEC;
    return temp;
}

 static int calcFormat(SNDSoundStruct *s);

static int calc_play_begin_time(SNDSoundStruct *s)
{
    int             temp = usec_timestamp(), lag;

    int             format = calcFormat(s);

    if ((format == SND_FORMAT_LINEAR_16 || format == SND_FORMAT_EMPHASIZED)
	&& s->channelCount == 2 &&
	(s->samplingRate == SND_RATE_LOW || s->samplingRate == SND_RATE_HIGH)) {
	lag = (s->samplingRate == SND_RATE_LOW) ? 120000 : 60000;
    } else {
    /* goes through the dsp */
	lag = 120000;
    /* this number is good for mulaw codec sounds */
    }
    return temp - lag;
}
 
static int play_begin(SNDSoundStruct *s, int tag, int err)
{
    play_begin_time = calc_play_begin_time(s);
    if (err) {
	lastError = err;
	post_message(tag, SOUND_MSG_ERR);
    } else
	post_message(tag, SOUND_MSG_P_BEGIN);
    return 0;
}

static int play_resume(SNDSoundStruct *s, int tag, int err)
{
    if (err) {
	lastError = err;
	post_message(tag, SOUND_MSG_ERR);
    } else
	play_begin_time = calc_play_begin_time(s);
    return 0;
}

static int play_end(SNDSoundStruct *s, int tag, int err)
{
    if (err && err != SND_ERR_ABORTED) {
	lastError = err;
	post_message(tag, SOUND_MSG_ERR);
    } else
	post_message(tag, SOUND_MSG_P_END);
    return 0;
}

static int record_begin(SNDSoundStruct *s, int tag, int err)
{
    if (err) {
	lastError = err;
	post_message(tag, SOUND_MSG_ERR);
    } else
	post_message(tag, SOUND_MSG_R_BEGIN);
    return 0;
}

static int record_end(SNDSoundStruct *s, int tag, int err)
{
    if (err && err != SND_ERR_ABORTED) {
	lastError = err;
	post_message(tag, SOUND_MSG_ERR);
    } else
	post_message(tag, SOUND_MSG_R_END);
    return 0;
}

static id findSoundfile(id factory, NSString * name)
{
    Sound *newSound = nil;
    NSString *filename;
    NSString *p;

    if (p = NSHomeDirectory()) {
	filename = [NSString stringWithFormat:@"%@%@%@.snd", p, HOME_SOUND_DIR, name];
	newSound = [[factory alloc] initFromSoundfile:filename];
	if (newSound) {
	    [newSound setName:name];
	    return newSound;
	}
    }

    filename = [NSString stringWithFormat:@"%@%@.snd", LOCAL_SOUND_DIR, name];
    newSound = [[factory alloc] initFromSoundfile:filename];
    if (newSound) {
	[newSound setName:name];
	return newSound;
    }

    filename = [NSString stringWithFormat:@"%@%@.snd", NETWORK_SOUND_DIR, name];
    newSound = [[factory alloc] initFromSoundfile:filename];
    if (newSound) {
      [newSound setName:name];
              return newSound;
    }
    
    filename = [NSString stringWithFormat:@"%@%@.snd", SYSTEM_SOUND_DIR, name];
    newSound = [[factory alloc] initFromSoundfile:filename];
    if (newSound)
	[newSound setName:name];
    return newSound;
}


/*
 * Support to maintain a list of named sounds.
 */
static id soundList=nil;

static int namesMatch(NSString * s1, NSString * s2)
{
    if (!s1 || !s2) return 0;
    return [s1 isEqualToString:s2] ? 1 : 0;
}

static id findNamedSound(List *aList, NSString * name)
{
    int i, max;
    Sound *aSound;

    if (aList) {
	max = [aList count];
	for (i=0; i<max; i++) {
	    aSound = [aList objectAt:i];
	    if (namesMatch([aSound name], name)) return aSound;
	}
    }
    return nil;
}

static id addNamedSound(List *aList, NSString * name, Sound *aSound)
{
    [aSound setName:name];
    if (!aList) return nil;
    [aList addObjectIfAbsent:aSound];
    return aSound;
}

static id removeNamedSound(List *aList, NSString * name)
{
    id aSound;
    if (!aList) return nil;
    if (aSound = findNamedSound(aList,name))
	[aList removeObject:aSound];
    return aSound;
}

/*
 * Miscellaneous support functions
 */
static int calcFormat(SNDSoundStruct *s)
{
    if (s->dataFormat != SND_FORMAT_INDIRECT)
	return s->dataFormat;
    else {
	SNDSoundStruct **iBlock = (SNDSoundStruct **)s->dataLocation;
	if (*iBlock)
	    return (*iBlock)->dataFormat;
	else
	    return SND_FORMAT_UNSPECIFIED;
    }
}

static int calcHeaderSize(s)
    SNDSoundStruct *s;
{
    int size = strlen(s->info) + 1;
    if (size < 4) size = 4;
    else size = (size + 3) & 3;
    return(sizeof(SNDSoundStruct) - 4 + size);
}

static int calcSoundSize(SNDSoundStruct *s)
{
    if (!s)
	return 0;
    else if (s->dataFormat != SND_FORMAT_INDIRECT)
	return s->dataLocation + s->dataSize;
    else
	return calcHeaderSize(s);
}

static int roundUpToPage(int size)
{
    int temp = size % vm_page_size;
    if (temp)
	return size + vm_page_size - temp;
    else
	return size;
}

static void trimTail(SNDSoundStruct *s, int *nbytes)
{
    int extraPtr = (int)s + s->dataLocation + s->dataSize;
    int extraBytes, extraTailPtr = (int)s+(*nbytes) + s->dataLocation;
    extraPtr = roundUpToPage(extraPtr);
    extraBytes = extraTailPtr - extraPtr;
    if (extraBytes > 0)
	vm_deallocate(task_self(),(pointer_t)extraPtr,extraBytes);
    *nbytes = s->dataSize;
}


/**************************
 *
 * Methods
 *
 */

+ (BOOL)isSound:(NSString *)aName
{
    return findNamedSound(soundList,aName)? YES : NO;
}

+ (id)findSoundFor:(NSString *)aName
{
    id aSound = findNamedSound(soundList,aName);
    if (aSound) return aSound;
    aSound = [[self alloc] initFromSection:aName];
    if (aSound) return aSound;
    aSound = findSoundfile(self, aName);
    return aSound;
}

static void allocSoundList()
{
    NXZone *zone = (NXZone *)[(NSApplication *)NSApp zone];
    if (!zone) zone = NXDefaultMallocZone();
    soundList = [[List allocFromZone:zone] init];
}

+ (Sound *)addName:(NSString *)aName sound:(id)aSound
{
    if (!aSound || !aName)
	return nil;
    if (!soundList) allocSoundList();
    else if (findNamedSound(soundList,aName))
	return nil;
    addNamedSound(soundList,aName,(Sound *)aSound);
    return aSound;
}

+ (Sound *)addName:(NSString *)aName fromSoundfile:(NSString *)filename
{
    Sound *aSound;
    if (!aName || !filename) return nil;
    if (!soundList) allocSoundList();
    else if (findNamedSound(soundList,aName))
	return nil;
    aSound = [[Sound alloc] initFromSoundfile:filename];
    if (!aSound)
	return nil;
    addNamedSound(soundList,aName,aSound);
    return aSound;
}

+ (Sound *)addName:(NSString *)aName fromSection:(NSString *)sectionName
{
    Sound *aSound;
    if (!aName || !sectionName) return nil;
    if (!soundList) allocSoundList();
    else if (findNamedSound(soundList,aName))
	return nil;
    aSound = [[Sound alloc] initFromSection:sectionName];
    if (!aSound)
	return nil;
    addNamedSound(soundList,aName,aSound);
    return aSound;
}

+ (Sound *)addName:(NSString *)aName fromMachO:(NSString *)sectionName
{
    return [self addName:aName fromSection:sectionName];
}

+ (Sound *)addName:(NSString *)aName fromBundle:(NSBundle *)aBundle
{
    NSString *path;
    if (path = [[NSBundle mainBundle] pathForResource:aName ofType:@"snd"]) {
	return [self addName:aName fromSoundfile:path];
    } else {
	return nil;
    }
}


+ (Sound *)removeSoundForName:(NSString *)aName
{
    if (!aName) return nil;
    return removeNamedSound(soundList, aName);
}

/************************** obsolete new methods **************************/

+ new
{
    return [[self alloc] init];
}

+ newFromSoundfile:(NSString *)filename
{
    return [[self alloc] initFromSoundfile:filename];
}

- (id)initFromSoundfile:(NSString *)filename
{
    SNDSoundStruct *theStruct;

    if (filename && !SNDReadSoundfile((char *)[filename cString],&theStruct)) {
	[super init];
	soundStruct = theStruct;
	soundStructSize = theStruct->dataLocation + theStruct->dataSize;
	_scratchSound = 0;
	return self;
    } else {
	 [self release];
	return nil;
    }
}

+ newFromMachO:(NSString *)sectionName
{
    return [[self alloc] initFromSection:sectionName];
}

/**************************** init methods ***************************/

- (id)initFromSection:(NSString *)sectionName
{
    SNDSoundStruct *s1, *s2;
    int size, err;
    s1 = (SNDSoundStruct *)getsectdata("__SND", [sectionName cString], &size);
    if (!s1) {
	NSString *path;
	if (!(path = [[NSBundle mainBundle] pathForResource:sectionName ofType:@"snd"])) {
	    path = sectionName;
	}
	if (SND_ERR_NONE != SNDReadSoundfile((char *)[path cString], &s2)) {
	     [self release];
	    return nil;
	}
    } else {
        err = SNDCopySound(&s2,s1);
        if (err) {
	     [self release];
	    return nil;
	}
    }
    [super init];
    soundStruct = s2;
    soundStructSize = size;
    _scratchSound = 0;
    return self;
}

- initFromMachO:(NSString *)sectionName
{
    return [self initFromSection:sectionName];
}

- initFromPasteboard
{
    return [self initFromPasteboard:[NSPasteboard generalPasteboard]];
}

// OBSOLETE API
+ newFromPasteboard
{
    return [[self alloc] initFromPasteboard];
}

- (id)initFromPasteboard:(NSPasteboard *)thePboard
{
    if (!thePboard) {
	 [self release];
	return nil;
    }

    if ([[thePboard types] containsObject:NXSoundPboardType]) {
	NSData *data;
	int dataLength;
	data = [thePboard dataForType:NXSoundPboardType];

	dataLength = [data length];
	if (data && dataLength) {
	    [super init];
	    soundStruct = (SNDSoundStruct *)[data bytes];
	    soundStructSize = dataLength;
	    _scratchSound = 0;
	    return self;
	}
    }
    [self release];
    return nil;
}

/************************ Sound device parameters ********************/

+ getVolume:(float *)left :(float *)right
{
    int rawLeft, rawRight;
    int err = SNDGetVolume(&rawLeft,&rawRight);
    if (!err) {
	*left = (float)rawLeft / 43.0;
	*right = (float)rawRight / 43.0;
	return self;
    }
    return nil;
}

+ setVolume:(float)left :(float)right
{
    int rawLeft = (int)(left * 43.0), rawRight = (int)(right * 43.0);
    int err = SNDSetVolume(rawLeft,rawRight);
    return err? nil : self;
}

+ (BOOL)isMuted
{
    int on;
    SNDGetMute(&on);
    return on? NO : YES;
}

+ setMute:(BOOL)aFlag
{
    int err = SNDSetMute(aFlag? 0 : 1);
    return err? nil : self;
}

static void clearScratchSound(Sound *self)
{
    if (self->_scratchSound) {
	SNDFree(self->_scratchSound);
	self->_scratchSound = 0;
	self->_scratchSize = 0;
    }
}

 static int freeSoundStruct(Sound *self)
{
    SNDSoundStruct *s = self->soundStruct;
    int             err;

    if (s && s->magic == SND_MAGIC) {
	if (s->dataFormat != SND_FORMAT_INDIRECT)
	    if (self->soundStructSize > (s->dataLocation + s->dataSize))
		s->dataSize = self->soundStructSize - s->dataLocation;
	err = SNDFree(s);
    } else
	err = SND_ERR_NOT_SOUND;
    self->soundStruct = (SNDSoundStruct *) 0;
    self->soundStructSize = 0;
    return err;
}

- (void)dealloc
{
    if (status != SK_STATUS_STOPPED) {
	status = SK_STATUS_FREED;
	return;
    }
    if (name) removeNamedSound (soundList, name);	// patch bs 8/4/89
    [name release];
    if (soundStruct) freeSoundStruct(self);
    [super dealloc];
}

- (BOOL)readSoundFromStream:(NXStream *)stream {
    SNDSoundStruct ss;
    if (soundStruct) {
      freeSoundStruct(self);
    }
    if (sizeof(SNDSoundStruct) != NXRead(stream, &ss, sizeof(SNDSoundStruct))) {
      return NO;
    }
    soundStructSize = ss.dataLocation + ss.dataSize;
    if (vm_allocate(task_self(), (pointer_t *)&soundStruct, soundStructSize,1)) {
	soundStructSize = 0;
	return NO;
    }
    bcopy((char *)&ss,(char *)soundStruct,sizeof(SNDSoundStruct));
    if (ss.dataSize != NXRead(stream, ((char *)soundStruct) + ss.dataLocation, ss.dataSize)) {
      return NO;
    }
    return YES;
}

- (void)writeSoundToStream:(NXStream *)stream {
    if (soundStructSize) {
	[self compactSamples];
	if (soundStructSize != NXWrite(stream, soundStruct, soundStructSize))
	  return /* nil */;
    }
}

- (void)encodeWithCoder:(NSCoder *)stream
{
    const char *cName = [name cString];
    [stream encodeValuesOfObjCTypes:"*i@i",&cName,&priority,&delegate,&soundStructSize];
    if (soundStructSize) {
	[self compactSamples];
	[stream encodeArrayOfObjCType:"c" count:soundStructSize at:soundStruct];
    }
}

- (id)initWithCoder:(NSCoder *)stream
{
    char *cName;
    [stream decodeValuesOfObjCTypes:"*i@i",&cName,&priority,&delegate,&soundStructSize];
    name = cName ? [[[[NSString alloc] initWithCStringNoCopy:cName length:strlen(cName) freeWhenDone:YES] autorelease] copyWithZone:[self zone]] : nil;
    if (soundStructSize) {
	if (vm_allocate(task_self(),(pointer_t *)&soundStruct,
							soundStructSize,1))
	    soundStructSize = 0;
	else
	    [stream decodeArrayOfObjCType:"c" count:soundStructSize at:soundStruct];
    }
    status = SK_STATUS_STOPPED;
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)coder
{
    if (name) {
	id existingSound = [Sound findSoundFor:name];
	if (existingSound) {
	     [self release];
	    return existingSound;
	} else {
	    [Sound addName:name sound:self];
	    return self;
	}
    } else
	return self;
}

- (NSString *)name
{
    return name;
}

- (BOOL)setName:(NSString *)theName
{
    if (theName) {
	if (findNamedSound(soundList,theName)) return NO;
    } else {
	theName = @"";
    }
    [name autorelease];
    name = [theName copyWithZone:(NSZone *)[self zone]];
    return YES;
}

- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)anObject
{
    delegate = anObject;
}

- (double)samplingRate
{
    if (soundStruct) 
		return makeRateDouble(soundStruct->samplingRate);
    else
	return 0.0;
}

- (int)sampleCount
{
    if (!soundStruct) return 0;
    return SNDSampleCount(soundStruct);
}

- (double)duration
{
    if (!soundStruct) return 0;
    return ((double)[self sampleCount]) / [self samplingRate];
}

- (int)channelCount
{
    return soundStruct ? soundStruct->channelCount : 0;
}

- (char *)info
{
    return soundStruct ? soundStruct->info : (char *)0;
}

- (int)infoSize
{
    SNDSoundStruct **iBlock, *s = soundStruct;

    /*
     * For an indirect sound, return the info size of the
     * first nested sound.
     */
    if (s && (s->dataFormat == SND_FORMAT_INDIRECT)) {
	iBlock = (SNDSoundStruct **)s->dataLocation;
        s = iBlock ? *iBlock : NULL;
    }
    return s ? (s->dataLocation - (sizeof(SNDSoundStruct)-4)) : 0;
}

- (void)play:sender
{
    int err = [self play];
    if (err) {
	lastError = err;
	messageReceived((Sound *)self,SOUND_MSG_ERR);
    }
}

- (int)play
{
    int err, preempt = 1;
    switch (status) {
	case SK_STATUS_PLAYING:
	    return SND_ERR_NONE;
	case SK_STATUS_PLAYING_PAUSED:
	    return [self resume];
	case SK_STATUS_RECORDING:
	    status = SK_STATUS_PLAYING_PENDING;
	    return [self stop];
	case SK_STATUS_RECORDING_PAUSED:
	    status = SK_STATUS_STOPPED;
	    clearScratchSound(self);
	    [self tellDelegate:@selector(didRecord:)];
	    break;
	case SK_STATUS_PLAYING_PENDING:
	    return SND_ERR_NONE;
	default:
	    break;
    }
    if (!soundStruct || [self isEmpty]) {
	post_message((int)self,SOUND_MSG_P_BEGIN);
	post_message((int)self,SOUND_MSG_P_END);
	return SND_ERR_NONE;
    }
    /*
     * This allows you to chain sounds from the didPlay:
     * delegate method.
     */
    err = SNDWait((int)self);
    if (err)
        return err;

    clearScratchSound(self);
    init_port(self);
    status = SK_STATUS_PLAYING;
    if (err = SNDStartPlaying(soundStruct,(int)self,priority,
			      preempt,play_begin,play_end))
      status = SK_STATUS_STOPPED;
    return err;
}

- (void)record:sender
{
    int err = [self record];
    if (err) {
	lastError = err;
	messageReceived((Sound *)self,SOUND_MSG_ERR);
    }
}

int getRecordingRate( int *rate );

- (int)record
{
    int             err, preempt = 0, rate = 0;

    switch (status) {
    case SK_STATUS_RECORDING:
	return SND_ERR_NONE;
    case SK_STATUS_RECORDING_PAUSED:
	return[self resume];
    case SK_STATUS_PLAYING:
	status = SK_STATUS_RECORDING_PENDING;
	return[self stop];
    case SK_STATUS_PLAYING_PAUSED:
	status = SK_STATUS_STOPPED;
	clearScratchSound(self);
	[self tellDelegate:@selector(didPlay:)];
	break;
    case SK_STATUS_RECORDING_PENDING:
	return SND_ERR_NONE;
    default:
	break;
    }
    clearScratchSound(self);
    if (status == SK_STATUS_INITIALIZED) {
	err = SNDCopySound(&_scratchSound, soundStruct);
	_scratchSize = soundStructSize - soundStruct->dataLocation;
    } else {
#ifndef ppc
	err = SNDAlloc(&_scratchSound, BIG_BUF_SIZE, SND_FORMAT_MULAW_8,
		       SND_RATE_CODEC, 1, DEFAULT_INFO_SIZE);
	_scratchSize = BIG_BUF_SIZE;
#else
        if ( err = getRecordingRate( &rate ) ) goto rec_err;
        
        err = SNDAlloc(&_scratchSound,
			(int)( rate * 2.0 * 60.0 * 3.0),
                        SND_FORMAT_MULAW_8,
                        rate,
                        2,
                        DEFAULT_INFO_SIZE);

        _scratchSize = (int)( rate * 2.0 * 60.0 * 3.0);  /* bytes = samples/sec * bytes/sample * sec/min * min */
#endif
    }

rec_err: ;
    if (soundStruct)
	freeSoundStruct(self);
    if (err) {
	_scratchSize = 0;
	_scratchSound = 0;
	return err;
    }
    init_port(self);
    status = SK_STATUS_RECORDING;
    if (err = SNDStartRecording(_scratchSound, (int)self,
				priority, preempt,
				record_begin, record_end))
	status = SK_STATUS_STOPPED;
    return err;
}

- (int)samplesProcessed
{
    int count, temp, now = usec_timestamp();
    double sec;
    switch (status) {
	case SK_STATUS_PLAYING:
	    sec = (double)(now - play_begin_time) / 1000000.0;
	    count = (int)(sec * [self samplingRate]);
	    if (_scratchSound)
		temp = SNDSampleCount(_scratchSound);
	    else
		temp = SNDSampleCount(soundStruct);
	    return (temp < count)? temp : count;
	case SK_STATUS_RECORDING:
	    return SNDSampleCount(_scratchSound);
	case SK_STATUS_PLAYING_PAUSED:
	    return _scratchSize;
	case SK_STATUS_RECORDING_PAUSED:
	    return SNDSampleCount(soundStruct);
	default:
	    return SNDSampleCount(soundStruct);
    }
}

- (int)status
{
    return status;
}

- (int)waitUntilStopped
{
    int err;
    if (status == SK_STATUS_RECORDING || status == SK_STATUS_PLAYING)
	err = SNDWait((int)self);
    else
	err = SND_ERR_NONE;
    return err;
}

- (void)stop:(id)sender
{
    [self stop];
}

- (int)stop
{
    int err;
    switch (status) {
	case SK_STATUS_RECORDING:
	case SK_STATUS_PLAYING_PENDING:
	    err = SNDStop((int)self);
	    if (err) {
		status = SK_STATUS_STOPPED;
		break;
	    }
	    break;
	case SK_STATUS_PLAYING:
	case SK_STATUS_RECORDING_PENDING:
	    err = SNDStop((int)self);
	    if (err) {
		status = SK_STATUS_STOPPED;
		clearScratchSound(self);
	    }
	    break;
	default:
	    err = SND_ERR_NONE;
	    status = SK_STATUS_STOPPED;
	    break;
    }
    return err;
}

- (void)pause:sender
{
    int err = [self pause];
    if (err) {
	lastError = err;
	messageReceived((Sound *)self,SOUND_MSG_ERR);
    }
}

- (int)pause
{
    int err, old_status = status, count;
    switch (status) {
	case SK_STATUS_RECORDING:
	    status = SK_STATUS_RECORDING_PAUSED;
	    err = SNDStop((int)self);
	    if (err) status = old_status;
	    break;
	case SK_STATUS_PLAYING:
	    count = [self samplesProcessed];
	    if (_scratchSound)
		_scratchSize += count;
	    else
		_scratchSize = count;
	    status = SK_STATUS_PLAYING_PAUSED;
	    err = SNDStop((int)self);
	    if (err) status = old_status;
	    break;
	default:
	    err = SND_ERR_NONE;
	    break;
    }
    return err;
}

- (void)resume:sender
{
    int err = [self resume];
    if (err) {
	lastError = err;
	messageReceived((Sound *)self,SOUND_MSG_ERR);
    }
}

- (int)resume
{
    int err, length, preempt = 1;
    switch (status) {
	case SK_STATUS_RECORDING_PAUSED:
	    status = SK_STATUS_RECORDING;
#ifdef DEBUG
	    if (!_scratchSound) printf("Scratchsound is bogus!\n");
#endif
	    _scratchSound->dataSize = _scratchSize;
	    if (err = SNDStartRecording(_scratchSound, (int)self, 
					    priority, preempt,
						0, record_end)) {
		status = SK_STATUS_STOPPED;
    		clearScratchSound(self);
	    }
	    break;
	case SK_STATUS_PLAYING_PAUSED:
	    if (_scratchSize <= 0) {
		clearScratchSound(self);
		status = SK_STATUS_PLAYING;
		if (err = SNDStartPlaying(soundStruct,(int)self,priority,
						 preempt,play_resume,play_end))
		    status = SK_STATUS_STOPPED;
	    } else {
		length = [self sampleCount] - _scratchSize;
#ifdef DEBUG
		printf("resume at %d, size = %d\n",_scratchSize,length);
#endif
		if (_scratchSound) SNDFree(_scratchSound);
		err = SNDCopySamples(&_scratchSound,soundStruct,
						    _scratchSize,length);
		if (err) {
		    status = SK_STATUS_STOPPED;
		    return err;
		}
		status = SK_STATUS_PLAYING;
		if (err = SNDStartPlaying(_scratchSound,(int)self,priority,
						 preempt,play_resume,play_end))
		    status = SK_STATUS_STOPPED;
	    }
	    break;
	default:
	    err = SND_ERR_NONE;
	    break;
    }
    return err;
}


- (int)readSoundfile:(NSString *)filename;
{
    SNDSoundStruct *theStruct;
    int err;

    if (status) return SND_ERR_UNKNOWN;
    if (!filename) return SND_ERR_BAD_FILENAME;
    err = SNDReadSoundfile((char *)[filename cString], &theStruct);
    if (err == SND_ERR_NONE) {
	if (soundStruct) 
	    freeSoundStruct(self);
	[self setName:nil];
	soundStruct = theStruct;
	soundStructSize = theStruct->dataLocation + theStruct->dataSize;
    }
    return err;
}

- (int)writeSoundfile:(NSString *)filename;
{
    if (!soundStruct) return SND_ERR_NOT_SOUND;
    return SNDWriteSoundfile((char *)[filename cString],soundStruct);
}

- (int)writeToPasteboard
{
    return [self writeToPasteboard:[NSPasteboard generalPasteboard]];
}

- (int)writeToPasteboard:(NSPasteboard *)thePboard
{
    int err = [self compactSamples]; //? is this efficient enough
    if (err) return err;
    [thePboard declareTypes:[[[NSArray alloc] initWithObjects:NXSoundPboardType, nil] autorelease] owner:NSApp];
    [thePboard setData:[NSData dataWithBytes:(char *)soundStruct length:soundStructSize] forType:NXSoundPboardType];
    return SND_ERR_NONE; //?
}

- (int)convertToFormat:(int)aFormat
	   samplingRate:(double)aRate
	   channelCount:(int)aChannelCount
{
    int err;
    SNDSoundStruct *oldStruct = soundStruct, *s;
    SNDSoundStruct header = {
	SND_MAGIC, sizeof(SNDSoundStruct),0,aFormat,(int)aRate,aChannelCount,0
    };
    if (!oldStruct)
      return SND_ERR_NONE;
    if (oldStruct->dataFormat == SND_FORMAT_INDIRECT) {
	s = oldStruct;
	err = SNDCompactSamples(&oldStruct,s);
	SNDFree(s);
    }
    s = &header;
    err = SNDConvertSound(oldStruct,&s);
    if (err)
	return SND_ERR_NOT_IMPLEMENTED;
    else {
	soundStruct = s;
	soundStructSize = calcSoundSize(soundStruct);
	if (oldStruct)
	    SNDFree(oldStruct);
	return SND_ERR_NONE;
    }
    return SND_ERR_NONE;
}

- (int)convertToFormat:(int)aFormat
{
    return [self convertToFormat:aFormat
	samplingRate:soundStruct->samplingRate
	channelCount:soundStruct->channelCount];
}

- (BOOL)compatibleWith:aSound
{
    SNDSoundStruct *s = [aSound soundStruct];
    if (!soundStruct || !s) return YES;
    if (calcFormat(soundStruct) == calcFormat(s) &&
    		soundStruct->samplingRate == s->samplingRate &&
			soundStruct->channelCount == s->channelCount)
	return YES;
    else
	return NO;
}

- (BOOL)isPlayable
{
    /* FIXME: remove prototype when new performsound.h released */
    extern int SNDVerifyPlayable(SNDSoundStruct *s);

    if (!soundStruct) return NO;
    return (SNDVerifyPlayable(soundStruct)==SND_ERR_NONE);
}


- (BOOL)isEmpty
{
    if (!soundStruct) return YES;
    if ([self isEditable])
	return [self sampleCount]? NO : YES;
    else
	return NO;
}


- (BOOL)isEditable
{
    if (!soundStruct)
	return YES;
    else if (soundStruct->dataFormat == SND_FORMAT_DSP_CORE)
	return NO;
    else
	return YES;
}

- (id)copy
{
    id newSound = [[[self class] alloc] init];
    [newSound copySound:self];
    return newSound;
}

- (int)copySound:aSound
{
    SNDSoundStruct *dst, *src = [aSound soundStruct];
    int err = SND_ERR_NONE;
    if (!src)
	dst = NULL_SOUND;
    else
	err = SNDCopySound(&dst,src);
    if (!err) {
	if (soundStruct)
	    freeSoundStruct(self);
	soundStruct = dst;
	soundStructSize = calcSoundSize(soundStruct);
    }
    return err;
}

- (int)copySamples:aSound at:(int)startSample count:(int)sampleCount
{
    int err;
    SNDSoundStruct *dst, *src = [aSound soundStruct];
    if (![self isEditable])
	return SND_ERR_CANNOT_EDIT;
    if (src) {
	err = SNDCopySamples(&dst,src,startSample,sampleCount);
	if (err)
	    return err;
	if (soundStruct)
	    freeSoundStruct(self);
	soundStruct = dst;
	soundStructSize = calcSoundSize(dst);
	return SND_ERR_NONE;
    } else {
	if (soundStruct)
	    freeSoundStruct(self);
	soundStruct = NULL_SOUND;
	soundStructSize = 0;
	return SND_ERR_NONE;
    }
}

- (int)deleteSamples
{
    int theCount, err;
    if (![self isEditable])
	return SND_ERR_CANNOT_EDIT;
    if (!soundStruct)
	return SND_ERR_NONE;
    theCount = SNDSampleCount(soundStruct);
    err = [self deleteSamplesAt:0 count:theCount];
    return err;
}

- (int)deleteSamplesAt:(int)startSample count:(int)sampleCount
{
    int saveFormat; //!! to fix bug in SNDDeleteSamples
    int err;
    if (![self isEditable])
	return SND_ERR_CANNOT_EDIT;
    if (!soundStruct)
	return SND_ERR_NONE;
    saveFormat = calcFormat(soundStruct);	//!!
    err = SNDDeleteSamples(soundStruct, startSample, sampleCount);
    soundStructSize = calcSoundSize(soundStruct);
    if (!soundStruct->dataSize)			//!
	soundStruct->dataFormat = saveFormat;	//!!
    return err;
}

- (int)insertSamples:aSound at:(int)startSample
{
    int err;
    SNDSoundStruct *s = [aSound soundStruct];
    if (![self isEditable])
	return SND_ERR_CANNOT_EDIT;
    if (!s || ![aSound sampleCount])
	return SND_ERR_NONE;
    if (soundStruct && [self sampleCount]) {
	if ([self compatibleWith:aSound]) {
	    err = SNDInsertSamples(soundStruct,s,startSample);
	    soundStructSize = calcSoundSize(soundStruct);
	} else {
	    SNDSoundStruct *s2, header = {
		    SND_MAGIC, sizeof(SNDSoundStruct),0,
		    calcFormat(soundStruct),
		    soundStruct->samplingRate,
		    soundStruct->channelCount, 0 };
	    s2 = &header;
	    err = SNDConvertSound(s,&s2);
	    if (!err) {
		err = SNDInsertSamples(soundStruct,s2,startSample);
		soundStructSize = calcSoundSize(soundStruct);
	    }
	}
    } else {
	if (soundStruct) SNDFree(soundStruct);
	soundStruct = NULL_SOUND;
	err = SNDCopySound(&soundStruct,s);
	soundStructSize = calcSoundSize(soundStruct);
    }
    return err;
}

- (int)compactSamples
{
    SNDSoundStruct *s;
    int err;
    if (![self isEditable])
	return SND_ERR_CANNOT_EDIT;
    if (soundStruct && [self needsCompacting]) {
	err = SNDCompactSamples(&s,soundStruct);
	if (!err) {
	    freeSoundStruct(self);
	    soundStruct = s;
	    soundStructSize = calcSoundSize(soundStruct);
	}
    } else
	err = SND_ERR_NONE;
    return err;
}

- (BOOL)needsCompacting
{
    if (soundStruct && soundStruct->dataFormat == SND_FORMAT_INDIRECT)
	return YES;
    else
	return NO;
}

- (unsigned char *)data
{
    unsigned char *foo;
    if (!soundStruct)
	foo = (unsigned char *)0;
    else if (soundStruct->dataFormat == SND_FORMAT_INDIRECT)
	foo = (unsigned char *)soundStruct->dataLocation;
    else {
	foo = (unsigned char *)soundStruct;
	foo += soundStruct->dataLocation;
    }
    return foo;
}

- (int)dataSize
{
    return soundStruct? soundStruct->dataSize : 0;
}

- (int)dataFormat
{
    return soundStruct? calcFormat(soundStruct) : 0;
}

- (int)setDataSize:(int)newDataSize
     dataFormat:(int)newDataFormat
     samplingRate:(double)newSamplingRate
     channelCount:(int)newChannelCount
     infoSize:(int)newInfoSize;
{
    SNDSoundStruct *s;
    int err;
    if (status != SK_STATUS_STOPPED && status != SK_STATUS_INITIALIZED)
	return SND_ERR_CANNOT_EDIT;
    err = SNDAlloc(&s,newDataSize,newDataFormat,(int)newSamplingRate,
    			newChannelCount, newInfoSize);
    if (!err) {
	if (soundStruct)
	    freeSoundStruct(self);
	soundStruct = s;
	soundStructSize = s->dataLocation + s->dataSize;
	status = SK_STATUS_INITIALIZED;
    }
    return err;
}


- (SNDSoundStruct *)soundStruct
{
    return soundStruct;
}

- (int)soundStructSize
{
    return soundStructSize;
}

- (void)setSoundStruct:(SNDSoundStruct *)aStruct soundStructSize:(int)aSize
{
    if (status == SK_STATUS_STOPPED || status == SK_STATUS_INITIALIZED) {
	soundStruct = aStruct;
	soundStructSize = aSize;
	status = SK_STATUS_INITIALIZED;
    }
}

- (void)tellDelegate:(SEL)theMessage
{
    if (theMessage && delegate && [delegate respondsToSelector:theMessage])
	[delegate performSelector:theMessage withObject:self];
}

- soundBeingProcessed
{
    return self;
}

- (SNDSoundStruct *)soundStructBeingProcessed
{
    switch (status) {
	case SK_STATUS_RECORDING:
	    return _scratchSound;
	case SK_STATUS_PLAYING:
	    if (_scratchSound)
		return _scratchSound;
	    else
		return soundStruct;
	default: 
	    return soundStruct;
    }
}

- (int)processingError
{
    return lastError;
}

@end

/*

Created by Lee Boynton.

Modification History:

25
--
 9/11/90 wot 	Changed newFromMachO: to look in the application's directory if
		the sound can't be found in the machO.
 9/20/90 wot	Added support for SND_FORMAT_EMPHASIZED.  Made it do the same
		things as SND_FORMAT_LINEAR_16.
 10/8/90 wot	Changed NXSoundPboard to NXSoundPboardType.

27
--
 10/11/90 aozer	Added initFromSoundfile:, initFromMachO:, and 
		initFromPasteboard. Got rid of init.

 12/11/91 mminnick Use static typing on messages to self -setName: to
                   prevent compiler warnings with NXImage -(BOOL)setName:.

 01/07/92 jos	Added new methods for 3.0 (all driven by BugTracker):
 	- duration;
	- isPlayable;
        - initFromPasteboard:pasteboard;
        - (int)writeToPasteboard:pasteboard;
        - readSoundFromStream:(NXStream *)aStream;
        - writeSoundToStream:(NXStream *)aStream;

 02/05/92 mtm Set status to SK_STATUS_STOPPED before calling self free
          (bug #16520).
 03/02/92 mtm Add small fix in convertToFormat for JOS.
 03/25/92 mtm Fix -infoSize method.
 04/02/92 mtm Put SNDWait() call in -(int)play.
 05/14/92 mtm Don't free active sound.
 05/14/92 mtm Fix trimTail vm leak.
 05/14/92 mtm Fix archive after record bug.
 10/7/93 aozer Changed to use NSString.

*/
