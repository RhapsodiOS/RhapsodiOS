/* Standalone 32-bit harness for the production PCI configuration module. */
#define A2940_CONFIG_STANDALONE 1
#define A2940_RECOVERY_STANDALONE 1
#define A2940_TEST 1

static unsigned char present[256][32];
static unsigned int words[256][32][64];
static unsigned int address_register;
static unsigned char selected_bus;
static unsigned char mechanism2;
static unsigned int reads;
static unsigned char input_registers[256];
static unsigned char cable_status;
static unsigned int eeprom_update_calls;
static unsigned int eeprom_update_host;
static int eeprom_update_io;
static unsigned short eeprom_update_register;
static int eeprom_update_result;
static unsigned int no_assist_calls;
static unsigned char no_assist_result;
static unsigned short init_trace_port[128];
static unsigned char init_trace_value[128];
static unsigned int init_trace_count;
static unsigned int init_driver_calls;
static unsigned int sequencer_load_calls;
static int sequencer_load_result;
static unsigned int delay_calls;
static int delay_last_duration;
static unsigned int unpause_calls;
static unsigned int abort_post_calls;
static unsigned int abort_post_status;
static unsigned int abort_prepare_calls;
static unsigned int abort_prepared_scb;
static int eeprom_read_result;
static unsigned int eeprom_read_calls;
static unsigned int driver_config_calls;
static unsigned int pause_calls;
static unsigned int hcntrl_write_calls;
static int hcntrl_write_base;
static unsigned char hcntrl_write_value;
static int interrupt_status;
static unsigned int async_event_calls;
static int async_event_value;
static int async_event_host;
static int async_event_io;
static int wt4req_status;
static unsigned int wt4req_calls;
static unsigned int bookmark_insert_calls;
static unsigned int bookmark_remove_calls;
int a2940_test_config_osm_override = -1;
int a2940_test_bus_count_override = -1;

void a2940_test_outb(unsigned short port, unsigned char value)
{
	if (init_trace_count < 128) {
		init_trace_port[init_trace_count] = port;
		init_trace_value[init_trace_count++] = value;
	}
	input_registers[port & 0xff] = value;
	if (port == 0xcfa)
		selected_bus = value;
	else if (port == 0xcf8)
		mechanism2 = value;
}

unsigned char a2940_test_inb(unsigned short port)
{
	return input_registers[port & 0xff];
}

unsigned char Ph_NoAssistTerm(int host)
{
	(void)host;
	++no_assist_calls;
	return no_assist_result;
}

int Ph_ReadCableStatus(int host)
{
	(void)host;
	return cable_status;
}

int Ph_UpdateEeprom(unsigned short *host, int io, unsigned short reg)
{
	++eeprom_update_calls;
	eeprom_update_host = (unsigned int)host;
	eeprom_update_io = io;
	eeprom_update_register = reg;
	return eeprom_update_result;
}

int Ph_GetDrvrConfig(int host)
{
	(void)host;
	++driver_config_calls;
	return 0;
}

int Ph_InitDrvrHA(int host)
{
	(void)host;
	++init_driver_calls;
	return 0;
}

int Ph_LoadSequencer(void *host)
{
	(void)host;
	++sequencer_load_calls;
	return sequencer_load_result;
}

int Ph_UnPause(int io)
{
	(void)io;
	++unpause_calls;
	return 0;
}

unsigned char Ph_Delay(int io, int duration)
{
	(void)io;
	++delay_calls;
	delay_last_duration = duration;
	return 0;
}

char Ph_CheckSyncNego(int host)
{
	(void)host;
	return 0;
}

char Ph_ResetChannel(int host)
{
	(void)host;
	return 0;
}

int Ph_ReadIntstat(short io)
{
	(void)io;
	return interrupt_status;
}

int Ph_AsynchEvent(int event, int host, int io)
{
	++async_event_calls;
	async_event_value = event;
	async_event_host = host;
	async_event_io = io;
	return 0;
}

int Ph_Wt4Req(int scb, short io)
{
	(void)scb;
	(void)io;
	++wt4req_calls;
	return wt4req_status;
}

char Ph_InsertBookmark(int host)
{
	(void)host;
	++bookmark_insert_calls;
	return 0;
}

int Ph_RemoveBookmark(int host)
{
	(void)host;
	++bookmark_remove_calls;
	return 0;
}

