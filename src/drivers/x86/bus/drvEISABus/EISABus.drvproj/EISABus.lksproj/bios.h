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
 * bios.h
 * BIOS Call Utilities
 */

#ifndef _BIOS_H_
#define _BIOS_H_

#include <driverkit/i386/ioPorts.h>

/* Registers */
#define PNP_READPORT			0x00
#define PNP_SERIALISOLATION 	0x01
#define PNP_CONFIGCONTROL		0x02
#define PNP_WAKE			    0x03
#define PNP_RESOURCEDATA		0x04
#define PNP_STATUS          	0x05
#define PNP_CARDSELECTNUMBER	0x06
#define PNP_LOGICALDEVICENUMBER	0x07
#define PNP_ACTIVATE			0x30
#define PNP_IORANGECHECK		0x31
#define PNP_IOBASE(n)		    ( 0x60 + ( (n) * 2 ) )
#define PNP_IRQNO(n)			( 0x70 + ( (n) * 2 ) )
#define PNP_IRQTYPE(n)		    ( 0x71 + ( (n) * 2 ) )

/* Bits in the CONFIGCONTROL register */
#define PNP_CONFIG_RESET		( 1 << 0 )
#define PNP_CONFIG_WAIT_FOR_KEY	( 1 << 1 )
#define PNP_CONFIG_RESET_CSN	( 1 << 2 )
#define PNP_CONFIG_RESET_DRV	( PNP_CONFIG_RESET | PNP_CONFIG_WAIT_FOR_KEY | PNP_CONFIG_RESET_CSN )

/* Port addresses */
#define PNP_ADDRESS		        0x279
#define PNP_WRITE_DATA	        0xa79
#define PNP_READ_PORT_MIN	    0x203
#define PNP_READ_PORT_MAX	    0x3ff
#define PNP_READ_PORT_STEP	    0x10 /* Can be any multiple of 4 according to the spec, but since ISA I/O addresses are allocated in blocks of 16, it makes no sense to use any value less than 16. */

/* The LFSR seed used for the initiation key and for checksumming */
#define PNP_LFSR_SEED           0x6a

/*
 * Construct a vendor ID from three ASCII characters
 *
 */
#define ISA_VENDOR(a,b,c)	(((((a)-'A'+1)&0x3f)<<2)| \
                            ((((b)-'A'+1)&0x18)>>3)|((((b)-'A'+1)&7)<<13)| \
                            ((((c)-'A'+1)&0x1f)<<8))
#define PNP_VENDOR(a,b,c)	ISA_VENDOR(a,b,c)

extern unsigned short pnpReadPort; /* PnP read port */

static inline void pnp_write_address ( unsigned char address ) {
	outb ( address, PNP_ADDRESS );
}

static inline void pnp_write_data ( unsigned char data ) {
	outb ( data, PNP_WRITE_DATA );
}

static inline unsigned char pnp_read_data ( void ) {
	return inb ( pnpReadPort );
}

static inline void pnp_write_byte ( unsigned char address, unsigned char value ) {
	pnp_write_address ( address );
	pnp_write_data ( value );
}

static inline unsigned char pnp_read_byte ( unsigned char address ) {
	pnp_write_address ( address );
	return pnp_read_data ();
}

static inline unsigned short pnp_read_word ( unsigned char address ) {
	/* Yes, they're in big-endian order */
	return ( ( pnp_read_byte ( address ) << 8 ) + pnp_read_byte ( address + 1 ) );
}

/** Inform cards of a new read port address */
static inline void pnp_set_read_port ( void ) {
	pnp_write_byte ( PNP_READPORT, pnpReadPort >> 2 );
}

/**
 * Enter the Isolation state.
 *
 * Only cards currently in the Sleep state will respond to this
 * command.
 *
 */
 static inline void pnp_serialisolation ( void ) {
	pnp_write_address ( PNP_SERIALISOLATION );
}

/**
 * Enter the Wait for Key state.
 *
 * All cards will respond to this command, regardless of their current
 * state.
 *
 */
 static inline void pnp_wait_for_key ( void ) {
	pnp_write_byte ( PNP_CONFIGCONTROL, PNP_CONFIG_WAIT_FOR_KEY );
}

/**
 * Reset (i.e. remove) Card Select Number.
 *
 * Only cards currently in the Sleep state will respond to this
 * command.
 *
 */
static inline void pnp_reset_csn ( void ) {
	pnp_write_byte ( PNP_CONFIGCONTROL, PNP_CONFIG_RESET_CSN );
}

/**
 * Perform a Global Software Reset.
 *
 * This forces all PnP cards to their default state, clearing CSNs
 * and Deactivating logical devices. Essential if BIOS has already run.
 *
 */
 static inline void pnp_reset_all_cards ( void ) {
    /* Send 0x07 to Register 0x02 (Reset All Cards) */
    pnp_write_byte ( PNP_CONFIGCONTROL, PNP_CONFIG_RESET_DRV );
}

/**
 * Place a specified card into the Config state.
 *
 * @v csn		Card Select Number
 *
 * Only cards currently in the Sleep, Isolation, or Config states will
 * respond to this command.  The card that has the specified CSN will
 * enter the Config state, all other cards will enter the Sleep state.
 *
 */
 static inline void pnp_wake ( unsigned char csn ) {
	pnp_write_byte ( PNP_WAKE, csn );
}

static inline unsigned char pnp_read_resourcedata ( void ) {
	return pnp_read_byte ( PNP_RESOURCEDATA );
}

static inline unsigned char pnp_read_status ( void ) {
	return pnp_read_byte ( PNP_STATUS );
}

