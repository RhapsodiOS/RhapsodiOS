#import <Foundation/Foundation.h>
#include <pwd.h>
#include <sys/types.h>
#include <unistd.h>
#import "../Process.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Process *first = [[Process alloc] initWithPid:31415];
    Process *second = [[Process alloc] initWithPid:31416];
    ProcessSortContext context;
    uid_t uid = getuid();
    struct passwd *account = getpwuid(uid);
    NSString *name;

    context.key = nil;
    PV_CHECK([Process getSortContext:&context forKey:@"%CPU" ascending:YES]);
    PV_CHECK(context.compareAsNumber == 'f');
    PV_CHECK(context.ascending == YES);
    PV_CHECK_OBJECTS_EQUAL(context.key, @"%CPU");
    PV_CHECK([Process getSortContext:&context forKey:@"%MEM" ascending:YES]);
    PV_CHECK(context.compareAsNumber == 'f');
    PV_CHECK_OBJECTS_EQUAL(context.key, @"%MEM");
    PV_CHECK([Process getSortContext:&context forKey:@"RSIZE" ascending:YES]);
    PV_CHECK(context.compareAsNumber == 'f');
    PV_CHECK([Process getSortContext:&context forKey:@"VSIZE" ascending:YES]);
    PV_CHECK(context.compareAsNumber == 'f');
    PV_CHECK(![Process getSortContext:&context forKey:@"USER" ascending:YES]);
    PV_CHECK(![Process getSortContext:&context forKey:@"STAT" ascending:YES]);

    PV_CHECK([first processId] == 31415);
    PV_CHECK([first parentProcessId] == 0);
    PV_CHECK([first processGroupId] == 0);
    PV_CHECK([first savedUserId] == 0);

    [first _setCString:"worker" forKey:@"NAME"];
    [second _setCString:"shell" forKey:@"NAME"];
    PV_CHECK_OBJECTS_EQUAL([first objectForKey:@"NAME"], @"worker");

    context.key = @"NAME";
    context.compareAsNumber = '@';
    context.ascending = YES;
    PV_CHECK([first compare:second context:&context] > 0);
    context.ascending = NO;
    PV_CHECK([first compare:second context:&context] < 0);

    [first _setCString:"" forKey:@"NAME"];
    PV_CHECK([first objectForKey:@"NAME"] == nil);
    [first _setCString:"worker" forKey:@"NAME"];
    [first _setCString:NULL forKey:@"NAME"];
    PV_CHECK([first objectForKey:@"NAME"] == nil);

    [first _setCString:"worker" forKey:@"NAME"];
    [second _setCString:NULL forKey:@"NAME"];
    context.key = @"NAME";
    context.compareAsNumber = '@';
    context.ascending = YES;
    PV_CHECK([first compare:second context:&context] > 0);
    context.ascending = NO;
    PV_CHECK([first compare:second context:&context] < 0);

    [first _setCString:"20K" forKey:@"VSIZE"];
    [second _setCString:"2M" forKey:@"VSIZE"];
    context.key = @"VSIZE";
    context.compareAsNumber = 'f';
    context.ascending = YES;
    PV_CHECK([first compare:second context:&context] < 0);
    PV_CHECK(floatFromNumberWithSuffix(@"2M") == 2097152.0);

    if (account != NULL) {
        name = (NSString *)NameForUID(uid);
        PV_CHECK(name != nil);
        PV_CHECK_OBJECTS_EQUAL(name, [NSString stringWithCString:account->pw_name]);
        PV_CHECK(NameForUID(uid) == name);
    }

    [first release];
    [second release];
    [pool release];
    return PVFinish();
}
