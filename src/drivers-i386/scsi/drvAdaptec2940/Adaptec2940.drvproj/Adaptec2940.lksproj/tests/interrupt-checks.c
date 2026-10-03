/* Native i386 checks for the production HIM interrupt state machine. */
#define A2940_INTERRUPT_STANDALONE 1
#include "../Adaptec2940Interrupt.c"

static unsigned char registers[512];
static unsigned char interrupt_script[8];
static unsigned int interrupt_script_count;
static unsigned int interrupt_script_index;
static unsigned int hcntrl_write_count;
static unsigned char hcntrl_writes[16];
static unsigned int send_command_calls;
static unsigned int post_command_calls;
static unsigned int completion_calls;
static unsigned int completion_host;
static unsigned int completion_control;
static unsigned int completion_mask;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i)
		bytes[i] = (unsigned char)value;
	return destination;
}

void a2940_test_outb(unsigned short port, unsigned char value)
{
	registers[port & 0x1ff] = value;
}

unsigned char a2940_test_inb(unsigned short port)
{
	return registers[port & 0x1ff];
}

int Ph_ReadIntstat(short io)
{
	(void)io;
	if (interrupt_script_index < interrupt_script_count)
		return interrupt_script[interrupt_script_index++];
	return 0;
}

int Ph_WriteHcntrl(short io, unsigned char value, ...)
{
	(void)io;
	if (hcntrl_write_count < 16)
		hcntrl_writes[hcntrl_write_count] = value;
	++hcntrl_write_count;
	return value;
}

char Ph_IntSrst(int host) { (void)host; return 0; }
char Ph_CheckLength(int scb, short io) { (void)scb; (void)io; return 0; }
char Ph_CdbAbort(int scb, int io) { (void)scb; (void)io; return 0; }
unsigned char Ph_SendMsgo(unsigned char *scb, int io) { (void)scb; (void)io; return 0; }
char Ph_CheckCondition(int scb, short io) { (void)scb; (void)io; return 0; }
char Ph_BadSeq(int host, int io) { (void)host; (void)io; return 0; }
char Ph_ExtMsgi(int scb, int io) { (void)scb; (void)io; return 0; }
char Ph_HandleMsgi(int scb, int io) { (void)scb; (void)io; return 0; }
int Ph_TargetAbort(int host, int scb, int io) { (void)host; (void)scb; (void)io; return 0; }
char Ph_Negotiate(int scb, int io) { (void)scb; (void)io; return 0; }
char Ph_IntSelto(int host, int scb) { (void)host; (void)scb; return 0; }
char Ph_IntFree(int host, int scb) { (void)host; (void)scb; return 0; }
unsigned char Ph_ParityError(int scb, int io) { (void)scb; (void)io; return 0; }
int Ph_SendCommand(int **ha, int io) { (void)ha; (void)io; ++send_command_calls; return 0; }
void *Ph_PostCommand(int host) { (void)host; ++post_command_calls; return 0; }
int Ph_SendTrmMsg(unsigned int host, unsigned int scb) { (void)host; (void)scb; return 0; }
int Ph_TrmCmplt(void) { return 0; }

static int completion_handler(int host, unsigned char control, unsigned int mask)
{
	++completion_calls;
	completion_host = (unsigned int)host;
	completion_control = control;
	completion_mask = mask;
	return 0;
}

__declspec(dllimport) __declspec(noreturn) void __stdcall ExitProcess(unsigned int);

int mainCRTStartup(void)
{
	unsigned char host[80] = {0};
	unsigned char ha[512] = {0};
	int result = 0;
	int (*handler)(int, unsigned char, unsigned int) = completion_handler;
	unsigned int check_index = 0;
#define CHECK(value) do { ++check_index; if (!(value)) result |= 1 << (check_index - 1); } while (0)

	*(int *)(host + 4) = 0x100;
	*(unsigned char **)(host + 52) = ha;
	*(int (**)(int, unsigned char, unsigned int))(ha + 444) = handler;
	registers[0x187] = 2;
	interrupt_script[0] = 2;
	interrupt_script[1] = 0;
	interrupt_script_count = 2;

	CHECK(PH_IntHandler((int)(unsigned long)host) == 2);
	CHECK(completion_calls == 1 && completion_host == (unsigned int)(unsigned long)host);
	CHECK(completion_control == 0x12 && completion_mask == 0x200);
	CHECK(send_command_calls == 3);
	CHECK(post_command_calls == 2);
	CHECK(*(unsigned short *)(ha + 284) == 0);
	CHECK(hcntrl_write_count == 3 && hcntrl_writes[0] == 0x12 &&
		hcntrl_writes[1] == 0x10 && hcntrl_writes[2] == 2);

	completion_calls = send_command_calls = post_command_calls = hcntrl_write_count = 0;
	interrupt_script_index = 0;
	interrupt_script_count = 1;
	interrupt_script[0] = 2;
	*(unsigned short *)(ha + 284) = 1;
	registers[0x187] = 0x12;
	CHECK(PH_IntHandler((int)(unsigned long)host) == 2);
	CHECK(completion_calls == 0 && send_command_calls == 0 &&
		post_command_calls == 0 && hcntrl_write_count == 0);
	CHECK(*(unsigned short *)(ha + 284) == 1);

	interrupt_script_index = 0;
	interrupt_script_count = 1;
	interrupt_script[0] = 0;
	CHECK(PH_IntHandler((int)(unsigned long)host) == 0);
	ExitProcess((unsigned int)result);
}
