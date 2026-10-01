#import <Foundation/Foundation.h>
#include <pwd.h>
#include <string.h>
#include <sys/types.h>
#import "Process.h"

static NSMapTable *uidCache = NULL;

void *NameForUID(uid_t uid)
{
    const void *key = (const void *)(unsigned long)(uid + 1);
    NSString *name;

    if (uidCache == NULL) {
        uidCache = NSCreateMapTableWithZone(NSIntMapKeyCallBacks,
            NSIntMapValueCallBacks, 0, NSDefaultMallocZone());
    }

    name = (NSString *)NSMapGet(uidCache, key);

    if (name == nil) {
        struct passwd *account = getpwuid(uid);
        if (account != NULL) {
            size_t length = strlen(account->pw_name);
            if (length > 0) {
                NSData *data = [NSData dataWithBytes:account->pw_name length:length];
                name = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
                if (name != nil)
                    NSMapInsert(uidCache, key, name);
            }
        }
    }

    return name;
}
