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
 * Copyright 1996 1995 by Open Software Foundation, Inc. 1997 1996 1995 1994 1993 1992 1991
 *              All Rights Reserved
 *
 * Permission to use, copy, modify, and distribute this software and
 * its documentation for any purpose and without fee is hereby granted,
 * provided that the above copyright notice appears in all copies and
 * that both the copyright notice and this permission notice appear in
 * supporting documentation.
 *
 * OSF DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE.
 *
 * IN NO EVENT SHALL OSF BE LIABLE FOR ANY SPECIAL, INDIRECT, OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN ACTION OF CONTRACT,
 * NEGLIGENCE, OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
 * WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#ifndef KEYLARGO_BINDING_HOST_TEST
#include <mach/boolean.h>
#include <kern/lock.h>
#include <mach/clock_types.h>
#include <machdep/ppc/DeviceTree.h>
#include <sys/systm.h>

#ifndef NULL
#define	NULL	((void *) 0)	/* lion@apple.com 2/12/97 */
#endif

#include <machdep/ppc/proc_reg.h>
#include <powermac.h>
#include <interrupts.h>
#include <chips/keylargo.h>
#endif
#include "keylargo_audio.h"
#include "davbus_audio.h"
#include "keylargo_discovery.h"

extern void read_processor_clock_tval(tvalspec_t *time);

typedef struct {
  unsigned int macIOBase;
  unsigned int macIOSize;
  unsigned int i2cOffset;
  unsigned int addressStep;
  unsigned int i2cRate;
  unsigned char i2cSpeed;
  lock_data_t lock;
  PEKeyLargoTransport transport;
  PEDAVBusTransport davbus;
  unsigned int audioMuxOwner;
  unsigned int davbusSaved;
  unsigned int davbusActive;
} keylargo_audio_state_t;

static keylargo_audio_state_t keylargo_audio_state;

static PEKeyLargoProperty
keylargo_property(DTEntry entry, const char *name)
{
  PEKeyLargoProperty property;
  void *bytes;
  int size;

  property.bytes = 0;
  property.size = 0;
  if (DTGetProperty(entry, name, &bytes, &size) == kSuccess) {
    property.bytes = (const unsigned char *)bytes;
    property.size = size < 0 ? ~0u : (unsigned int)size;
  }
  return property;
}

static boolean_t
keylargo_string_property_is(DTEntry entry, const char *name,
  const char *expected)
{
  PEKeyLargoProperty property;
  unsigned int length;

  property = keylargo_property(entry, name);
  length = strlen(expected) + 1;
  return property.bytes != 0 && property.size == length &&
    strcmp((const char *)property.bytes, expected) == 0;
}

boolean_t
PEKeyLargoGetMacIOInfo(unsigned int *base, unsigned int *size)
{
  DTEntry macIO;

  if (base == 0 || size == 0 ||
    DTFindEntry("device_type", "mac-io", &macIO) != kSuccess)
    return FALSE;
  return PEKeyLargoParseMacIO(keylargo_property(macIO, "AAPL,address"),
    keylargo_property(macIO, "assigned-addresses"),
    keylargo_property(macIO, "reg"), base, size) ? TRUE : FALSE;
}

/*
 * Runs from configure_machine, before kalloc_init(), so no entry
 * iterator: those kalloc, and freeing one then lands in an uninitialised
 * kmem_free.
 */
static boolean_t
keylargo_find_i2c(DTEntry macIO, DTEntry *i2c)
{
  return DTFindChildEntry(macIO, "name", "i2c", i2c) == kSuccess ||
    DTFindChildEntry(macIO, "device_type", "i2c", i2c) == kSuccess;
}

static unsigned char
keylargo_read8(void *context, unsigned int offset)
{
  keylargo_audio_state_t *state;
  volatile unsigned char *address;

  state = (keylargo_audio_state_t *)context;
  address = (volatile unsigned char *)POWERMAC_IO(state->macIOBase +
    state->i2cOffset + offset * state->addressStep);
  return *address;
}

