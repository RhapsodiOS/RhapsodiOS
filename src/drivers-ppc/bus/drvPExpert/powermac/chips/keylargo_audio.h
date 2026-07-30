#ifndef _PEXPERT_KEYLARGO_AUDIO_H_
#define _PEXPERT_KEYLARGO_AUDIO_H_

#include <machdep/ppc/PEKeyLargo.h>

enum {
    kPEKeyWestRegMode = 0,
    kPEKeyWestRegControl = 1,
    kPEKeyWestRegStatus = 2,
    kPEKeyWestRegISR = 3,
    kPEKeyWestRegIER = 4,
    kPEKeyWestRegAddress = 5,
    kPEKeyWestRegSubaddress = 6,
    kPEKeyWestRegData = 7
};

#define kPEKeyWestModeStandardSubaddress 0x08
#define kPEKeyWestModeCombined           0x0c
#define kPEKeyWestSpeedMask              0x03
#define kPEKeyWestSpeed100kHz            0x00
#define kPEKeyWestSpeed50kHz             0x01
#define kPEKeyWestSpeed25kHz             0x02
#define kPEKeyWestControlSendACK         0x01
#define kPEKeyWestControlTransferAddress 0x02
#define kPEKeyWestControlStop            0x04
#define kPEKeyWestStatusBusy             0x01
#define kPEKeyWestStatusLastACK          0x02
#define kPEKeyWestInterruptData          0x01
#define kPEKeyWestInterruptAddress       0x02
#define kPEKeyWestInterruptStop          0x04
#define kPEKeyWestInterruptStart         0x08
#define kPEKeyWestInterruptMask          0x0f

#define kPEAudioGPIOOutputData   0x01
#define kPEAudioGPIOInputData    0x02
#define kPEAudioGPIOOutputEnable 0x04

typedef struct {
    unsigned char speed;
    void *context;
    unsigned char (*read8)(void *context, unsigned int offset);
    void (*write8)(void *context, unsigned int offset,
        unsigned char value);
    unsigned char (*readGPIO8)(void *context, unsigned int offset);
    void (*writeGPIO8)(void *context, unsigned int offset,
        unsigned char value);
    unsigned int (*readFCR1LE)(void *context);
    void (*writeFCR1LE)(void *context, unsigned int value);
    void (*getTime)(void *context, tvalspec_t *now);
    int (*compareTime)(void *context, const tvalspec_t *left,
        const tvalspec_t *right);
    kern_return_t (*transferStatus)(void *context);
    void (*lock)(void *context);
    void (*unlock)(void *context);
    boolean_t (*inInterruptContext)(void *context);
    boolean_t (*validOffset)(void *context, unsigned int offset,
        unsigned int length);
} PEKeyLargoTransport;

void PEKeyLargoBindTransport(const PEKeyLargoTransport *transport);

kern_return_t PEKeyWestI2CTransferCore(
    const PEKeyLargoTransport *transport,
    const PEKeyWestI2CRequest *request);
kern_return_t PEAudioGPIOReadCore(const PEKeyLargoTransport *transport,
    const PEAudioGPIO *gpio, boolean_t *active);
kern_return_t PEAudioGPIOWriteCore(const PEKeyLargoTransport *transport,
    const PEAudioGPIO *gpio, boolean_t active);
kern_return_t PEI2SSetCellStateCore(const PEKeyLargoTransport *transport,
    unsigned int cell, PEI2SCellState state);

#endif /* _PEXPERT_KEYLARGO_AUDIO_H_ */
