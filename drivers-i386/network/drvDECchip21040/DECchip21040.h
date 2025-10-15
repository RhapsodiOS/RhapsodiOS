/*
 * DECchip21040.h
 * DECchip 21040 specific subclass
 */

#import "DECchip2104x.h"

@interface DECchip21040 : DECchip2104x
{
    /* 21040-specific instance variables */
    BOOL _mediaAutoDetect;
    unsigned int _linkCheckInterval;
}

/* Class probe method */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* 21040-specific methods */
- (BOOL)detect10BaseT;
- (BOOL)detect10Base2;
- (BOOL)detect10Base5;
- (void)autoDetectMedia;
- (void)checkLinkStatus;

/* Override base class methods */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;

@end
