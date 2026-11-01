/*
 * E100Port.h - port I/O and delay for E100Hw.c and IntelE100.m.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * In the kernel these are DriverKit's inline port instructions and
 * IODelay. tests/ builds with -DE100_HOST_TEST, which swaps in a
 * simulated device (tests/e100_test_ports.h).
 */
#ifndef E100PORT_H
#define E100PORT_H

#ifdef E100_HOST_TEST
#include "e100_test_ports.h"
#else
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#define E100_INB(p)             inb((IOEISAPortAddress)(p))
#define E100_INW(p)             inw((IOEISAPortAddress)(p))
#define E100_INL(p)             inl((IOEISAPortAddress)(p))
#define E100_OUTB(p, v)         outb((IOEISAPortAddress)(p), (v))
#define E100_OUTW(p, v)         outw((IOEISAPortAddress)(p), (v))
#define E100_OUTL(p, v)         outl((IOEISAPortAddress)(p), (v))
#define E100_DELAY(us)          IODelay(us)
#endif

#endif
