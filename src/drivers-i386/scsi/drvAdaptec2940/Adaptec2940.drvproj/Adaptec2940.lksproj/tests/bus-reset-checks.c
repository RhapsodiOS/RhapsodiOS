/* Native i386 checks for active and queued device-reset SCBs. */
#define A2940_BUS_RESET_STANDALONE 1

static unsigned int active_calls;
static int active_scb;
static int active_result;
static unsigned int index_calls;
static int index_scb;
static unsigned char index_result;
static unsigned int reset_calls;
static int reset_host;
static unsigned int append_calls;
static unsigned int prepare_calls;
static unsigned int terminate_calls;
static int terminate_scb;
static char terminate_index;
static unsigned int post_calls;
static int post_host;
static unsigned int abort_calls;
static int abort_scb;
static unsigned int completed_calls;
static int completed_scb;
static unsigned char reads[8];
static unsigned int read_count;
static unsigned int read_index;
static unsigned char writes[8];
static unsigned int write_count;
static unsigned int start_calls;
static unsigned char start_index;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

static unsigned char __cdecl test_is_active(int *ha, int scb)
{
	(void)ha;
	++active_calls;
	active_scb = scb;
	return (unsigned char)active_result;
}

static unsigned char __cdecl test_scb_index(int *ha, int scb)
{
	(void)ha;
	++index_calls;
	index_scb = scb;
	return index_result;
}

static void __stdcall test_start_scb(unsigned char index)
{
	++start_calls;
	start_index = index;
}

unsigned char a2940_bus_reset_test_inb(unsigned short port)
{
	if (port != 0x187) return 0;
	if (read_index < read_count) return reads[read_index++];
	return reads[read_count - 1];
}

unsigned char Ph_HaHardReset(int host)
{
	++reset_calls;
	reset_host = host;
	return 0;
}

char Ph_ChainAppendEnd(int host, unsigned int *scb)
{
	(void)host;
	(void)scb;
	++append_calls;
	return 0;
}

int Ph_ScbPrepare(int host, int *scb)
{
	(void)host;
	(void)scb;
	++prepare_calls;
	return 0;
}

void Ph_TerminateCommand(int scb, char index)
{
	++terminate_calls;
	terminate_scb = scb;
	terminate_index = index;
}

void *Ph_PostCommand(int host)
{
	++post_calls;
	post_host = host;
	return (void *)0x5a;
}

char Ph_ScbAbort(int scb)
{
	++abort_calls;
	abort_scb = scb;
	return 0;
}

void *PH_ScbCompleted(int scb)
{
	++completed_calls;
	completed_scb = scb;
	return (void *)0x34;
}

unsigned char Ph_WriteHcntrl(short io, unsigned char value)
{
	(void)io;
	writes[write_count++] = value;
	return value;
}

#include "../Adaptec2940BusReset.c"

static unsigned int check_index;
static int check(int condition)
{
	unsigned int bit = 1U << check_index++;
	return condition ? 0 : (int)bit;
}
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char host[80] = {0};
	unsigned char ha[512] = {0};
	unsigned char scb[64] = {0};
	unsigned char queued_a[16] = {0};
	unsigned char queued_b[16] = {0};
	int map[8];
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;
	int result = 0;
	*(int *)(host + 4) = 0x100;
	*(int **)(host + 52) = (int *)ha;
	*(int *)(ha + 272) = (int)(unsigned long)map;
	*(unsigned short *)(ha + 266) = 2;
	*(int *)(ha + 440) = (int)(unsigned long)&test_is_active;
	*(int *)(ha + 448) = (int)(unsigned long)&test_scb_index;
	*(int *)(ha + 480) = (int)(unsigned long)&test_start_scb;
	*(int *)(scb + 4) = host_address;
	scb[12] = 0x30;
	index_result = 4;
	active_result = 1;
	host[30] = 3;
	result |= check(Ph_BusDeviceReset(scb_address) == 0x5a);
	result |= check(active_calls == 1 && active_scb == scb_address);
	result |= check(reset_calls == 1 && reset_host == host_address);
	result |= check(append_calls == 1 && prepare_calls == 1);
	result |= check(index_calls == 1 && index_scb == scb_address);
	result |= check(*(unsigned short *)(ha + 266) == 1 && scb[11] == 64);
	result |= check(map[4] == (int)(unsigned long)scb && scb[24] == 0 && scb[43] == 0);
	result |= check(terminate_calls == 1 && terminate_scb == scb_address && terminate_index == 4);
	result |= check(post_calls == 1 && post_host == host_address);

	active_calls = completed_calls = 0;
	active_result = 0;
	scb[11] = 0; scb[43] = 0;
	result |= check(Ph_BusDeviceReset(scb_address) == 0x34);
	result |= check(active_calls == 1 && completed_calls == 1 && completed_scb == scb_address);
	result |= check(scb[43] == 48 && scb[11] == 4);

	active_calls = index_calls = append_calls = prepare_calls = abort_calls = start_calls = 0;
	write_count = read_index = 0;
	active_result = 1;
	host[30] = 1;
	*(unsigned int *)ha = (unsigned int)(unsigned long)queued_a;
	*(unsigned int *)queued_a = (unsigned int)(unsigned long)queued_b;
	*(unsigned int *)queued_b = 0xffffffffU;
	queued_a[12] = 0x30;
	queued_b[12] = 0x40;
	reads[0] = 0x10; reads[1] = 0x14; reads[2] = 0x14; read_count = 3;
	scb[11] = 0; scb[13] = 0; scb[15] = 0xff;
	*(unsigned int *)(scb + 16) = 0;
	index_result = 6;
	result |= check(Ph_BusDeviceReset(scb_address) == 0x10);
	result |= check(abort_calls == 1 && abort_scb == (int)(unsigned long)queued_a);
	result |= check(append_calls == 1 && prepare_calls == 1 && index_calls == 1);
	result |= check(scb[15] == 0 && *(unsigned int *)(scb + 16) == 12);
	result |= check((scb[13] & 8) != 0 && scb[11] == 65 && map[6] == (int)(unsigned long)scb);
	result |= check(write_count == 2 && writes[0] == 0x14 && writes[1] == 0x10);
	result |= check(start_calls == 1 && start_index == 6);
	ExitProcess((unsigned int)result);
}
