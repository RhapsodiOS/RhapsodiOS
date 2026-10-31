/* Native i386 branch checks for the production special-command dispatcher. */
#define A2940_SPECIAL_STANDALONE 1

static unsigned char reads[16];
static unsigned int read_count;
static unsigned int read_index;
static unsigned char writes[16];
static unsigned int write_count;
static unsigned short write_port;
static unsigned int abort_calls;
static int abort_scb;
static unsigned int hard_reset_calls;
static int hard_reset_host;
static unsigned int renego_calls;
static int renego_host;
static unsigned char renego_target;
static unsigned int swap_calls;
static int swap_host;
static char swap_save;
static unsigned short swap_mode;
static int swap_result;
static unsigned int send_calls;
static unsigned short send_mode;
static int send_result;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int index;
	for (index = 0; index < length; ++index)
		bytes[index] = (unsigned char)value;
	return destination;
}

unsigned char a2940_special_test_inb(unsigned short port)
{
	if (port != 0x187) return 0;
	if (read_index >= read_count) return reads[read_count - 1];
	return reads[read_index++];
}

int Ph_ScbAbort(int scb)
{
	++abort_calls;
	abort_scb = scb;
	return 0;
}

unsigned char Ph_HaHardReset(int host)
{
	++hard_reset_calls;
	hard_reset_host = host;
	return 0;
}

char Ph_ScbRenego(int host, unsigned char target)
{
	++renego_calls;
	renego_host = host;
	renego_target = target;
	return 0;
}

int SWAPCurrScratchRam(int host, char save)
{
	++swap_calls;
	swap_host = host;
	swap_save = save;
	swap_mode = *(unsigned short *)((unsigned char *)(*(unsigned char **)
		((unsigned char *)(unsigned long)(unsigned int)host + 52)) + 284);
	return swap_result;
}

int Ph_SendCommand(int **ha, int io)
{
	(void)io;
	++send_calls;
	send_mode = *(unsigned short *)((unsigned char *)ha + 284);
	return send_result;
}

int Ph_WriteHcntrl(short io, unsigned char value)
{
	write_port = (unsigned short)(io + 135);
	writes[write_count++] = value;
	return value;
}

#include "../Adaptec2940Special.c"

static int check(int condition) { return condition ? 0 : 1; }
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char host[80] = {0};
	unsigned char ha[512] = {0};
	unsigned char scb[32] = {0};
	int host_address = (int)(unsigned long)host;
	int scb_address = (int)(unsigned long)scb;
	int result = 0;
	*(int *)(host + 4) = 0x100;
	*(unsigned char **)(host + 52) = ha;
	*(unsigned char *)(scb + 12) = 0x35;
	*(unsigned short *)(ha + 284) = 0;

	reads[0] = 2; reads[1] = 6; read_count = 2; read_index = 0;
	swap_result = 7;
	result |= check(PH_Special(16, host_address, scb_address) == 7);
	result |= check(swap_calls == 1 && swap_host == host_address && swap_save == 1 && swap_mode == 1);
	result |= check(ha[287] == 3 && *(unsigned short *)(ha + 284) == 0);
	result |= check(write_count == 2 && writes[0] == 6 && writes[1] == 2 && write_port == 0x187);

	write_count = swap_calls = read_index = 0;
	*(unsigned int *)ha = 0xffffffffU;
	ha[287] = 0;
	reads[0] = 0x10; reads[1] = 0x14; read_count = 2;
	swap_result = -2;
	result |= check(PH_Special(5, host_address, scb_address) == -2);
	result |= check(swap_calls == 1 && ha[287] == 2 && writes[0] == 0x14 && writes[1] == 0x10);
	result |= check(*(unsigned short *)(ha + 284) == 0);

	write_count = swap_calls = 0;
	*(unsigned int *)ha = 0;
	ha[287] = 0;
	result |= check(PH_Special(5, host_address, scb_address) == -1);
	result |= check(swap_calls == 0 && write_count == 0 && *(unsigned short *)(ha + 284) == 0);

	write_count = renego_calls = read_index = 0;
	reads[0] = 2; reads[1] = 6; reads[2] = 6; read_count = 3;
	*(unsigned short *)(ha + 284) = 9;
	result |= check(PH_Special(3, host_address, scb_address) == 0);
	result |= check(renego_calls == 1 && renego_host == host_address && renego_target == 0x35);
	result |= check(write_count == 2 && writes[0] == 6 && writes[1] == 2);
	result |= check(*(unsigned short *)(ha + 284) == 9);

	write_count = send_calls = 0;
	reads[0] = 0x21; read_count = 1; read_index = 0;
	*(unsigned short *)(ha + 284) = 0;
	send_result = 1;
	result |= check(PH_Special(0, host_address, scb_address) == 0);
	result |= check(abort_calls == 1 && abort_scb == scb_address);
	result |= check(send_calls == 1 && send_mode == 1 && writes[0] == 0x31);
	result |= check(*(unsigned short *)(ha + 284) == 0);

	result |= check(PH_Special(2, host_address, scb_address) == 0 &&
		hard_reset_calls == 1 && hard_reset_host == host_address);
	ExitProcess((unsigned int)result);
}
