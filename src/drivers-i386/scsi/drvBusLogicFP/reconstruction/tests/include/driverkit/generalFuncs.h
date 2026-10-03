#ifndef BLFP_TEST_GENERAL_FUNCS_H
#define BLFP_TEST_GENERAL_FUNCS_H
void IOLog(const char *format, ...);
void IOSleep(unsigned int milliseconds);
void IOFree(void *address, unsigned int size);
#endif
