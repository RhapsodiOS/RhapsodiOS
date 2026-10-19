/*	NSParagraphStyle.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSParagraphStyle.h>

static NSArray *defaultTabStops(void)
{
    static NSArray *tabStops = nil;

    if (!tabStops) {
        NSMutableArray *stops = [[NSMutableArray alloc] initWithCapacity:12];
        unsigned int index;

        for (index = 1; index <= 12; index++) {
            NSTextTab *tab = [[NSTextTab alloc] initWithType:NSLeftTabStopType
                                                    location:28.0f * index];
            [stops addObject:tab];
            [tab release];
        }

        tabStops = [stops copy];
        [stops release];
    }

    return tabStops;
}

@interface NSParagraphStyle (Private)
- (id)_initWithParagraphStyle:(NSParagraphStyle *)style;
@end

@implementation NSTextTab

- (id)initWithType:(NSTextTabType)type location:(float)location
{
    self = [super init];
    if (self) {
        _flags.type = type;
        _location = location;
    }
    return self;
}

- (float)location
{
    return _location;
}

- (NSTextTabType)tabStopType
{
    return (NSTextTabType)_flags.type;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

@end

@implementation NSParagraphStyle

+ (NSParagraphStyle *)defaultParagraphStyle
{
    static NSParagraphStyle *style = nil;
    if (!style)
        style = [[self alloc] init];
    return style;
}

- (id)init
{
    return [self _initWithParagraphStyle:nil];
}

- (id)_initWithParagraphStyle:(NSParagraphStyle *)style
{
    self = [super init];
    if (self) {
        if (style) {
            _lineSpacing = style->_lineSpacing;
            _paragraphSpacing = style->_paragraphSpacing;
            _headIndent = style->_headIndent;
            _tailIndent = style->_tailIndent;
            _firstLineHeadIndent = style->_firstLineHeadIndent;
            _minimumLineHeight = style->_minimumLineHeight;
            _maximumLineHeight = style->_maximumLineHeight;
            _flags.alignment = style->_flags.alignment;
            _flags.lineBreakMode = style->_flags.lineBreakMode;
            _tabStops = [style->_tabStops copyWithZone:[self zone]];
        } else {
            _flags.alignment = NSNaturalTextAlignment;
            _tailIndent = 0.0f;
            _maximumLineHeight = 0.0f;
        }
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSParagraphStyle *copy = [[self class] allocWithZone:zone];
    return [copy _initWithParagraphStyle:self];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    NSMutableParagraphStyle *copy = [[NSMutableParagraphStyle allocWithZone:zone] init];
    [copy setParagraphStyle:self];
    return copy;
}

- (void)dealloc
{
    [_tabStops release];
    [super dealloc];
}

- (float)lineSpacing
{
    return _lineSpacing;
}

- (float)paragraphSpacing
{
    return _paragraphSpacing;
}

- (NSTextAlignment)alignment
{
    return (NSTextAlignment)_flags.alignment;
}

- (float)headIndent
{
    return _headIndent;
}

- (float)tailIndent
{
    return _tailIndent;
}

- (float)firstLineHeadIndent
{
    return _firstLineHeadIndent;
}

- (float)minimumLineHeight
{
    return _minimumLineHeight;
}

- (float)maximumLineHeight
{
    return _maximumLineHeight;
}

- (NSLineBreakMode)lineBreakMode
{
    return (NSLineBreakMode)_flags.lineBreakMode;
}

- (NSArray *)tabStops
{
    return _tabStops ? _tabStops : defaultTabStops();
}

@end

@implementation NSMutableParagraphStyle

- (void)_mutateTabStops
{
    if (_tabStops && [_tabStops isKindOfClass:[NSMutableArray class]])
        return;

    NSArray *tabStops = _tabStops ? _tabStops : defaultTabStops();
    NSMutableArray *mutableStops = [tabStops mutableCopyWithZone:[self zone]];
    [_tabStops release];
    _tabStops = mutableStops;
}

- (void)addTabStop:(NSTextTab *)tab
{
    [self _mutateTabStops];

    NSMutableArray *mutableStops = (NSMutableArray *)_tabStops;
    unsigned int count = [mutableStops count];
    unsigned int index;
    for (index = 0; index < count; index++) {
        if ([[mutableStops objectAtIndex:index] location] > [tab location])
            break;
    }

    if (index == count)
        [mutableStops addObject:tab];
    else
        [mutableStops insertObject:tab atIndex:index];
}

- (void)removeTabStop:(NSTextTab *)tab
{
    [self _mutateTabStops];
    [(NSMutableArray *)_tabStops removeObject:tab];
}

- (void)setLineSpacing:(float)lineSpacing
{
    _lineSpacing = lineSpacing;
}

- (void)setParagraphSpacing:(float)paragraphSpacing
{
    _paragraphSpacing = paragraphSpacing;
}

- (void)setAlignment:(NSTextAlignment)alignment
{
    _flags.alignment = alignment;
}

- (void)setFirstLineHeadIndent:(float)indent
{
    _firstLineHeadIndent = indent;
}

- (void)setHeadIndent:(float)indent
{
    _headIndent = indent;
}

- (void)setTailIndent:(float)indent
{
    _tailIndent = indent;
}

- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode
{
    _flags.lineBreakMode = lineBreakMode;
}

- (void)setMinimumLineHeight:(float)lineHeight
{
    _minimumLineHeight = lineHeight;
}

- (void)setMaximumLineHeight:(float)lineHeight
{
    _maximumLineHeight = lineHeight;
}

- (void)setTabStops:(NSArray *)tabStops
{
    if (_tabStops == tabStops)
        return;

    NSArray *copy = tabStops == defaultTabStops()
        ? nil
        : [tabStops copyWithZone:[self zone]];
    [_tabStops release];
    _tabStops = copy;
}

- (void)setParagraphStyle:(NSParagraphStyle *)style
{
    [self setAlignment:[style alignment]];
    [self setLineSpacing:[style lineSpacing]];
    [self setParagraphSpacing:[style paragraphSpacing]];
    [self setHeadIndent:[style headIndent]];
    [self setTailIndent:[style tailIndent]];
    [self setFirstLineHeadIndent:[style firstLineHeadIndent]];
    [self setMinimumLineHeight:[style minimumLineHeight]];
    [self setMaximumLineHeight:[style maximumLineHeight]];
    [self setLineBreakMode:[style lineBreakMode]];
    [self setTabStops:[style tabStops]];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSParagraphStyle *copy = [[NSParagraphStyle allocWithZone:zone] _initWithParagraphStyle:self];
    return copy;
}

@end
