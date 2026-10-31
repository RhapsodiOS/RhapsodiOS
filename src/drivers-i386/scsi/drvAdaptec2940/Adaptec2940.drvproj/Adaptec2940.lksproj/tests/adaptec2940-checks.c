/* Compile and exercise production declarations and routines with I/O shims. */
#include <stdio.h>
#include <string.h>

#import "../Adaptec2940.h"
#import "../SCSIBus.h"

#ifndef A2940_FREESTANDING
struct Adaptec2940InstanceLayout { @defs(Adaptec2940); };
struct SCSIBusInstanceLayout { @defs(SCSIBus); };
#endif

#ifndef A2940_BUILD_HASH
#define A2940_BUILD_HASH "unrecorded"
#endif

#define A2940_TEST_TRACE_CAPACITY 16384

/* The compiler's Objective-C class layout must preserve the IDA offsets. */
#ifndef A2940_FREESTANDING
A2940_LAYOUT_ASSERT(a2940_ivar_ioBase_at_296,
	offsetof(struct Adaptec2940InstanceLayout, ioBase) == 296);
A2940_LAYOUT_ASSERT(a2940_ivar_ioBase_pad_at_298,
	offsetof(struct Adaptec2940InstanceLayout, _pad_ioBase) == 298);
A2940_LAYOUT_ASSERT(a2940_ivar_channel_at_300,
	offsetof(struct Adaptec2940InstanceLayout, channelInfo) == 300);
A2940_LAYOUT_ASSERT(a2940_ivar_host_block_at_308,
	offsetof(struct Adaptec2940InstanceLayout, hspStructSave) == 308);
A2940_LAYOUT_ASSERT(a2940_ivar_host_block_size_at_312,
	offsetof(struct Adaptec2940InstanceLayout, hspStructFreeSize) == 312);
A2940_LAYOUT_ASSERT(a2940_ivar_interrupt_port_at_316,
	offsetof(struct Adaptec2940InstanceLayout, interruptPortKern) == 316);
A2940_LAYOUT_ASSERT(a2940_ivar_command_queue_at_320,
	offsetof(struct Adaptec2940InstanceLayout, commandQ) == 320);
A2940_LAYOUT_ASSERT(a2940_ivar_command_lock_at_328,
	offsetof(struct Adaptec2940InstanceLayout, commandLock) == 328);
A2940_LAYOUT_ASSERT(a2940_ivar_active_queue_at_332,
	offsetof(struct Adaptec2940InstanceLayout, activeQ) == 332);
A2940_LAYOUT_ASSERT(a2940_ivar_scb_queue_at_340,
	offsetof(struct Adaptec2940InstanceLayout, scbQ) == 340);
A2940_LAYOUT_ASSERT(a2940_ivar_scb_queue_length_at_348,
	offsetof(struct Adaptec2940InstanceLayout, scbQLength) == 348);
A2940_LAYOUT_ASSERT(a2940_ivar_bad_scb_queue_at_352,
	offsetof(struct Adaptec2940InstanceLayout, scbBadQ) == 352);
A2940_LAYOUT_ASSERT(a2940_ivar_flags_at_360,
	offsetof(struct Adaptec2940InstanceLayout, reinitChannel) - sizeof(unsigned int) == 360);
A2940_LAYOUT_ASSERT(a2940_ivar_reinit_channel_at_364,
	offsetof(struct Adaptec2940InstanceLayout, reinitChannel) == 364);
A2940_LAYOUT_ASSERT(a2940_ivar_reset_state_at_368,
	offsetof(struct Adaptec2940InstanceLayout, resetState) == 368);
A2940_LAYOUT_ASSERT(a2940_ivar_max_queue_at_372,
	offsetof(struct Adaptec2940InstanceLayout, maxQueueLen) == 372);
A2940_LAYOUT_ASSERT(a2940_ivar_queue_total_at_376,
	offsetof(struct Adaptec2940InstanceLayout, queueLenTotal) == 376);
A2940_LAYOUT_ASSERT(a2940_ivar_total_commands_at_380,
	offsetof(struct Adaptec2940InstanceLayout, totalCommands) == 380);
A2940_LAYOUT_ASSERT(a2940_ivar_outstanding_count_at_384,
	offsetof(struct Adaptec2940InstanceLayout, outstandingCount) == 384);
A2940_LAYOUT_ASSERT(a2940_ivar_bus_type_at_388,
	offsetof(struct Adaptec2940InstanceLayout, busType) == 388);
A2940_LAYOUT_ASSERT(a2940_ivar_level_irq_at_392,
	offsetof(struct Adaptec2940InstanceLayout, levelIRQ) == 392);
A2940_LAYOUT_ASSERT(a2940_ivar_bus_number_at_393,
	offsetof(struct Adaptec2940InstanceLayout, busNumber) == 393);
A2940_LAYOUT_ASSERT(a2940_ivar_device_number_at_394,
	offsetof(struct Adaptec2940InstanceLayout, deviceNumber) == 394);
A2940_LAYOUT_ASSERT(a2940_ivar_function_number_at_395,
	offsetof(struct Adaptec2940InstanceLayout, functionNumber) == 395);
A2940_LAYOUT_ASSERT(a2940_bus_direct_at_580,
	offsetof(struct SCSIBusInstanceLayout, _direct) == 580);
A2940_LAYOUT_ASSERT(a2940_bus_channel_at_584,
	offsetof(struct SCSIBusInstanceLayout, _scsiChannel) == 584);
#endif /* !A2940_FREESTANDING */

static unsigned char sequencer_ram[A2940_SEQ_IMAGE_SIZE];
static unsigned int sequencer_address;
static unsigned int sequencer_writes;
static unsigned int sequencer_reads;
static unsigned int sequencer_barriers;
static int sequencer_fail_read = -1;
static unsigned short sequencer_trace_port[A2940_TEST_TRACE_CAPACITY];
static unsigned char sequencer_trace_value[A2940_TEST_TRACE_CAPACITY];
static unsigned int sequencer_trace_count;
static unsigned char test_registers[256];
static unsigned int pci_config_address;
static unsigned char pci_present[256][32];
static unsigned int pci_config_words[256][32][64];
static unsigned char pci_config_bus;
static unsigned char pci_mech2_enable;
int a2940_test_config_osm_override = -1;
int a2940_test_bus_count_override = -1;
int a2940_test_bus_count_override = -1;
static unsigned int pci_config_reads;
static unsigned int pci_config_writes;
static unsigned int test_read_count;
static int sequencer_script_address = -1;
static unsigned char sequencer_script_value;
static unsigned int abort_callback_calls;
static int abort_callback_index;
static int abort_callback_scb;
static int abort_callback_io;
static unsigned int him_scb_complete_calls;
static int him_completed_scb;
static unsigned int him_bus_reset_calls;
static int him_bus_reset_scb;
static unsigned int him_selection_calls;
static int him_selection_host;
static unsigned int him_selection_id;
static unsigned int him_event_calls;
static int him_event_args[3];
static unsigned int him_post_mark_calls;
static unsigned int him_post_mark_indices[8];
static unsigned int him_reset_target_calls;
static unsigned int him_reset_target_last;
static int hcntrl_pause_after_reads = -1;
static int simulate_delay_pause;
static int simulate_eeprom_data_one;
static int simulate_request_status_ready;
static unsigned short eeprom_script_words[128];
static unsigned int eeprom_script_count;
static unsigned int eeprom_script_bit;
static int eeprom_script_active;

void a2940_test_outb(unsigned short port, unsigned char value)
{
	unsigned int offset = (unsigned int)port - 0x100;
	if (port == 0xcfa)
		pci_config_bus = value;
	else if (port == 0xcf8)
		pci_mech2_enable = value;
	if (sequencer_trace_count < A2940_TEST_TRACE_CAPACITY) {
		sequencer_trace_port[sequencer_trace_count] = port;
		sequencer_trace_value[sequencer_trace_count++] = value;
	}
	++sequencer_barriers;
	test_registers[offset & 0xff] = value;
	if (offset == 0x87 && value == 0 && simulate_delay_pause) {
		hcntrl_pause_after_reads = 1;
		simulate_delay_pause = 0;
	}
	if (offset == AIC_SEQADDR0)
		sequencer_address = (sequencer_address & 0xffffff00U) | value;
	else if (offset == AIC_SEQADDR1)
		sequencer_address = (sequencer_address & 0xffff00ffU) | ((unsigned int)value << 8);
	else if (offset == AIC_SEQRAM && sequencer_address < A2940_SEQ_IMAGE_SIZE) {
		sequencer_ram[sequencer_address++] = value;
		++sequencer_writes;
	}
}

void a2940_test_outl(unsigned short port, unsigned int value)
{
	unsigned int bus;
	unsigned int device;
	unsigned int reg;
	++pci_config_writes;
	if (port == 0xcf8) {
		pci_config_address = value;
		return;
	}
	if (port == 0xcfc && (pci_config_address & 0x80000000U) != 0) {
		bus = (pci_config_address >> 16) & 0xff;
		device = (pci_config_address >> 11) & 0x1f;
		reg = (pci_config_address & 0xfc) >> 2;
	} else if (port >= 0xc000 && pci_mech2_enable == 0x60) {
		bus = pci_config_bus;
		device = (port >> 8) & 0x0f;
		reg = (port & 0xfc) >> 2;
	} else {
		return;
	}
	if (pci_present[bus][device])
		pci_config_words[bus][device][reg] = value;
}

unsigned int a2940_test_inl(unsigned short port)
{
	unsigned int bus;
	unsigned int device;
	unsigned int reg;
	++pci_config_reads;
	if (port == 0xcfc && (pci_config_address & 0x80000000U) != 0) {
		bus = (pci_config_address >> 16) & 0xff;
		device = (pci_config_address >> 11) & 0x1f;
		reg = (pci_config_address & 0xfc) >> 2;
	} else if (port >= 0xc000 && pci_mech2_enable == 0x60) {
		bus = pci_config_bus;
		device = (port >> 8) & 0x0f;
		reg = (port & 0xfc) >> 2;
	} else {
		return 0xffffffffU;
	}
	if (!pci_present[bus][device])
		return 0xffffffffU;
	if (reg == 2 && pci_config_words[bus][device][reg] == 0)
		return 0x12345678U;
	return pci_config_words[bus][device][reg];
}

unsigned char a2940_test_inb(unsigned short port)
{
	unsigned int offset = (unsigned int)port - 0x100;
	unsigned int address;
	if (offset != AIC_SEQRAM) {
		unsigned char value;
		++test_read_count;
		if (offset == 0x87 && hcntrl_pause_after_reads >= 0 &&
		    (test_registers[offset] & 4) == 0) {
			if (hcntrl_pause_after_reads == 0) {
				test_registers[offset] |= 4;
				hcntrl_pause_after_reads = -1;
			} else {
				--hcntrl_pause_after_reads;
			}
		}
		value = test_registers[offset & 0xff];
		if (offset == 12 && simulate_request_status_ready)
			value |= 1;
		if (offset == 30)
			value |= 0x10;
		if (offset == 30 && simulate_eeprom_data_one)
			value |= 1;
		return value;
	}
	address = sequencer_address++;
	if (address >= A2940_SEQ_IMAGE_SIZE)
		return 0;
	++sequencer_reads;
	if ((int)address == sequencer_script_address)
		return sequencer_script_value;
	if ((int)address == sequencer_fail_read)
		return sequencer_ram[address] ^ 1;
	return sequencer_ram[address];
}

unsigned char a2940_test_eeprom_inb(unsigned short port)
{
	unsigned char bit;
	(void)port;
	if (!eeprom_script_active || eeprom_script_count == 0)
		return simulate_eeprom_data_one ? 1 : 0;
	bit = (unsigned char)((eeprom_script_words[eeprom_script_bit / 16] >>
		(15 - (eeprom_script_bit & 15))) & 1);
	++eeprom_script_bit;
	return bit;
}

