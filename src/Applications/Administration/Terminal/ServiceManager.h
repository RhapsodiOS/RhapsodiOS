#ifndef TERMINAL_SERVICE_MANAGER_H
#define TERMINAL_SERVICE_MANAGER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

#include "TerminalServices.h"

@interface ServiceManager : NSObject
{
    id shellOpts;
    id selTypes;
    id selOpts;
    id polymorphicOpts;
    id execTypePopUp;
    id addButton;
    id changeButton;
    id removeButton;
    id saveButton;
    id svcMatrix;
    id commandForm;
    id keyForm;
    id svcScrollView;
    id window;
    id saveAccessory;
    id saveMatrix;
    id saveScrollView;
    char dirty;
    char currentExecType;
    char _padding0[2];
    NSRect origFrame;
    unsigned int currentSequenceNumber;
    char neverLoaded;
    char _padding1[3];
    int lastSelected;
    unsigned char currentFlags;
    char ignoreNextMatrixAction;
    char _padding2[2];
    void *savingFile;
    void *savingSet;
    ServiceCache *savingCache;
}

- (int)cellCountFor:(id)table;
- (id)init;
- (void)go:(char)forceReload;
- (void)renewForServiceSet:(TerminalServiceSet *)serviceSet;
- (char)isDirty;
- (void)setDirty:(char)value;
- (void)updateForCurrentDirtiness;
- (void)editSelectedServiceName:(id)sender;
- (void)serviceSelected:(id)sender;
- (void)setControlsFromService:(TerminalServiceRecord *)service;
- (void)setupExecBoxForWindowType:(unsigned char)windowType
    routingFlags:(unsigned char)routingFlags andSetPopUp:(char)setPopUp;
- (id)setControlsIn:(id)controls fromFlags:(unsigned char)flags;
- (void)polymorphicOptsChanged:(id)sender;
- (void)execTypeChanged:(id)sender;
- (void)makeDirty:(id)sender;
- (void)add:(id)sender;
- (void)freeService:(TerminalServiceRecord *)service;
- (int)whyAreSettingsNotAcceptable;
- (char)nameUnique:(id)name;
- (void)fillServiceFromWindow:(TerminalServiceRecord *)service;
- (void)setFlags:(unsigned char *)flags fromControlsIn:(id)controls;
- (char)setFlagsFromCell:(id)cell;
- (void)change:(id)sender;
- (void)warnAboutStrangeness:(TerminalServiceRecord *)service;
- (char)checkSettings;
- (char)windowShouldClose:(id)sender;
- (void)remove:(id)sender;
- (void)windowDidResize:(id)sender;
- (NSSize)windowWillResize:(id)window toSize:(NSSize)size;
- (void)controlTextDidChange:(id)sender;
- (char)control:(id)control textShouldEndEditing:(id)fieldEditor;
- (void)controlTextDidEndEditing:(id)sender;
- (void)save:(id)sender;
- (void)saveService:(id)sender;

@end

_Static_assert(sizeof(ServiceManager) == 120,
    "Terminal ServiceManager PPC/i386 instance size");

typedef struct {
    @defs(ServiceManager);
} ServiceManagerLayout;

_Static_assert(__builtin_offsetof(ServiceManagerLayout, shellOpts) == 4,
    "Terminal ServiceManager first outlet offset");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, dirty) == 72,
    "Terminal ServiceManager dirty flag offset");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, origFrame) == 76,
    "Terminal ServiceManager original-frame offset");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, savingCache) == 116,
    "Terminal ServiceManager cache offset");

#endif
