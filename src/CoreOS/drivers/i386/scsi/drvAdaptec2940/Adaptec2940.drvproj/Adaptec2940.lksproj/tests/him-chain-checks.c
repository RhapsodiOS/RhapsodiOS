/* Freestanding i386 execution test for production HIM chain helpers. */
#define A2940_HIM_STANDALONE 1
#include "../Adaptec2940HIM.c"

extern __declspec(dllimport) __declspec(noreturn)
void __stdcall ExitProcess(unsigned int exitCode);

static unsigned char host[140];
static unsigned char chain[272];
static unsigned char first[256];
static unsigned char middle[256];
static unsigned char last[256];
static unsigned char fill[4];
static unsigned char registers[256];
static unsigned short output_ports[8];
static unsigned char output_values[8];
static unsigned int output_count;
static unsigned int read_count;
static unsigned int barrier_count;
static int hcntrl_pause_after_reads = -1;
static int simulate_delay_pause;

void a2940_test_outb(unsigned short port, unsigned char value)
{
	unsigned int offset = (unsigned int)port - 0x100;
	if (output_count < 8) {
		output_ports[output_count] = port;
		output_values[output_count] = value;
	}
	++output_count;
	++barrier_count;
	registers[offset & 0xff] = value;
	if (offset == 0x87 && value == 0 && simulate_delay_pause) {
		hcntrl_pause_after_reads = 1;
		simulate_delay_pause = 0;
	}
}

unsigned char a2940_test_inb(unsigned short port)
{
	unsigned int offset = ((unsigned int)port - 0x100) & 0xff;
	++read_count;
	if (offset == 0x87 && hcntrl_pause_after_reads >= 0 &&
	    (registers[offset] & 4) == 0) {
		if (hcntrl_pause_after_reads == 0) {
			registers[offset] |= 4;
			hcntrl_pause_after_reads = -1;
		} else {
			--hcntrl_pause_after_reads;
		}
	}
	return registers[offset];
}

static void clear_bytes(unsigned char *bytes, unsigned int count)
{
	while (count--)
		*bytes++ = 0;
}

static int run_chain_checks(void)
{
	unsigned int *links = (unsigned int *)chain;
	unsigned int *first_link = (unsigned int *)first;
	unsigned int *middle_link = (unsigned int *)middle;
	unsigned int *last_link = (unsigned int *)last;
	int previous;
	clear_bytes(host, sizeof(host));
	clear_bytes(chain, sizeof(chain));
	clear_bytes(first, sizeof(first));
	clear_bytes(middle, sizeof(middle));
	clear_bytes(last, sizeof(last));
	clear_bytes(fill, sizeof(fill));
	*(unsigned int **)(host + 52) = links;
	links[0] = links[1] = 0xffffffffU;
	host[13] = 0x80;
	host[62] = 0x37;
	host[64] = 0x42;
	if (Ph_ChainPrevious((int *)links, 0) != -1)
		return 0;
	Ph_ChainInsertFront();
	if (links[0] != 0xffffffffU || links[1] != 0xffffffffU)
		return 0;
	Ph_ChainAppendEnd((int)host, first_link);
	if (links[0] != (unsigned int)first_link || links[1] != (unsigned int)first_link ||
	    chain[268] != 0x37 || chain[269] != 0x42 || (host[13] & 0x80) != 0 ||
	    *first_link != 0xffffffffU)
		return 0;
	Ph_ChainAppendEnd((int)host, middle_link);
	Ph_ChainAppendEnd((int)host, last_link);
	if (*first_link != (unsigned int)middle_link ||
	    *middle_link != (unsigned int)last_link || *last_link != 0xffffffffU ||
	    links[1] != (unsigned int)last_link)
		return 0;
	if (Ph_ChainPrevious((int *)links, (int)last_link) != (int)middle_link ||
	    Ph_ChainPrevious((int *)links, 1) != -1)
		return 0;
	previous = Ph_ChainRemove((int)host, middle_link);
	if (previous != (int)first_link || *first_link != (unsigned int)last_link ||
	    links[1] != (unsigned int)last_link)
		return 0;
	previous = Ph_ChainRemove((int)host, last_link);
	if (previous != (int)first_link || *first_link != 0xffffffffU ||
	    links[1] != (unsigned int)first_link)
		return 0;
	previous = Ph_ChainRemove((int)host, first_link);
	if (previous != -1 || links[0] != 0xffffffffU || links[1] != 0xffffffffU ||
	    (host[13] & 0x80) == 0)
		return 0;
	if (Ph_MemorySet(fill, (char)0xa5, 3) != 3 ||
	    fill[0] != 0xa5 || fill[1] != 0xa5 || fill[2] != 0xa5 || fill[3] != 0)
		return 0;
	return Ph_MemorySet(fill, (char)0x5a, 0) == 0x5a;
}

