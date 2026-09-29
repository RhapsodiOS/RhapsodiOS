#ifndef _INTERCEPTOR_PRIVATE_H_
#define _INTERCEPTOR_PRIVATE_H_

#import "NSInterceptedRect.h"
#import "NSInterceptorClient.h"

@interface _NSShapeEnumerator : NSObject
{
@private
    short *xloc;
    short *yloc;
    NSRect r;
}
- initForShapeImpl:(id)shape;
@end

#endif