#define A2940_TEST 1
#include "../Adaptec2940Sequencer.c"
#include "../Adaptec2940HIM.c"
#include "../Adaptec2940Config.c"
void *PH_ScbCompleted(int scb_address)
{
	++him_scb_complete_calls;
	him_completed_scb = scb_address;
	return 0;
}
unsigned char Ph_BusDeviceReset(int scb_address)
{
	++him_bus_reset_calls;
	him_bus_reset_scb = scb_address;
	return 0;
}
static void test_optima_abort_callback(int index, int scb, int io_base)
{
	++abort_callback_calls;
	abort_callback_index = index;
	abort_callback_scb = scb;
	abort_callback_io = io_base;
}

static void __attribute__((stdcall)) test_him_event_callback(int event, int scb, int io_base)
{
	++him_event_calls;
	him_event_args[0] = event;
	him_event_args[1] = scb;
	him_event_args[2] = io_base;
}

static void test_him_selection_timeout(int host, unsigned int selection_id)
{
	++him_selection_calls;
	him_selection_host = host;
	him_selection_id = selection_id;
}

static void test_him_post_mark(int host, unsigned int index)
{
	(void)host;
	if (him_post_mark_calls < 8)
		him_post_mark_indices[him_post_mark_calls] = index;
	++him_post_mark_calls;
}

static void test_him_reset_target(int host, unsigned int target)
{
	(void)host;
	him_reset_target_last = target;
	++him_reset_target_calls;
}

static int run_him_config_access_checks(void)
{
	memset(pci_present, 0, sizeof(pci_present));
	pci_config_address = pci_config_reads = pci_config_writes = 0;
	pci_present[0][5] = 1;
	if (Ph_AccessConfig(2) != 1 || pci_config_reads != 6 ||
	    pci_config_address != 0)
		return 0;

	memset(pci_present, 0, sizeof(pci_present));
	pci_config_reads = pci_config_writes = 0;
	pci_present[2][3] = 1;
	if (Ph_AccessConfig(2) != 1 || pci_config_reads != 36 ||
	    pci_config_address != 0)
		return 0;

	memset(pci_present, 0, sizeof(pci_present));
	pci_config_reads = pci_config_writes = 0;
	if (Ph_AccessConfig(0) != 2 || pci_config_reads != 32 ||
	    pci_config_address != 0)
		return 0;

	pci_present[0][0] = 1;
	if (PH_FindMechanism() != 1)
		return 0;
	memset(pci_present, 0, sizeof(pci_present));
	if (PH_FindMechanism() != 2)
		return 0;

	memset(pci_present, 0, sizeof(pci_present));
	memset(pci_config_words, 0, sizeof(pci_config_words));
	pci_present[4][7] = 1;
	pci_config_words[4][7][4] = 0xa1b2c3d4U;
	a2940_test_config_osm_override = 1;
	if ((unsigned int)Ph_ReadConfig(-1, 4, 7, 0x10) != 0xa1b2c3d4U ||
	    Ph_WriteConfig(-1, 4, 7, 0x10, 0x55667788U) != 0 ||
	    pci_config_words[4][7][4] != 0x55667788U)
		return 0;
	if (Ph_WriteConfig(-1, 4, 8, 0x10, 0) != -1)
		return 0;

	a2940_test_config_osm_override = 2;
	pci_config_words[4][7][4] = 0x10203040U;
	if ((unsigned int)Ph_ReadConfig(-1, 4, 7, 0x10) != 0x10203040U ||
	    Ph_WriteConfig(-1, 4, 7, 0x10, 0x89abcdefU) != 0 ||
	    pci_config_words[4][7][4] != 0x89abcdefU ||
	    Ph_ReadConfig(-1, 4, 16, 0x10) != -1 ||
	    Ph_WriteConfig(-1, 4, 16, 0x10, 0) != -1)
		return 0;
	a2940_test_config_osm_override = -1;
	a2940_test_bus_count_override = 7;
	if (PH_GetNumOfBuses() != 7)
		return 0;
	a2940_test_bus_count_override = -1;
	a2940_test_config_osm_override = 1;
	pci_present[0][0] = 1;
	pci_present[0][1] = 1;
	pci_config_words[0][0][2] = 0;
	pci_config_words[0][1][2] = 0x06040000U;
	pci_config_words[0][1][6] = 0x00020000U;
	if (PH_GetNumOfBuses() != 3)
		return 0;
	a2940_test_config_osm_override = -1;
	return pci_mech2_enable == 0 && pci_config_address == 0;
}

#include "../Adaptec2940Optima.c"

static int run_him_chain_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[272];
	unsigned int *links = (unsigned int *)chain;
	Adaptec2940SCB a;
	Adaptec2940SCB b;
	Adaptec2940SCB c;
	int result;
	memset(&host, 0, sizeof(host));
	memset(&a, 0, sizeof(a));
	memset(&b, 0, sizeof(b));
	memset(&c, 0, sizeof(c));
	*(unsigned int **)(host.bytes + 52) = links;
	links[0] = links[1] = 0xffffffffU;
	host.bytes[13] = 0x80;
	host.bytes[62] = 0x37;
	host.bytes[64] = 0x42;
	if (Ph_ChainPrevious((int *)links, 0) != -1)
		return 0;
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&a);
	if (links[0] != (unsigned int)&a || links[1] != (unsigned int)&a ||
	    ((unsigned char *)links)[268] != 0x37 ||
	    ((unsigned char *)links)[269] != 0x42 ||
	    (host.bytes[13] & 0x80) != 0 || a.chain_next != (void *)0xffffffffU)
		return 0;
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&b);
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&c);
	if (a.chain_next != (void *)&b || b.chain_next != (void *)&c ||
	    c.chain_next != (void *)0xffffffffU || links[1] != (unsigned int)&c)
		return 0;
	if (Ph_ChainPrevious((int *)links, (int)&c) != (int)&b)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&b);
	if (result != (int)&a || a.chain_next != (void *)&c || links[1] != (unsigned int)&c)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&c);
	if (result != (int)&a || a.chain_next != (void *)0xffffffffU ||
	    links[1] != (unsigned int)&a)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&a);
	return result == -1 && links[0] == 0xffffffffU && links[1] == 0xffffffffU &&
	       (host.bytes[13] & 0x80) != 0;
}

static int run_him_hcntrl_checks(void)
{
	unsigned char result;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	sequencer_address = 0;
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x20 || sequencer_trace_count != 2 || test_read_count != 3 ||
	    sequencer_barriers != 2 || sequencer_trace_port[0] != 0x187 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 0x20)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 1;
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x24 || sequencer_trace_count != 2 || sequencer_trace_value[1] != 0x24)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x87] = 4;
	test_registers[0x91] = 8;
	if (Ph_ReadIntstat(0x100) != 8 || sequencer_trace_count != 0 || test_read_count != 2)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 8;
	if (Ph_ReadIntstat(0x100) != 8 || sequencer_trace_count != 2 ||
	    sequencer_barriers != 2 || sequencer_trace_value[0] != 4 ||
	    sequencer_trace_value[1] != 4)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	return Ph_Pause(0x100) == 4 && sequencer_trace_count == 1 &&
	       sequencer_trace_value[0] == 4;
}

static int run_him_status_checks(void)
{
	unsigned char chain[272];
	unsigned char scb[256];
	memset(chain, 0, sizeof(chain));
	memset(scb, 0, sizeof(scb));
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[3] = 0xc0;
	test_registers[176] = 0x78;
	test_registers[177] = 0x56;
	test_registers[178] = 0x34;
	test_registers[179] = 0x12;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 ||
	    *(unsigned int *)(scb + 28) != 0x12345678 || scb[43] != 18 ||
	    sequencer_trace_count != 0 || test_read_count != 5)
		return 0;
	scb[10] = 0x40;
	scb[43] = 7;
	*(unsigned int *)(scb + 28) = 0xfeedface;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[3] = 0xc0;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 || scb[43] != 7 ||
	    *(unsigned int *)(scb + 28) != 0xfeedface || test_read_count != 1)
		return 0;
	scb[24] = 20;
	scb[43] = 1;
	if (Ph_SetMgrStat(scb) != 20 || scb[11] != 4)
		return 0;
	chain[268] = 1;
	chain[269] = 2;
	chain[8] = 2;
	scb[12] = 0;
	if (Ph_GetScbStatus((int)chain, (int)scb) != 32)
		return 0;
	scb[13] = 0x20;
	return Ph_GetScbStatus((int)chain, (int)scb) == 16;
}

static int run_him_terminate_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char first[A2940_SCB_SIZE];
	unsigned char next[A2940_SCB_SIZE];
	unsigned char abort_queue[16];

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(first, 0, sizeof(first));
	memset(next, 0, sizeof(next));
	memset(abort_queue, 0xff, sizeof(abort_queue));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(block + 280) = (unsigned int)(unsigned long)abort_queue;
	*(unsigned int *)(block + 0) = (unsigned int)(unsigned long)first;
	*(unsigned int *)(block + 4) = (unsigned int)(unsigned long)next;
	*(unsigned int *)(first + 0) = (unsigned int)(unsigned long)next;
	*(unsigned int *)(next + 0) = 0xffffffffU;
	*(unsigned int *)(first + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)(next + 4) = (unsigned int)(unsigned long)host;
	first[12] = next[12] = 1;
	next[11] = 32;
	block[9] = 1;
	Ph_TerminateCommand((int)(unsigned long)first, (char)0xff);
	if (first[11] != 1 || next[11] != 16 ||
	    *(unsigned short *)(block + 266) != 1 || block[9] != 0 ||
	    abort_queue[0] != 0xff)
		return 0;

	*(unsigned short *)(block + 266) = 0;
	block[9] = 0;
	memset(first, 0, sizeof(first));
	*(unsigned int *)(first + 4) = (unsigned int)(unsigned long)host;
	first[12] = 1;
	block[270] = 0;
	Ph_TerminateCommand((int)(unsigned long)first, 0x44);
	return first[11] == 1 && block[270] == 1 && abort_queue[0] == 0x44;
}

static int run_him_misc_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char source[3] = {0x11, 0x22, 0x33};
	unsigned char destination[3] = {0, 0, 0};
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_OutBuffer(0x120, (int)source, 3) != 0x33 || sequencer_trace_count != 3 ||
	    sequencer_trace_port[0] != 0x120 || sequencer_trace_value[0] != 0x11 ||
	    sequencer_trace_port[2] != 0x122 || sequencer_trace_value[2] != 0x33 ||
	    sequencer_barriers != 3)
		return 0;
	if (Ph_InBuffer(0x120, (int)destination, 3) != 0x33 ||
	    destination[0] != 0x11 || destination[1] != 0x22 || destination[2] != 0x33)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_SetNeedNego(3, 0x100) != (char)-113 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x123 || sequencer_trace_value[0] != 0x8f)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (PH_EnableInt((int)&host) != 2 || sequencer_trace_count != 2 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 2)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	test_registers[0x87] = 6;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (PH_DisableInt((int)&host) != 4 || sequencer_trace_count != 1 ||
	    sequencer_trace_value[0] != 4)
		return 0;
	Ph_Abort();
	Ph_BusReset();
	Ph_HaSoftReset();
	Ph_SoftReset();
	return Ph_SendTrmMsg(0, 0) == 0 && Ph_TrmCmplt() == 0;
}

