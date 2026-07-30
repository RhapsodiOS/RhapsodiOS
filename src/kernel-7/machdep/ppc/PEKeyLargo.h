#ifndef _MACHDEP_PPC_PEKEYLARGO_H_
#define _MACHDEP_PPC_PEKEYLARGO_H_

#include <mach/boolean.h>
#include <mach/kern_return.h>
#include <mach/clock_types.h>
#include <mach/error.h>

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

/* Subsystem 4000 is PM; 4001 is otherwise unused and reserved here. */
#define PE_KEYLARGO_ERROR_SUBSYSTEM 4001
#define pe_keylargo_err(code) \
    ((kern_return_t)(err_kern | err_sub(PE_KEYLARGO_ERROR_SUBSYSTEM) | \
    (code)))

#define KERN_PE_KEYWEST_NACK             pe_keylargo_err(1)
#define KERN_PE_KEYWEST_BUSY             pe_keylargo_err(2)
#define KERN_PE_KEYWEST_ARBITRATION_LOST pe_keylargo_err(3)
#define KERN_PE_KEYWEST_TIMEOUT          pe_keylargo_err(4)
#define KERN_PE_KEYLARGO_NOT_READY       pe_keylargo_err(5)

kern_return_t PEKeyWestI2CTransfer(const PEKeyWestI2CRequest *request);
kern_return_t PEAudioGPIORead(const PEAudioGPIO *gpio, boolean_t *active);
kern_return_t PEAudioGPIOWrite(const PEAudioGPIO *gpio, boolean_t active);
kern_return_t PEI2SSetCellState(unsigned int cell, PEI2SCellState state);

#endif /* _MACHDEP_PPC_PEKEYLARGO_H_ */
