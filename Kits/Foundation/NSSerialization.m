/*	NSSerialization.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSSerialization.h>

@implementation NSMutableData

- (void)serializeInt:(int)value {
    // TODO: Implement this method
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)numInts {
    // TODO: Implement this method
}

- (void)serializeInt:(int)value atIndex:(unsigned)index {
    // TODO: Implement this method
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)numInts atIndex:(unsigned)index {
    // TODO: Implement this method
}

- (void)serializeAlignedBytesLength:(unsigned)length {
    // TODO: Implement this method
}

@end

@implementation NSData

- (int)deserializeIntAtIndex:(unsigned)index {
    // TODO: Implement this method
    return 0;
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)numInts atIndex:(unsigned)index {
    // TODO: Implement this method
}

- (int)deserializeIntAtCursor:(unsigned *)cursor {
    // TODO: Implement this method
    return 0;
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)numInts atCursor:(unsigned *)cursor {
    // TODO: Implement this method
}

- (unsigned)deserializeAlignedBytesLengthAtCursor:(unsigned *)cursor {
    // TODO: Implement this method
    return 0;
}

- (void)deserializeBytes:(void *)buffer length:(unsigned)bytes atCursor:(unsigned *)cursor {
    // TODO: Implement this method
}

@end

@implementation NSMutableData

- (void)serializeDataAt:(const void *)data ofObjCType:(const char *)type context:(id <NSObjCTypeSerializationCallBack>)callback {
    // TODO: Implement this method
}

@end

@implementation NSData

- (void)deserializeDataAt:(void *)data ofObjCType:(const char *)type atCursor:(unsigned *)cursor context:(id <NSObjCTypeSerializationCallBack>)callback {
    // TODO: Implement this method
}

@end

@implementation NSSerializer

+ (void)serializePropertyList:(id)aPropertyList intoData:(NSMutableData *)mdata {
    // TODO: Implement this method
}

+ (NSData *)serializePropertyList:(id)aPropertyList {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSDeserializer

+ (id)deserializePropertyListFromData:(NSData *)data atCursor:(unsigned *)cursor mutableContainers:(BOOL)mut {
    // TODO: Implement this method
    return nil;
}

+ (id)deserializePropertyListLazilyFromData:(NSData *)data atCursor:(unsigned *)cursor length:(unsigned)length mutableContainers:(BOOL)mut {
    // TODO: Implement this method
    return nil;
}

+ (id)deserializePropertyListFromData:(NSData *)serialization mutableContainers:(BOOL)mut {
    // TODO: Implement this method
    return nil;
}

@end
