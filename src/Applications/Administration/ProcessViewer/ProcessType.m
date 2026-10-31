#import <Foundation/Foundation.h>
#import "ProcessType.h"
#import "Process.h"

static NSMutableArray *_allTypes = nil;
static NSString * const _TypesFileDefaultKey = @"TypeDescriptionFile";

#define PVAppendProcessType(typeClass, definitionArg, stringsArg) do { ProcessType *processType = [[typeClass alloc] initWithDictionary:(definitionArg) strings:(stringsArg)]; if (processType != nil) { [_allTypes addObject:processType]; [processType release]; } } while (0)

void _readTypesFromFile(id processTypeClass, NSString *processTypesDirectory,
                        NSString *path)
{
    NSString *contents = nil;
    id definitions = nil;
    NSDictionary *strings = nil;
    NSString *stringsPath = nil;
    NSString *stringsContents = nil;

    if (path == nil)
        return;

    NS_DURING
        contents = [NSString stringWithContentsOfFile:path];
        if (contents != nil)
            definitions = [contents propertyList];
    NS_HANDLER
        NSLog(@"Unable to parse contents of %@: %@", path,
              [localException reason]);
        definitions = nil;
    NS_ENDHANDLER

    if (definitions == nil)
        return;

    if (processTypesDirectory != nil) {
        stringsPath = [NSBundle pathForResource:[path lastPathComponent]
                                         ofType:@"strings"
                                    inDirectory:processTypesDirectory];
    } else {
        stringsPath = [[NSBundle mainBundle] pathForResource:[path lastPathComponent]
                                                       ofType:@"strings"];
    }

    if (stringsPath != nil) {
        NS_DURING
            stringsContents = [NSString stringWithContentsOfFile:stringsPath];
            if (stringsContents != nil)
                strings = [stringsContents propertyListFromStringsFileFormat];
        NS_HANDLER
            strings = nil;
        NS_ENDHANDLER
    }

    if ([definitions isKindOfClass:[NSDictionary class]]) {
        PVAppendProcessType(processTypeClass, definitions, strings);
    } else if ([definitions isKindOfClass:[NSArray class]]) {
        unsigned int index;
        unsigned int count = [definitions count];

        for (index = 0; index < count; ++index) {
            id definition = [definitions objectAtIndex:index];
            if ([definition isKindOfClass:[NSDictionary class]])
                PVAppendProcessType(processTypeClass, definition, strings);
        }
    }
}

@implementation ProcessType

+ (id)allProcessTypes
{
    if (_allTypes == nil) {
        NSArray *bundlePaths;
        NSArray *libraryPaths;
        unsigned int libraryIndex;
        unsigned int libraryCount;
        unsigned int bundleIndex;
        unsigned int bundleCount;

        _allTypes = [[NSMutableArray alloc] init];

        bundlePaths = [[NSBundle mainBundle]
            pathsForResourcesOfType:@"processType" inDirectory:nil];
        bundleCount = [bundlePaths count];
        for (bundleIndex = 0; bundleIndex < bundleCount; ++bundleIndex)
            _readTypesFromFile(self, nil, [bundlePaths objectAtIndex:bundleIndex]);

        libraryPaths = NSSearchPathForDirectoriesInDomains(
            NSAllLibrariesDirectory, NSAllDomainsMask, YES);
        libraryCount = [libraryPaths count];

        for (libraryIndex = 0; libraryIndex < libraryCount; ++libraryIndex) {
            NSString *processTypesDirectory = [[libraryPaths objectAtIndex:libraryIndex]
                stringByAppendingPathComponent:@"ProcessTypes"];
            NSArray *paths = [NSBundle pathsForResourcesOfType:@"processType"
                inDirectory:processTypesDirectory];
            unsigned int pathIndex;
            unsigned int pathCount = [paths count];

            for (pathIndex = 0; pathIndex < pathCount; ++pathIndex) {
                _readTypesFromFile(self, processTypesDirectory,
                    [paths objectAtIndex:pathIndex]);
            }
        }
    }

    return _allTypes;
}

- (id)initWithDictionary:(NSDictionary *)dictionary strings:(NSDictionary *)strings
{
    NSString *name = [dictionary objectForKey:@"Name"];
    NSString *localizedName;
    id values;

    if (name == nil) {
        NSLog(@"No Name specified in type dictionary %@", dictionary);
        [self release];
        return nil;
    }

    localizedName = [strings objectForKey:name];
    _name = [(localizedName != nil ? localizedName : name) copyWithZone:[self zone]];
    _key = [[dictionary objectForKey:@"Key"] copyWithZone:[self zone]];
    values = [dictionary objectForKey:@"Values"];

    if (![values isKindOfClass:[NSArray class]]) {
        if ([_key isEqualToString:@"USER"]) {
            values = [NSArray arrayWithObject:NSUserName()];
        } else if (_key != nil) {
            NSLog(@"No Values specified in type dictionary %@", dictionary);
            [self release];
            return nil;
        }
    }

    if (values != nil)
        _values = [[NSSet allocWithZone:[self zone]] initWithArray:values];

    return self;
}

- (BOOL)matchesProcess:(Process *)process
{
    if (_key == nil || _values == nil)
        return YES;

    return [_values containsObject:[process objectForKey:_key]];
}

- (id)localizedName
{
    return _name;
}

- (id)name
{
    return _name;
}

- (void)dealloc
{
    [_name release];
    [super dealloc];
}

@end