static void
keylargo_write8(void *context, unsigned int offset, unsigned char value)
{
  keylargo_audio_state_t *state;
  volatile unsigned char *address;

  state = (keylargo_audio_state_t *)context;
  address = (volatile unsigned char *)POWERMAC_IO(state->macIOBase +
    state->i2cOffset + offset * state->addressStep);
  *address = value;
  eieio();
}

static unsigned char
keylargo_read_gpio8(void *context, unsigned int offset)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  return *(volatile unsigned char *)POWERMAC_IO(state->macIOBase + offset);
}

static void
keylargo_write_gpio8(void *context, unsigned int offset,
  unsigned char value)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  *(volatile unsigned char *)POWERMAC_IO(state->macIOBase + offset) = value;
  eieio();
}

static unsigned int
keylargo_read_fcr1(void *context)
{
  keylargo_audio_state_t *state;
  unsigned int value;

  state = (keylargo_audio_state_t *)context;
  eieio();
  value = lwbrx(POWERMAC_IO(state->macIOBase + KEYLARGO_FCR1_OFFSET));
  sync();
  return value;
}

static void
keylargo_write_fcr1(void *context, unsigned int value)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  stwbrx(value, POWERMAC_IO(state->macIOBase + KEYLARGO_FCR1_OFFSET));
  eieio();
  sync();
}

static void
keylargo_get_time(void *context, tvalspec_t *now)
{
  (void)context;
  read_processor_clock_tval(now);
}

static int
keylargo_compare_time(void *context, const tvalspec_t *left,
  const tvalspec_t *right)
{
  (void)context;
  if (left->tv_sec != right->tv_sec)
    return left->tv_sec < right->tv_sec ? -1 : 1;
  if (left->tv_nsec == right->tv_nsec)
    return 0;
  return left->tv_nsec < right->tv_nsec ? -1 : 1;
}

static kern_return_t
keylargo_transfer_status(void *context)
{
  (void)context;
  /* Published KeyWest status bits provide no arbitration-loss signal. */
  return KERN_SUCCESS;
}

static void
keylargo_lock(void *context)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  lock_write(&state->lock);
}

static void
keylargo_unlock(void *context)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  lock_done(&state->lock);
}

static boolean_t
keylargo_in_interrupt(void *context)
{
  (void)context;
  return PEIsInInterruptContext();
}

static boolean_t
keylargo_valid_offset(void *context, unsigned int offset,
  unsigned int length)
{
  keylargo_audio_state_t *state;

  state = (keylargo_audio_state_t *)context;
  return PEKeyLargoRangeContains(state->macIOSize, offset, length) ?
    TRUE : FALSE;
}

static kern_return_t
keylargo_davbus_write(void *context, unsigned int value)
{
  keylargo_audio_state_t *state;
  unsigned int offset;

  state = (keylargo_audio_state_t *)context;
  offset = state->davbus.family == kPEDAVBusPaddington ?
    0x38 : KEYLARGO_FCR1_OFFSET;
  stwbrx(value, POWERMAC_IO(state->macIOBase + offset));
  eieio();
  sync();
  return KERN_SUCCESS;
}

static unsigned int
keylargo_davbus_read(void *context)
{
  keylargo_audio_state_t *state;
  unsigned int offset;
  unsigned int value;

  state = (keylargo_audio_state_t *)context;
  offset = state->davbus.family == kPEDAVBusPaddington ?
    0x38 : KEYLARGO_FCR1_OFFSET;
  eieio();
  value = lwbrx(POWERMAC_IO(state->macIOBase + offset));
  sync();
  return value;
}

static void
keylargo_davbus_barrier(void *context)
{
  (void)context;
  eieio();
  sync();
}