static void reset_ports(unsigned char control, unsigned char status)
{
	unsigned int i;
	for (i = 0; i < sizeof(registers); ++i)
		registers[i] = 0;
	for (i = 0; i < 8; ++i) {
		output_ports[i] = 0;
		output_values[i] = 0;
	}
	registers[0x87] = control;
	registers[0x91] = status;
	output_count = read_count = barrier_count = 0;
	hcntrl_pause_after_reads = -1;
	simulate_delay_pause = 0;
}

static int run_hcntrl_checks(void)
{
	unsigned char result;
	reset_ports(0, 0);
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x20 || output_count != 2 || read_count != 3 ||
	    barrier_count != 2 || output_ports[0] != 0x187 ||
	    output_values[0] != 4 || output_values[1] != 0x20)
		return 0;
	reset_ports(0, 1);
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x24 || output_count != 2 || output_values[1] != 0x24)
		return 0;
	reset_ports(0, 0);
	result = Ph_WriteHcntrl(0x100, 0x24);
	if (result != 0x24 || output_count != 1 || read_count != 0)
		return 0;
	reset_ports(4, 8);
	if (Ph_ReadIntstat(0x100) != 8 || output_count != 0 || read_count != 2)
		return 0;
	reset_ports(0, 8);
	if (Ph_ReadIntstat(0x100) != 8 || output_count != 2 || barrier_count != 2 ||
	    output_values[0] != 4 || output_values[1] != 4)
		return 0;
	reset_ports(0, 0);
	if (Ph_ReadIntstat(0x100) != 0 || output_count != 2 || output_values[1] != 0)
		return 0;
	reset_ports(0, 0);
	if (Ph_Pause(0x100) != 4 || output_count != 1 || output_values[0] != 4)
		return 0;
	reset_ports(4, 0);
	return Ph_UnPause(0x100) == 0 && output_count == 1 && output_values[0] == 0;
}

static int run_status_checks(void)
{
	unsigned char chain[272];
	unsigned char scb[256];
	unsigned int i;
	for (i = 0; i < sizeof(chain); ++i)
		chain[i] = 0;
	for (i = 0; i < sizeof(scb); ++i)
		scb[i] = 0;
	reset_ports(0, 0);
	registers[3] = 0x20;
	registers[2] = 2;
	registers[12] = 0x10;
	if (Ph_CheckLength((int)scb, 0x100) != 0x20 ||
	    *(unsigned int *)(scb + 28) != 0 || scb[43] != 18 ||
	    output_count != 3 || output_values[0] != 0x20 ||
	    output_values[1] != 0x82 || output_values[2] != 2)
		return 0;
	reset_ports(0, 0);
	registers[3] = 0xc0;
	registers[176] = 0x78;
	registers[177] = 0x56;
	registers[178] = 0x34;
	registers[179] = 0x12;
	scb[43] = 0;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 || scb[43] != 18 ||
	    *(unsigned int *)(scb + 28) != 0x12345678 || output_count != 0)
		return 0;
	scb[10] = 0x40;
	scb[43] = 7;
	*(unsigned int *)(scb + 28) = 0xfeedface;
	reset_ports(0, 0);
	registers[3] = 0xc0;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 || scb[43] != 7 ||
	    *(unsigned int *)(scb + 28) != 0xfeedface || read_count != 1)
		return 0;
	for (i = 0; i < sizeof(scb); ++i)
		scb[i] = 0;
	scb[24] = 0;
	if (Ph_SetMgrStat(scb) != 0 || scb[11] != 1)
		return 0;
	scb[24] = 16;
	if (Ph_SetMgrStat(scb) != 16 || scb[11] != 1)
		return 0;
	scb[43] = 1;
	scb[24] = 20;
	if (Ph_SetMgrStat(scb) != 20 || scb[11] != 4)
		return 0;
	scb[43] = 0;
	scb[24] = 2;
	if (Ph_SetMgrStat(scb) != 2 || scb[11] != 4)
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