static int run_him_bookmark_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[512];
	memset(&host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	*(unsigned int **)(host.bytes + 52) = (unsigned int *)chain;
	*(unsigned int *)(host.bytes + 56) = 0x1000;
	host.bytes[13] = 0x80;
	*(unsigned int *)chain = 0xffffffffU;
	*(unsigned int *)(chain + 4) = 0xffffffffU;
	*(unsigned int *)(chain + 352) = 0xffffffffU;
	if (Ph_SetScbMark((int)&host) != (int)chain ||
	    *(unsigned int *)(chain + 372) != 0x1194 ||
	    *(unsigned int *)(chain + 356) != (unsigned int)&host)
		return 0;
	Ph_InsertBookmark((int)&host);
	if (*(unsigned int *)chain != (unsigned int)(chain + 352) ||
	    *(unsigned int *)(chain + 4) != (unsigned int)(chain + 352) ||
	    chain[360] != 0xff || *(unsigned int *)(chain + 352) != 0xffffffffU ||
	    (host.bytes[13] & 0x80) != 0)
		return 0;
	return Ph_RemoveBookmark((int)&host) == -1 &&
	       *(unsigned int *)chain == 0xffffffffU &&
	       *(unsigned int *)(chain + 4) == 0xffffffffU &&
	       (host.bytes[13] & 0x80) != 0;
}

static int run_him_scb_prepare_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[512];
	unsigned char first[256];
	unsigned char second[256];
	memset(&host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	memset(first, 0, sizeof(first));
	memset(second, 0, sizeof(second));
	*(unsigned char **)(host.bytes + 52) = chain;
	chain[268] = 1;
	*(unsigned int *)first = (unsigned int)second;
	*(unsigned int *)second = 0xffffffffU;
	first[9] = second[9] = 0xaa;
	if (Ph_ScbPrepare((int)&host, (int *)first) != 32)
		return 0;
	return chain[8] == 2 && *(unsigned short *)(chain + 266) == 1 &&
	       first[9] == 0 && first[11] == 16 && second[9] == 0 && second[11] == 32;
}

static int run_him_sync_map_checks(void)
{
	static const unsigned char periods[] = {
		0x00, 0x10, 0x11, 0x12, 0x13, 0x14, 0x19, 0x1a, 0x1f, 0x20,
		0x25, 0x26, 0x2b, 0x2c, 0x32, 0x33, 0x38, 0x39, 0x3e, 0x3f, 0xff
	};
	static const unsigned char expected[] = {
		16, 16, 32, 0, 32, 0, 0, 16, 16, 32, 32, 48, 48, 64, 64,
		80, 80, 96, 96, 112, 112
	};
	unsigned char scb[256];
	unsigned int i;
	for (i = 0; i < sizeof(periods); ++i) {
		scb[67] = periods[i];
		if (Ph_SyncSet((int)scb) != expected[i])
			return 0;
	}
	return 1;
}

static int run_him_negotiation_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char scb[256];
	memset(&host, 0, sizeof(host));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	host.bytes[41] = 0x80;
	if (Ph_ScbRenego((int)&host, 0x90) != (char)-113 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x129 || sequencer_trace_value[0] != 0x8f)
		return 0;
	host.bytes[41] = 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x29] = 0x8f;
	if (Ph_ScbRenego((int)&host, 0x90) != (char)-113 || host.bytes[41] != 0x81 ||
	    sequencer_trace_count != 1 || sequencer_trace_value[0] != 0x8f)
		return 0;
	host.bytes[41] = 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_ScbRenego((int)&host, 0x90) != 0 || sequencer_trace_count != 1 ||
	    sequencer_trace_value[0] != 0)
		return 0;
	scb[66] = 1;
	scb[12] = 0x90;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x31] = 0xff;
	test_registers[1] = 0xff;
	if (Ph_ClearFast20Reg((int)&host, (int)scb) != 0xdf || sequencer_trace_count != 2 ||
	    sequencer_trace_port[0] != 0x131 || sequencer_trace_value[0] != 0xfd ||
	    sequencer_trace_port[1] != 0x101 || sequencer_trace_value[1] != 0xdf)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	scb[67] = 0x18;
	Ph_LogFast20Map((int)&host, scb);
	if (sequencer_trace_count != 2 || sequencer_trace_value[0] != 2 ||
	    sequencer_trace_value[1] != 0x20)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x31] = 0xff;
	test_registers[1] = 0xff;
	scb[67] = 0x19;
	Ph_LogFast20Map((int)&host, scb);
	return sequencer_trace_count == 2 && sequencer_trace_value[0] == 0xfd &&
	       sequencer_trace_value[1] == 0xdf;
}

static int run_him_delay_checks(void)
{
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	sequencer_address = 0;
	hcntrl_pause_after_reads = -1;
	test_registers[0x87] = 4;
	test_registers[176] = 0xaa;
	test_registers[177] = 0xbb;
	simulate_delay_pause = 1;
	if (Ph_Delay(0x100, 1) != 0xbb || sequencer_trace_count != 8 ||
	    sequencer_barriers != 8)
		return 0;
	return sequencer_trace_port[0] == 0x1b0 && sequencer_trace_value[0] == 0x54 &&
	       sequencer_trace_port[1] == 0x1b1 && sequencer_trace_value[1] == 0x0b &&
	       sequencer_trace_port[2] == 0x162 && sequencer_trace_value[2] == 4 &&
	       sequencer_trace_port[3] == 0x163 && sequencer_trace_value[3] == 0 &&
	       sequencer_trace_port[4] == 0x187 && sequencer_trace_value[4] == 0 &&
	       sequencer_trace_port[5] == 0x192 && sequencer_trace_value[5] == 1 &&
	       sequencer_trace_port[6] == 0x1b0 && sequencer_trace_value[6] == 0xaa &&
	       sequencer_trace_port[7] == 0x1b1 && sequencer_trace_value[7] == 0xbb;
}

static int run_him_pollint_checks(void)
{
	Adaptec2940HostInfo host;
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 0x0b;
	if (PH_PollInt((int)&host) != 0x0b || sequencer_trace_count != 2 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 4)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 0x80;
	return PH_PollInt((int)&host) == 0 && sequencer_trace_count == 2 &&
	       sequencer_trace_value[0] == 4 && sequencer_trace_value[1] == 0;
}

static int run_him_leaf_checks(void)
{
	unsigned char scb[108];
	Adaptec2940HostInfo host;
	memset(&host, 0, sizeof(host));
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = test_read_count = 0;
	test_registers[0x1e] = 0x10;
	if (Ph_Wait2usec(0x15, 0x100) != 0x15 || sequencer_trace_count != 3 ||
	    sequencer_trace_port[0] != 0x11e || sequencer_trace_value[0] != 0x15 ||
	    sequencer_trace_port[1] != 0x11e || sequencer_trace_value[1] != 0x15 ||
	    sequencer_trace_port[2] != 0x11e || sequencer_trace_value[2] != 0x15)
		return 0;
	if (PH_ReadConfigOSM() != 0x55555555 || PH_WriteConfigOSM() != 0x55555555 ||
	    PH_GetNumOfBusesOSM() != 0x55555555)
		return 0;
	host.bytes[13] = 0x10;
	if (Ph_RebuildEEControl((int)&host, (short)0xabff) != 0xabf7)
		return 0;
	host.bytes[13] = 0x30;
	if (Ph_RebuildEEControl((int)&host, (short)0x12f3) != 0x12ff)
		return 0;
	host.bytes[13] = 0;
	if (Ph_RebuildEEControl((int)&host, (short)0x7f0c) != 0x7f00)
		return 0;
	memset(scb, 0, sizeof(scb));
	scb[13] = 0;
	him_event_calls = 0;
	if (Ph_AsynchEvent(1, (int)scb, 0x100) != 255 || him_event_calls != 0)
		return 0;
	scb[13] = 0x40;
	*(unsigned int *)(scb + 104) = 0xffffffffU;
	if (Ph_AsynchEvent(2, (int)scb, 0x101) != 255 || him_event_calls != 0)
		return 0;
	*(unsigned int *)(scb + 104) = (unsigned int)(unsigned long)test_him_event_callback;
	if (Ph_AsynchEvent(7, (int)scb, 0x1234) != 0 || him_event_calls != 1 ||
	    him_event_args[0] != 7 || him_event_args[1] != (int)scb ||
	    him_event_args[2] != 0x1234)
		return 0;
	*(unsigned int *)(host.bytes + 4) = 0x100;
	host.bytes[13] = 0x10;
	host.bytes[31] = 8;
	test_registers[2] = 0xa4;
	sequencer_trace_count = 0;
	if (Ph_NoAssistTerm((int)&host) != 0xa5 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x102 || sequencer_trace_value[0] != 0xa5)
		return 0;
	host.bytes[13] = 0x30;
	host.bytes[31] = 16;
	test_registers[2] = 0x80;
	test_registers[30] = 0x40;
	sequencer_trace_count = 0;
	if (Ph_NoAssistTerm((int)&host) != 0 || sequencer_trace_count != 7 ||
	    sequencer_trace_port[0] != 0x102 || sequencer_trace_value[0] != 0x81 ||
	    sequencer_trace_port[1] != 0x11e || sequencer_trace_value[1] != 0x20 ||
	    sequencer_trace_port[2] != 0x11e || sequencer_trace_value[2] != 0x28 ||
	    sequencer_trace_port[3] != 0x11d || sequencer_trace_value[3] != 0x58 ||
	    sequencer_trace_port[4] != 0x11d || sequencer_trace_value[4] != 72 ||
	    sequencer_trace_port[5] != 0x11d || sequencer_trace_value[5] != 0 ||
	    sequencer_trace_port[6] != 0x11e || sequencer_trace_value[6] != 0)
		return 0;
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)&host;
	scb[10] = 0;
	scb[64] = 0x01;
	scb[65] = 0;
	test_registers[3] = 0xa0;
	test_registers[12] = 0;
	test_registers[8] = 0x18;
	test_registers[9] = 0x28;
	test_registers[10] = 0x38;
	simulate_request_status_ready = 1;
	sequencer_trace_count = 0;
	if (Ph_ExtMsgo((int)scb, 0x100) != 0xa0 || scb[10] != 0 ||
	    sequencer_trace_count != 8 ||
	    sequencer_trace_port[0] != 0x106 || sequencer_trace_value[0] != 1 ||
	    sequencer_trace_port[2] != 0x10c || sequencer_trace_value[2] != 0x40 ||
	    sequencer_trace_port[3] != 0x106 || sequencer_trace_value[3] != 0 ||
	    sequencer_trace_port[4] != 0x108 || sequencer_trace_value[4] != 0x18 ||
	    sequencer_trace_port[5] != 0x109 || sequencer_trace_value[5] != 0x28 ||
	    sequencer_trace_port[6] != 0x10a || sequencer_trace_value[6] != 0x38 ||
	    sequencer_trace_port[7] != 0x10c || sequencer_trace_value[7] != 4)
		return 0;
	simulate_request_status_ready = 1;
	sequencer_trace_count = 0;
	if (Ph_SyncNego((int)scb, 0x100) != 0xa0 || scb[10] != 0 ||
	    sequencer_trace_count != 8 || sequencer_trace_port[0] != 0x106 ||
	    sequencer_trace_value[0] != 1 || sequencer_trace_port[4] != 0x108 ||
	    sequencer_trace_value[4] != 0x18)
		return 0;
	simulate_request_status_ready = 0;
	*(unsigned short *)host.bytes = 0x7550;
	test_registers[29] = 0;
	test_registers[30] = 0x40;
	sequencer_trace_count = 0;
	if (Ph_ReadCableStatus((int)&host) != 5 || sequencer_trace_count != 5 ||
	    sequencer_trace_port[0] != 0x11e || sequencer_trace_value[0] != 0x20 ||
	    sequencer_trace_port[1] != 0x11b || sequencer_trace_value[1] != 0x10 ||
	    sequencer_trace_port[2] != 0x11d || sequencer_trace_value[2] != 0x0c ||
	    sequencer_trace_port[3] != 0x11e || sequencer_trace_value[3] != 0x30 ||
	    sequencer_trace_port[4] != 0x11e || sequencer_trace_value[4] != 0x10)
		return 0;
	*(unsigned short *)host.bytes = 0x7870;
	test_registers[31] = 2;
	sequencer_trace_count = 0;
	if (Ph_ReadCableStatus((int)&host) != 7 || sequencer_trace_count != 13 ||
	    sequencer_trace_port[1] != 0x11e || sequencer_trace_value[1] != 0x28 ||
	    sequencer_trace_port[2] != 0x11d || sequencer_trace_value[2] != 0x18 ||
	    sequencer_trace_port[7] != 0x11d || sequencer_trace_value[7] != 0x38 ||
	    sequencer_trace_port[12] != 0x11e || sequencer_trace_value[12] != 0)
		return 0;
	{
		unsigned char reset_block[600];
		memset(reset_block, 0, sizeof(reset_block));
		*(unsigned int *)(host.bytes + 52) = (unsigned int)(unsigned long)reset_block;
		host.bytes[12] = 0x38;
		host.bytes[13] = 0x11;
		*(unsigned int *)(reset_block + 464) = (unsigned int)(unsigned long)test_him_reset_target;
		test_registers[0] = 0x3c;
		him_reset_target_calls = him_reset_target_last = 0;
		sequencer_trace_count = 0;
		if (Ph_ResetChannel((int)&host) != 0 || him_reset_target_calls != 128 ||
		    him_reset_target_last != 127 || sequencer_trace_count != 8 ||
		    sequencer_trace_port[0] != 0x100 || sequencer_trace_value[0] != 0x30 ||
		    sequencer_trace_port[1] != 0x10b || sequencer_trace_value[1] != 0xff ||
		    sequencer_trace_port[2] != 0x10c || sequencer_trace_value[2] != 0xff ||
		    sequencer_trace_port[3] != 0x101 || sequencer_trace_value[3] != 0x12 ||
		    sequencer_trace_port[4] != 0x102 || sequencer_trace_value[4] != 0x3f ||
		    sequencer_trace_port[5] != 0x193 || sequencer_trace_value[5] != 1 ||
		    sequencer_trace_port[6] != 0x111 || sequencer_trace_value[6] != 0xa4 ||
		    sequencer_trace_port[7] != 0x190 || sequencer_trace_value[7] != 0)
			return 0;
	}
	return 1;
}

