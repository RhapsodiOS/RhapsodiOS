/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * WD83C584 Bus Interface Chip.
 *
 * HISTORY
 *
 * Mar 1998
 *	Created for SMCUltra driver.
 */

/*
 * Memory select register.
 */

#define BIC_MSR_OFF		0x00

typedef struct {
    unsigned char	madr	:6,
    			menb	:1,
			rst	:1;
} bic_msr_t;

/*
 * Interface configuration register.
 */

#define BIC_ICR_OFF		0x01

typedef struct {
    unsigned char	bus16	:1,
    			ora	:1,
#define BIC_ACCESS_BIO	0
#define BIC_ACCESS_EAR	1
    			ir2	:1,
#define ICR_IR2_9	0x00
#define ICR_IR2_3	0x00
#define ICR_IR2_5	0x00
#define ICR_IR2_7	0x00
#define ICR_IR2_10	0x01
#define ICR_IR2_11	0x01
#define ICR_IR2_15	0x01
#define ICR_IR2_4	0x01
			msz	:1,
			rla	:1,
			rx7	:1,
			rio	:1,
			sto	:1;
} bic_icr_t;

/*
 * IO Address register.
 */

#define BIC_IAR_OFF		0x02

typedef struct {
    unsigned char	adrlo	:5,
    			adrhi	:3;
} bic_iar_t;

/*
 * BIOS ROM Address register.
 */

#define BIC_BIO_OFF		0x03

typedef struct {
    unsigned char	swint	:1,
    			bioadr	:5,
			biosz	:2;
#define BIC_NO_BIOS	0x00
#define BIC_BIOS_16K	0x01
#define BIC_BIOS_32K	0x02
#define BIC_BIOS_64K	0x03
} bic_bio_t;

/*
 * EEROM Address register.
 */

#define BIC_EAR_OFF		0x03

typedef struct {
    unsigned char	rpg	:2,
    			rpe	:1,
			ram	:1,
			eeadr	:4;
} bic_ear_t;

/*
 * Interrupt request register.
 */

#define BIC_IRR_OFF		0x04

typedef struct {
    unsigned char	zws8	:1,
    			out	:3,
			flsh	:1,
			irx	:2,
#define BIC_IRX_9	0x00
#define BIC_IRX_3	0x01
#define BIC_IRX_5	0x02
#define BIC_IRX_7	0x03
#define BIC_IRX_10	0x00
#define BIC_IRX_11	0x01
#define BIC_IRX_15	0x02
#define BIC_IRX_4	0x03
			ien	:1;
} bic_irr_t;

/*
 * LA Address register.
 */

#define BIC_LAAR_OFF		0x05

typedef struct {
    unsigned char	ladr	:5,
    			zws16	:1,
			l16en	:1,
			m16en	:1;
} bic_laar_t;

/*
 * Initialize Jumper register.
 */

#define BIC_JMP_OFF		0x06

typedef struct {
    unsigned char	init0	:1,
    			init1	:1,
			init2	:1,
				:2,
			in1	:1,
			in2	:1,
				:1;
} bic_jmp_t;

/*
 * General Purpose register 2.
 */

#define BIC_GP2_OFF		0x07

/*
 * LAN Address register.
 */

#define BIC_LAR_OFF		0x08
#define BIC_ID_OFF		0x0e
#define BIC_LAR_CKSUM_OFF	0x0f