void *Ph_PostNonActiveScb(int host, int scb)
{
	unsigned int *queue = *(unsigned int **)((unsigned char *)(unsigned long)(unsigned int)host + 52);
	unsigned char *entry = (unsigned char *)(unsigned long)(unsigned int)scb;
	++abort_post_calls;
	abort_post_status = entry[43];
	queue[0] = *(unsigned int *)entry;
	if (queue[0] == 0xffffffffU)
		queue[1] = 0xffffffffU;
	return 0;
}

int Ph_SetHaData(int host)
{
	unsigned int *queue = *(unsigned int **)((unsigned char *)(unsigned long)(unsigned int)host + 52);
	queue[0] = 0;
	queue[1] = 0;
	return 0;
}

int Ph_ScbPrepare(int host, int *scb)
{
	(void)host;
	++abort_prepare_calls;
	abort_prepared_scb = (unsigned int)scb;
	return 0;
}

int Ph_ReadEeprom(unsigned short *host, int io)
{
	(void)host;
	(void)io;
	++eeprom_read_calls;
	return eeprom_read_result;
}

unsigned char Ph_Pause(int io)
{
	(void)io;
	++pause_calls;
	return 0;
}

unsigned char Ph_WriteHcntrl(short io, unsigned char value, ...)
{
	++hcntrl_write_calls;
	hcntrl_write_base = io;
	hcntrl_write_value = value;
	return value;
}

char Ph_MemorySet(unsigned char *destination, char value, int length)
{
	int i;
	for (i = 0; i < length; ++i)
		destination[i] = (unsigned char)value;
	return (char)length;
}

void a2940_test_outl(unsigned short port, unsigned int value)
{
	unsigned int bus;
	unsigned int device;
	unsigned int reg;
	if (port == 0xcf8) {
		address_register = value;
		return;
	}
	if (port == 0xcfc && (address_register & 0x80000000U) != 0) {
		bus = (address_register >> 16) & 0xff;
		device = (address_register >> 11) & 0x1f;
		reg = (address_register & 0xfc) >> 2;
	} else if (port >= 0xc000 && mechanism2 == 0x60) {
		bus = selected_bus;
		device = (port >> 8) & 0x0f;
		reg = (port & 0xfc) >> 2;
	} else {
		return;
	}
	if (present[bus][device])
		words[bus][device][reg] = value;
}

unsigned int a2940_test_inl(unsigned short port)
{
	unsigned int bus;
	unsigned int device;
	unsigned int reg;
	++reads;
	if (port == 0xcfc && (address_register & 0x80000000U) != 0) {
		bus = (address_register >> 16) & 0xff;
		device = (address_register >> 11) & 0x1f;
		reg = (address_register & 0xfc) >> 2;
	} else if (port >= 0xc000 && mechanism2 == 0x60) {
		bus = selected_bus;
		device = (port >> 8) & 0x0f;
		reg = (port & 0xfc) >> 2;
	} else {
		return 0xffffffffU;
	}
	if (!present[bus][device])
		return 0xffffffffU;
	if (reg == 2 && words[bus][device][reg] == 0)
		return 0x12345678U;
	return words[bus][device][reg];
}

#include "../Adaptec2940Config.c"
#include "../Adaptec2940Recovery.c"

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i)
		bytes[i] = (unsigned char)value;
	return destination;
}

__declspec(dllimport) __declspec(noreturn) void __stdcall ExitProcess(unsigned int);

static int check(int condition)
{
	static unsigned int check_index;
	++check_index;
	if (!condition)
		ExitProcess(check_index);
	return 0;
}