static int run_him_post_checks(void)
{
	unsigned char host[128];
	unsigned char chain[272];
	unsigned char scb[96];
	unsigned char block[600];
	unsigned char post_host[128];
	unsigned char post_block[1024];
	unsigned char post_scb0[96];
	unsigned char post_scb1[96];
	unsigned char *term_scb;
	memset(host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)chain;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)chain = (unsigned int)(unsigned long)scb;
	*(unsigned int *)(chain + 4) = (unsigned int)(unsigned long)scb;
	*(unsigned int *)scb = 0xffffffffU;
	scb[11] = 68;
	scb[12] = 2;
	chain[10] = 1;
	him_scb_complete_calls = 0;
	if (Ph_PostNonActiveScb((int)(unsigned long)host,
				(int)(unsigned long)scb) != 0 ||
	    chain[10] != 0 || *(unsigned int *)chain != 0xffffffffU ||
	    *(unsigned int *)(chain + 4) != 0xffffffffU || scb[9] != 68 ||
	    him_scb_complete_calls != 1 ||
	    him_completed_scb != (int)(unsigned long)scb)
		return 0;
	*(unsigned int *)chain = (unsigned int)(unsigned long)scb;
	*(unsigned int *)(chain + 4) = (unsigned int)(unsigned long)scb;
	*(unsigned int *)scb = 0xffffffffU;
	scb[11] = 16;
	if (Ph_RemoveAndPostScb((int)(unsigned long)host,
				(int)(unsigned long)scb) != 0 ||
	    *(unsigned int *)chain != 0xffffffffU || scb[9] != 16 ||
	    him_scb_complete_calls != 2)
		return 0;
	memset(block, 0, sizeof(block));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	term_scb = block + 352;
	*(unsigned int *)(term_scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)term_scb = 0xffffffffU;
	*(unsigned int *)block = (unsigned int)(unsigned long)term_scb;
	*(unsigned int *)(block + 4) = (unsigned int)(unsigned long)term_scb;
	if (Ph_TermPostNonActiveScb((int)(unsigned long)term_scb) != 0 ||
	    *(unsigned int *)block != 0xffffffffU || him_scb_complete_calls != 3 ||
	    him_completed_scb != (int)(unsigned long)term_scb)
		return 0;
	memset(post_host, 0, sizeof(post_host));
	memset(post_block, 0, sizeof(post_block));
	memset(post_scb0, 0, sizeof(post_scb0));
	memset(post_scb1, 0, sizeof(post_scb1));
	*(unsigned int *)(post_host + 52) = (unsigned int)(unsigned long)post_block;
	*(unsigned int *)(post_block + 272) = (unsigned int)(unsigned long)(post_block + 512);
	*(unsigned int *)(post_block + 280) = (unsigned int)(unsigned long)(post_block + 700);
	*(unsigned int *)(post_block + 452) = (unsigned int)(unsigned long)test_him_post_mark;
	post_block[270] = 2;
	*(unsigned int *)post_block = (unsigned int)(unsigned long)post_scb0;
	*(unsigned int *)(post_block + 4) = (unsigned int)(unsigned long)post_scb1;
	*(unsigned int *)post_scb0 = (unsigned int)(unsigned long)post_scb1;
	*(unsigned int *)post_scb1 = 0xffffffffU;
	post_scb0[11] = 40;
	post_scb1[11] = 68;
	*(unsigned int *)(post_block + 512 + 3 * 4) = (unsigned int)(unsigned long)post_scb1;
	*(unsigned int *)(post_block + 512 + 7 * 4) = (unsigned int)(unsigned long)post_scb0;
	post_block[700] = 7;
	post_block[701] = 3;
	him_post_mark_calls = 0;
	if (Ph_PostCommand((int)(unsigned long)post_host) != 0 ||
	    post_block[270] != 0 || post_scb0[9] != 40 || post_scb1[9] != 68 ||
	    *(unsigned int *)post_block != 0xffffffffU ||
	    *(unsigned int *)(post_block + 4) != 0xffffffffU ||
	    him_post_mark_calls != 2 || him_post_mark_indices[0] != 3 ||
	    him_post_mark_indices[1] != 7 || him_scb_complete_calls != 5 ||
	    him_completed_scb != (int)(unsigned long)post_scb0)
		return 0;
	if (Ph_PostCommand((int)(unsigned long)post_host) != 0)
		return 0;
	memset(post_block, 0, sizeof(post_block));
	memset(post_scb0, 0, sizeof(post_scb0));
	*(unsigned int *)(post_host + 52) = (unsigned int)(unsigned long)post_block;
	*(unsigned int *)(post_scb0 + 4) = (unsigned int)(unsigned long)post_host;
	*(unsigned int *)post_scb0 = 0xffffffffU;
	*(unsigned int *)post_block = (unsigned int)(unsigned long)post_scb0;
	*(unsigned int *)(post_block + 4) = (unsigned int)(unsigned long)post_scb0;
	post_block[10] = 1;
	post_scb0[11] = 32;
	post_scb0[12] = 2;
	him_scb_complete_calls = 0;
	if (Ph_ScbAbort((int)(unsigned long)post_scb0) != 0 ||
	    post_scb0[11] != 2 || post_scb0[43] != 4 || post_block[10] != 0 ||
	    *(unsigned int *)post_block != 0xffffffffU ||
	    him_scb_complete_calls != 1 ||
	    him_completed_scb != (int)(unsigned long)post_scb0)
		return 0;
	return 1;
}

static int run_him_req_checks(void)
{
	unsigned char scb[64];
	memset(scb, 0, sizeof(scb));
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[3] = 0x20;
	test_registers[12] = 1;
	if (Ph_Wt4Req((int)(unsigned long)scb, 0x100) != 0x20 ||
	    sequencer_trace_count != 1 || sequencer_trace_port[0] != 0x10c ||
	    sequencer_trace_value[0] != 4)
		return 0;
	test_registers[3] = 0x20;
	test_registers[12] = 1;
	test_registers[2] = 0xff;
	sequencer_trace_count = 0;
	if (Ph_ParityError((int)(unsigned long)scb, 0x100) != 0xdf ||
	    scb[43] != 72 || sequencer_trace_count != 2 ||
	    sequencer_trace_port[0] != 0x10c || sequencer_trace_value[0] != 4 ||
	    sequencer_trace_port[1] != 0x102 || sequencer_trace_value[1] != 0xdf)
		return 0;
	test_registers[3] = 0;
	test_registers[12] = 1;
	if (Ph_Wt4Req((int)(unsigned long)scb, 0x100) != 0x00)
		return 0;
	test_registers[3] = 0;
	test_registers[12] = 0x28;
	return Ph_Wt4Req((int)(unsigned long)scb, 0x100) == 0xff;
}

static int run_him_interrupt_checks(void)
{
	unsigned char host[128];
	unsigned int chain[128];
	memset(host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	memset(test_registers, 0, sizeof(test_registers));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)chain;
	chain[117] = (unsigned int)(unsigned long)test_him_selection_timeout;
	test_registers[0x3b] = 0x5a;
	test_registers[0] = 0xff;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	him_selection_calls = 0;
	if ((unsigned char)Ph_IntSelto((int)(unsigned long)host, -1) != 0x88 ||
	    him_selection_calls != 1 || him_selection_host != (int)(unsigned long)host ||
	    him_selection_id != 0x5a || sequencer_trace_count != 2 ||
	    sequencer_trace_port[0] != 0x100 || sequencer_trace_value[0] != 0x33 ||
	    sequencer_trace_port[1] != 0x10c || sequencer_trace_value[1] != 0x88)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	test_registers[0x3c] = 0xa5;
	test_registers[1] = 0x41;
	test_registers[17] = 0xff;
	sequencer_trace_count = 0;
	if (Ph_IntFree((int)(unsigned long)host, -1) != 0 || sequencer_trace_count != 7)
		return 0;
	return sequencer_trace_port[0] == 0x193 && sequencer_trace_value[0] == 1 &&
	       sequencer_trace_port[1] == 0x101 && sequencer_trace_value[1] == 0x5b &&
	       sequencer_trace_port[2] == 0x111 && sequencer_trace_value[2] == 0xf7 &&
	       sequencer_trace_port[3] == 0x104 && sequencer_trace_value[3] == 0 &&
	       sequencer_trace_port[4] == 0x10c && sequencer_trace_value[4] == 8 &&
	       sequencer_trace_port[5] == 0x162 && sequencer_trace_value[5] == 0 &&
	       sequencer_trace_port[6] == 0x163 && sequencer_trace_value[6] == 0;
}

static int run_him_noninit_checks(void)
{
	unsigned char host[128];
	unsigned char chain[272];
	unsigned char scb[96];
	memset(host, 0, sizeof(host));
	memset(chain, 0xff, sizeof(chain));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)chain;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	host[13] = 0x80;
	host[62] = 5;
	host[64] = 2;
	*(unsigned int *)chain = 0xffffffffU;
	*(unsigned int *)(chain + 4) = 0xffffffffU;
	chain[270] = 3;
	scb[8] = 2;
	if (Ph_NonInit((int)(unsigned long)scb) != 0 || scb[11] != 0x80 ||
	    *(unsigned int *)chain != (unsigned int)(unsigned long)scb ||
	    *(unsigned int *)scb != 0xffffffffU || chain[270] != 4 ||
	    (host[13] & 0x80) != 0 || chain[268] != 5 || chain[269] != 2)
		return 0;
	scb[8] = 0;
	if (Ph_NonInit((int)(unsigned long)scb) != 0 || chain[270] != 4)
		return 0;
	scb[8] = 4;
	him_bus_reset_calls = 0;
	return Ph_NonInit((int)(unsigned long)scb) == 0 &&
	       him_bus_reset_calls == 1 &&
	       him_bus_reset_scb == (int)(unsigned long)scb;
}

