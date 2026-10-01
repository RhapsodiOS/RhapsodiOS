#import <Foundation/Foundation.h>
#include <sys/types.h>

typedef struct {
    id key;
    char compareAsNumber;
    BOOL ascending;
} ProcessSortContext;

@interface MapTableEnumerator : NSEnumerator {
    struct {
        unsigned int _pi;
        void *_nk;
        void *_bs;
    } _mapEnum;
}
+ (id)_newWithMapTable:(void *)table;
- (id)nextObject;
@end

@interface Process : NSObject {
    int _pid;
    int _ppid;
    int _pgid;
    unsigned int _saved_euid;
    unsigned int _real_uid;
    NSArray *_args;
    NSMutableDictionary *_values;
}
+ (id)enumerateProcessesAndFetch:(BOOL)fetch;
+ (BOOL)getSortContext:(ProcessSortContext *)context forKey:(id)key ascending:(BOOL)ascending;
+ (void)initialize;
- (id)arguments;
- (int)compare:(id)other context:(ProcessSortContext *)context;
- (void)dealloc;
- (id)description;
- (id)dictionaryRepresentation;
- (id)initWithPid:(int)pid;
- (void)invalidate;
- (id)objectForKey:(id)key;
- (unsigned int)parentProcessId;
- (unsigned int)processGroupId;
- (unsigned int)processId;
- (unsigned int)savedUserId;
- (id)tty;
@end

@interface Process (Private)
- (void)_setCString:(const char *)value forKey:(id)key;
- (void)_update;
@end

int sortFunction(id left, id right, void *context);
double floatFromNumberWithSuffix(id number);
void *NameForUID(uid_t uid);
