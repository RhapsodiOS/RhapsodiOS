/* Timeout notification message recovered from the IDA data template. */
#ifdef A2940_TIMEOUT_STANDALONE
extern int a2940_timeout_test_log(const char *, ...);
extern int a2940_timeout_test_send(void *, int, int);
#define A2940_TIMEOUT_LOG a2940_timeout_test_log
#define A2940_TIMEOUT_SEND a2940_timeout_test_send
#else
extern int IOLog(const char *, ...);
extern int msg_send_from_kernel(void *, int, int);
#define A2940_TIMEOUT_LOG IOLog
#define A2940_TIMEOUT_SEND msg_send_from_kernel
#endif

static const unsigned char timeoutMsgTemplate[24] = {
	0x00, 0x00, 0x00, 0x01, 0x18, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x23, 0x23, 0x23, 0x00
};

int a2940Timeout(int scb_address)
{
	unsigned char message[24];
	int *scb = (int *)(unsigned long)(unsigned int)scb_address;
	int send_result;
	unsigned int index;
	for (index = 0; index < sizeof(timeoutMsgTemplate); ++index)
		message[index] = timeoutMsgTemplate[index];
	*(int *)(message + 16) = *(int *)((unsigned char *)scb + 236);
	A2940_TIMEOUT_LOG("Adaptec2940 timeout\n");
	send_result = A2940_TIMEOUT_SEND(message, 0, 0);
	if (send_result != 0)
		return A2940_TIMEOUT_LOG("a2940Timeout: msg_send_from_kernel() returned %d\n", send_result);
	return 0;
}
