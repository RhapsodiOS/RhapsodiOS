#import <Foundation/NSBundle.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>

#include "WindowTitleRuntime.h"

const char *terminalHomeDirectory(void)
{
    return [NSHomeDirectory() cString];
}

const char *terminalProcessName(void)
{
    return [[[NSProcessInfo processInfo] processName] cString];
}

const char *terminalKeyStealerSuffix(void)
{
    return [[[NSBundle mainBundle]
        localizedStringForKey:[NSString stringWithCString:" \xD0 (Key Stealer)"]
        value:@"" table:nil]
        cString];
}
