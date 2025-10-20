/*
	NSOpenPanel.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSSavePanel.h>

/* Tags of views in the OpenPanel */

@interface NSOpenPanel : NSSavePanel
{
    /*All instance variables are private*/
    NSArray	       *_filterTypes;
    void		*_reserved_op;
}

+ (NSOpenPanel *)openPanel;

- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)allowsMultipleSelection;
- (void)setCanChooseDirectories:(BOOL)flag;
- (BOOL)canChooseDirectories;
- (void)setCanChooseFiles:(BOOL)flag;
- (BOOL)canChooseFiles;
- (NSArray *)filenames;
- (NSArray *)URLs;
- (int)runModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes;
- (int)runModalForTypes:(NSArray *)fileTypes;

@end
