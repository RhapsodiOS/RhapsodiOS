/*
 * E100Hw.c - register-level access to the 8255x: SCB commands, PORT, the
 * microwire EEPROM and the MDI. Every access goes through the macros in
 * E100Port.h, so tests/ runs this against a simulated device.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 */
#include "E100Regs.h"
#include "E100Hw.h"
#include "E100Port.h"

#define SCB_WAIT_LOOPS  10000   /* x 2 us = 20 ms, what FreeBSD allows    */
#define CU_IDLE_LOOPS   500     /* x 2 us = 1 ms                          */
#define MDI_WAIT_LOOPS  1000    /* x 10 us = 10 ms                        */
#define EE_PHASE_US     4       /* SK at least 4 us each way (SDM 6.3.4)  */

/* The SCB command byte reads 0 once the chip has accepted a command. */
int
e100WaitScb(unsigned int io)
{
    int i;

    for (i = 0; i < SCB_WAIT_LOOPS; i++) {
        if (E100_INB(io + E100_SCB_CMD) == 0)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

int
e100ScbCommand(unsigned int io, unsigned char command)
{
    if (!e100WaitScb(io))
        return 0;
    E100_OUTB(io + E100_SCB_CMD, command);
    return 1;
}

int
e100ScbCommandPtr(unsigned int io, unsigned char command, unsigned long pointer)
{
    if (!e100WaitScb(io))
        return 0;
    E100_OUTL(io + E100_SCB_GENPTR, pointer);
    E100_OUTB(io + E100_SCB_CMD, command);
    return 1;
}

/*
 * CU Resume, optionally preceded by a CU NOP. The NOP is FreeBSD's
 * workaround for Intel 82801BA erratum 30 (if_fxp.c, fxp_scb_cmd): with
 * Dynamic Standby enabled in the EEPROM, a resume that arrives as the chip
 * drops into standby can violate the PCI protocol.
 */
int
e100CuResume(unsigned int io, int nopFirst)
{
    if (!e100WaitScb(io))
        return 0;
    if (nopFirst) {
        E100_OUTB(io + E100_SCB_CMD, E100_CUC_NOP);
        if (!e100WaitScb(io))
            return 0;
    }
    E100_OUTB(io + E100_SCB_CMD, E100_CUC_RESUME);
    return 1;
}

int
e100WaitCuIdle(unsigned int io)
{
    int i;

    for (i = 0; i < CU_IDLE_LOOPS; i++) {
        if ((E100_INB(io + E100_SCB_STATUS) & E100_CUS_MASK) == 0)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

void
e100PortCommand(unsigned int io, unsigned long opcode)
{
    E100_OUTL(io + E100_PORT, opcode);
    /* SDM 6.2: leave the SCB alone for 10 system plus 5 transmit clocks,
     * about 10 us; FreeBSD waits 50 after a reset. */
    E100_DELAY(50);
}

int
e100WaitCB(const volatile unsigned short *status, int loops)
{
    while (loops-- > 0) {
        if (*status & E100_CB_C)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

/* --- microwire EEPROM (SDM 6.3.4) ------------------------------------ */

static void
eeOut(unsigned int io, int bit)
{
    unsigned short v = (unsigned short)(E100_EE_CS | (bit ? E100_EE_DI : 0));

    E100_OUTW(io + E100_EECTL, v);
    E100_DELAY(EE_PHASE_US);
    E100_OUTW(io + E100_EECTL, (unsigned short)(v | E100_EE_SK));
    E100_DELAY(EE_PHASE_US);
    E100_OUTW(io + E100_EECTL, v);
    E100_DELAY(EE_PHASE_US);
}

static int
eeIn(unsigned int io)
{
    int bit;

    E100_OUTW(io + E100_EECTL, E100_EE_CS | E100_EE_SK);
    E100_DELAY(EE_PHASE_US);
    bit = (E100_INW(io + E100_EECTL) & E100_EE_DO) ? 1 : 0;
    E100_OUTW(io + E100_EECTL, E100_EE_CS);
    E100_DELAY(EE_PHASE_US);
    return bit;
}

static void
eeStartRead(unsigned int io)
{
    int i;

    E100_OUTW(io + E100_EECTL, E100_EE_CS);
    E100_DELAY(EE_PHASE_US);
    for (i = 2; i >= 0; i--)
        eeOut(io, (E100_EE_OP_READ >> i) & 1);
}

static void
eeStop(unsigned int io)
{
    E100_OUTW(io + E100_EECTL, 0);
    E100_DELAY(EE_PHASE_US);
}

/*
 * SDM 6.3.4.2: after a read opcode, clock address zeros until the part
 * drives its dummy zero on EEDO; the number clocked is the address width.
 */
int
e100EepromAddressBits(unsigned int io)
{
    int bits, i, found = 0;

    eeStartRead(io);
    for (bits = 1; bits <= 8; bits++) {
        eeOut(io, 0);
        if ((E100_INW(io + E100_EECTL) & E100_EE_DO) == 0) {
            found = bits;
            break;
        }
    }
    for (i = 0; i < 16; i++)
        (void)eeIn(io);
    eeStop(io);
    return found;
}

unsigned short
e100EepromRead(unsigned int io, int addressBits, int word)
{
    unsigned short data = 0;
    int i;

    eeStartRead(io);
    for (i = addressBits - 1; i >= 0; i--)
        eeOut(io, (word >> i) & 1);
    for (i = 0; i < 16; i++)
        data = (unsigned short)((data << 1) | eeIn(io));
    eeStop(io);
    return data;
}

/* --- MDI (SDM 6.3.5) ------------------------------------------------- */

static int
mdiWait(unsigned int io, unsigned long *value)
{
    int i;

    for (i = 0; i < MDI_WAIT_LOOPS; i++) {
        *value = E100_INL(io + E100_MDICTL);
        if (*value & E100_MDI_READY)
            return 1;
        E100_DELAY(10);
    }
    return 0;
}

int
e100MdiRead(unsigned int io, int phy, int reg)
{
    unsigned long v;

    E100_OUTL(io + E100_MDICTL, E100_MDI_OP_READ
              | ((unsigned long)phy << E100_MDI_PHY_SHIFT)
              | ((unsigned long)reg << E100_MDI_REG_SHIFT));
    if (!mdiWait(io, &v))
        return -1;
    return (int)(v & 0xFFFFUL);
}

int
e100MdiWrite(unsigned int io, int phy, int reg, unsigned short value)
{
    unsigned long v;

    E100_OUTL(io + E100_MDICTL, E100_MDI_OP_WRITE
              | ((unsigned long)phy << E100_MDI_PHY_SHIFT)
              | ((unsigned long)reg << E100_MDI_REG_SHIFT)
              | (unsigned long)value);
    return mdiWait(io, &v);
}