static void
keylargo_bind_davbus(DTEntry macIO)
{
  unsigned long index;
  DTEntry child;
  PEKeyLargoProperty property;
  unsigned int controller;
  unsigned int family;
  unsigned int vendor;
  unsigned int device;
  unsigned int cells;
  unsigned int matches;
  PEDAVBusTransport *transport;

  if (!PEKeyLargoCellProperty(keylargo_property(macIO, "vendor-id"),
    &vendor) || !PEKeyLargoCellProperty(
    keylargo_property(macIO, "device-id"), &device))
    return;
  family = PEDAVBusFamilyForMacIO(vendor, device);
  if (family == 0 ||
    (family == kPEDAVBusPaddington ?
    powermac_info.class != POWERMAC_CLASS_YOSEMITE :
    powermac_info.class != POWERMAC_CLASS_SAWTOOTH))
    return;
  if (!PEKeyLargoCellProperty(keylargo_property(macIO, "#address-cells"),
    &cells) || cells != 1 ||
    !PEKeyLargoCellProperty(keylargo_property(macIO, "#size-cells"),
    &cells) || cells != 1)
    return;
  property = keylargo_property(macIO, "ranges");
  if (!PEDAVBusValidateMacIORanges(property.bytes, property.size,
    keylargo_audio_state.macIOBase, keylargo_audio_state.macIOSize))
    return;
  /* Runs from configure_machine, before kalloc_init(): no DT iterator. */
  index = 0;
  matches = 0;
  controller = 0;
  while (DTIterateChildren(macIO, &index, &child) == kSuccess) {
    if (!keylargo_string_property_is(child, "name", "davbus") &&
      !keylargo_string_property_is(child, "name", "awacs"))
      continue;
    ++matches;
    property = keylargo_property(child, "reg");
    if (!PEDAVBusValidateRanges(property.bytes, property.size,
      keylargo_audio_state.macIOBase, keylargo_audio_state.macIOSize,
      &controller)) {
      matches = 2;
      break;
    }
  }
  if (matches != 1 || controller !=
    (unsigned int)powermac_io_info.audio_base_phys)
    return;
  transport = &keylargo_audio_state.davbus;
  transport->context = &keylargo_audio_state;
  transport->controllerBase = controller;
  transport->family = family;
  transport->owner = &keylargo_audio_state.audioMuxOwner;
  transport->saved = &keylargo_audio_state.davbusSaved;
  transport->active = &keylargo_audio_state.davbusActive;
  transport->readFCR1 = keylargo_davbus_read;
  transport->writeFCR1 = keylargo_davbus_write;
  transport->lock = keylargo_lock;
  transport->unlock = keylargo_unlock;
  transport->barrier = keylargo_davbus_barrier;
  transport->inInterruptContext = keylargo_in_interrupt;
  transport->readGPIO = keylargo_read_gpio8;
  transport->writeGPIO = keylargo_write_gpio8;
  PEDAVBusBindTransport(transport);
}

static boolean_t
keylargo_prepare_audio(DTEntry *macIO)
{
  unsigned int base;
  unsigned int size;

  PEKeyLargoBindTransport(0);
  PEDAVBusBindTransport(0);
  keylargo_audio_state.davbus.family = 0;
  if (DTFindEntry("device_type", "mac-io", macIO) != kSuccess ||
    !PEKeyLargoGetMacIOInfo(&base, &size) ||
    base != (unsigned int)powermac_io_info.io_base_phys ||
    size != (unsigned int)powermac_io_info.io_size)
    return FALSE;
  keylargo_audio_state.macIOBase = base;
  keylargo_audio_state.macIOSize = size;
  lock_init(&keylargo_audio_state.lock, TRUE);
  return TRUE;
}

kern_return_t
PEHeathrowDAVBusInitialize(void)
{
  DTEntry macIO;

  if (!keylargo_prepare_audio(&macIO))
    return KERN_PE_KEYLARGO_NOT_READY;
  if (powermac_info.class != POWERMAC_CLASS_YOSEMITE)
    return KERN_PE_KEYLARGO_NOT_READY;
  keylargo_bind_davbus(macIO);
  return keylargo_audio_state.davbus.family == kPEDAVBusPaddington ?
    KERN_SUCCESS : KERN_PE_KEYLARGO_NOT_READY;
}

