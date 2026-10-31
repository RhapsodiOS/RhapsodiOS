#import <Foundation/Foundation.h>
#import "../ProcessType.h"
#import "test_support.h"

static ProcessType *PVType(NSDictionary *definition, NSDictionary *strings)
{
    return [[ProcessType alloc] initWithDictionary:definition strings:strings];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *strings = [NSDictionary dictionaryWithObject:@"Localized worker"
                                                         forKey:@"Worker"];
    ProcessType *type = PVType([NSDictionary dictionaryWithObjectsAndKeys:
        @"Worker", @"Name", @"NAME", @"Key", [NSArray arrayWithObject:@"worker"], @"Values", nil], strings);
    PV_CHECK(type != nil);
    PV_CHECK_OBJECTS_EQUAL([type name], @"Localized worker");
    PV_CHECK_OBJECTS_EQUAL([type localizedName], @"Localized worker");
    PV_CHECK([type matchesProcess:[NSDictionary dictionaryWithObject:@"worker" forKey:@"NAME"]]);
    PV_CHECK(![type matchesProcess:[NSDictionary dictionaryWithObject:@"shell" forKey:@"NAME"]]);
    [type release];

    type = PVType([NSDictionary dictionaryWithObject:@"Unfiltered" forKey:@"Name"], nil);
    PV_CHECK(type != nil);
    PV_CHECK([type matchesProcess:[NSDictionary dictionary]]);
    [type release];

    type = PVType([NSDictionary dictionaryWithObjectsAndKeys:
        @"Current user", @"Name", @"USER", @"Key", nil], nil);
    PV_CHECK(type != nil);
    PV_CHECK([type matchesProcess:[NSDictionary dictionaryWithObject:NSUserName() forKey:@"USER"]]);
    PV_CHECK(![type matchesProcess:[NSDictionary dictionaryWithObject:@"another-user" forKey:@"USER"]]);
    [type release];

    type = PVType([NSDictionary dictionaryWithObjectsAndKeys:
        @"Missing values", @"Name", @"NAME", @"Key", nil], nil);
    PV_CHECK(type == nil);

    type = PVType([NSDictionary dictionaryWithObject:@"Missing name" forKey:@"Key"], nil);
    PV_CHECK(type == nil);

    if ([[NSBundle mainBundle] pathForResource:@"Extra" ofType:@"processType"] != nil) {
        NSArray *types = [ProcessType allProcessTypes];
        BOOL foundExtra = NO;
        unsigned int index;
        for (index = 0; index < [types count]; ++index) {
            if ([[[types objectAtIndex:index] localizedName]
                    isEqualToString:@"Localized extra"]) {
                foundExtra = YES;
                break;
            }
        }
        PV_CHECK(foundExtra);
    }

    [pool release];
    return PVFinish();
}
