/*	NSDecimal.m
	Public library for large precision base-10 arithmetic
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDecimal.h>

// Function implementations

void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source) {
    // TODO: Implement this function
}

void NSDecimalCompact(NSDecimal *number) {
    // TODO: Implement this function
}

NSComparisonResult NSDecimalCompare(const NSDecimal *leftOperand, const NSDecimal *rightOperand) {
    // TODO: Implement this function
    return NSOrderedSame;
}

void NSDecimalRound(NSDecimal *result, const NSDecimal *number, int scale, NSRoundingMode roundingMode) {
    // TODO: Implement this function
}

NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, unsigned power, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power, NSRoundingMode roundingMode) {
    // TODO: Implement this function
    return NSCalculationNoError;
}

NSString *NSDecimalString(const NSDecimal *decimal, NSDictionary *locale) {
    // TODO: Implement this function
    return nil;
}
