/*
 * e100_test_ports.h - the simulated device E100Hw.c talks to under
 * -DE100_HOST_TEST. e100_hw_test.c implements these.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 */
#ifndef E100_TEST_PORTS_H
#define E100_TEST_PORTS_H

unsigned char e100TestInb(unsigned int port);
unsigned short e100TestInw(unsigned int port);
unsigned long e100TestInl(unsigned int port);
void e100TestOutb(unsigned int port, unsigned char value);
void e100TestOutw(unsigned int port, unsigned short value);
void e100TestOutl(unsigned int port, unsigned long value);
void e100TestDelay(unsigned int microseconds);

#define E100_INB(p)             e100TestInb(p)
#define E100_INW(p)             e100TestInw(p)
#define E100_INL(p)             e100TestInl(p)
#define E100_OUTB(p, v)         e100TestOutb((p), (v))
#define E100_OUTW(p, v)         e100TestOutw((p), (v))
#define E100_OUTL(p, v)         e100TestOutl((p), (v))
#define E100_DELAY(us)          e100TestDelay(us)

#endif
