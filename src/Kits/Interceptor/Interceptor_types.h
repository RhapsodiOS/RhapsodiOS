/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved. 
 *
 * Interceptor_types.h - Data types and #defines for Interceptor interface.
 *
 * HISTORY
 * 28-July-93    Mike Paquette at NeXT
 *      Created. 
 */
#ifndef __INTERCEPTOR_TYPES__
#define __INTERCEPTOR_TYPES__

#import <mach/mach.h>

typedef enum
{
	InterceptorSuccess,
	InterceptorNoDriver,
	InterceptorNoDevice,
	InterceptorNoAccess,
	InterceptorNoWindow,
	InterceptorInvalidRect,
	InterceptorUnsupportedOperation
} InterceptorReturn;

/* Enumeration to encode the use of bits within a pixel. */
typedef enum
{
	SampleType_End = '\0',
	SampleType_Red = 'R',
	SampleType_Green = 'G',
	SampleType_Blue = 'B',
	SampleType_Alpha = 'A',
	SampleType_Gray = 'W',	/* 1 is white colorspace */
	
	SampleType_Cyan = 'C',
	SampleType_Magenta = 'M',
	SampleType_Yellow = 'Y',
	SampleType_Black = 'K',	/* 1 is black colorspace */
	
	SampleType_Luminance = 'l',
	SampleType_ChromaU = 'u',
	SampleType_ChromaV = 'v',
	SampleType_ChromaA = 'a',
	SampleType_ChromaB = 'b',
	
	SampleType_PseudoColor = 'P',
	
	SampleType_MustSet = '1',
	SampleType_MustClear = '0',
	SampleType_Skip = '-'	/* Unused bits in the pixel */
} InterceptorSampleType;

/*
 * The bits composing a pixel are identified by an array of SampleTypes
 * cast as chars in an array.  The first char describes the most significant
 * bit of the pixel.  The encoding char is repeated as many times as is needed
 * to represent the number of bits in the encoded channel of the pixel.  The
 * array is terminated by SampleType_End, or a NUL char.
 *
 * When pixels are not the size of an integer multiple (1,2,...) of an
 * addressable unit of storage, they are assumed to be packed into an
 * addressable unit of storage with the left-hand-most pixel in the most
 * significant bits of the store.
 *
 * strlen( pixel_description_t ) returns the bit depth of the pixels.
 */
#define MAX_PIXEL_DESC_BITS	64	 /* Max length to keep MiG happy */
typedef char pixel_encoding_t[MAX_PIXEL_DESC_BITS];

/*
 * Common pixel formats as const char strings
 */
#if hppa //[
#define PIXEL_RGB_32	"--------RRRRRRRRGGGGGGGGBBBBBBBB"
#else //][
#define PIXEL_RGB_32	"RRRRRRRRGGGGGGGGBBBBBBBB--------"
#endif //]
#define PIXEL_RGBA_32	"RRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA"
#define PIXEL_RGBA_16	"RRRRGGGGBBBBAAAA"
#define PIXEL_RGB_16	"RRRRGGGGBBBB----"
#define PIXEL_PC_RGB_15	"-RRRRRGGGGGBBBBB"
#define PIXEL_GRAY_8	"WWWWWWWW"
#define PIXEL_RGB_8	"PPPPPPPP"
#define PIXEL_GRAY_2	"KK"

/*
 * Client side stuff
 */
typedef struct
{
	port_t	contextPort;
	port_t	replyPort;
	port_t	notifyPort;	// Port for rect geometry change messages
} InterceptorClientContext;


typedef char 	driver_name_t[80];
typedef unsigned int	driver_info_t[64];
typedef unsigned short *bm34To35Table;
typedef unsigned short *bm35To34Table;
typedef unsigned int *bm256To38Table;
typedef unsigned char *bm38To256Table;
typedef unsigned char *bit_data_t;

#define MAX_BM34TO35TABLE_ENTRIES	4096
#define MAX_BM35TO34TABLE_ENTRIES	32768