static int run_misc_checks(void)
{
	unsigned char host[140];
	unsigned char source[3];
	unsigned char destination[3];
	unsigned int i;
	for (i = 0; i < sizeof(host); ++i)
		host[i] = 0;
	source[0] = 0x11; source[1] = 0x22; source[2] = 0x33;
	destination[0] = destination[1] = destination[2] = 0;
	*(unsigned int *)(host + 4) = 0x100;
	reset_ports(0, 0);
	if (Ph_OutBuffer(0x120, (int)source, 3) != 0x33 || output_count != 3 ||
	    output_ports[0] != 0x120 || output_values[0] != 0x11 ||
	    output_ports[2] != 0x122 || output_values[2] != 0x33 || barrier_count != 3)
		return 0;
	if (Ph_InBuffer(0x120, (int)destination, 3) != 0x33 ||
	    destination[0] != 0x11 || destination[1] != 0x22 || destination[2] != 0x33)
		return 0;
	reset_ports(0, 0);
	if (Ph_SetNeedNego(3, 0x100) != (char)-113 || output_count != 1 ||
	    output_ports[0] != 0x123 || output_values[0] != 0x8f)
		return 0;
	reset_ports(0, 0);
	if (PH_EnableInt((int)host) != 2 || output_count != 2 ||
	    output_values[0] != 4 || output_values[1] != 2)
		return 0;
	reset_ports(6, 0);
	if (PH_DisableInt((int)host) != 4 || output_count != 1 || output_values[0] != 4)
		return 0;
	Ph_Abort();
	Ph_BusReset();
	Ph_HaSoftReset();
	Ph_SoftReset();
	return Ph_SendTrmMsg(0, 0) == 0 && Ph_TrmCmplt() == 0;
}

static int run_bookmark_checks(void)
{
	unsigned char host[64];
	unsigned char chain[512];
	unsigned int i;
	for (i = 0; i < sizeof(host); ++i)
		host[i] = 0;
	for (i = 0; i < sizeof(chain); ++i)
		chain[i] = 0;
	*(unsigned char **)(host + 52) = chain;
	*(unsigned int *)(host + 56) = 0x1000;
	host[13] = 0x80;
	*(unsigned int *)chain = 0xffffffffU;
	*(unsigned int *)(chain + 4) = 0xffffffffU;
	*(unsigned int *)(chain + 352) = 0xffffffffU;
	if (Ph_SetScbMark((int)host) != (int)chain ||
	    *(unsigned int *)(chain + 372) != 0x1194 ||
	    *(unsigned int *)(chain + 356) != (unsigned int)host)
		return 0;
	Ph_InsertBookmark((int)host);
	if (*(unsigned int *)chain != (unsigned int)(chain + 352) ||
	    *(unsigned int *)(chain + 4) != (unsigned int)(chain + 352) ||
	    chain[360] != 0xff || *(unsigned int *)(chain + 352) != 0xffffffffU ||
	    (host[13] & 0x80) != 0)
		return 0;
	return Ph_RemoveBookmark((int)host) == -1 &&
	       *(unsigned int *)chain == 0xffffffffU &&
	       *(unsigned int *)(chain + 4) == 0xffffffffU &&
	       (host[13] & 0x80) != 0;
}

static int run_scb_prepare_checks(void)
{
	unsigned char host[64];
	unsigned char chain[512];
	unsigned char first[256];
	unsigned char second[256];
	unsigned int i;
	for (i = 0; i < sizeof(host); ++i) host[i] = 0;
	for (i = 0; i < sizeof(chain); ++i) chain[i] = 0;
	for (i = 0; i < sizeof(first); ++i) first[i] = second[i] = 0;
	*(unsigned char **)(host + 52) = chain;
	chain[268] = 1;
	*(unsigned int *)first = (unsigned int)second;
	*(unsigned int *)second = 0xffffffffU;
	first[9] = second[9] = 0xaa;
	first[12] = second[12] = 0;
	if (Ph_ScbPrepare((int)host, (int *)first) != 32)
		return 0;
	return chain[8] == 2 && *(unsigned short *)(chain + 266) == 1 &&
	       first[9] == 0 && first[11] == 16 && second[9] == 0 && second[11] == 32;
}

