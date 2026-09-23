/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * kernBootStruct.h
 * What the booter leaves behind for the kernel.
 */

/* The config table has room for 13 drivers if their config files
 * are the maximum size allowed.
 */
#define CONFIG_SIZE (13 * 4096)

/* Maximum number of boot drivers supported, assuming their
 * config files fit in the bootstruct.
 */
#define NDRIVERS		64

typedef struct {
    char    *address;			// address where driver was loaded
    int	    size;			// entry point for driver
} driver_config_t;

typedef struct {
    unsigned short	major_vers;	// == 0 if not present
    unsigned short	minor_vers;
    unsigned long	cs32_base;
    unsigned long	cs16_base;
    unsigned long	ds_base;
    unsigned long	cs_length;
    unsigned long	ds_length;
    unsigned long	entry_offset;
    union {
	struct {
	    unsigned long	mode_16		:1;
	    unsigned long	mode_32		:1;
	    unsigned long	idle_slows_cpu	:1;
	    unsigned long	reserved	:29;
	} f;
	unsigned long data;
    } flags;
    unsigned long	connected;
} APM_config_t;

typedef struct _EISA_slot_info_t {
    union {
	struct {
	    unsigned char	duplicateID	:4;
	    unsigned char	slotType	:1;
	    unsigned char	prodIDPresent	:1;
	    unsigned char	dupIDPresent	:1;
	} s;
	unsigned char d;
    } u_ID;
    unsigned char	configMajor;
    unsigned char 	configMinor;
    unsigned short	checksum;
    unsigned char	numFunctions;
    union {
	struct {
	    unsigned char	fnTypesPresent	:1;
	    unsigned char	memoryPresent	:1;
	    unsigned char	irqPresent	:1;
	    unsigned char	dmaPresent	:1;
	    unsigned char	portRangePresent:1;
	    unsigned char	portInitPresent	:1;
	    unsigned char	freeFormPresent	:1;
	    unsigned char	reserved:1;
	} s;
	unsigned char d;
    } u_resources;
    unsigned char	id[8];
} EISA_slot_info_t;

typedef struct _EISA_func_info_t {
    unsigned char	slot;
    unsigned char	function;
    unsigned char	reserved[2];
    unsigned char	data[320];
} EISA_func_info_t;

#define NUM_EISA_SLOTS	64

typedef struct _PCI_bus_info_t {
    union {
	struct {
	    unsigned char configMethod1	:1;
	    unsigned char configMethod2	:1;
	    unsigned char		:2;
	    unsigned char specialCycle1	:1;
	    unsigned char specialCycle2	:1;
	} s;
	unsigned char d;
    } u_bus;
    unsigned char maxBusNum;
    unsigned char majorVersion;
    unsigned char minorVersion;
    unsigned char BIOSPresent;
} PCI_bus_info_t;

/*
 * Video information..
 */

struct boot_video {
        unsigned long   v_baseAddr;     /* Base address of video memory */
        unsigned long   v_display;      /* Display Code (if Applicable */
        unsigned long   v_rowBytes;     /* Number of bytes per pixel row */
        unsigned long   v_width;        /* Width */
        unsigned long   v_height;       /* Height */
        unsigned long   v_depth;        /* Pixel Depth */
};

typedef struct boot_video       boot_video;

#define BOOT_STRING_LEN		160

/*
 * One VBE mode as OPENSTEP 4.2 User Patch 4 recorded it for the kernel and
 * the VBE20DisplayDriver. 24 bytes; 0x12-0x13 are padding. The layout is
 * spec 1's, confirmed by the driver's type encoding and by the kernel's
 * VBEModeInfo2IODisplayInfo (0x0019ED8C in the 4.2 kernel).
 */
struct boot_vbe_mode {
	unsigned short	modeNumber;		/* 0x00 */
	unsigned short	modeAttributes;		/* 0x02 */
	unsigned short	xResolution;		/* 0x04 */
	unsigned short	yResolution;		/* 0x06 */
	unsigned short	bytesPerScanline;	/* 0x08 */
	unsigned char	bitsPerPixel;		/* 0x0A */
	unsigned char	memoryModel;		/* 0x0B */
	unsigned char	redMaskSize;		/* 0x0C */
	unsigned char	redFieldPosition;	/* 0x0D */
	unsigned char	greenMaskSize;		/* 0x0E */
	unsigned char	greenFieldPosition;	/* 0x0F */
	unsigned char	blueMaskSize;		/* 0x10 */
	unsigned char	blueFieldPosition;	/* 0x11 */
	unsigned long	frameBuffer;		/* 0x14, physical */
};