static int run_him_eeprom_command_checks(void)
{
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_SendStartBitEE(0x100) != 0x2a || sequencer_trace_count != 12 ||
	    sequencer_trace_port[0] != 0x11e || sequencer_trace_value[0] != 0x2a ||
	    sequencer_trace_port[1] != 0x11e || sequencer_trace_value[1] != 0x2a ||
	    sequencer_trace_port[4] != 0x11e || sequencer_trace_value[4] != 0x2e ||
	    sequencer_trace_port[8] != 0x11e || sequencer_trace_value[8] != 0x2a ||
	    sequencer_trace_value[11] != 0x2a)
		return 0;
	sequencer_trace_count = 0;
	if (Ph_SendAddressEE(0x100, 8, 0x80) != 0x2c || sequencer_trace_count != 64 ||
	    sequencer_trace_port[0] != 0x11e || sequencer_trace_value[0] != 0x2a ||
	    sequencer_trace_value[4] != 0x2e || sequencer_trace_value[8] != 0x28 ||
	    sequencer_trace_value[12] != 0x2c || sequencer_trace_value[63] != 0x2c)
		return 0;
	sequencer_trace_count = 0;
	if (Ph_EnableEraseWriteEE(0x100, 0) != 0 || sequencer_trace_count != 84 ||
	    sequencer_trace_value[12] != 0x28 ||
	    sequencer_trace_value[76] != 0x28 ||
	    sequencer_trace_value[80] != 0x20 ||
	    sequencer_trace_value[83] != 0x20)
		return 0;
	sequencer_trace_count = 0;
	if (Ph_DisableEraseWriteEE(0x100, 1) != 0) {
		return 0;
	}
	if (sequencer_trace_count != 100) {
		return 0;
	}
	if (sequencer_trace_value[12] != 0x28) {
		return 0;
	}
	if (sequencer_trace_value[92] != 0x28) {
		return 0;
	}
	if (sequencer_trace_value[96] != 0x20 || sequencer_trace_value[99] != 0x20) {
		return 0;
	}
	return 1;
}

static int run_him_eeprom_data_checks(void)
{
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	simulate_eeprom_data_one = 1;
	if (Ph_ReadE2Register(0x12, 0x100, 0) != 0xffff ||
	    sequencer_trace_count != 212 ||
	    sequencer_trace_value[76] != 0x28 ||
	    sequencer_trace_value[80] != 0x2c ||
	    sequencer_trace_value[84] != 0x28 ||
	    sequencer_trace_value[208] != 0x20 ||
	    sequencer_trace_value[211] != 0x20) {
		simulate_eeprom_data_one = 0;
		return 0;
	}
	sequencer_trace_count = 0;
	if (Ph_WriteE2Register(0x12, 0x100, 0, (short)0xa55a) != 0 ||
	    sequencer_trace_count != 312 ||
	    sequencer_trace_value[76] != 0x28 ||
	    sequencer_trace_value[92] != 0x2a ||
	    sequencer_trace_value[104] != 0x28 ||
	    sequencer_trace_value[168] != 0x2a ||
	    sequencer_trace_value[296] != 0x28 ||
	    sequencer_trace_value[300] != 0x20 ||
	    sequencer_trace_value[304] != 0x28 ||
	    sequencer_trace_value[308] != 0x20 ||
	    sequencer_trace_value[311] != 0x20) {
		simulate_eeprom_data_one = 0;
		return 0;
	}
	simulate_eeprom_data_one = 0;
	return 1;
}

static int run_him_eeprom_storage_checks(void)
{
	unsigned char host[128];
	unsigned short words[32];
	unsigned short checksum = 0;
	unsigned int i;
	memset(host, 0, sizeof(host));
	memset(words, 0, sizeof(words));
	*(unsigned short *)host = 0x7872;
	host[9] = 4;
	words[1] = 0x003f;
	words[17] = 0x001f;
	words[18] = 0xabcd;
	words[19] = 7;
	for (i = 0; i <= 30; ++i)
		checksum = (unsigned short)(checksum + words[i]);
	host[31] = 7;
	for (i = 0; i <= 30; ++i) {
		eeprom_script_words[i] = words[i];
		eeprom_script_words[32 + i] = words[i];
	}
	eeprom_script_words[31] = checksum;
	eeprom_script_count = 63;
	eeprom_script_bit = 0;
	eeprom_script_active = 1;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_ReadEeprom((unsigned short *)host, 0x100) != 0 ||
	    eeprom_script_bit != 63 * 16 ||
	    host[33] != 0xf1 || host[12] != 0x20 || host[14] != 2 ||
	    host[13] != 0x30 || host[15] != 0x20 || host[30] != 0x0d ||
	    host[21] != 0xab || ((unsigned short *)(void *)host)[24] != 2 ||
	    test_registers[30] != 0)
		goto fail;
	memset(host, 0, sizeof(host));
	*(unsigned short *)host = 0x7872;
	host[9] = 4;
	host[31] = 7;
	eeprom_script_words[31] = (unsigned short)(checksum + 1);
	eeprom_script_count = 32;
	eeprom_script_bit = 0;
	if (Ph_ReadEeprom((unsigned short *)host, 0x100) != 1 ||
	    eeprom_script_bit != 32 * 16 || test_registers[30] != 0)
		goto fail;
	memset(host, 0, sizeof(host));
	*(unsigned short *)host = 0x7872;
	host[9] = 4;
	host[13] = 0x30;
	memset(eeprom_script_words, 0, sizeof(eeprom_script_words));
	eeprom_script_count = 32;
	eeprom_script_bit = 0;
	eeprom_script_active = 1;
	simulate_eeprom_data_one = 1;
	sequencer_trace_count = 0;
	if (Ph_UpdateEeprom((unsigned short *)host, 0x100, 17) != 0) {
		goto fail;
	}
	if (eeprom_script_bit != 32 * 16 || sequencer_trace_count != 7579) {
		goto fail;
	}
	if (sequencer_trace_value[7038] != 0x28 ||
	    sequencer_trace_value[7350] != 0x28 ||
	    sequencer_trace_value[7578] != 0) {
		goto fail;
	}
	eeprom_script_active = 0;
	simulate_eeprom_data_one = 0;
	return 1;
fail:
	eeprom_script_active = 0;
	simulate_eeprom_data_one = 0;
	return 0;
}

static int run_him_bios_buffer_checks(void)
{
	unsigned char host[128];
	unsigned char buffer[3];
	memset(host, 0, sizeof(host));
	*(unsigned int *)(host + 4) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	test_registers[0x87] = 4;
	test_registers[0x90] = 0xa0;
	test_registers[0xa3] = 0x11;
	test_registers[0xa4] = 0x22;
	test_registers[0xa5] = 0x33;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_ReadBiosInfo((int)(unsigned long)host, 3,
			    (int)(unsigned long)buffer, 3) != 4 ||
	    buffer[0] != 0x11 || buffer[1] != 0x22 || buffer[2] != 0x33 ||
	    sequencer_trace_count != 4 ||
	    sequencer_trace_port[0] != 0x187 || sequencer_trace_value[0] != 4 ||
	    sequencer_trace_port[1] != 0x190 || sequencer_trace_value[1] != 2 ||
	    sequencer_trace_port[2] != 0x190 || sequencer_trace_value[2] != 0xa0 ||
	    sequencer_trace_port[3] != 0x187 || sequencer_trace_value[3] != 4)
		return 0;
	buffer[0] = 0xaa;
	buffer[1] = 0xbb;
	buffer[2] = 0xcc;
	sequencer_trace_count = 0;
	if (Ph_WriteBiosInfo((int)(unsigned long)host, 5,
			     (int)(unsigned long)buffer, 3) != 4 ||
	    sequencer_trace_count != 7 ||
	    sequencer_trace_port[0] != 0x187 || sequencer_trace_value[0] != 4 ||
	    sequencer_trace_port[1] != 0x190 || sequencer_trace_value[1] != 2 ||
	    sequencer_trace_port[2] != 0x1a5 || sequencer_trace_value[2] != 0xaa ||
	    sequencer_trace_port[3] != 0x1a6 || sequencer_trace_value[3] != 0xbb ||
	    sequencer_trace_port[4] != 0x1a7 || sequencer_trace_value[4] != 0xcc ||
	    sequencer_trace_port[5] != 0x190 || sequencer_trace_value[5] != 0xa0 ||
	    sequencer_trace_port[6] != 0x187 || sequencer_trace_value[6] != 4)
		return 0;
	return test_registers[0xa5] == 0xaa && test_registers[0xa6] == 0xbb &&
	       test_registers[0xa7] == 0xcc;
}

static int run_him_sync_nego_checks(void)
{
	unsigned char host[128];
	memset(host, 0, sizeof(host));
	*(unsigned short *)(host + 4) = 0x100;
	host[31] = 3;
	host[32] = 0x81;
	host[33] = 0;
	host[34] = 0x80;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_CheckSyncNego((int)(unsigned long)host) != (char)-113 ||
	    sequencer_trace_count != 3 || sequencer_trace_port[0] != 0x120 ||
	    sequencer_trace_value[0] != 0x8f || sequencer_trace_port[1] != 0x121 ||
	    sequencer_trace_value[1] != 0 || sequencer_trace_port[2] != 0x122 ||
	    sequencer_trace_value[2] != 0x8f)
		return 0;
	host[14] = 1;
	sequencer_trace_count = 0;
	if (Ph_CheckSyncNego((int)(unsigned long)host) != 0 ||
	    sequencer_trace_count != 3 || sequencer_trace_value[0] != 0 ||
	    sequencer_trace_value[1] != 0 || sequencer_trace_value[2] != 0)
		return 0;
	host[31] = 0;
	return Ph_CheckSyncNego((int)(unsigned long)host) == 0 &&
	       sequencer_trace_count == 3;
}

static int run_him_driver_config_checks(void)
{
	unsigned char host[128];
	unsigned char init_host[128];
	unsigned char init_block[8192];
	unsigned int *function_table;
	unsigned int i;
	int init_result;
	memset(host, 0, sizeof(host));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned short *)(host + 66) = 4;
	memset(test_registers, 0, sizeof(test_registers));
	test_registers[0x87] = 4;
	test_registers[0xb0] = 0x78;
	test_registers[0xb1] = 0x56;
	test_registers[0xb2] = 0x34;
	test_registers[0xb3] = 0x12;
	if (Ph_GetDrvrConfig((int)(unsigned long)host) != 1582 ||
	    (host[12] & 2) == 0 || host[13] != 0x81 ||
	    *(unsigned short *)(host + 62) != 2 ||
	    *(unsigned short *)(host + 64) != 32 ||
	    *(unsigned short *)(host + 16) != 2 ||
	    *(unsigned short *)(host + 60) != 1582)
		return 0;
	memset(host, 0, sizeof(host));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned short *)(host + 66) = 4;
	test_registers[0xb0] = test_registers[0xb1] = 0;
	test_registers[0xb2] = test_registers[0xb3] = 0;
	if (Ph_GetDrvrConfig((int)(unsigned long)host) != 1582 ||
	    (host[12] & 2) != 0 || host[13] != 0x81)
		return 0;

	memset(init_host, 0, sizeof(init_host));
	memset(init_block, 0xa5, sizeof(init_block));
	memset(test_registers, 0, sizeof(test_registers));
	*(unsigned int *)(init_host + 4) = 0x100;
	*(unsigned int *)(init_host + 52) = (unsigned int)(unsigned long)init_block;
	*(unsigned int *)(init_host + 56) = 0x2000;
	*(unsigned short *)(init_host + 66) = 4;
	for (i = 32; i <= 0x5f; ++i)
		test_registers[i] = (unsigned char)i;
	if (SWAPCurrScratchRam((int)(unsigned long)init_host, 0) != 0 ||
	    init_block[256 + 32] != 32 || init_block[256 + 65] != 0 ||
	    init_block[256 + 69] != 69 || init_block[256 + 70] != 0x7f ||
	    init_block[256 + 85] != 0x7f || init_block[256 + 86] != 86 ||
	    init_block[256 + 95] != 95 || test_registers[98] != 0 ||
	    test_registers[99] != 0)
		return 0;
	for (i = 32; i <= 0x5f; ++i)
		init_block[256 + i] = (unsigned char)(0xe0 + (i & 0x0f));
	sequencer_trace_count = 0;
	if (SWAPCurrScratchRam((int)(unsigned long)init_host, 1) != 0 ||
	    sequencer_trace_count != 39 || sequencer_trace_port[0] != 0x13b ||
	    sequencer_trace_value[0] != 0xeb ||
	    sequencer_trace_port[36] != 0x15f ||
	    sequencer_trace_value[36] != 0xef ||
	    sequencer_trace_port[37] != 0x162 || sequencer_trace_value[37] != 0 ||
	    sequencer_trace_port[38] != 0x163 || sequencer_trace_value[38] != 0)
		return 0;

	memset(init_block, 0xa5, sizeof(init_block));
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_script_address = 3;
	sequencer_script_value = 11;
	init_result = Ph_InitDrvrHA((int)(unsigned long)init_host);
	sequencer_script_address = -1;
	if (init_result == 0 ||
	    *(unsigned int *)(init_block + 432) != 0 ||
	    *(unsigned short *)(init_block + 284) != 0 || init_block[287] != 3 ||
	    *(unsigned short *)(init_block + 264) != 12 ||
	    *(unsigned int *)(init_block + 356) != (unsigned int)(unsigned long)init_host ||
	    *(unsigned int *)(init_block + 372) != 0x2000 + 404 ||
	    test_registers[96] != 0x80 || test_registers[98] != 1 ||
	    test_registers[99] != 0)
		return 0;
	function_table = (unsigned int *)(unsigned long)init_block;
	return function_table[110] == (unsigned int)(unsigned long)Ph_OptimaMoreFreeScb &&
	       function_table[119] == (unsigned int)(unsigned long)Ph_OptimaEnque &&
	       function_table[121] == (unsigned int)(unsigned long)Ph_OptimaEnableNextScbArray;
}

