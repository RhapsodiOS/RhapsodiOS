/*
 * Created by Mirko Viviani 3 Apr 1999
 */

#ifndef MGA_XMODES
#define MGA_XMODES

#import <driverkit/displayDefs.h>
#import <driverkit/i386/ioPorts.h>


#define ONE_MEGABYTE				(1024 * 1024)
#define TWO_MEGABYTES			(2048 * 1024)
#define THREE_MEGABYTES			(3072 * 1024)
#define FOUR_MEGABYTES			(4096 * 1024)
#define EIGHT_MEGABYTES			(8192 * 1024)
#define SIXTEEN_MEGABYTES		(16384 * 1024)
#define THIRTYTWO_MEGABYTES	(32768 * 1024)


struct XMode
{
	unsigned long memSize;	/* The memory necessary for this mode. */

	int	Clock;              /* pixel clock */
	int	HDisplay;           /* horizontal timing */
	int	HSyncStart;
	int	HSyncEnd;
	int	HTotal;
	int	VDisplay;           /* vertical timing */
	int	VSyncStart;
	int	VSyncEnd;
	int	VTotal;
	int	Flags;
};

typedef struct XMode	XMode;

#endif /* MGA_XMODES */