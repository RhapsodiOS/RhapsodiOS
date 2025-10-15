/*
 * DECchip21041.h
 * DECchip 21041 specific subclass
 */

#import "DECchip2104x.h"

@interface DECchip21041 : DECchip2104x
{
    /* 21041-specific instance variables */
    BOOL _mediaAutoDetect;
    BOOL _nwayEnabled;
    unsigned int _linkCheckInterval;
    unsigned int _autosenseState;
}

/* Class probe method */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* 21041-specific methods */
- (BOOL)detect10BaseT;
- (BOOL)detect10BaseTFD;
- (BOOL)detect10Base2;
- (BOOL)detect10Base5;
- (void)autoDetectMedia;
- (void)checkLinkStatus;
- (void)performAutosense;

/* N-Way auto-negotiation (limited on 21041) */
- (BOOL)enableNway;
- (void)disableNway;
- (BOOL)nwayComplete;

/* Override base class methods */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;

@end
