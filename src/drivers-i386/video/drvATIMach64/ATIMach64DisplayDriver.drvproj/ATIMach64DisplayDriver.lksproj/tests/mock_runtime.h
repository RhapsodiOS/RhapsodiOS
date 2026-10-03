#ifndef ATI_MOCK_RUNTIME_H
#define ATI_MOCK_RUNTIME_H

#include <stddef.h>
#include "../ATIBIOSTypes.h"

#define ATI_MOCK_MAX_EVENTS 256
#define ATI_MOCK_ROM_SIZE 65536
#define ATI_MOCK_GDT_SIZE 4096

typedef struct { unsigned short port; unsigned int value; unsigned char width, isWrite; } ATI_mockPortEvent;
typedef struct { unsigned int delay; } ATI_mockDelayEvent;

void ATI_mockReset(void);
unsigned int ATI_mockPanicCount(void);
unsigned int ATI_mockLogCount(void);
void ATI_mockFailNextAllocation(void);
void *ATI_mockAlloc(size_t size);
void ATI_mockFree(void *address, size_t size);
unsigned int ATI_mockAllocationCount(void);
unsigned int ATI_mockFreeCount(void);
void *IOMalloc(int size);
void IOFree(void *address, int size);
int ATI_mockDispatch(void *receiver, const char *selector, void *argument);
void ATI_mockSetDispatchReturn(int value);
const char *ATI_mockLastSelector(void);
unsigned int ATI_mockDispatchCount(void);
unsigned char *ATI_mockROM(void);
unsigned char *ATI_mockGDT(void);
void ATI_mockCaptureBIOS(const ATIBIOSRegisters *registers, int result);
unsigned int ATI_mockBIOSCallCount(void);
const ATIBIOSRegisters *ATI_mockLastBIOSRegisters(void);
int ATI_mockBIOSResult(void);
void ATI_mockRecordPort(unsigned short port, unsigned int value, unsigned char width, unsigned char isWrite);
void ATI_mockRecordDelay(unsigned int delay);
unsigned int ATI_mockPortEventCount(void);
unsigned int ATI_mockDelayEventCount(void);
const ATI_mockPortEvent *ATI_mockPortEvents(void);
const ATI_mockDelayEvent *ATI_mockDelayEvents(void);

#endif