typedef struct boot_vbe_mode boot_vbe_mode;

/*
 * 4.2 allowed 90 records (0x870 bytes from 0x1870; the driver scans 0x880
 * bytes from there). In this struct the 90th would overwrite `video`, so
 * the booter stops at 89 and leaves the 90th slot's xResolution zero for
 * the driver's scan to stop on.
 */
#define BOOT_VBE_MAX_MODES	89

typedef struct {
    short   version;
    char    bootString[BOOT_STRING_LEN];// string we booted with
    int	    magicCookie;		// KERNBOOTMAGIC if struct valid
    int	    numIDEs;			// how many IDE drives
    int	    rootdev;			// booters guess as to rootdev
    unsigned int convmem;		// conventional memory (in KB)
    unsigned int extmem;		// extended memory (in KB)
    char    boot_file[128];		// name of the kernel we booted
    int	    first_addr0;		// first address for kern convmem
    int	    diskInfo[4];		// bios info for bios dev 80-83
    int	    graphicsMode;		// did we boot in graphics mode?
    int	    kernDev;			// device kernel was fetched from
    int     numBootDrivers;		// number of drivers loaded by booter    
    char    *configEnd;			// pointer to end of config files
    int	    kaddr;			// kernel load address
    int     ksize;			// size of kernel
    void    *rld_entry;			// entry point for standalone rld

    driver_config_t driverConfig[NDRIVERS];
    APM_config_t apm_config;
    
    char   _reserved[5320];		// 908 .. 6228

    /*
     * VBE hand-off, at OPENSTEP 4.2 User Patch 4's offsets. The driver and
     * the kernel address these as bare constants, because the 4.2 binaries
     * do: VBE20DisplayDriver.m's VBE_BOOTER_MODE (0x12858) and
     * VBE_BOOTER_MODES (0x12870), FBConsole.c's VBE_BOOTER_MODE and
     * VBE_FRAMEBUFFER_VIRT (0x12854). The assertions below keep these
     * members on those addresses.
     */
    unsigned long	vbeFrameBuffer;		// 0x1854: kernel virtual, pmap_bootstrap
    boot_vbe_mode	vbeCurrentMode;		// 0x1858: the mode the booter set
    boot_vbe_mode	vbeModes[BOOT_VBE_MAX_MODES];	// 0x1870
    char   _reserved2[16];		// 8392 .. 8408, keeps `video` at 8408

    boot_video video;

    PCI_bus_info_t pciInfo;
    
    int	    eisaConfigFunctions;
    EISA_slot_info_t eisaSlotInfo[NUM_EISA_SLOTS];// EISA slot information

    char   config[CONFIG_SIZE];		// the config file contents
} KERNBOOTSTRUCT;

#define __KBS_OFF(f)	((unsigned long)&((KERNBOOTSTRUCT *)0)->f)
typedef char __kbs_vbe_mode_size[(sizeof (boot_vbe_mode) == 24) ? 1 : -1];
typedef char __kbs_vbe_fb[(__KBS_OFF(vbeFrameBuffer) == 0x1854) ? 1 : -1];
typedef char __kbs_vbe_current[(__KBS_OFF(vbeCurrentMode) == 0x1858) ? 1 : -1];
typedef char __kbs_vbe_modes[(__KBS_OFF(vbeModes) == 0x1870) ? 1 : -1];
typedef char __kbs_video[(__KBS_OFF(video) == 8408) ? 1 : -1];

#define GRAPHICS_MODE	1
#define TEXT_MODE 0

#define KERNSTRUCT_ADDR ((KERNBOOTSTRUCT *)0x11000)
#define KERNBOOTMAGIC 0xa7a7a7a7

#ifndef EISA_CONFIG_ADDR
#define EISA_CONFIG_ADDR	0x20000
#define EISA_CONFIG_LEN		0x10000
#endif

#ifndef KERNEL
extern KERNBOOTSTRUCT *kernBootStruct;
#endif
