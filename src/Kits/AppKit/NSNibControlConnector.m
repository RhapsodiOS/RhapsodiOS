/*	NSNibControlConnector.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSNibControlConnector.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>

static BOOL NSNibControlConnectorUsesMappedActions;

static NSString *NSNibControlConnectorCompatibleActionName(NSString *name)
{
    if (name == nil || [name isEqualToString:@""])
        return nil;

    if ([name hasPrefix:@"alignSel"]) {
        if ([name isEqualToString:@"alignSelLeft:"])
            return @"alignLeft:";
        if ([name isEqualToString:@"alignSelRight:"])
            return @"alignRight:";
        if ([name isEqualToString:@"alignSelCenter:"])
            return @"alignCenter:";
    } else {
        if ([name isEqualToString:@"printPSCode:"] ||
            [name isEqualToString:@"smartPrintPSCode:"])
            return @"print:";
        if ([name isEqualToString:@"faxPSCode:"] ||
            [name isEqualToString:@"smartFaxPSCode:"])
            return @"fax:";
        if ([name isEqualToString:@"showHelpPanel:"])
            return @"showHelp:";
        if ([name isEqualToString:@"scrollUpOrDown:"])
            NSLog(@"The action method `%@' is invalid; please remove it from your .nib file", name);
    }

    return nil;
}

static SEL NSNibControlConnectorActionSelector(NSString *actionName)
{
    const char *name = [actionName UTF8String];

    if (NSNibControlConnectorUsesMappedActions)
        return sel_getUid(name);
    return sel_registerName(name);
}

@implementation NSNibControlConnector

+ (void)initialize
{
    if (self == [NSNibControlConnector class]) {
        [self setVersion:207];
        NSNibControlConnectorUsesMappedActions =
            [self respondsToSelector:@selector(isInInterfaceBuilder)];
    }
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    NSString *label = [self label];
    if (![label isEqualToString:@""]) {
        NSRange colonRange = [label rangeOfString:@":"];
        if (colonRange.location == NSNotFound)
            [self setLabel:[label stringByAppendingString:@":"]];
    }

    if ([coder versionForClassName:@"NSNibControlConnector"] <= 206) {
        NSString *compatibleName =
            NSNibControlConnectorCompatibleActionName([self label]);
        if (compatibleName != nil)
            [self setLabel:compatibleName];
    }

    return self;
}

- (void)establishConnection
{
    id source = [self source];
    id destination = [self destination];
    NSString *label = [self label];
    SEL action = NSNibControlConnectorActionSelector(label);

    [source setTarget:destination];

    if (destination != nil && ![destination respondsToSelector:action]) {
        if (!NSNibControlConnectorUsesMappedActions)
            NSLog(@"Could not connect the action %@ to target of class %@",
                  label, [destination description]);
    } else {
        [source setAction:action];
    }
}

@end