static int run_optima_size_checks(void)
{
	return Ph_CalcOptimaSize(0) == 1542 &&
	       Ph_CalcOptimaSize(1) == 1552 &&
	       Ph_CalcOptimaSize(254) == 4082 &&
	       Ph_CalcOptimaSize(255) == 4082 &&
	       PH_CalcDataSize(0, 254) == 4082 &&
	       PH_CalcDataSize(0, -1) == 4082;
}

static int run_optima_config_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	int host_address = (int)(unsigned long)host;

	memset(host, 0, sizeof(host));
	if (Ph_GetOptimaConfig(host_address) != 4082 ||
	    *(unsigned short *)(host + 66) != 254 ||
	    *(unsigned short *)(host + 60) != 4082 || host[13] != 1)
		return 0;
	*(unsigned short *)(host + 66) = 8;
	host[13] = 0xa0;
	return Ph_GetOptimaConfig(host_address) == 1622 &&
	       *(unsigned short *)(host + 66) == 8 &&
	       *(unsigned short *)(host + 60) == 1622 && host[13] == 0xa1;
}

static int run_optima_busy_map_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	unsigned char free_queue[256];
	unsigned char qin_map[256];
	unsigned char busy_map[256];
	unsigned int host_address = (unsigned int)(unsigned long)host;
	int result;
	int index;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	memset(scb_array, 0xff, sizeof(scb_array));
	memset(scb_command, 0xff, sizeof(scb_command));
	memset(free_queue, 0xff, sizeof(free_queue));
	memset(qin_map, 0, sizeof(qin_map));
	memset(busy_map, 0, sizeof(busy_map));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 276) = (unsigned int)(unsigned long)free_queue;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned int *)(block + 496) = (unsigned int)(unsigned long)qin_map;
	*(unsigned int *)(block + 504) = (unsigned int)(unsigned long)busy_map;
	scb[12] = 77;
	scb_array[0] = (unsigned int)(unsigned long)scb;
	result = Ph_OptimaClearTargetBusy((int)host_address, 0);
	if (result != (int)(unsigned long)busy_map || busy_map[77] != 0xff)
		return 0;
	busy_map[31] = 0;
	result = Ph_OptimaIndexClearBusy((int)host_address, 31);
	if (result != (int)(unsigned long)busy_map || busy_map[31] != 0xff)
		return 0;
	result = Ph_OptimaClearQinFifo((int)host_address);
	if (result != (int)(unsigned long)qin_map)
		return 0;
	for (index = 0; index <= 255; ++index) {
		if (qin_map[index] != 0xff)
			return 0;
	}
	return 1;
}

static int run_optima_free_scb_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	unsigned char free_queue[256];
	int host_address = (int)(unsigned long)host;
	int block_address = (int)(unsigned long)block;
	int scb_address = (int)(unsigned long)scb;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	memset(scb_array, 0, sizeof(scb_array));
	memset(scb_command, 0, sizeof(scb_command));
	memset(free_queue, 0xff, sizeof(free_queue));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 276) = (unsigned int)(unsigned long)free_queue;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned short *)(host + 66) = 8;
	block[488] = 1;
	block[271] = 3;
	scb[13] = 0;
	if (Ph_OptimaMoreFreeScb(block_address, scb_address) != 8)
		return 0;
	free_queue[1] = 0x42;
	if (Ph_OptimaGetFreeScb(block_address, scb_address) != 0x42 || block[488] != 2)
		return 0;

	*(unsigned short *)(host + 66) = 40;
	block[488] = 2;
	block[271] = 32;
	scb[13] = 0x20;
	free_queue[32] = 0x71;
	if (Ph_OptimaMoreFreeScb(block_address, scb_address) != 31 ||
	    Ph_OptimaGetFreeScb(block_address, scb_address) != 0x71 || block[271] != 31)
		return 0;

	block[488] = 5;
	block[271] = 10;
	if (Ph_OptimaReturnFreeScb(host_address, 20) != 20 ||
	    block[488] != 4 || free_queue[4] != 20 ||
	    scb_array[20] != 0xffffffffU || scb_command[20] != 0xffffffffU)
		return 0;
	return Ph_OptimaReturnFreeScb(host_address, 40) == 40 &&
	       block[271] == 11 && free_queue[11] == 40;
}

static int run_optima_enqueue_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	unsigned char qin_map[256];
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	memset(scb_array, 0, sizeof(scb_array));
	memset(scb_command, 0, sizeof(scb_command));
	memset(qin_map, 0, sizeof(qin_map));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)(scb + 20) = 0x1000;
	scb[12] = 0x20;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned int *)(block + 496) = (unsigned int)(unsigned long)qin_map;
	block[489] = 200;
	test_registers[0x41] = 4;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_OptimaEnque(7, scb_address, 0x100) != 5 || block[489] != 201 ||
	    qin_map[200] != 7 || scb_array[7] != (unsigned int)(unsigned long)scb ||
	    scb_command[7] != 0x0fd8 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x141 || sequencer_trace_value[0] != 5)
		return 0;

	block[489] = 10;
	test_registers[0x48] = 5;
	test_registers[0x42] = 3;
	test_registers[0x41] = 4;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_OptimaEnqueHead(8, scb_address, 0x100) != 6 ||
	    scb_command[8] != 0x0fd8 || qin_map[5] != 5 || qin_map[4] != 8 ||
	    sequencer_trace_count != 5 || sequencer_trace_port[0] != 0x148 ||
	    sequencer_trace_value[0] != 0x7f)
		return 0;
	return 1;
}

static int run_optima_function_table_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned int *function_table = (unsigned int *)block;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	if (Ph_OptimaLoadFuncPtrs((int)(unsigned long)host) != function_table)
		return 0;
	return function_table[110] == (unsigned int)(unsigned long)Ph_OptimaMoreFreeScb &&
	       function_table[111] == (unsigned int)(unsigned long)Ph_OptimaCmdComplete &&
	       function_table[112] == (unsigned int)(unsigned long)Ph_OptimaGetFreeScb &&
	       function_table[113] == (unsigned int)(unsigned long)Ph_OptimaReturnFreeScb &&
	       function_table[119] == (unsigned int)(unsigned long)Ph_OptimaEnque &&
	       function_table[120] == (unsigned int)(unsigned long)Ph_OptimaEnqueHead;
}

static int run_optima_request_sense_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned char busy_map[256];
	unsigned char qin_map[256];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	int scb_address = (int)(unsigned long)scb;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0xa5, sizeof(scb));
	memset(busy_map, 0, sizeof(busy_map));
	memset(qin_map, 0, sizeof(qin_map));
	memset(scb_array, 0, sizeof(scb_array));
	memset(scb_command, 0, sizeof(scb_command));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned int *)(scb + 20) = 0x108;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned int *)(block + 496) = (unsigned int)(unsigned long)qin_map;
	*(unsigned int *)(block + 504) = (unsigned int)(unsigned long)busy_map;
	scb[12] = 0x20;
	scb[13] = 0xe0;
	scb[15] = 9;
	scb[24] = 0x88;
	*(unsigned int *)(scb + 28) = 0x12345678;
	*(unsigned int *)(scb + 32) = 0x11111111;
	*(unsigned int *)(scb + 36) = 0x22222222;
	*(unsigned int *)(scb + 40) = 0x33333333;
	scb[48] = 0x5a;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_OptimaRequestSense(scb_address, 3) != (int)(unsigned long)busy_map)
		return 0;
	return scb[52] == 3 && scb[53] == 0xa0 && scb[54] == 0 &&
	       scb[55] == 0 && scb[56] == 0x5a && scb[57] == 0 &&
	       (scb[13] & 0xe0) == 0x80 && scb[15] == 1 && scb[14] == 6 &&
	       *(unsigned int *)(scb + 16) == 0x100 && scb[24] == 0 &&
	       *(unsigned int *)(scb + 28) == 0 &&
	       *(unsigned int *)(scb + 32) == 0 &&
	       *(unsigned int *)(scb + 36) == 0 &&
	       *(unsigned int *)(scb + 40) == 0 && scb[11] == 8 &&
	       busy_map[0x20] == 0xff;
}

static int run_optima_completion_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	unsigned char free_queue[256];
	unsigned char qin_map[256];
	unsigned char qout_map[256];
	unsigned char busy_map[256];
	unsigned char abort_queue[32];
	int result;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	memset(scb_array, 0, sizeof(scb_array));
	memset(scb_command, 0, sizeof(scb_command));
	memset(free_queue, 0xff, sizeof(free_queue));
	memset(qin_map, 0xff, sizeof(qin_map));
	memset(qout_map, 0xff, sizeof(qout_map));
	memset(busy_map, 0xff, sizeof(busy_map));
	memset(abort_queue, 0xff, sizeof(abort_queue));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 276) = (unsigned int)(unsigned long)free_queue;
	*(unsigned int *)(block + 280) = (unsigned int)(unsigned long)abort_queue;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned int *)(block + 496) = (unsigned int)(unsigned long)qin_map;
	*(unsigned int *)(block + 500) = (unsigned int)(unsigned long)qout_map;
	*(unsigned int *)(block + 504) = (unsigned int)(unsigned long)busy_map;
	block[490] = 2;
	qout_map[2] = 7;
	scb_array[7] = (unsigned int)(unsigned long)scb;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	scb[8] = 0;
	scb[11] = 8;
	scb[12] = 1;
	scb[43] = 12;
	test_registers[0x87] = 0;
	result = Ph_OptimaCmdComplete((int)(unsigned long)host, 0x13, 0x12340105);
	if ((unsigned int)result != 0x01344105U || block[490] != 3 ||
	    scb[11] != 4 || scb[24] != 2 || scb[43] != 0 ||
	    block[270] != 1 || abort_queue[0] != 7)
		return 0;

	block[490] = 4;
	qout_map[4] = 8;
	scb_array[8] = (unsigned int)(unsigned long)scb;
	scb[8] = 0;
	scb[11] = 68;
	scb[25] = 8;
	result = Ph_OptimaCmdComplete((int)(unsigned long)host, 0x13, 0x00001205);
	if ((unsigned int)result != 0x01001205U || block[490] != 5 ||
	    scb[11] != 68 || block[270] != 1)
		return 0;

	block[490] = 0;
	qout_map[0] = 0xff;
	test_registers[0x87] = 0;
	test_registers[0x9e] = 1;
	sequencer_trace_count = sequencer_barriers = 0;
	result = Ph_OptimaCmdComplete((int)(unsigned long)host, 0x13, 0x00000200);
	return (unsigned int)result == 0x01008201U &&
	       test_registers[0x87] == 0x13 &&
	       sequencer_trace_count >= 2 &&
	       sequencer_trace_port[sequencer_trace_count - 1] == 0x187 &&
	       sequencer_trace_value[sequencer_trace_count - 1] == 0x13;
}