#define NX_INTERCEPTOR_PKGID	7196

extern int Interceptor_mig_error( int error );

#if ! defined(_NeXT_MACH_EVENT_DRIVER_)
#define MEGAPIXEL_DEV	"/dev/vid0"
#endif

/*
 * Structure for setting up InterceptedRect.  This struct is passed in/out
 * through the mig interface. When passed out the rectangle of interest is
 * transformed to screen coordinates and the flags data structure is
 * updated as in the InterceptorNotification structure (to initially set
 * the totally obscured bit, etc.)
 */
typedef struct {
    int x,y,w,h;		/* rectangle of interest */
    int idNum;			/* unqiue ID for this rect */
    int wnum;			/* window number for the rect */
    int snum;			/* screen number */
    int flags;			/* flags indicating what type of notification
				 * is necessary */
} InterceptedRectangle;

typedef struct {
    int x,y,w,h;
} IntRect;

/*
 * what follows is the basic interceptor notification message.
 */
typedef struct {
    msg_header_t h;
    msg_type_t interceptorMsgType;
    int	sequenceNumber;		/* Serial number for message */
    int uniqueID;		/* id of rect for this notification */
    int type;			/* type of notification (see below) */
    int flags;			/* tracks totally obscured/revealed state */
    int args[16];		/* 16 type-dependent integer args */
#if 0
    /* TODO -- handle clipping list, etc. */
    msg_type_long_t oobType;	
    unsigned char *clip;	/* current clip list */
    unsigned char *data;	/* other type-dependent oob data */
#endif 
} InterceptorNotification;


/*
 * Msg id for interceptor notification
 */

#define INTERCEPT_NOTIFY_MSGID		1234
#define INTERCEPT_REPLY_MSGID		4321

/*
 * Types of interceptor messages.
 */
#define INTERCEPT_DID_REVEAL	1
#define INTERCEPT_WILL_OBSCURE	2
#define INTERCEPT_INVALID	3
#define INTERCEPT_WILL_MOVE	4
#define INTERCEPT_DID_MOVE	5
#define INTERCEPT_ORDER_IN	6
#define INTERCEPT_ORDER_OUT	7
#define INTERCEPT_FLUSH		8
#define INTERCEPT_NEW_SCREEN	9
#define INTERCEPT_WINDOW_FREED	10
#define INTERCEPT_WILL_CHANGE_BUFFERING	11
#define INTERCEPT_DID_CHANGE_BUFFERING	12

#define INTERCEPT_HOOK_MASK	( (1 << NX_MOVEWINDOW) \
				 |(1 << NX_OBSCUREWINDOW) \
				 |(1 << NX_ORDERWINDOW) \
				 |(1 << NX_REVEALWINDOW) \
				 |(1 << NX_PLACEWINDOW) \
				 |(1 << NX_FLUSHWINDOW) \
				 |(1 << NX_NEWSCREEN) \
				 |(1 << NX_BUFFERINGWINDOW) \
				 |(1 << NX_FREEWINDOW) )
/*
 * Flags bits
 */
#define INTERCEPT_TOTALLY_OBSCURED	1
#define INTERCEPT_TOTALLY_VISIBLE	2

/*
 * IntClipRegion -- used to communicate
 */
typedef struct {
    int numRects;
    IntRect rect[0];
} IntClipRegion;

typedef struct {
    msg_header_t h;
    msg_type_t interceptorMsgType;
    int	sequenceNumber;		/* Serial number for reply, matches message */
    msg_type_t replyType;
    int	replyCode;		/* Return special request codes */
} InterceptorReply;


typedef enum {
    NXInteceptorFlushBits,
    NXInterceptorSoverBits,
    NXInteceptorFlushNewBits,
    NXInterceptorSoverNewBits,
    NXInterceptorFlushDone,
} NXInterceptorFlushReturn;

/* Reply codes used in InterceptorRelpy message.  These may be ORed together */
#define InterceptorReplyNeedPaletteRepair	0x00000001

#endif  /* __INTERCEPTOR_TYPES__ */
