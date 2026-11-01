/* Native i386 checks for adapter BIOS and target-ID discovery. */
#define A2940_BIOS_STANDALONE 1

static unsigned char registers[0x3000];
static unsigned short out_ports[8];
static unsigned char out_values[8];
static unsigned int out_count;
static unsigned int config_calls;
static int config_host;
static unsigned char config_bus;
static unsigned char config_device;
static unsigned char config_offset;
static int pause_calls;
static int pause_io;
static int hcntrl_calls;
static short hcntrl_io;
static unsigned char hcntrl_value;

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

int Ph_ReadConfig(int host, unsigned char bus, unsigned char device, unsigned char offset)
{
	++config_calls; config_host = host; config_bus = bus; config_device = device; config_offset = offset;
	return 0x1003;
}

unsigned char Ph_Pause(int io)
{
	++pause_calls; pause_io = io; return 0;
}

unsigned char Ph_WriteHcntrl(short io, unsigned char value, ...)
{
	++hcntrl_calls; hcntrl_io = io; hcntrl_value = value; return value;
}

unsigned char a2940_bios_test_inb(unsigned short port) { return registers[port]; }
void a2940_bios_test_outb(unsigned short port, unsigned char value)
{
	out_ports[out_count] = port;
	out_values[out_count++] = value;
	registers[port] = value;
}

#include "../Adaptec2940Bios.c"

static unsigned int check_index;
static int check(int condition)
{
	unsigned int bit = 1U << check_index++;
	return condition ? 0 : (int)bit;
}
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char info[16];
	int result = 0;
	registers[0x1087] = 0x30;
	registers[0x1090] = 0x46;
	registers[0x10a0] = 0; registers[0x10a1] = 0x20;
	registers[0x10a2] = 0; registers[0x10a3] = 0;
	registers[0x10b0] = 0; registers[0x10b1] = 0x30;
	registers[0x10b2] = 0; registers[0x10b3] = 0;
	registers[0x10ac] = 0x40; registers[0x10ad] = 1; registers[0x10ae] = 0x42;
	registers[0x10a4] = 0xa2; registers[0x10a5] = 0xb3; registers[0x10a6] = 0x14;
	registers[0x10b2] = 0xab; registers[0x10b3] = 0xcd;
	memset(info, 0x55, sizeof(info));
	result |= check(PH_GetBiosInfo(77, 2, 5, info) == 0);
	result |= check(config_calls == 1 && config_host == -1 && config_bus == 2 &&
		config_device == 5 && config_offset == 16);
	result |= check(pause_calls == 1 && pause_io == 0x1000);
	result |= check(info[0] == 7 && info[1] == 2 && info[2] == 4);
	result |= check(info[3] == 2 && info[4] == 3 && info[5] == 4);
	result |= check(info[6] == 0xff && info[10] == 0xff && info[11] == 0x55);
	result |= check(info[12] == 0xab && info[13] == 0xcd);
	result |= check(out_count == 2 && out_ports[0] == 0x1090 && out_values[0] == 2 &&
		out_ports[1] == 0x1090 && out_values[1] == 3);
	result |= check(hcntrl_calls == 1 && hcntrl_io == 0x1000 && hcntrl_value == 0x30);

	out_count = 0;
	registers[0x1090] = 0x55;
	registers[0x10a0] = registers[0x10a1] = registers[0x10a2] = registers[0x10a3] = 0;
	memset(info, 0, sizeof(info));
	result |= check(PH_GetBiosInfo(0, 1, 3, info) == 0xff);
	result |= check(info[0] == 0 && info[1] == 0xff && info[2] == 0xff);
	result |= check(info[3] == 0xff && info[10] == 0xff);
	result |= check(out_count == 2 && out_values[0] == 2 && out_values[1] == 0x55);
	result |= check(hcntrl_calls == 2 && hcntrl_value == 0x30);
	ExitProcess((unsigned int)result);
}
