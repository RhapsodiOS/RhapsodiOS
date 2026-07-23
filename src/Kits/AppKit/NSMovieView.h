/*
        NSMovieView.h
        Copyright 1998, Apple Computer, Inc. All rights reserved.
*/

#import <AppKit/NSView.h>

typedef enum {
    NSQTMovieNormalPlayback,
    NSQTMovieLoopingPlayback,
    NSQTMovieLoopingBackAndForthPlayback,
} NSQTMovieLoopMode;

typedef struct __MVFlags {
    unsigned int        editable:1;
    NSQTMovieLoopMode   loopMode:3;
    unsigned int        playsEveryFrame:1;
    unsigned int        playsSelectionOnly:1;
    unsigned int        controllerVisible:1;
    unsigned int        reserved:25;
} _MVFlags;

@interface NSMovieView : NSView
{
    @protected
    id            _fQTMLMovieView;	// not archived
    NSString*     _fMoviePath;
    float         _fRate;
    float         _fVolume;
    _MVFlags      _fFlags;

    unsigned long _reserved1;
    unsigned long _reserved2;
    unsigned long _reserved3;
}

- (BOOL) loadMovieFromURL:(NSURL*)url;
- (BOOL) loadMovieFromFile:(NSString*)path;

    // playing

- (void)start:(id)sender;
- (void)stop:(id)sender;
- (BOOL)isPlaying;

- (void)gotoPosterFrame:(id)sender;
- (void)gotoBeginning:(id)sender;
- (void)gotoEnd:(id)sender;
- (void)stepForward:(id)sender;
- (void)stepBack:(id)sender;

- (void)setRate:(float)rate;
- (float)rate;

    // sound

- (void)setVolume:(float)volume;
- (float)volume;
- (void)setMuted:(BOOL)mute;
- (BOOL)isMuted;

    // play modes

- (void)setLoopMode:(NSQTMovieLoopMode)mode;
- (NSQTMovieLoopMode)loopMode;
- (void)setPlaysSelectionOnly:(BOOL)flag;
- (BOOL)playsSelectionOnly;
- (void)setPlaysEveryFrame:(BOOL)flag;
- (BOOL)playsEveryFrame;

    // controller

- (void)showController:(BOOL)show adjustingSize:(BOOL)adjustSize;
- (BOOL)isControllerVisible;

    // size

- (void)resizeWithMagnification:(float)magnification;
- (NSSize)sizeForMagnification:(float)magnification;

    // editing

- (void)setEditable:(BOOL)editable;
- (BOOL)isEditable;

- (void)cut:(id)sender;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)clear:(id)sender;
- (void)undo:(id)sender;
- (void)selectAll:(id)sender;

@end
