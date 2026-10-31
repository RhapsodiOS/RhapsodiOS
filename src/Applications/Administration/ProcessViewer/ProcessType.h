#import <Foundation/Foundation.h>

@class Process;

@interface ProcessType : NSObject {
    NSString *_name;
    NSString *_key;
    NSSet *_values;
}
+ (id)allProcessTypes;
- (void)dealloc;
- (id)initWithDictionary:(NSDictionary *)dictionary strings:(NSDictionary *)strings;
- (id)localizedName;
- (BOOL)matchesProcess:(Process *)process;
- (id)name;
@end

void _readTypesFromFile(id processTypeClass, NSString *processTypesDirectory,
                        NSString *path);
