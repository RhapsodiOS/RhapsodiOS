/*	NSByteOrder.h
	Definitions for low-level byte swapping
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObjCRuntime.h>

enum _NSByteOrder {
    NS_UnknownByteOrder,
    NS_LittleEndian,
    NS_BigEndian
};

typedef struct {unsigned long v;} NSSwappedFloat;
typedef struct {unsigned long long v;} NSSwappedDouble;

FOUNDATION_STATIC_INLINE unsigned NSHostByteOrder(void) {
    unsigned int _x;
    _x = (NS_BigEndian << 24) | NS_LittleEndian;
    return ((unsigned)*((unsigned char *)&_x));
}

/****************	Basic arch-dependent swapping	****************/

#if defined(__m68k__) || defined(__hppa__) || defined(__sparc__) || defined(__ppc__)

FOUNDATION_STATIC_INLINE unsigned short NSSwapShort(unsigned short inv) {
    union sconv {
	unsigned short us;
	unsigned char uc[2];
    } *inp, outv;
    inp = (union sconv *)&inv;
    outv.uc[0] = inp->uc[1];
    outv.uc[1] = inp->uc[0];
    return (outv.us);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapInt(unsigned int inv) {
    union iconv {
	unsigned int ui;
	unsigned char uc[4];
    } *inp, outv;
    inp = (union iconv *)&inv;
    outv.uc[0] = inp->uc[3];
    outv.uc[1] = inp->uc[2];
    outv.uc[2] = inp->uc[1];
    outv.uc[3] = inp->uc[0];
    return (outv.ui);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapLong(unsigned long inv) {
    union lconv {
	unsigned long ul;
	unsigned char uc[4];
    } *inp, outv;
    inp = (union lconv *)&inv;
    outv.uc[0] = inp->uc[3];
    outv.uc[1] = inp->uc[2];
    outv.uc[2] = inp->uc[1];
    outv.uc[3] = inp->uc[0];
    return (outv.ul);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapLongLong(unsigned long long inv) {
    union llconv {
	unsigned long long ull;
	unsigned char uc[8];
    } *inp, outv;
    inp = (union llconv *)&inv;
    outv.uc[0] = inp->uc[7];
    outv.uc[1] = inp->uc[6];
    outv.uc[2] = inp->uc[5];
    outv.uc[3] = inp->uc[4];
    outv.uc[4] = inp->uc[3];
    outv.uc[5] = inp->uc[2];
    outv.uc[6] = inp->uc[1];
    outv.uc[7] = inp->uc[0];
    return (outv.ull);
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSConvertHostFloatToSwapped(float x) {
    union fconv {
	float number;
	NSSwappedFloat sf;
    };
    return ((union fconv *)&x)->sf;
}

FOUNDATION_STATIC_INLINE float NSConvertSwappedFloatToHost(NSSwappedFloat x) {
    union fconv {
	float number;
	NSSwappedFloat sf;
    };
    return ((union fconv *)&x)->number;
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSConvertHostDoubleToSwapped(double x) {
    union dconv {
	double number;
	NSSwappedDouble sd;
    };
    return ((union dconv *)&x)->sd;
}

FOUNDATION_STATIC_INLINE double NSConvertSwappedDoubleToHost(NSSwappedDouble x) {
    union dconv {
	double number;
	NSSwappedDouble sd;
    };
    return ((union dconv *)&x)->number;
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapFloat(NSSwappedFloat x) {
    x.v = NSSwapLong(x.v);
    return x;
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapDouble(NSSwappedDouble x) {
    x.v = NSSwapLongLong(x.v);
    return x;
}

#elif defined(__i386__)

FOUNDATION_STATIC_INLINE unsigned short NSSwapShort (unsigned short inv) {
    unsigned short outv;
    __asm__ volatile("rorw $8,%0" : "=r" (outv) : "0" (inv));
    return (outv);
}
 
FOUNDATION_STATIC_INLINE unsigned int NSSwapInt (unsigned int inv) {
    unsigned int outv;
    __asm__ volatile("bswap %0" : "=r" (outv) : "0" (inv));
    return (outv);
}
 
FOUNDATION_STATIC_INLINE unsigned long NSSwapLong(unsigned long inv) {
    unsigned long outv;
    __asm__ volatile("bswap %0" : "=r" (outv) : "0" (inv));
    return (outv);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapLongLong(unsigned long long inv) {
    union llconv {
	unsigned long long ull;
	unsigned long ul[2];
    } *inp, outv;
    inp = (union llconv *)&inv;
    outv.ul[0] = NSSwapLong(inp->ul[1]);
    outv.ul[1] = NSSwapLong(inp->ul[0]);
    return (outv.ull);
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSConvertHostFloatToSwapped(float x) {
    union fconv {
	float number;
	NSSwappedFloat sf;
    };
    return ((union fconv *)&x)->sf;
}

FOUNDATION_STATIC_INLINE float NSConvertSwappedFloatToHost(NSSwappedFloat x) {
    union fconv {
	float number;
	NSSwappedFloat sf;
    };
    return ((union fconv *)&x)->number;
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSConvertHostDoubleToSwapped(double x) {
    union dconv {
	double number;
	NSSwappedDouble sd;
    };
    return ((union dconv *)&x)->sd;
}

FOUNDATION_STATIC_INLINE double NSConvertSwappedDoubleToHost(NSSwappedDouble x) {
    union dconv {
	double number;
	NSSwappedDouble sd;
    };
    return ((union dconv *)&x)->number;
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapFloat(NSSwappedFloat x) {
    x.v = NSSwapLong(x.v);
    return x;
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapDouble(NSSwappedDouble x) {
    x.v = NSSwapLongLong(x.v);
    return x;
}

#else
#error Do not know how to byte order this architecture
#endif

/*************** Swapping to big/little endian ***************/

#if defined(__BIG_ENDIAN__)

FOUNDATION_STATIC_INLINE unsigned short NSSwapBigShortToHost(unsigned short x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapBigIntToHost(unsigned int x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapBigLongToHost(unsigned long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapBigLongLongToHost(unsigned long long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE double NSSwapBigDoubleToHost(NSSwappedDouble x) {
    return NSConvertSwappedDoubleToHost(x);
}

FOUNDATION_STATIC_INLINE float NSSwapBigFloatToHost(NSSwappedFloat x) {
    return NSConvertSwappedFloatToHost(x);
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapHostShortToBig(unsigned short x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapHostIntToBig(unsigned int x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapHostLongToBig(unsigned long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapHostLongLongToBig(unsigned long long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapHostDoubleToBig(double x) {
    return NSConvertHostDoubleToSwapped(x);
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapHostFloatToBig(float x) {
    return NSConvertHostFloatToSwapped(x);
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapLittleShortToHost(unsigned short x) {
    return NSSwapShort(x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapLittleIntToHost(unsigned int x) {
    return NSSwapInt(x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapLittleLongToHost(unsigned long x) {
    return NSSwapLong(x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapLittleLongLongToHost(unsigned long long x) {
    return NSSwapLongLong(x);
}

FOUNDATION_STATIC_INLINE double NSSwapLittleDoubleToHost(NSSwappedDouble x) {
    return NSConvertSwappedDoubleToHost(NSSwapDouble(x));
}

FOUNDATION_STATIC_INLINE float NSSwapLittleFloatToHost(NSSwappedFloat x) {
    return NSConvertSwappedFloatToHost(NSSwapFloat(x));
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapHostShortToLittle(unsigned short x) {
    return NSSwapShort(x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapHostIntToLittle(unsigned int x) {
    return NSSwapInt(x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapHostLongToLittle(unsigned long x) {
    return NSSwapLong(x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapHostLongLongToLittle(unsigned long long x) {
    return NSSwapLongLong(x);
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapHostDoubleToLittle(double x) {
    return NSSwapDouble(NSConvertHostDoubleToSwapped(x));
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapHostFloatToLittle(float x) {
    return NSSwapFloat(NSConvertHostFloatToSwapped(x));
}

#elif defined(__LITTLE_ENDIAN__)

FOUNDATION_STATIC_INLINE unsigned short NSSwapBigShortToHost(unsigned short x) {
    return NSSwapShort(x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapBigIntToHost(unsigned int x) {
    return NSSwapInt(x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapBigLongToHost(unsigned long x) {
    return NSSwapLong(x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapBigLongLongToHost(unsigned long long x) {
    return NSSwapLongLong(x);
}

FOUNDATION_STATIC_INLINE double NSSwapBigDoubleToHost(NSSwappedDouble x) {
    return NSConvertSwappedDoubleToHost(NSSwapDouble(x));
}

FOUNDATION_STATIC_INLINE float NSSwapBigFloatToHost(NSSwappedFloat x) {
    return NSConvertSwappedFloatToHost(NSSwapFloat(x));
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapHostShortToBig(unsigned short x) {
    return NSSwapShort(x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapHostIntToBig(unsigned int x) {
    return NSSwapInt(x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapHostLongToBig(unsigned long x) {
    return NSSwapLong(x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapHostLongLongToBig(unsigned long long x) {
    return NSSwapLongLong(x);
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapHostDoubleToBig(double x) {
    return NSSwapDouble(NSConvertHostDoubleToSwapped(x));
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapHostFloatToBig(float x) {
    return NSSwapFloat(NSConvertHostFloatToSwapped(x));
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapLittleShortToHost(unsigned short x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapLittleIntToHost(unsigned int x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapLittleLongToHost(unsigned long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapLittleLongLongToHost(unsigned long long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE double NSSwapLittleDoubleToHost(NSSwappedDouble x) {
    return NSConvertSwappedDoubleToHost(x);
}

FOUNDATION_STATIC_INLINE float NSSwapLittleFloatToHost(NSSwappedFloat x) {
    return NSConvertSwappedFloatToHost(x);
}

FOUNDATION_STATIC_INLINE unsigned short NSSwapHostShortToLittle(unsigned short x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned int NSSwapHostIntToLittle(unsigned int x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long NSSwapHostLongToLittle(unsigned long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE unsigned long long NSSwapHostLongLongToLittle(unsigned long long x) {
    return (x);
}

FOUNDATION_STATIC_INLINE NSSwappedDouble NSSwapHostDoubleToLittle(double x) {
    return NSConvertHostDoubleToSwapped(x);
}

FOUNDATION_STATIC_INLINE NSSwappedFloat NSSwapHostFloatToLittle(float x) {
    return NSConvertHostFloatToSwapped(x);
}

#else
#error Do not know the endianess of this architecture
#endif