static int run_optima_enable_array_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char scb[A2940_SCB_SIZE];
	memset(host, 0, sizeof(host));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	*(unsigned short *)(host + 4) = 0x100;
	scb[12] = 0x20;
	test_registers[0x48] = 3;
	sequencer_trace_count = sequencer_barriers = 0;
	if (Ph_OptimaEnableNextScbArray((int)(unsigned long)scb) != 0x83 ||
	    sequencer_trace_count != 1 || sequencer_trace_port[0] != 0x148 ||
	    sequencer_trace_value[0] != 0x83)
		return 0;
	test_registers[0x48] = 0x7f;
	sequencer_trace_count = sequencer_barriers = 0;
	if (Ph_OptimaEnableNextScbArray((int)(unsigned long)scb) != 0x7f ||
	    sequencer_trace_count != 0)
		return 0;
	test_registers[0x48] = 0x80;
	return Ph_OptimaEnableNextScbArray((int)(unsigned long)scb) == 0x80 &&
	       sequencer_trace_count == 0;
}

static int run_optima_abort_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int scb_array[256];
	unsigned int scb_command[256];
	unsigned char qin_map[256];
	unsigned char qout_map[256];
	unsigned char free_queue[256];
	unsigned char busy_map[256];
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;
	unsigned int i;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	memset(scb_array, 0, sizeof(scb_array));
	memset(scb_command, 0, sizeof(scb_command));
	memset(qin_map, 0xff, sizeof(qin_map));
	memset(qout_map, 0xff, sizeof(qout_map));
	memset(free_queue, 0xff, sizeof(free_queue));
	memset(busy_map, 0xff, sizeof(busy_map));
	memset(test_registers, 0, sizeof(test_registers));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned short *)(host + 66) = 8;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	scb[12] = 0x10;
	scb_array[7] = (unsigned int)(unsigned long)scb;
	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_array;
	*(unsigned int *)(block + 276) = (unsigned int)(unsigned long)free_queue;
	*(unsigned int *)(block + 492) = (unsigned int)(unsigned long)scb_command;
	*(unsigned int *)(block + 496) = (unsigned int)(unsigned long)qin_map;
	*(unsigned int *)(block + 500) = (unsigned int)(unsigned long)qout_map;
	*(unsigned int *)(block + 504) = (unsigned int)(unsigned long)busy_map;
	block[489] = 6;
	test_registers[0x42] = 3;
	test_registers[0x41] = 3;
	qin_map[3] = 1;
	qin_map[4] = 7;
	qin_map[5] = 2;
	if (Ph_OptimaAbortActive(scb_address) != 0 || block[489] != 5 ||
	    qin_map[3] != 1 || qin_map[4] != 2 || test_registers[0x41] != 2 ||
	    (scb[25] & 8) != 0 || (test_registers[0x87] & 4) != 0)
		return 0;

	memset(qin_map, 0xff, sizeof(qin_map));
	block[489] = 5;
	qin_map[3] = 7;
	qin_map[4] = 1;
	test_registers[0x42] = 3;
	test_registers[0x41] = 2;
	scb[25] = 0;
	if (Ph_OptimaAbortActive(scb_address) != 1 ||
	    (scb[25] & 8) == 0 || block[489] != 5 || test_registers[0x41] != 2)
		return 0;

	memset(qin_map, 0xff, sizeof(qin_map));
	block[489] = 3;
	test_registers[0x42] = 3;
	test_registers[0x41] = 0;
	test_registers[0x47] = 7;
	scb[25] = 0;
	if (Ph_OptimaAbortActive(scb_address) != 1 || (scb[25] & 8) == 0 ||
	    scb[11] != 0)
		return 0;

	for (i = 0; i != 256; ++i)
		qout_map[i] = 0xff;
	*(unsigned int *)(block + 480) = (unsigned int)(unsigned long)test_optima_abort_callback;
	test_registers[0x47] = 0;
	test_registers[0x3b] = 0;
	test_registers[0] = 0;
	scb[25] = 0;
	scb[11] = 0;
	scb[13] = 0;
	abort_callback_calls = 0;
	if (Ph_OptimaAbortActive(scb_address) != 1 || scb[11] != 68 ||
	    (scb[25] & 8) == 0 || scb[13] != 8 || scb[15] != 0 ||
	    *(unsigned int *)(scb + 16) != 6 || abort_callback_calls != 1 ||
	    abort_callback_index != 7 || abort_callback_scb != scb_address ||
	    abort_callback_io != 0x100 ||
	    (test_registers[0x87] & 4) != 0)
		return 0;

	return 1;
}

static int run_optima_setup_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[8192];
	unsigned char *qin;
	unsigned char *qout;
	unsigned char *busy;
	unsigned char *free_queue;
	unsigned int *scb_table;
	unsigned int *commands;
	unsigned int i;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(test_registers, 0, sizeof(test_registers));
	*(unsigned int *)(host + 4) = 0x100;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	*(unsigned int *)(host + 56) = 0x2000;
	*(unsigned short *)(host + 66) = 4;
	host[12] = 2;
	sequencer_trace_count = sequencer_barriers = 0;
	if (Ph_SetOptimaHaData((int)(unsigned long)host) != 0x7f)
		return 0;
	scb_table = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
	free_queue = (unsigned char *)(unsigned long)*(unsigned int *)(block + 276);
	qin = (unsigned char *)(unsigned long)*(unsigned int *)(block + 496);
	qout = (unsigned char *)(unsigned long)*(unsigned int *)(block + 500);
	busy = (unsigned char *)(unsigned long)*(unsigned int *)(block + 504);
	commands = (unsigned int *)(unsigned long)*(unsigned int *)(block + 492);
	if ((unsigned char *)scb_table != block + 508 || free_queue != block + 528 ||
	    (unsigned char *)(unsigned long)*(unsigned int *)(block + 280) != block + 533 ||
	    scb_table[0] != 0xfffffffeU || block[271] != 4 ||
	    free_queue[1] != 1 || free_queue[4] != 4 ||
	    block[488] != 1 || block[489] != 0 || block[490] != 0)
		return 0;
	for (i = 0; i != 256; ++i)
		if (qin[i] != 0xff || qout[i] != 0xff || busy[i] != 0xff) {
			return 0;
		}
	for (i = 0; i < 5; ++i)
		if (((unsigned char *)commands)[i] != 0xff) {
			return 0;
		}
	if (Ph_ScbPageJustifyQIN((int)(unsigned long)host) !=
	    (int)(unsigned long)(block + 768))
		return 0;
	host[56] = 0x1c;
	if (Ph_ScbPageJustifyQIN((int)(unsigned long)host) !=
	    (int)(unsigned long)(block + 740))
		return 0;
	if (!(sequencer_trace_count == 35 &&
	       sequencer_trace_port[0] == 0x141 && sequencer_trace_value[0] == 0 &&
	       sequencer_trace_port[1] == 0x13b && sequencer_trace_value[1] == 0xff &&
	       sequencer_trace_port[2] == 0x13c && sequencer_trace_value[2] == 0xff &&
	       sequencer_trace_port[3] == 0x13d && sequencer_trace_value[3] == 0x00 &&
	       sequencer_trace_port[4] == 0x13e && sequencer_trace_value[4] == 0x26 &&
	       sequencer_trace_port[7] == 0x142 && sequencer_trace_value[7] == 0x00 &&
	       sequencer_trace_port[19] == 0x146 && sequencer_trace_value[19] == 0x7f &&
	       sequencer_trace_port[34] == 0x155 && sequencer_trace_value[34] == 0x7f))
		return 0;
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block + 0x100;
	*(unsigned int *)(host + 56) = 0x2100;
	if (PH_RelocatePointers((int)(unsigned long)host, 0x100) != 0x7f ||
	    *(unsigned int *)(host + 52) != (unsigned int)(unsigned long)block ||
	    *(unsigned int *)(host + 56) != 0x2000 ||
	    *(unsigned int *)(block + 272) != (unsigned int)(unsigned long)(block + 508))
		return 0;
	host[62] = 5;
	host[64] = 2;
	if (Ph_SetHaData((int)(unsigned long)host) != 0x7f ||
	    *(unsigned int *)block != 0xffffffffU ||
	    *(unsigned int *)(block + 4) != 0xffffffffU ||
	    *(unsigned short *)(block + 266) != 0 ||
	    block[268] != 5 || block[269] != 2 || block[270] != 0 ||
	    *(unsigned int *)(block + 356) != (unsigned int)(unsigned long)host ||
	    *(unsigned int *)(block + 372) != 0x2000 + 404)
		return 0;
	for (i = 8; i != 264; ++i)
		if (block[i] != 0)
			return 0;
	return 1;
}

static int run_optima_noop_checks(void)
{
	Ph_OptimaClearDevQue();
	Ph_OptimaClearChannelBusy();
	return 1;
}

static int run_optima_checks(void)
{
	return run_optima_size_checks() && run_optima_config_checks() &&
	       run_optima_busy_map_checks() && run_optima_free_scb_checks() &&
	       run_optima_enqueue_checks() && run_optima_request_sense_checks() &&
	       run_optima_completion_checks() && run_optima_enable_array_checks() &&
	       run_optima_abort_checks() && run_optima_setup_checks() &&
	       run_optima_function_table_checks() && run_optima_noop_checks();
}

static int is_group(const char *value, const char *expected)
{
	return strcmp(value, expected) == 0;
}

static int run_firmware_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char original = P_Seq_01[17];
	unsigned char expected;
	unsigned int i;
	int result;
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	*(unsigned short *)(host.bytes + A2940_HA_MODE_OFFSET) = 0;
	sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_address = 0;
	result = Ph_LoadSequencer(&host);
	if (result != -2 || sequencer_writes != 0 || sequencer_reads != 0)
		return 0;

	*(unsigned short *)(host.bytes + A2940_HA_MODE_OFFSET) = 2;
	P_SeqExist[20] = 17;
	host.bytes[A2940_HA_OPTIONS_OFFSET] = 1;
	sequencer_address = sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_fail_read = -1;
	result = Ph_LoadSequencer(&host);
	if (result != 0 || P_Seq_01[17] != 0xff ||
	    sequencer_writes != 1960 || sequencer_reads != 1960 ||
	    sequencer_trace_count != 1968 || sequencer_barriers != 1968)
		return 0;
	if (sequencer_trace_port[0] != 0x160 || sequencer_trace_value[0] != 0x91 ||
	    sequencer_trace_port[1] != 0x162 || sequencer_trace_value[1] != 0 ||
	    sequencer_trace_port[2] != 0x163 || sequencer_trace_value[2] != 0 ||
	    sequencer_trace_port[1963] != 0x160 || sequencer_trace_value[1963] != 0x90 ||
	    sequencer_trace_port[1964] != 0x160 || sequencer_trace_value[1964] != 0x91 ||
	    sequencer_trace_port[1965] != 0x162 || sequencer_trace_value[1965] != 0 ||
	    sequencer_trace_port[1966] != 0x163 || sequencer_trace_value[1966] != 0 ||
	    sequencer_trace_port[1967] != 0x160 || sequencer_trace_value[1967] != 0x90)
		return 0;
	for (i = 0; i < 1960; ++i) {
		expected = i == 17 ? 0xff : P_Seq_01[i];
		if (sequencer_ram[i] != expected)
			return 0;
	}

	sequencer_address = sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_fail_read = 17;
	result = Ph_LoadSequencer(&host);
	sequencer_fail_read = -1;
	P_Seq_01[17] = original;
	P_SeqExist[20] = 0;
	return result == 255 && sequencer_writes == 1960 && sequencer_reads == 18 &&
	       sequencer_trace_count == 1967 && sequencer_barriers == 1967;
}