/**
 * Assign a Card Select Number to a card, and enter the Config state.
 *
 * @v csn		Card Select Number
 *
 * Only cards in the Isolation state will respond to this command.
 * The isolation protocol is designed so that only one card will
 * remain in the Isolation state by the time the isolation protocol
 * completes.
 *
 */
static inline void pnp_write_csn ( unsigned char csn ) {
	pnp_write_byte ( PNP_CARDSELECTNUMBER, csn );
}

static inline void pnp_logicaldevice ( unsigned char logdev ) {
	pnp_write_byte ( PNP_LOGICALDEVICENUMBER, logdev );
}

static inline void pnp_activate ( unsigned char logdev ) {
	pnp_logicaldevice ( logdev );
	pnp_write_byte ( PNP_ACTIVATE, 1 );
}

static inline void pnp_deactivate ( unsigned char logdev ) {
	pnp_logicaldevice ( logdev );
	pnp_write_byte ( PNP_ACTIVATE, 0 );
}

static inline unsigned short pnp_read_iobase ( unsigned int index ) {
	return pnp_read_word ( PNP_IOBASE ( index ) );
}

static inline unsigned char pnp_read_irqno ( unsigned int index ) {
	return pnp_read_byte ( PNP_IRQNO ( index ) );
}

/**
 * Linear feedback shift register.
 *
 * @v lfsr		Current value of the LFSR
 * @v input_bit		Current input bit to the LFSR
 * @ret lfsr		Next value of the LFSR
 *
 * This routine implements the linear feedback shift register as
 * described in Appendix B of the PnP ISA spec.  The hardware
 * implementation uses eight D-type latches and two XOR gates.
 *
 */
 static inline unsigned char pnp_lfsr_next ( unsigned char lfsr, int input_bit ) {
	register unsigned char lfsr_next;

	lfsr_next = lfsr >> 1;
	lfsr_next |= ( ( ( lfsr ^ lfsr_next ) ^ input_bit ) ) << 7;
	return lfsr_next;
}

/**
 * Byte swap a 16-bit value.
 *
 * @v value		16-bit value to byte swap
 * @ret swapped		Byte-swapped value
 *
 * Swaps the high and low bytes of a 16-bit value.
 * For example, 0x1234 becomes 0x3412.
 *
 */
static inline unsigned short bswap_16 ( unsigned short value ) {
	return ( ( value >> 8 ) | ( value << 8 ) );
}

/*
 * An PnP serial identifier
 *
 */
 #pragma pack(1)
 struct pnp_identifier {
	unsigned short vendor_id;
	unsigned short prod_id;
	unsigned int serial;
	unsigned char checksum;
};
#pragma pack()

/*
 * x86 GDT Descriptor Structure
 * Standard Intel x86 segment descriptor format (8 bytes)
 * Used for manipulating Global Descriptor Table entries
 */
#pragma pack(1)
struct real_descriptor {
    unsigned short limit_low;       /* Segment limit bits 0-15 */
    unsigned short base_low;        /* Base address bits 0-15 */
    unsigned char base_med;         /* Base address bits 16-23 */
    unsigned char access;           /* Access byte (P, DPL, S, Type) */
    unsigned char granularity;      /* Granularity/flags (G, D/B, L, AVL, limit 16-19) */
    unsigned char base_high;        /* Base address bits 24-31 */
};
#pragma pack()

/*
 * BIOS call structure for register passing
 * Used by __bios32PnP for structure-based BIOS calls
 * Total size: 48 bytes (0x30)
 * Field offsets match biospnp.s structure layout
 */
typedef struct {
    unsigned int intno;                     /* +0x00: Interrupt/function number */
    unsigned int eax;                       /* +0x04: EAX register value */
    unsigned int ebx;                       /* +0x08: EBX register value */
    unsigned int ecx;                       /* +0x0C: ECX register value */
    unsigned int edx;                       /* +0x10: EDX register value */
    unsigned int edi;                       /* +0x14: EDI register value */
    unsigned int esi;                       /* +0x18: ESI register value */
    unsigned int ebp;                       /* +0x1C: EBP register value */
    unsigned short cs;                      /* +0x20: CS segment selector */
    unsigned short ds;                      /* +0x22: DS segment selector */
    unsigned short es;                      /* +0x24: ES segment selector */
    unsigned short pad;                     /* +0x26: Padding for alignment */
    unsigned int flags;                     /* +0x28: FLAGS register value */
    unsigned int addr;                      /* +0x2C: Far call address/offset */
} BIOSCallStruct;

/*
 * Global variables for BIOS operations
 */
extern char verbose;                             /* Verbose logging flag */
extern void *bios32PnP_ptr;                      /* BIOS32 PnP entry point function pointer */
extern unsigned short kernDataSel;               /* Kernel data segment selector */

/*
 * PnP BIOS call wrapper
 *
 * Calls the BIOS32 PnP entry point with a pointer to a BIOSCallStruct.
 * The BIOS writes its return code to the eax field of the structure.
 *
 * @param bb  Pointer to BIOSCallStruct containing BIOS call parameters
 * @return    BIOS return code from bb->eax
 */
extern int call_bios(BIOSCallStruct *bb);

/*
 * Clear all PnP configuration registers
 * Writes zero to all PnP config registers
 */
void clearPnPConfigRegisters(void);

/*
 * Convert a PnP vendor and product ID to a string
 *
 * @param vendor		PnP vendor ID
 * @param product		PnP product ID
 * @ret string		String representation of the PnP ID
 */
char * pnp_id_string(unsigned short vendor, unsigned short product);

#endif /* _BIOS_H_ */