static int run_sync_map_checks(void)
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

static int run_negotiation_fast20_checks(void)
{
	unsigned char host[140];
	unsigned char scb[256];
	unsigned int i;
	for (i = 0; i < sizeof(host); ++i) host[i] = 0;
	for (i = 0; i < sizeof(scb); ++i) scb[i] = 0;
	*(unsigned int *)(host + 4) = 0x100;
	reset_ports(0, 0);
	host[41] = 0x80;
	if (Ph_ScbRenego((int)host, 0x90) != (char)-113 || output_count != 1 ||
	    output_ports[0] != 0x129 || output_values[0] != 0x8f)
		return 0;
	host[41] = 0;
	reset_ports(0, 0);
	registers[0x29] = 0x8f;
	if (Ph_ScbRenego((int)host, 0x90) != (char)-113 || host[41] != 0x81 ||
	    output_count != 1 || output_values[0] != 0x8f)
		return 0;
	host[41] = 0;
	reset_ports(0, 0);
	if (Ph_ScbRenego((int)host, 0x90) != 0 || output_count != 1 || output_values[0] != 0)
		return 0;
	scb[66] = 1;
	scb[12] = 0x90;
	reset_ports(0, 0);
	registers[0x31] = 0xff;
	registers[1] = 0xff;
	if (Ph_ClearFast20Reg((int)host, (int)scb) != 0xdf || output_count != 2 ||
	    output_ports[0] != 0x131 || output_values[0] != 0xfd ||
	    output_ports[1] != 0x101 || output_values[1] != 0xdf)
		return 0;
	reset_ports(0, 0);
	scb[67] = 0x18;
	Ph_LogFast20Map((int)host, scb);
	if (output_count != 2 || output_ports[0] != 0x131 || output_values[0] != 2 ||
	    output_ports[1] != 0x101 || output_values[1] != 0x20)
		return 0;
	reset_ports(0, 0);
	registers[0x31] = 0xff;
	registers[1] = 0xff;
	scb[67] = 0x19;
	Ph_LogFast20Map((int)host, scb);
	return output_count == 2 && output_values[0] == 0xfd && output_values[1] == 0xdf;
}

static int run_delay_checks(void)
{
	reset_ports(4, 0);
	registers[176] = 0xaa;
	registers[177] = 0xbb;
	simulate_delay_pause = 1;
	if (Ph_Delay(0x100, 1) != 0xbb || output_count != 8 || barrier_count != 8)
		return 0;
	return output_ports[0] == 0x1b0 && output_values[0] == 0x54 &&
	       output_ports[1] == 0x1b1 && output_values[1] == 0x0b &&
	       output_ports[2] == 0x162 && output_values[2] == 4 &&
	       output_ports[3] == 0x163 && output_values[3] == 0 &&
	       output_ports[4] == 0x187 && output_values[4] == 0 &&
	       output_ports[5] == 0x192 && output_values[5] == 1 &&
	       output_ports[6] == 0x1b0 && output_values[6] == 0xaa &&
	       output_ports[7] == 0x1b1 && output_values[7] == 0xbb;
}

static int run_pollint_checks(void)
{
	unsigned char host[64];
	unsigned int i;
	for (i = 0; i < sizeof(host); ++i) host[i] = 0;
	*(unsigned int *)(host + 4) = 0x100;
	reset_ports(0, 0x0b);
	if (PH_PollInt((int)host) != 0x0b || output_count != 2 ||
	    output_values[0] != 4 || output_values[1] != 4)
		return 0;
	reset_ports(0, 0x80);
	return PH_PollInt((int)host) == 0 && output_count == 2 &&
	       output_values[0] == 4 && output_values[1] == 0;
}

void mainCRTStartup(void)
{
	ExitProcess(run_chain_checks() && run_hcntrl_checks() &&
	            run_status_checks() && run_misc_checks() &&
	            run_bookmark_checks() && run_scb_prepare_checks() &&
	            run_sync_map_checks() && run_negotiation_fast20_checks() &&
	            run_delay_checks() && run_pollint_checks() ? 0 : 42);
}
