/*
	NSSplitView.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSView.h>
#import <AppKit/AppKitDefines.h>

@interface NSSplitView : NSView {
    /*All instance variables are private*/
    id	_delegate;
}

- (void)setDelegate:(id)anObject;
- (id)delegate;
- (void)adjustSubviews;
- (float)dividerThickness;
- (void)drawDividerInRect:(NSRect)aRect;

- (void)setVertical:(BOOL)flag;	/* Vertical splitview has a vertical split bar */ 
- (BOOL)isVertical;

@end

@interface NSObject(NSSplitViewDelegate)
- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize;
- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedCoord ofSubviewAt:(int)offset;
- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedCoord ofSubviewAt:(int)offset;
- (void)splitViewWillResizeSubviews:(NSNotification *)notification;
- (void)splitViewDidResizeSubviews:(NSNotification *)notification;
- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview;
- (float)splitView:(NSSplitView *)splitView constrainSplitPosition:(float)proposedPosition ofSubviewAt:(int)index;
@end

/* Notifications */
APPKIT_EXTERN NSString *NSSplitViewDidResizeSubviewsNotification;
APPKIT_EXTERN NSString *NSSplitViewWillResizeSubviewsNotification;
