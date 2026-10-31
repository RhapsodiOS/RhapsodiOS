//  CONFIDENTIAL
//  Copyright (c) 1994 by NeXT Computer, Inc as an unpublished work.
//  All rights reserved.


#import <Foundation/NSObject.h>

@protocol NSShapeEnumerator
- (NSRect *) nextRect;			/* returns null when done. */
@end

@interface NSShape : NSObject
{
@private
    NSZone *zone;
    void *_impl;
}



- init;						/* empty shape */
- initFromRect:(NSRect)aRect;
- (void)intersectWithShape:(NSShape *)other;	/* self = self isect other */
- (void)unionWithShape:(NSShape *)other;		/* self = self union other */
- (void)differenceWithShape:(NSShape *)other;	/* self = self - other */
- (void)offsetShape:(NSPoint)offset;
- (BOOL) isEmpty;
- (BOOL) isEqual: (NSShape *) other;
- copyWithZone:(NSZone *)zone;

- (id <NSShapeEnumerator>) rectEnumerator;


@end



