/*
 * E100Hw.h - register-level access to the 8255x.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * io is the base of the I/O BAR. Functions returning int give 1 for
 * success and 0 for a timeout unless noted.
 */
#ifndef E100HW_H
#define E100HW_H

int e100WaitScb(unsigned int io);
int e100ScbCommand(unsigned int io, unsigned char command);
int e100ScbCommandPtr(unsigned int io, unsigned char command,
                      unsigned long pointer);
int e100CuResume(unsigned int io, int nopFirst);
int e100WaitCuIdle(unsigned int io);
void e100PortCommand(unsigned int io, unsigned long opcode);
int e100WaitCB(const volatile unsigned short *status, int loops);

/* Address width in bits (6 or 8), or 0 when no EEPROM answers. */
int e100EepromAddressBits(unsigned int io);
unsigned short e100EepromRead(unsigned int io, int addressBits, int word);

/* The register value, or -1 when the MDI never reports ready. */
int e100MdiRead(unsigned int io, int phy, int reg);
int e100MdiWrite(unsigned int io, int phy, int reg, unsigned short value);

#endif