void mainCRTStartup(void)
{
	int result = 0;
	present[0][5] = 1;
	result |= check(Ph_AccessConfig(2) == 1 && address_register == 0);
	present[0][5] = 0;
	present[2][3] = 1;
	reads = 0;
	result |= check(Ph_AccessConfig(2) == 1 && reads == 36 && address_register == 0);
	present[2][3] = 0;
	reads = 0;
	result |= check(Ph_AccessConfig(0) == 2 && reads == 32);
	present[0][0] = 1;
	result |= check(PH_FindMechanism() == 1);
	present[0][0] = 0;
	result |= check(PH_FindMechanism() == 2);

	present[4][7] = 1;
	words[4][7][4] = 0xa1b2c3d4U;
	a2940_test_config_osm_override = 1;
	result |= check((unsigned int)Ph_ReadConfig(-1, 4, 7, 0x10) == 0xa1b2c3d4U);
	result |= check(Ph_WriteConfig(-1, 4, 7, 0x10, 0x55667788U) == 0 &&
		words[4][7][4] == 0x55667788U);
	result |= check(Ph_WriteConfig(-1, 4, 8, 0x10, 0) == -1);

	a2940_test_config_osm_override = 2;
	words[4][7][4] = 0x10203040U;
	result |= check((unsigned int)Ph_ReadConfig(-1, 4, 7, 0x10) == 0x10203040U);
	result |= check(Ph_WriteConfig(-1, 4, 7, 0x10, 0x89abcdefU) == 0 &&
		words[4][7][4] == 0x89abcdefU);
	result |= check(Ph_ReadConfig(-1, 4, 16, 0x10) == -1 &&
		Ph_WriteConfig(-1, 4, 16, 0x10, 0) == -1);
	result |= check(mechanism2 == 0 && address_register == 0);

	a2940_test_config_osm_override = 1;
	present[0][0] = 1;
	words[0][0][0] = 0x00789004U;
	words[0][0][1] = 1;
	result |= check(PH_FindHA(0, 0) == 1 && words[0][0][1] == 5);
	words[0][0][0] = 0x00759004U;
	words[0][0][1] = 0;
	result |= check(PH_FindHA(0, 0) == 0x81 && words[0][0][1] == 4);
	words[0][0][0] = 0x12345678U;
	words[0][0][1] = 0;
	result |= check(PH_FindHA(0, 0) == 0 && words[0][0][1] == 0);

	a2940_test_config_osm_override = -1;
	a2940_test_bus_count_override = 7;
	result |= check(PH_GetNumOfBuses() == 7);
	a2940_test_bus_count_override = -1;
	a2940_test_config_osm_override = 1;
	present[0][1] = 1;
	words[0][0][2] = 0x06000000U;
	words[0][1][2] = 0x06040000U;
	words[0][1][6] = 0x00020000U;
	result |= check(PH_GetNumOfBuses() == 3);

	{
		unsigned char host[64] = {0};
		*(unsigned int *)(host + 4) = 0x100;
		host[15] = 0x20;
		input_registers[0x1f] = 0;
		cable_status = 0;
		eeprom_update_calls = 0;
		eeprom_update_result = 0x55;
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 0x55 &&
			(host[13] & 0x30) == 0x10 && eeprom_update_calls == 1 &&
			eeprom_update_host == (unsigned int)(unsigned long)host &&
			eeprom_update_io == 0x100 && eeprom_update_register == 17);
		cable_status = 5;
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 0x55 &&
			(host[13] & 0x30) == 0 && eeprom_update_calls == 2);
		input_registers[0x1f] = 2;
		cable_status = 0;
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 0x55 &&
			(host[13] & 0x30) == 0x30 && eeprom_update_calls == 3);
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 1 &&
			eeprom_update_calls == 3);
		cable_status = 6;
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 0x55 &&
			(host[13] & 0x30) == 0 && eeprom_update_calls == 4);
		host[15] = 0;
		no_assist_result = 0xa5;
		result |= check(Ph_AutoTermCable((int)(unsigned long)host) == 0xa5 &&
			no_assist_calls == 1);
	}

	{
		unsigned char host[64] = {0};
		unsigned char config_result;
		*(unsigned int *)(host + 4) = 0;
		host[8] = 0;
		host[9] = 0;
		host[14] = 2;
		present[0][0] = 1;
		words[0][0][2] = 0;
		words[0][0][4] = 0x1003;
		words[0][0][16] = 0x1000;
		input_registers[0x82] = 0x12;
		input_registers[0x83] = 0x34;
		input_registers[0x85] = 0xab;
		input_registers[0x87] = 0;
		input_registers[0x1f] = 2;
		a2940_test_config_osm_override = 1;
		eeprom_read_result = 0;
		config_result = PH_GetConfig((int)(unsigned long)host);
		result |= check(config_result == 2);
		result |= check(*(unsigned int *)(host + 4) == 0x1000);
		result |= check(host[0] == 0x34 && host[1] == 0x12 && host[2] == 0);
		result |= check(host[3] == 0x78);
		result |= check(host[12] == 0xa0 && host[13] == 0x30 && host[14] == 2);
		result |= check(host[21] == 0xa8 && host[22] == 3 && host[30] == 7);
		result |= check(host[31] == 16 && host[32] == 0x81 &&
			*(unsigned short *)(host + 48) == 0xffff);
		result |= check(driver_config_calls == 1 && pause_calls == 1);
		result |= check(hcntrl_write_calls == 1 && hcntrl_write_base == 0x1000 &&
			hcntrl_write_value == 0);

		input_registers[0x86] = 0xc0;
		input_registers[0x05] = 0x0a;
		input_registers[0x02] = 0x38;
		input_registers[0x20] = 0x24;
		input_registers[0x21] = 0x8f;
		input_registers[0x22] = 0x51;
		input_registers[0x32] = 0xaa;
		input_registers[0x33] = 0x55;
		host[12] = 0x40;
		host[15] = 0x10;
		eeprom_read_result = 1;
		config_result = PH_GetConfig((int)(unsigned long)host);
		result |= check(config_result == 2);
		result |= check(host[22] == 3 && host[30] == 10);
		result |= check(host[32] == 0x21 && host[33] == 0x81 && host[34] == 0x51);
		result |= check(host[12] == 0xf8 && host[48] == 0x55 && host[49] == 0xaa);
		result |= check(eeprom_read_calls == 2);
		a2940_test_config_osm_override = -1;
	}

	{
		unsigned char host[64] = {0};
		static const unsigned short expected_ports[16] = {
			0x160, 0x162, 0x163, 0x168, 0x186, 0x101,
			0x11e, 0x11e, 0x11d, 0x11d, 0x11d, 0x11e,
			0x130, 0x131, 0x132, 0x133
		};
		static const unsigned char expected_values[16] = {
			0x32, 0, 0, 0x80, 0x80, 0x80,
			0x20, 0x28, 0x58, 0x48, 0, 0,
			0, 0, 0xaa, 0x55
		};
		unsigned int i;
		*(unsigned int *)(host + 4) = 0x100;
		host[22] = 2;
		host[31] = 16;
		host[13] = 0x20;
		host[14] = 2;
		host[48] = 0x55;
		host[49] = 0xaa;
		init_trace_count = 0;
		result |= check(PH_InitHA((int)(unsigned long)host) == 0);
		result |= check(init_trace_count == 16);
		for (i = 0; i < 16; ++i)
			result |= check(init_trace_port[i] == expected_ports[i] &&
				init_trace_value[i] == expected_values[i]);

		host[12] = 0x80;
		sequencer_load_result = 7;
		init_trace_count = 0;
		result |= check(PH_InitHA((int)(unsigned long)host) == 7 &&
			sequencer_load_calls == 1 && init_trace_count == 0);
	}

	{
		static const unsigned short expected_ports[17] = {
			0x1b0, 0x1b1, 0x162, 0x163, 0x110, 0x111, 0x192, 0x100,
			0x100, 0x10c, 0x10b, 0x10c, 0x192, 0x110, 0x111, 0x1b0, 0x1b1
		};
		static const unsigned char expected_values[17] = {
			0xff, 0, 4, 0, 0, 0, 0x0f, 0x33, 0x32,
			0x20, 0xff, 0x20, 5, 0xcc, 0xa4, 0xaa, 0xbb
		};
		unsigned int i;
		input_registers[0x00] = 0x77;
		input_registers[0x87] = 4;
		input_registers[0x0c] = 0;
		input_registers[0x10] = 0xcc;
		input_registers[0xb0] = 0xaa;
		input_registers[0xb1] = 0xbb;
		init_trace_count = delay_calls = unpause_calls = 0;
		result |= check(Ph_ResetSCSI(0x100) == 0xbb);
		result |= check(init_trace_count == 17 && delay_calls == 1 &&
			delay_last_duration == 4000 && unpause_calls == 1);
		for (i = 0; i < 17; ++i)
			result |= check(init_trace_port[i] == expected_ports[i] &&
				init_trace_value[i] == expected_values[i]);
	}

	{
		unsigned char host[80] = {0};
		unsigned int queue[2];
		unsigned char active[256] = {0};
		unsigned char prepared[256] = {0};
		unsigned char pending[256] = {0};
		*(unsigned int *)(host + 4) = 0x100;
		*(unsigned int **)(host + 52) = queue;
		*(unsigned int *)active = (unsigned int)(unsigned long)prepared;
		*(unsigned int *)prepared = 0xffffffffU;
		active[8] = 0xff;
		queue[0] = (unsigned int)(unsigned long)active;
		queue[1] = (unsigned int)(unsigned long)active;
		input_registers[0x87] = 4;
		abort_prepare_calls = abort_post_calls = 0;
		result |= check(Ph_AbortChannel((int)(unsigned long)host, 5) == 4 &&
			abort_prepare_calls == 1 &&
			abort_prepared_scb == (unsigned int)(unsigned long)prepared &&
			abort_post_calls == 0 && queue[0] == (unsigned int)(unsigned long)active &&
			queue[1] == (unsigned int)(unsigned long)active);

		*(unsigned int *)pending = 0xffffffffU;
		pending[8] = 0;
		queue[0] = (unsigned int)(unsigned long)pending;
		queue[1] = (unsigned int)(unsigned long)pending;
		abort_prepare_calls = abort_post_calls = 0;
		result |= check(Ph_AbortChannel((int)(unsigned long)host, 9) == 4 &&
			pending[43] == 9 && pending[11] == 4 && abort_post_calls == 1 &&
			abort_post_status == 9 && abort_prepare_calls == 0 &&
			queue[0] == 0xffffffffU && queue[1] == 0xffffffffU);
	}

	{
		unsigned char host[80] = {0};
		*(unsigned int *)(host + 4) = 0x100;
		interrupt_status = 4;
		input_registers[0x0c] = 8;
		async_event_calls = init_trace_count = 0;
		result |= check(Ph_BadSeq((int)(unsigned long)host, 0x100) == 0 &&
			async_event_calls == 1 && async_event_value == 1 &&
			async_event_host == (int)(unsigned long)host &&
			init_trace_count == 2 && init_trace_port[0] == 0x162 &&
			init_trace_value[0] == 0 && init_trace_port[1] == 0x163 &&
			init_trace_value[1] == 0);
	}

	{
		unsigned char scb[16] = {0};
		*(unsigned int *)(scb + 4) = 0;
		input_registers[0x03] = 0xe0;
		input_registers[0x12] = 3;
		init_trace_count = 0;
		result |= check(Ph_CdbAbort((int)(unsigned long)scb, 0x100) == 0 &&
			init_trace_count == 3 && init_trace_port[0] == 0x103 &&
			init_trace_value[0] == 0xe0 && init_trace_port[1] == 0x162 &&
			init_trace_value[1] == 2 && init_trace_port[2] == 0x163 &&
			init_trace_value[2] == 0);
	}

	{
		unsigned char host[80] = {0};
		unsigned char ha[512] = {0};
		int scb_map[256];
		*(int *)(host + 4) = 0x100;
		*(unsigned char **)(host + 52) = ha;
		*(int **)(ha + 272) = scb_map;
		*(unsigned int *)ha = 0xffffffffU;
		*((unsigned int *)ha + 1) = 0xffffffffU;
		input_registers[0x87] = 4;
		input_registers[0x3c] = 0xff;
		input_registers[0x11] = 0;
		async_event_calls = bookmark_insert_calls = bookmark_remove_calls = 0;
		init_trace_count = 0;
		{
			unsigned char reset_result = Ph_HaHardReset((int)(unsigned long)host);
			if (reset_result != 0)
				ExitProcess(180 + reset_result);
			result |= check(reset_result == 0);
		}
		result |= check(async_event_calls == 1);
		result |= check(async_event_value == 3);
		result |= check(async_event_host == (int)(unsigned long)host);
		result |= check(async_event_io == -1);
		result |= check(bookmark_insert_calls == 1 && bookmark_remove_calls == 1);
		result |= check(init_trace_count >= 3 && init_trace_port[0] == 0x192 &&
			init_trace_value[0] == 0x0f && init_trace_port[1] == 0x162 &&
			init_trace_value[1] == 0 && init_trace_port[2] == 0x163 &&
			init_trace_value[2] == 0);
		result |= check(hcntrl_write_value == 0);
	}

	{
		unsigned char host[80] = {0};
		unsigned int queue[2] = {0xffffffffU, 0xffffffffU};
		*(unsigned int *)(host + 4) = 0x100;
		*(unsigned int **)(host + 52) = queue;
		input_registers[0x0c] = 0;
		input_registers[0x03] = 0;
		input_registers[0x00] = 0;
		input_registers[0x87] = 4;
		async_event_calls = bookmark_insert_calls = bookmark_remove_calls = 0;
		init_trace_count = 0;
		result |= check(Ph_IntSrst((int)(unsigned long)host) == 0 &&
			async_event_calls == 1 && async_event_value == 0 &&
			bookmark_insert_calls == 1 && bookmark_remove_calls == 1 &&
			queue[0] == 0xffffffffU && queue[1] == 0xffffffffU &&
			init_trace_count >= 3 && init_trace_port[0] == 0x100 &&
			init_trace_value[0] == 0 && init_trace_port[1] == 0x162 &&
			init_trace_value[1] == 0 && init_trace_port[2] == 0x163 &&
			init_trace_value[2] == 0);
	}
	ExitProcess((unsigned int)result);
}
