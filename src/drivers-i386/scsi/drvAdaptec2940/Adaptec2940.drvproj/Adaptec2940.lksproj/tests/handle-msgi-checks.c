/* Native i386 checks for standard SCSI message-in handling. */
#define A2940_HANDLE_MSGI_STANDALONE 1

static unsigned char registers[512];
static unsigned short ports[32];
static unsigned char values[32];
static unsigned int out_count;
static unsigned char message_code;
static unsigned char transfer_count;
static unsigned int msg18_reads;
static unsigned char wt4_results[8];
static unsigned int wt4_count;
static unsigned int wt4_index;
static unsigned int wt4_calls;
static unsigned int badseq_calls;
static int badseq_host;
static int badseq_io;
static unsigned int target_abort_calls;
static int target_abort_args[3];

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

unsigned char a2940_msgi_test_inb(unsigned short port)
{
	if (port == 0x112) {
		++msg18_reads;
		return msg18_reads == 1 ? message_code : transfer_count;
	}
	return registers[port & 0x1ff];
}

void a2940_msgi_test_outb(unsigned short port, unsigned char value)
{
	ports[out_count] = port;
	values[out_count++] = value;
	registers[port & 0x1ff] = value;
}

int Ph_Wt4Req(int scb, short io)
{
	(void)scb; (void)io; ++wt4_calls;
	if (wt4_index >= wt4_count) return -1;
	return wt4_results[wt4_index++];
}

int Ph_BadSeq(int host, int io)
{
	++badseq_calls; badseq_host = host; badseq_io = io; return 0x35;
}

int Ph_TargetAbort(int host, int scb, int io)
{
	++target_abort_calls;
	target_abort_args[0] = host; target_abort_args[1] = scb; target_abort_args[2] = io;
	return -3;
}

#include "../Adaptec2940HandleMsgi.c"

static unsigned int check_index;
static int check(int condition)
{
	unsigned int bit = 1U << check_index++;
	return condition ? 0 : (int)bit;
}
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

static void reset_trace(void)
{
	out_count = msg18_reads = wt4_calls = wt4_index = badseq_calls = target_abort_calls = 0;
	wt4_count = 0;
}

void mainCRTStartup(void)
{
	unsigned char host[80] = {0};
	unsigned char scb[64] = {0};
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;
	int result = 0;
	*(int *)(scb + 4) = host_address;

	registers[0x103] = 0x10; registers[0x106] = 9;
	reset_trace();
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == 9 && out_count == 0 && msg18_reads == 0);

	registers[0x103] = 0; message_code = 7; registers[0x13a] = 0xa0; registers[0x106] = 8;
	reset_trace();
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == -3);
	result |= check(target_abort_calls == 1 && target_abort_args[0] == host_address &&
		target_abort_args[1] == scb_address && target_abort_args[2] == 0x100);
	result |= check(out_count == 1 && ports[0] == 0x103 && values[0] == 0xf0);

	registers[0x13a] = 0; message_code = 7;
	reset_trace();
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == 8 && out_count == 0);

	message_code = 35; transfer_count = 3; registers[0x103] = 0;
	registers[0x108] = 0xff; registers[0x109] = 0; registers[0x10a] = 0;
	registers[0x114] = 0; registers[0x115] = 0; registers[0x116] = 1; registers[0x117] = 0;
	registers[0x106] = 7; *(unsigned int *)(scb + 28) = 0xa123;
	reset_trace();
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == 7);
	result |= check(wt4_calls == 1 && msg18_reads == 2);
	result |= check(registers[0x108] == 2 && registers[0x109] == 1 && registers[0x10a] == 0);
	result |= check(*(unsigned int *)(scb + 28) == 0xa126);
	result |= check(registers[0x188] == 0xfd && registers[0x189] == 0xff &&
		registers[0x18a] == 0 && registers[0x18b] == 0);
	result |= check(out_count == 7 && ports[0] == 0x108 && ports[3] == 0x188);

	message_code = 1;
	reset_trace();
	wt4_results[0] = (unsigned char)-32; wt4_results[1] = (unsigned char)-32;
	wt4_results[2] = (unsigned char)-96; wt4_count = 3;
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == 7 && wt4_calls == 3);
	result |= check(out_count == 4 && ports[0] == 0x103 && values[0] == 0xf0 &&
		ports[1] == 0x103 && values[1] == 0xa0 && ports[2] == 0x10c &&
		values[2] == 0x40 && ports[3] == 0x106 && values[3] == 7);

	message_code = 1;
	reset_trace();
	wt4_results[0] = 0; wt4_count = 1;
	result |= check(Ph_HandleMsgi(scb_address, 0x100) == 0x35 &&
		badseq_calls == 1 && badseq_host == host_address && badseq_io == 0x100);
	ExitProcess((unsigned int)result);
}
