#define A2940_EXTMSG_TESTING 1
static unsigned char port_values[512];
static unsigned short out_ports[128];
static unsigned char out_values[128];
static unsigned int out_count;
static unsigned char message_status_values[8];
static unsigned int message_status_count;
static unsigned int message_status_index;
static unsigned char wt4_values[8];
static unsigned int wt4_count;
static unsigned int wt4_index;
static unsigned int badseq_count;
static unsigned int set_nego_count;
static unsigned int sync_map_count;
static unsigned char nego_target;
static unsigned char nego_reg;

unsigned char a2940_extmsg_inb(unsigned short port)
{
	if (port == 0x112 && message_status_index < message_status_count)
		return message_status_values[message_status_index++];
	return port_values[port & 511];
}

void a2940_extmsg_outb(unsigned short port, unsigned char value)
{
	out_ports[out_count] = port;
	out_values[out_count++] = value;
	port_values[port & 511] = value;
}

int Ph_Wt4Req(int scb, short io)
{
	(void)scb; (void)io;
	return wt4_index < wt4_count ? wt4_values[wt4_index++] : 0xff;
}

char Ph_BadSeq(int host, int io)
{
	(void)host; (void)io;
	++badseq_count;
	return 0x35;
}

char Ph_SetNeedNego(unsigned char target, short io)
{
	nego_target = target;
	nego_reg = (unsigned char)(io + target + 32);
	++set_nego_count;
	return 0;
}

int Ph_SyncSet(int scb)
{
	(void)scb;
	return 16;
}

unsigned char Ph_ClearFast20Reg(int host, int scb)
{
	(void)host; (void)scb;
	return 0;
}

void Ph_LogFast20Map(int host, unsigned char *scb)
{
	(void)host; (void)scb;
	++sync_map_count;
}

#include "../Adaptec2940ExtMsgi.c"

static unsigned int fail;
static unsigned char host[140];
static unsigned char scb[256];

static void reset_case(unsigned char count, unsigned char status)
{
	unsigned int i;
	for (i = 0; i < 512; ++i) port_values[i] = 0;
	for (i = 0; i < 128; ++i) { out_ports[i] = 0; out_values[i] = 0; }
	out_count = message_status_count = message_status_index = 0;
	wt4_count = wt4_index = 0;
	badseq_count = set_nego_count = sync_map_count = 0;
	for (i = 0; i < sizeof(host); ++i) host[i] = 0;
	for (i = 0; i < sizeof(scb); ++i) scb[i] = 0;
	*(unsigned int *)(scb + 4) = (unsigned int)(unsigned long)host;
	scb[12] = 0x20;
	port_values[0x13a] = count;
	port_values[0x112] = status;
	port_values[0x103] = 0x10;
}

static void check(int condition)
{
	if (!condition) ++fail;
}

int mainCRTStartup(void)
{
	char result;

	/* Unexpected message-in phase is sent to the bad-sequence handler. */
	reset_case(2, 0);
	message_status_values[0] = 0;
	message_status_count = 1;
	wt4_values[0] = 0x20;
	wt4_count = 1;
	result = Ph_ExtMsgi((int)(unsigned long)scb, 0x100);
	check(result == 0x35 && badseq_count == 1);

	/* A target-requested negotiation restarts message-out and marks the SCB. */
	reset_case(3, 0);
	scb[10] = 2;
	message_status_values[0] = 0;
	message_status_values[1] = 0xaa;
	message_status_count = 2;
	wt4_values[0] = 0xe0;
	wt4_values[1] = 0x20;
	wt4_count = 2;
	port_values[0x103] = 0xb0;
	port_values[0x101] = 0x04;
	port_values[0x102] = 0x08;
	result = Ph_ExtMsgi((int)(unsigned long)scb, 0x100);
	check((unsigned char)result == 0x0c && set_nego_count == 1 && nego_target == 2);
	check(scb[67] == 0xaa && out_count >= 7);

	/* Agreed sync parameters update the transfer register and Fast20 map. */
	reset_case(3, 1);
	host[14] = 1;
	host[34] = 0x80;
	scb[10] = 2;
	message_status_values[0] = 1;
	message_status_values[1] = 25;
	message_status_values[2] = 8;
	message_status_count = 3;
	wt4_values[0] = 0xe0;
	wt4_values[1] = 0xe0;
	wt4_count = 2;
	port_values[0x11f] = 2;
	port_values[0x122] = 0x80;
	result = Ph_ExtMsgi((int)(unsigned long)scb, 0x100);
	check((unsigned char)result == (unsigned char)(8 + 16 + 0x80));
	check(sync_map_count == 1 && port_values[0x122] == (unsigned char)result);

	/* A peer downgrade requests renegotiation and returns the HIM retry code. */
	reset_case(2, 3);
	host[14] = 0;
	port_values[0x11f] = 0;
	scb[10] = 0;
	message_status_values[0] = 3;
	message_status_values[1] = 0;
	message_status_count = 2;
	wt4_values[0] = 0xe0;
	wt4_count = 1;
	result = Ph_ExtMsgi((int)(unsigned long)scb, 0x100);
	check(result == -16 && (scb[10] & 2) != 0 && (host[34] & 0x80) != 0);
	check(out_count == 3 && out_ports[2] == 0x103 && out_values[2] == 0xf0);

	return (int)fail;
}
