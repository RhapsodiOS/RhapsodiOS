#ifndef _MACHDEP_PPC_PEKEYLARGO_H_
#define _MACHDEP_PPC_PEKEYLARGO_H_

#include <mach/boolean.h>
#include <mach/kern_return.h>
#include <mach/clock_types.h>

typedef enum {
    kPEKeyWestWrite = 0,
    kPEKeyWestRead = 1
} PEKeyWestDirection;

typedef struct {
    unsigned int port;
    unsigned char address;
    unsigned char subaddress;
    PEKeyWestDirection direction;
    unsigned char *buffer;
    unsigned int length;
    tvalspec_t deadline;
} PEKeyWestI2CRequest;

typedef struct {
    unsigned int offset;
    boolean_t activeHigh;
} PEAudioGPIO;

typedef enum {
    kPEI2SCellDisabledReset = 0,
    kPEI2SCellEnabledClockHeld = 1,
    kPEI2SCellRunning = 2
} PEI2SCellState;

#define KERN_PE_KEYWEST_NACK             ((kern_return_t)0x100)
#define KERN_PE_KEYWEST_BUSY             ((kern_return_t)0x101)
#define KERN_PE_KEYWEST_ARBITRATION_LOST ((kern_return_t)0x102)
#define KERN_PE_KEYWEST_TIMEOUT          ((kern_return_t)0x103)
#define KERN_PE_KEYLARGO_NOT_READY       ((kern_return_t)0x104)

kern_return_t PEKeyWestI2CTransfer(const PEKeyWestI2CRequest *request);
kern_return_t PEAudioGPIORead(const PEAudioGPIO *gpio, boolean_t *active);
kern_return_t PEAudioGPIOWrite(const PEAudioGPIO *gpio, boolean_t active);
kern_return_t PEI2SSetCellState(unsigned int cell, PEI2SCellState state);

#endif /* _MACHDEP_PPC_PEKEYLARGO_H_ */
