/* Native i386 checks for timeout IPC construction and error handling. */
#define A2940_TIMEOUT_STANDALONE 1

static unsigned char sent_message[24];
static int send_result;
static int log_result;
static unsigned int send_calls;
static unsigned int log_calls;
static int send_arguments[2];
static const char *log_formats[2];

void *memset(void *destination, int value, unsigned int length)
{
	unsigned char *bytes = (unsigned char *)destination;
	unsigned int i;
	for (i = 0; i < length; ++i) bytes[i] = (unsigned char)value;
	return destination;
}

void *memcpy(void *destination, const void *source, unsigned int length)
{
	unsigned char *to = (unsigned char *)destination;
	const unsigned char *from = (const unsigned char *)source;
	unsigned int i;
	for (i = 0; i < length; ++i) to[i] = from[i];
	return destination;
}

int a2940_timeout_test_log(const char *format, ...)
{
	if (log_calls < 2) log_formats[log_calls] = format;
	++log_calls;
	return log_result;
}

int a2940_timeout_test_send(void *message, int destination, int timeout)
{
	unsigned int i;
	const unsigned char *bytes = (const unsigned char *)message;
	for (i = 0; i < 24; ++i) sent_message[i] = bytes[i];
	send_arguments[0] = destination;
	send_arguments[1] = timeout;
	++send_calls;
	return send_result;
}

#include "../Adaptec2940Timeout.c"

static int check(int condition) { return condition ? 0 : 1; }
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);

void mainCRTStartup(void)
{
	unsigned char scb[256] = {0};
	unsigned char expected[24] = {
		0, 0, 0, 1, 0x18, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0x78, 0x56, 0x34, 0x12, 0x23, 0x23, 0x23, 0
	};
	unsigned int i;
	int result = 0;
	*(int *)(scb + 236) = 0x12345678;
	log_result = 0;
	send_result = 0;
	result |= check(a2940Timeout((int)(unsigned long)scb) == 0);
	result |= check(send_calls == 1 && log_calls == 1);
	result |= check(log_formats[0] != 0 && log_formats[1] == 0);
	result |= check(send_arguments[0] == 0 && send_arguments[1] == 0);
	for (i = 0; i < 24; ++i) result |= check(sent_message[i] == expected[i]);

	log_calls = send_calls = 0;
	send_result = -7;
	log_result = 19;
	result |= check(a2940Timeout((int)(unsigned long)scb) == 19);
	result |= check(send_calls == 1 && log_calls == 2);
	result |= check(log_formats[1] != 0);
	ExitProcess((unsigned int)result);
}
