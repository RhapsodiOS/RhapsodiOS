/*
	NSDragging.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <Foundation/NSGeometry.h>

@class NSImage;
@class NSPasteboard;
@class NSWindow;

enum {
    NSDragOperationNone			= 0, /* no operation == rejection */
    NSDragOperationCopy			= 1,
    NSDragOperationLink			= 2,
    NSDragOperationGeneric		= 4,
    NSDragOperationPrivate		= 8, /* system leaves the cursor alone until exit */
    NSDragOperationAll			= 15
};


/* protocol for the sender of messages to a drag destination.  The view or
   window that registered dragging types sends these messages as dragging is
   happening to find out details about that session of dragging.
 */
@protocol NSDraggingInfo
- (NSWindow *)draggingDestinationWindow;
- (unsigned int)draggingSourceOperationMask;
- (NSPoint)draggingLocation;
- (NSPoint)draggedImageLocation;
- (NSImage *)draggedImage;
- (NSPasteboard *)draggingPasteboard;
- (id)draggingSource;
- (int)draggingSequenceNumber;
- (void)slideDraggedImageTo:(NSPoint)screenPoint;
@end


/* Methods implemented by an object that receives dragged images.  The
   destination view or window is sent these messages during dragging if it
   responds to them.
 */
@interface NSObject(NSDraggingDestination)
- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender;
- (unsigned int)draggingUpdated:(id <NSDraggingInfo>)sender;
- (void)draggingExited:(id <NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;
@end


/* Methods implemented by an object that initiates a drag session.  The
   source app is sent these messages during dragging.  The first must be
   implemented, the others are sent if the source responds to them.
 */
@interface NSObject(NSDraggingSource)
- (unsigned int)draggingSourceOperationMaskForLocal:(BOOL)flag;
- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)screenPoint;
- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint deposited:(BOOL)flag;
- (BOOL)ignoreModifierKeysWhileDragging;
@end
