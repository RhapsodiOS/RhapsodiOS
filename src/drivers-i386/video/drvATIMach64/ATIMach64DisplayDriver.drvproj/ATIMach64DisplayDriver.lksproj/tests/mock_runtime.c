#include "mock_runtime.h"
#include <stdlib.h>
#include <string.h>

static unsigned int panicCount, logCount, allocationCount, freeCount;
static unsigned int failAllocation, dispatchCount, biosCallCount;
static unsigned int portEventCount, delayEventCount;
static int dispatchReturn, biosResult;
static const char *lastSelector;
static ATIBIOSRegisters lastBIOSRegisters;
static ATI_mockPortEvent portEvents[ATI_MOCK_MAX_EVENTS];
static ATI_mockDelayEvent delayEvents[ATI_MOCK_MAX_EVENTS];
static unsigned char rom[ATI_MOCK_ROM_SIZE];
static unsigned char gdt[ATI_MOCK_GDT_SIZE];

void ATI_mockReset(void)
{
    panicCount = logCount = allocationCount = freeCount = failAllocation = 0;
    dispatchCount = biosCallCount = portEventCount = delayEventCount = 0;
    dispatchReturn = biosResult = 0;
    lastSelector = 0;
    memset(&lastBIOSRegisters, 0, sizeof(lastBIOSRegisters));
    memset(portEvents, 0, sizeof(portEvents));
    memset(delayEvents, 0, sizeof(delayEvents));
    memset(rom, 0, sizeof(rom));
    memset(gdt, 0, sizeof(gdt));
}
unsigned int ATI_mockPanicCount(void) { return panicCount; }
unsigned int ATI_mockLogCount(void) { return logCount; }
void ATI_mockFailNextAllocation(void) { failAllocation = 1; }
void *ATI_mockAlloc(size_t size)
{
    void *result;
    if (failAllocation) { failAllocation = 0; return 0; }
    result = malloc(size);
    if (result) ++allocationCount;
    return result;
}
void ATI_mockFree(void *address, size_t size)
{
    (void)size;
    if (address) { ++freeCount; free(address); }
}
void *IOMalloc(int size) { return ATI_mockAlloc((size_t)size); }
void IOFree(void *address, int size) { ATI_mockFree(address, (size_t)size); }
unsigned int ATI_mockAllocationCount(void) { return allocationCount; }
unsigned int ATI_mockFreeCount(void) { return freeCount; }
int ATI_mockDispatch(void *receiver, const char *selector, void *argument)
{
    (void)receiver; (void)argument;
    lastSelector = selector;
    ++dispatchCount;
    return dispatchReturn;
}
void ATI_mockSetDispatchReturn(int value) { dispatchReturn = value; }
const char *ATI_mockLastSelector(void) { return lastSelector; }
unsigned int ATI_mockDispatchCount(void) { return dispatchCount; }
unsigned char *ATI_mockROM(void) { return rom; }
const unsigned char *ATI_mockROMAddress(unsigned int address)
{
    return rom + (address - 0xc0000U);
}
unsigned char *ATI_mockGDT(void) { return gdt; }
void ATI_mockCaptureBIOS(const ATIBIOSRegisters *registers, int result)
{
    if (registers) lastBIOSRegisters = *registers;
    biosResult = result;
    ++biosCallCount;
}
unsigned int ATI_mockBIOSCallCount(void) { return biosCallCount; }
const ATIBIOSRegisters *ATI_mockLastBIOSRegisters(void) { return &lastBIOSRegisters; }
int ATI_mockBIOSResult(void) { return biosResult; }
void ATI_mockRecordPort(unsigned short port, unsigned int value,
                        unsigned char width, unsigned char isWrite)
{
    ATI_mockPortEvent *event;
    if (portEventCount >= ATI_MOCK_MAX_EVENTS) return;
    event = &portEvents[portEventCount++];
    event->port = port; event->value = value; event->width = width; event->isWrite = isWrite;
}
void ATI_mockRecordDelay(unsigned int delay)
{
    if (delayEventCount < ATI_MOCK_MAX_EVENTS)
        delayEvents[delayEventCount++].delay = delay;
}
unsigned int ATI_mockPortEventCount(void) { return portEventCount; }
unsigned int ATI_mockDelayEventCount(void) { return delayEventCount; }
const ATI_mockPortEvent *ATI_mockPortEvents(void) { return portEvents; }
const ATI_mockDelayEvent *ATI_mockDelayEvents(void) { return delayEvents; }

void IOLog(const char *format, ...)
{
    (void)format;
    ++logCount;
}

void IOPanic(const char *reason)
{
    (void)reason;
    ++panicCount;
}
