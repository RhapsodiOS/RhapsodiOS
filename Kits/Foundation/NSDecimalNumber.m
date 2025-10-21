/*	NSDecimalNumber.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDecimalNumber.h>

@implementation NSDecimalNumber

- (id)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag {
    // TODO: Implement this method
    return nil;
}

- (id)initWithDecimal:(NSDecimal)decimal {
    // TODO: Implement this method
    return nil;
}

- (id)initWithString:(NSString *)numberValue {
    // TODO: Implement this method
    return nil;
}

- (id)initWithString:(NSString *)numberValue locale:(NSDictionary *)locale {
    // TODO: Implement this method
    return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    // TODO: Implement this method
    return nil;
}

- (NSDecimal)decimalValue {
    // TODO: Implement this method
    return (NSDecimal)0;
}

+ (NSDecimalNumber *)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)decimal {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue locale:(NSDictionary *)locale {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)zero {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)one {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)minimumDecimalNumber {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)maximumDecimalNumber {
    // TODO: Implement this method
    return nil;
}

+ (NSDecimalNumber *)notANumber {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByRaisingToPower:(unsigned)power {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByRaisingToPower:(unsigned)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSDecimalNumber *)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
    return nil;
}

- (NSComparisonResult)compare:(NSNumber *)decimalNumber {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

+ (void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    // TODO: Implement this method
}

+ (id <NSDecimalNumberBehaviors>)defaultBehavior {
    // TODO: Implement this method
    return (id <NSDecimalNumberBehaviors>)0;
}

- (const char *)objCType {
    // TODO: Implement this method
    return nil;
}

- (double)doubleValue {
    // TODO: Implement this method
    return 0.0;
}

@end

@implementation NSDecimalNumberHandler

+ (id)defaultDecimalNumberHandler {
    // TODO: Implement this method
    return nil;
}

- (id)initWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    // TODO: Implement this method
    return nil;
}

+ (id)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSNumber

- (NSDecimal)decimalValue {
    // TODO: Implement this method
    return (NSDecimal)0;
}

@end

@implementation NSScanner

- (BOOL)scanDecimal:(NSDecimal *)decimal {
    // TODO: Implement this method
    return NO;
}

@end
