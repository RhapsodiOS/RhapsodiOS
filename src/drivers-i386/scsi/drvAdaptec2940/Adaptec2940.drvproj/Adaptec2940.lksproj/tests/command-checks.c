/* Native i386 checks for host-adapter command queue draining. */
#define A2940_COMMAND_STANDALONE 1

static unsigned int active_calls;
static int active_scb[8];
static int allowed_scb;
static unsigned int index_calls;
static int index_scb;
static unsigned char index_result;
static unsigned int start_calls;
static int start_scb;
static int start_io;
static unsigned char start_index;
static unsigned char reads[8];
static unsigned int read_count;
static unsigned int read_index;
static unsigned char writes[8];
static unsigned int write_count;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

static unsigned char __cdecl test_is_active(int **ha, int *scb)
{
	(void)ha;
	if (active_calls < 8) active_scb[active_calls] = (int)(unsigned long)scb;
	++active_calls;
	return scb == (int *)(unsigned long)(unsigned int)allowed_scb;
}

static unsigned char __cdecl test_scb_index(int **ha, int *scb)
{
	(void)ha;
	++index_calls;
	index_scb = (int)(unsigned long)scb;
	return index_result;
}

static void __cdecl test_start_command(int index, int *scb, int io)
{
	++start_calls;
	start_index = (unsigned char)index;
	start_scb = (int)(unsigned long)scb;
	start_io = io;
}

unsigned char a2940_command_test_inb(unsigned short port)
{
	if (port != 0x187) return 0;
	if (read_index < read_count) return reads[read_index++];
	return reads[read_count - 1];
}

unsigned char Ph_WriteHcntrl(short io, unsigned char value)
{
	(void)io;
	writes[write_count++] = value;
	return value;
}

#include "../Adaptec2940Command.c"

static int check(int condition) { return condition ? 0 : 1; }
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char ha_bytes[512] = {0};
	unsigned char scb_a[32] = {0};
	unsigned char scb_b[32] = {0};
	int map[8];
	int **ha = (int **)ha_bytes;
	int scb_a_address = (int)(unsigned long)scb_a;
	int scb_b_address = (int)(unsigned long)scb_b;
	int result = 0;
	ha[0] = (int *)scb_a;
	ha[68] = map;
	ha[110] = (int *)(unsigned long)(unsigned int)&test_is_active;
	ha[112] = (int *)(unsigned long)(unsigned int)&test_scb_index;
	ha[119] = (int *)(unsigned long)(unsigned int)&test_start_command;
	*(unsigned short *)(ha_bytes + 266) = 2;
	*(int *)scb_a = (int)(unsigned long)scb_b;
	*(int *)scb_b = -1;
	scb_a[11] = 16;
	scb_b[11] = 16;
	allowed_scb = scb_a_address;
	index_result = 3;
	reads[0] = 0x10; reads[1] = 0x14; read_count = 2;
	result |= check(Ph_SendCommand(ha, 0x100) == 0);
	result |= check(active_calls == 2 && active_scb[0] == scb_a_address && active_scb[1] == scb_b_address);
	result |= check(index_calls == 1 && index_scb == scb_a_address);
	result |= check(*(unsigned short *)(ha_bytes + 266) == 1 && scb_a[11] == 64);
	result |= check(map[3] == scb_a_address);
	result |= check(start_calls == 1 && start_index == 3 && start_scb == scb_a_address && start_io == 0x100);
	result |= check(write_count == 2 && writes[0] == 0x14 && writes[1] == 0x10);

	active_calls = index_calls = start_calls = write_count = 0;
	*(unsigned short *)(ha_bytes + 266) = 1;
	*(int *)scb_a = -1;
	scb_a[11] = 4;
	allowed_scb = scb_a_address;
	result |= check(Ph_SendCommand(ha, 0x100) == 0);
	result |= check(active_calls == 1 && active_scb[0] == scb_a_address);
	result |= check(index_calls == 0 && start_calls == 0 && scb_a[11] == 4);

	active_calls = 0;
	ha[0] = (int *)-1;
	*(unsigned short *)(ha_bytes + 266) = 3;
	result |= check(Ph_SendCommand(ha, 0x100) == 0 && active_calls == 0);
	ExitProcess((unsigned int)result);
}