#ifdef A2940_FREESTANDING
void __objc_exec_class(void *module)
{
	(void)module;
}

void *memset(void *destination, int value, size_t length)
{
	unsigned char *bytes = (unsigned char *)destination;
	size_t i;
	for (i = 0; i < length; ++i)
		bytes[i] = (unsigned char)value;
	return destination;
}

extern __declspec(dllimport) __declspec(noreturn)
void __stdcall ExitProcess(unsigned int exitCode);

void mainCRTStartup(void)
{
	ExitProcess(run_firmware_checks() && run_him_chain_checks() &&
	            run_him_config_access_checks() &&
	            run_him_hcntrl_checks() && run_him_status_checks() &&
	            run_him_terminate_checks() &&
	            run_him_misc_checks() && run_him_bookmark_checks() &&
	            run_him_scb_prepare_checks() && run_him_sync_map_checks() &&
	            run_him_negotiation_checks() && run_him_delay_checks() &&
	            run_him_pollint_checks() && run_him_leaf_checks() &&
	            run_him_post_checks() && run_him_req_checks() &&
	            run_him_interrupt_checks() && run_him_noninit_checks() &&
	            run_him_eeprom_command_checks() && run_him_eeprom_data_checks() &&
	            run_him_eeprom_storage_checks() && run_him_bios_buffer_checks() &&
	            run_him_sync_nego_checks() && run_him_driver_config_checks() &&
	            run_optima_checks() ? 0 : 42);
}
#else
int main(int argc, char **argv)
{
	const char *group = argc > 1 ? argv[1] : "all";
	if (is_group(group, "layouts")) {
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"layouts\",\"ok\":true,"
		       "\"cases\":[{\"id\":\"shared-layouts\",\"result\":\"pass\"}],"
		       "\"build_hash\":\"%s\"}\n", A2940_BUILD_HASH);
		return 0;
	}
	if (is_group(group, "firmware")) {
		int ok = run_firmware_checks();
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"firmware\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"sequencer-absent\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-success\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-runtime-patch\",\"result\":\"%s\"},"
		       "{\"id\":\"register-width-order\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-readback-failure\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n", ok ? "true" : "false",
		       ok ? "pass" : "fail", ok ? "pass" : "fail", ok ? "pass" : "fail",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (is_group(group, "config")) {
		int ok = run_him_config_access_checks();
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"config\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"pci-mechanism-scan\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n", ok ? "true" : "false",
		       ok ? "pass" : "fail", A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (is_group(group, "optima")) {
		int size_ok = run_optima_size_checks();
		int config_ok = run_optima_config_checks();
		int busy_ok = run_optima_busy_map_checks();
		int free_ok = run_optima_free_scb_checks();
		int enqueue_ok = run_optima_enqueue_checks();
		int sense_ok = run_optima_request_sense_checks();
		int completion_ok = run_optima_completion_checks();
		int enable_ok = run_optima_enable_array_checks();
		int abort_ok = run_optima_abort_checks();
		int setup_ok = run_optima_setup_checks();
		int table_ok = run_optima_function_table_checks();
		int noop_ok = run_optima_noop_checks();
		int ok = size_ok && config_ok && busy_ok && free_ok && enqueue_ok &&
		         sense_ok && completion_ok && enable_ok && abort_ok && setup_ok &&
		         table_ok && noop_ok;
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"optima\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"optima-size-bounds\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-host-config\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-busy-map\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-free-scb-rings\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-qin-enqueue\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-request-sense\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-command-completion\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-enable-array\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-relocate-pointers\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-abort-active\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-host-setup-scratch\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-hardware-data-init\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-function-table\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-qin-fifo\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-clear-noops\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n",
		       ok ? "true" : "false", size_ok ? "pass" : "fail",
		       config_ok ? "pass" : "fail", busy_ok ? "pass" : "fail",
		       free_ok ? "pass" : "fail", enqueue_ok ? "pass" : "fail",
		       sense_ok ? "pass" : "fail", completion_ok ? "pass" : "fail",
		       enable_ok ? "pass" : "fail", setup_ok ? "pass" : "fail",
		       setup_ok ? "pass" : "fail", abort_ok ? "pass" : "fail",
		       setup_ok ? "pass" : "fail", table_ok ? "pass" : "fail",
		       busy_ok ? "pass" : "fail",
		       noop_ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (is_group(group, "him")) {
		int chain_ok = run_him_chain_checks();
		int config_access_ok = run_him_config_access_checks();
		int hcntrl_ok = run_him_hcntrl_checks();
		int status_ok = run_him_status_checks();
		int terminate_ok = run_him_terminate_checks();
		int misc_ok = run_him_misc_checks();
		int bookmark_ok = run_him_bookmark_checks();
		int prepare_ok = run_him_scb_prepare_checks();
		int sync_map_ok = run_him_sync_map_checks();
		int negotiation_ok = run_him_negotiation_checks();
		int delay_ok = run_him_delay_checks();
		int pollint_ok = run_him_pollint_checks();
		int leaf_ok = run_him_leaf_checks();
		int post_ok = run_him_post_checks();
		int req_ok = run_him_req_checks();
		int irq_ok = run_him_interrupt_checks();
		int noninit_ok = run_him_noninit_checks();
		int eeprom_ok = run_him_eeprom_command_checks();
		int eeprom_data_ok = run_him_eeprom_data_checks();
		int eeprom_storage_ok = run_him_eeprom_storage_checks();
		int bios_buffer_ok = run_him_bios_buffer_checks();
		int sync_nego_ok = run_him_sync_nego_checks();
		int driver_config_ok = run_him_driver_config_checks();
		int ok = chain_ok && config_access_ok && hcntrl_ok && status_ok && terminate_ok && misc_ok && bookmark_ok && prepare_ok && sync_map_ok && negotiation_ok && delay_ok && pollint_ok && leaf_ok && post_ok && req_ok && irq_ok && noninit_ok && eeprom_ok && eeprom_data_ok && eeprom_storage_ok && bios_buffer_ok && sync_nego_ok && driver_config_ok;
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"him\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"chain-empty\",\"result\":\"%s\"},"
		       "{\"id\":\"chain-front-middle-tail\",\"result\":\"%s\"},"
		       "{\"id\":\"chain-previous-miss\",\"result\":\"%s\"},"
		       "{\"id\":\"memory-set\",\"result\":\"%s\"},"
		       "{\"id\":\"hcntrl-write-mask\",\"result\":\"%s\"},"
		       "{\"id\":\"intstat-paused-unpaused\",\"result\":\"%s\"},"
		       "{\"id\":\"pause-unpause\",\"result\":\"%s\"},"
		       "{\"id\":\"short-transfer\",\"result\":\"%s\"},"
		       "{\"id\":\"terminate-queued-scb\",\"result\":\"%s\"},"
		       "{\"id\":\"port-buffer-transfer\",\"result\":\"%s\"},"
		       "{\"id\":\"interrupt-enable-disable\",\"result\":\"%s\"},"
		       "{\"id\":\"negotiation-marker\",\"result\":\"%s\"},"
		       "{\"id\":\"reset-trampolines\",\"result\":\"%s\"},"
		       "{\"id\":\"bookmark-insert-remove\",\"result\":\"%s\"},"
		       "{\"id\":\"scb-mark\",\"result\":\"%s\"},"
		       "{\"id\":\"scb-prepare-status-count\",\"result\":\"%s\"},"
		       "{\"id\":\"sync-period-map\",\"result\":\"%s\"},"
		       "{\"id\":\"renegotiation-marker\",\"result\":\"%s\"},"
		       "{\"id\":\"fast20-map\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-delay\",\"result\":\"%s\"},"
		       "{\"id\":\"poll-interrupt-mask\",\"result\":\"%s\"},"
		       "{\"id\":\"wait-two-usec\",\"result\":\"%s\"},"
		       "{\"id\":\"async-event-callback\",\"result\":\"%s\"},"
		       "{\"id\":\"rebuild-ee-control\",\"result\":\"%s\"},"
		       "{\"id\":\"osm-config-stubs\",\"result\":\"%s\"},"
		       "{\"id\":\"post-nonactive-scb\",\"result\":\"%s\"},"
		       "{\"id\":\"request-phase-parity-error\",\"result\":\"%s\"},"
		       "{\"id\":\"selection-timeout-free-interrupt\",\"result\":\"%s\"},"
		       "{\"id\":\"noninit-event-dispatch\",\"result\":\"%s\"},"
		       "{\"id\":\"eeprom-write-enable-disable\",\"result\":\"%s\"},"
		       "{\"id\":\"eeprom-register-read-write\",\"result\":\"%s\"},"
		       "{\"id\":\"eeprom-image-checksum-update\",\"result\":\"%s\"},"
		       "{\"id\":\"bios-buffer-read-write\",\"result\":\"%s\"},"
		       "{\"id\":\"sync-negotiation-masks\",\"result\":\"%s\"},"
		       "{\"id\":\"driver-config-bios-presence\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n", ok ? "true" : "false",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       hcntrl_ok ? "pass" : "fail", hcntrl_ok ? "pass" : "fail",
		       hcntrl_ok ? "pass" : "fail", status_ok ? "pass" : "fail",
		       terminate_ok ? "pass" : "fail",
		       misc_ok ? "pass" : "fail", misc_ok ? "pass" : "fail",
		       misc_ok ? "pass" : "fail", misc_ok ? "pass" : "fail",
		       bookmark_ok ? "pass" : "fail", bookmark_ok ? "pass" : "fail",
		       prepare_ok ? "pass" : "fail",
		       sync_map_ok ? "pass" : "fail",
		       negotiation_ok ? "pass" : "fail", negotiation_ok ? "pass" : "fail",
		       delay_ok ? "pass" : "fail",
		       pollint_ok ? "pass" : "fail",
		       leaf_ok ? "pass" : "fail", leaf_ok ? "pass" : "fail",
		       leaf_ok ? "pass" : "fail", post_ok ? "pass" : "fail",
		       req_ok ? "pass" : "fail", irq_ok ? "pass" : "fail",
		       noninit_ok ? "pass" : "fail", eeprom_ok ? "pass" : "fail",
		       eeprom_data_ok ? "pass" : "fail",
		       eeprom_storage_ok ? "pass" : "fail",
		       bios_buffer_ok ? "pass" : "fail",
		       sync_nego_ok ? "pass" : "fail",
		       driver_config_ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (!is_group(group, "firmware") && !is_group(group, "him") &&
	    !is_group(group, "config") && !is_group(group, "optima") &&
	    !is_group(group, "integration") && !is_group(group, "all")) {
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"%s\",\"ok\":false,"
		       "\"error\":\"unknown group\",\"build_hash\":\"%s\"}\n",
		       group, A2940_BUILD_HASH);
		return 2;
	}
	printf("{\"schema_version\":\"adaptec2940-checks-v1\","
	       "\"group\":\"%s\",\"ok\":false,"
	       "\"error\":\"production routines for this group are not linked yet\","
	       "\"build_hash\":\"%s\"}\n", group, A2940_BUILD_HASH);
	return 2;
}
#endif /* A2940_FREESTANDING */
