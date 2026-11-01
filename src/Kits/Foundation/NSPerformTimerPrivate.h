/*	NSPerformTimerPrivate.h
	Private delayed run-loop performer interface
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSTimer.h>

@interface NSPerformTimer : NSTimer {
    NSPerformTimer *link;
    id target;
    SEL selector;
    id argument;
    unsigned order;
    NSArray *modes;
    unsigned short firing : 1;
    unsigned short invalid : 1;
    unsigned short filler : 14;
    unsigned short refCount : 16;
}
+ (id)newPerformSelector:(SEL)selector target:(id)target argument:(id)argument
                   order:(unsigned)order modes:(NSArray *)modes;
@end
