/* Native i386 checks for the production SCB submission entry point. */
#define A2940_SCB_STANDALONE 1

static unsigned char hcntrl_value;
static unsigned char hcntrl_written;
static unsigned short hcntrl_port;
static unsigned short mode_seen;
static unsigned int trace[8];
static unsigned int trace_count;
static unsigned int special_calls;
static unsigned int append_calls;
static unsigned int prepare_calls;
static unsigned int send_calls;
static unsigned int noninit_calls;
static int send_result;
static int noninit_result;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int index;
	for (index = 0; index < length; ++index)
		bytes[index] = (unsigned char)value;
	return destination;
}

unsigned char a2940_scb_test_inb(unsigned short port)
{
	hcntrl_port = port;
	return hcntrl_value;
}

int PH_Special(char code, int host, int scb)
{
	(void)host;
	(void)scb;
	if (code != 16) return -1;
	++special_calls;
	trace[trace_count++] = 1;
	return 0;
}

char Ph_ChainAppendEnd(int host, unsigned int *scb)
{
	(void)host;
	(void)scb;
	++append_calls;
	trace[trace_count++] = 2;
	return 0;
}

int Ph_ScbPrepare(int host, int *scb)
{
	(void)host;
	(void)scb;
	++prepare_calls;
	trace[trace_count++] = 3;
	return 0;
}

int Ph_SendCommand(int **ha, int io)
{
	(void)io;
	mode_seen = *(unsigned short *)((unsigned char *)ha + 284);
	++send_calls;
	trace[trace_count++] = 4;
	return send_result;
}

int Ph_WriteHcntrl(short io, unsigned char value)
{
	hcntrl_port = (unsigned short)(io + 135);
	hcntrl_written = value;
	trace[trace_count++] = 5;
	return value;
}

int Ph_NonInit(int scb)
{
	(void)scb;
	++noninit_calls;
	trace[trace_count++] = 6;
	return noninit_result;
}

#include "../Adaptec2940Scb.c"

static int check(int condition) { return condition ? 0 : 1; }
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char host[80] = {0};
	unsigned char ha[512] = {0};
	unsigned char scb[32] = {0};
	int result = 0;
	*(int *)(host + 4) = 0x100;
	*(unsigned char **)(host + 52) = ha;
	*(int *)(scb + 4) = (int)(unsigned long)host;
	scb[8] = 2;
	scb[13] = 0x18;
	ha[287] = 2;
	*(unsigned short *)(ha + 284) = 0;
	hcntrl_value = 2;
	send_result = 1;
	result |= check(PH_ScbSend((int)(unsigned long)scb) == 0x12);
	result |= check(hcntrl_port == 0x187 && hcntrl_written == 0x12);
	result |= check(special_calls == 1 && append_calls == 1 && prepare_calls == 1);
	result |= check(send_calls == 1 && mode_seen == 1 && noninit_calls == 0);
	result |= check(scb[13] == 0x10 && *(unsigned short *)(ha + 284) == 0);
	result |= check(trace_count == 5 && trace[0] == 1 && trace[1] == 2 &&
		trace[2] == 3 && trace[3] == 4 && trace[4] == 5);

	trace_count = special_calls = append_calls = prepare_calls = send_calls = 0;
	*(unsigned short *)(ha + 284) = 7;
	*(unsigned char *)(ha + 287) = 0;
	scb[8] = 0;
	scb[13] = 8;
	hcntrl_value = 0x20;
	result |= check(PH_ScbSend((int)(unsigned long)scb) == 0x20);
	result |= check(special_calls == 0 && append_calls == 1 && prepare_calls == 1);
	result |= check(send_calls == 0 && *(unsigned short *)(ha + 284) == 7);
	result |= check(scb[13] == 0 && hcntrl_written == 0x20);

	trace_count = 0;
	scb[8] = 1;
	noninit_result = -3;
	*(unsigned short *)(ha + 284) = 9;
	result |= check(PH_ScbSend((int)(unsigned long)scb) == -3);
	result |= check(noninit_calls == 1 && *(unsigned short *)(ha + 284) == 9);
	result |= check(trace_count == 1 && trace[0] == 6);
	ExitProcess((unsigned int)result);
}
