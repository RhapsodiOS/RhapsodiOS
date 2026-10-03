/* Native i386 checks for CHECK CONDITION callbacks and register handling. */
#define A2940_CHECK_CONDITION_STANDALONE 1

static unsigned char registers[512];
static unsigned short out_ports[16];
static unsigned char out_values[16];
static unsigned int out_count;
static unsigned int normal_calls;
static int normal_host;
static unsigned char normal_status;
static unsigned int autosense_calls;
static int autosense_scb;
static unsigned char autosense_status;
static unsigned int terminate_calls;
static int terminate_scb;
static char terminate_status;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

unsigned char a2940_cc_test_inb(unsigned short port) { return registers[port & 0x1ff]; }
void a2940_cc_test_outb(unsigned short port, unsigned char value)
{
	out_ports[out_count] = port;
	out_values[out_count++] = value;
	registers[port & 0x1ff] = value;
}

static void __attribute__((stdcall)) test_normal_callback(int host, unsigned char status)
{
	++normal_calls; normal_host = host; normal_status = status;
}

static void __attribute__((stdcall)) test_autosense_callback(int scb, unsigned char status)
{
	++autosense_calls; autosense_scb = scb; autosense_status = status;
}

void Ph_TerminateCommand(int scb, char status)
{
	++terminate_calls; terminate_scb = scb; terminate_status = status;
}

#include "../Adaptec2940CheckCondition.c"

static unsigned int check_index;
static int check(int condition)
{
	unsigned int bit = 1U << check_index++;
	return condition ? 0 : (int)bit;
}
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

static void reset_trace(void)
{
	out_count = normal_calls = autosense_calls = terminate_calls = 0;
}

void mainCRTStartup(void)
{
	unsigned char host[128] = {0};
	unsigned char ha[512] = {0};
	unsigned char scb[64] = {0};
	int result = 0;
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;
	int **callbacks = (int **)ha;
	*(int **)(host + 52) = (int *)ha;
	callbacks[117] = (int *)(unsigned long)(unsigned int)&test_normal_callback;
	callbacks[118] = (int *)(unsigned long)(unsigned int)&test_autosense_callback;

	*(int *)(scb + 4) = host_address;
	scb[12] = 0x30; scb[10] = 0x82; scb[11] = 0;
	host[14] = 1;
	registers[0x13a] = 2; registers[0x13c] = 0x22;
	registers[0x101] = 0x10; registers[0x111] = 0x28; registers[0x106] = 0xee;
	reset_trace();
	result |= check(Ph_CheckCondition(scb_address, 0x100) == 0);
	result |= check(scb[24] == 2 && scb[10] == 0x80);
	result |= check(autosense_calls == 1 && autosense_scb == scb_address && autosense_status == 0x22);
	result |= check(normal_calls == 0 && terminate_calls == 0);
	result |= check(out_count == 5 && out_ports[0] == 0x123 && out_values[0] == 0 &&
		out_ports[1] == 0x101 && out_values[1] == 0x12 &&
		out_ports[2] == 0x111 && out_values[2] == 0x20 &&
		out_ports[3] == 0x162 && out_ports[4] == 0x163);

	host[14] = 0; scb[10] = 0; registers[0x13a] = 0; registers[0x13c] = 5;
	registers[0x101] = 0; registers[0x111] = 0xf8;
	reset_trace();
	result |= check(Ph_CheckCondition(scb_address, 0x100) == 0);
	result |= check(normal_calls == 1 && normal_host == host_address && normal_status == 5);
	result |= check(terminate_calls == 1 && terminate_scb == scb_address && terminate_status == 5);
	result |= check(out_count == 4 && out_ports[0] == 0x101 && out_values[0] == 2 &&
		out_ports[1] == 0x111 && out_values[1] == 0xf0);

	*(unsigned char *)(host + 35) = 0x81;
	registers[0x13a] = 2; registers[0x13c] = 0x28;
	reset_trace();
	result |= check(Ph_CheckCondition(scb_address, 0x100) == 0);
	result |= check(out_count == 5 && out_ports[0] == 0x123 && out_values[0] == 0x8f);

	scb[11] = 8; scb[24] = 0; scb[43] = 0; registers[0x13c] = 1;
	reset_trace();
	result |= check(Ph_CheckCondition(scb_address, 0x100) == 0);
	result |= check(scb[43] == 27 && scb[24] == 0 && normal_calls == 1);
	ExitProcess((unsigned int)result);
}