kern_return_t
PEKeyLargoInitialize(void)
{
  DTEntry macIO;
  DTEntry i2c;
  PEKeyLargoDiscoveryInput input;
  PEKeyLargoDiscovery discovery;
  PEKeyLargoProperty device;

  if (!keylargo_prepare_audio(&macIO))
    return KERN_PE_KEYLARGO_NOT_READY;
  device = keylargo_property(macIO, "device-id");
  if (device.bytes != 0 && device.size == 4 &&
    (PEKeyLargoCell(device.bytes) == 0x10 ||
    PEKeyLargoCell(device.bytes) == 0x17))
    return KERN_PE_KEYLARGO_NOT_READY;
  keylargo_bind_davbus(macIO);
  if (!keylargo_find_i2c(macIO, &i2c))
    return KERN_PE_KEYLARGO_NOT_READY;
  bzero(&input, sizeof(input));
  input.macIOBase = keylargo_audio_state.macIOBase;
  input.macIOSize = keylargo_audio_state.macIOSize;
  input.reg = keylargo_property(i2c, "reg");
  input.absoluteAddress = keylargo_property(i2c, "AAPL,address");
  input.addressStep = keylargo_property(i2c, "AAPL,address-step");
  input.rate = keylargo_property(i2c, "AAPL,i2c-rate");
  if (!PEKeyLargoParseDiscovery(&input, &discovery))
    return KERN_PE_KEYLARGO_NOT_READY;

  keylargo_audio_state.i2cOffset = discovery.i2cOffset;
  keylargo_audio_state.addressStep = discovery.addressStep;
  keylargo_audio_state.i2cRate = discovery.rate;
  keylargo_audio_state.i2cSpeed = (unsigned char)discovery.speed;
  keylargo_audio_state.transport.context = &keylargo_audio_state;
  keylargo_audio_state.transport.audioMuxOwner =
    &keylargo_audio_state.audioMuxOwner;
  keylargo_audio_state.transport.speed = keylargo_audio_state.i2cSpeed;
  keylargo_audio_state.transport.read8 = keylargo_read8;
  keylargo_audio_state.transport.write8 = keylargo_write8;
  keylargo_audio_state.transport.readGPIO8 = keylargo_read_gpio8;
  keylargo_audio_state.transport.writeGPIO8 = keylargo_write_gpio8;
  keylargo_audio_state.transport.readFCR1LE = keylargo_read_fcr1;
  keylargo_audio_state.transport.writeFCR1LE = keylargo_write_fcr1;
  keylargo_audio_state.transport.getTime = keylargo_get_time;
  keylargo_audio_state.transport.compareTime = keylargo_compare_time;
  keylargo_audio_state.transport.transferStatus = keylargo_transfer_status;
  keylargo_audio_state.transport.lock = keylargo_lock;
  keylargo_audio_state.transport.unlock = keylargo_unlock;
  keylargo_audio_state.transport.inInterruptContext =
    keylargo_in_interrupt;
  keylargo_audio_state.transport.validOffset = keylargo_valid_offset;
  PEKeyLargoBindTransport(&keylargo_audio_state.transport);
  return KERN_SUCCESS;
}

#ifndef KEYLARGO_BINDING_HOST_TEST
/* DBDMA Channel Map for KeyLargo */
powermac_dbdma_channels_t keylargo_dbdma_channels =
{ -1,      // KeyLargo does not have Curio
  0x00,    // Mesh (SCSI)
  0x01,    // Floppy
  0x02,    // Ethernet Transmit
  0x03,    // Ethernet Receive
  0x04,    // SCC Channel A Transmit
  0x05,    // SCC Channel A Receive
  0x06,    // SCC Channel B Transmit
  0x07,    // SCC Channel B Receive
  0x08,    // Audio Out
  0x09,    // Audio In
  0x0A,    // IDE 0
  0x0B,    // IDE 1
};
#endif
