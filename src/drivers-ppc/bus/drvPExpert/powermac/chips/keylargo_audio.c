#include "keylargo_audio.h"

static const PEKeyLargoTransport *keylargo_transport;

static boolean_t
keylargo_transport_valid(const PEKeyLargoTransport *transport)
{
    return transport != 0 && transport->speed <= kPEKeyWestSpeed25kHz &&
        transport->read8 != 0 &&
        transport->write8 != 0 && transport->readGPIO8 != 0 &&
        transport->writeGPIO8 != 0 && transport->readFCR1LE != 0 &&
        transport->writeFCR1LE != 0 && transport->getTime != 0 &&
        transport->compareTime != 0 && transport->transferStatus != 0 &&
        transport->lock != 0 && transport->unlock != 0 &&
        transport->inInterruptContext != 0 &&
        transport->validOffset != 0;
}

void
PEKeyLargoBindTransport(const PEKeyLargoTransport *transport)
{
    keylargo_transport = keylargo_transport_valid(transport) ? transport : 0;
}

static boolean_t
keywest_deadline_reached(const PEKeyLargoTransport *transport,
    const tvalspec_t *deadline)
{
    tvalspec_t now;

    transport->getTime(transport->context, &now);
    return transport->compareTime(transport->context, &now, deadline) >= 0;
}

static kern_return_t
keywest_wait_interrupt(const PEKeyLargoTransport *transport,
    unsigned char expected, const tvalspec_t *deadline)
{
    unsigned char pending;
    kern_return_t status;

    for (;;) {
        if (keywest_deadline_reached(transport, deadline))
            return KERN_PE_KEYWEST_TIMEOUT;
        status = transport->transferStatus(transport->context);
        if (status != KERN_SUCCESS)
            return status;
        pending = transport->read8(transport->context,
            kPEKeyWestRegISR);
        if ((pending & expected) != 0)
            return KERN_SUCCESS;
        if (pending != 0)
            transport->write8(transport->context, kPEKeyWestRegISR,
                pending);
    }
}

static void
keywest_issue_stop(const PEKeyLargoTransport *transport)
{
    transport->write8(transport->context, kPEKeyWestRegControl,
        kPEKeyWestControlStop);
}

static void
keywest_cleanup(const PEKeyLargoTransport *transport)
{
    transport->write8(transport->context, kPEKeyWestRegControl, 0);
    transport->write8(transport->context, kPEKeyWestRegIER, 0);
    transport->write8(transport->context, kPEKeyWestRegStatus, 0);
    transport->write8(transport->context, kPEKeyWestRegISR,
        kPEKeyWestInterruptMask);
}

kern_return_t
PEKeyWestI2CTransferCore(const PEKeyLargoTransport *transport,
    const PEKeyWestI2CRequest *request)
{
    kern_return_t result;
    kern_return_t stopResult;
    unsigned int index;
    unsigned char status;
    unsigned char mode;
    boolean_t started;

    if (!keylargo_transport_valid(transport) || request == 0 ||
        request->buffer == 0 || request->length == 0 ||
        request->address < 0x08 || request->address > 0x77 ||
        request->port > 0x0f ||
        (request->direction != kPEKeyWestWrite &&
        request->direction != kPEKeyWestRead))
        return KERN_INVALID_ARGUMENT;

    result = KERN_SUCCESS;
    stopResult = KERN_SUCCESS;
    started = FALSE;
    transport->lock(transport->context);

    status = transport->read8(transport->context, kPEKeyWestRegStatus);
    if ((status & kPEKeyWestStatusBusy) != 0) {
        result = KERN_PE_KEYWEST_BUSY;
        keywest_issue_stop(transport);
        stopResult = keywest_wait_interrupt(transport,
            kPEKeyWestInterruptStop, &request->deadline);
        if (stopResult == KERN_SUCCESS)
            transport->write8(transport->context, kPEKeyWestRegISR,
                kPEKeyWestInterruptStop);
        else
            result = stopResult;
        goto out;
    }

    mode = request->direction == kPEKeyWestRead ?
        kPEKeyWestModeCombined : kPEKeyWestModeStandardSubaddress;
    mode = (unsigned char)(mode | (request->port << 4) |
        transport->speed);
    transport->write8(transport->context, kPEKeyWestRegMode, mode);
    transport->write8(transport->context, kPEKeyWestRegStatus, 0);
    status = transport->read8(transport->context, kPEKeyWestRegISR);
    transport->write8(transport->context, kPEKeyWestRegISR, status);
    transport->write8(transport->context, kPEKeyWestRegIER,
        kPEKeyWestInterruptMask);
    transport->write8(transport->context, kPEKeyWestRegAddress,
        (unsigned char)((request->address << 1) |
        (request->direction == kPEKeyWestRead ? 1 : 0)));
    transport->write8(transport->context, kPEKeyWestRegSubaddress,
        request->subaddress);
    transport->write8(transport->context, kPEKeyWestRegControl,
        kPEKeyWestControlTransferAddress);
    started = TRUE;

    result = keywest_wait_interrupt(transport,
        kPEKeyWestInterruptAddress, &request->deadline);
    if (result != KERN_SUCCESS)
        goto stop;
    status = transport->read8(transport->context, kPEKeyWestRegStatus);
    transport->write8(transport->context, kPEKeyWestRegISR,
        kPEKeyWestInterruptAddress);
    if ((status & kPEKeyWestStatusLastACK) == 0) {
        result = KERN_PE_KEYWEST_NACK;
        goto stop;
    }

    if (request->direction == kPEKeyWestWrite) {
        for (index = 0; index < request->length; index++) {
            transport->write8(transport->context, kPEKeyWestRegData,
                request->buffer[index]);
            result = keywest_wait_interrupt(transport,
                kPEKeyWestInterruptData, &request->deadline);
            if (result != KERN_SUCCESS)
                goto stop;
            status = transport->read8(transport->context,
                kPEKeyWestRegStatus);
            transport->write8(transport->context, kPEKeyWestRegISR,
                kPEKeyWestInterruptData);
            if ((status & kPEKeyWestStatusLastACK) == 0) {
                result = KERN_PE_KEYWEST_NACK;
                goto stop;
            }
        }
    } else {
        if (request->length > 1)
            transport->write8(transport->context,
                kPEKeyWestRegControl, kPEKeyWestControlSendACK);
        for (index = 0; index < request->length; index++) {
            result = keywest_wait_interrupt(transport,
                kPEKeyWestInterruptData, &request->deadline);
            if (result != KERN_SUCCESS)
                goto stop;
            request->buffer[index] = transport->read8(transport->context,
                kPEKeyWestRegData);
            transport->write8(transport->context, kPEKeyWestRegISR,
                kPEKeyWestInterruptData);
            if (index + 2 == request->length)
                transport->write8(transport->context,
                    kPEKeyWestRegControl, 0);
        }
    }

stop:
    keywest_issue_stop(transport);
    if (started && result != KERN_PE_KEYWEST_TIMEOUT) {
        stopResult = keywest_wait_interrupt(transport,
            kPEKeyWestInterruptStop, &request->deadline);
        if (stopResult == KERN_SUCCESS)
            transport->write8(transport->context, kPEKeyWestRegISR,
                kPEKeyWestInterruptStop);
        else if (result == KERN_SUCCESS)
            result = stopResult;
    }
out:
    keywest_cleanup(transport);
    transport->unlock(transport->context);
    return result;
}

kern_return_t
PEAudioGPIOReadCore(const PEKeyLargoTransport *transport,
    const PEAudioGPIO *gpio, boolean_t *active)
{
    unsigned char value;
    boolean_t high;

    if (!keylargo_transport_valid(transport) || gpio == 0 || active == 0)
        return KERN_INVALID_ARGUMENT;
    transport->lock(transport->context);
    value = transport->readGPIO8(transport->context, gpio->offset);
    high = (value & kPEAudioGPIOInputData) != 0;
    *active = gpio->activeHigh ? high : !high;
    transport->unlock(transport->context);
    return KERN_SUCCESS;
}

kern_return_t
PEAudioGPIOWriteCore(const PEKeyLargoTransport *transport,
    const PEAudioGPIO *gpio, boolean_t active)
{
    unsigned char value;
    boolean_t high;

    if (!keylargo_transport_valid(transport) || gpio == 0)
        return KERN_INVALID_ARGUMENT;
    transport->lock(transport->context);
    value = transport->readGPIO8(transport->context, gpio->offset);
    high = gpio->activeHigh ? active : !active;
    if (high)
        value |= kPEAudioGPIOOutputData;
    else
        value &= (unsigned char)~kPEAudioGPIOOutputData;
    value |= kPEAudioGPIOOutputEnable;
    transport->writeGPIO8(transport->context, gpio->offset, value);
    transport->unlock(transport->context);
    return KERN_SUCCESS;
}

static void
fcr_set_bit(const PEKeyLargoTransport *transport, unsigned int *value,
    unsigned int bit, boolean_t set)
{
    unsigned int changed;

    changed = set ? (*value | bit) : (*value & ~bit);
    if (changed != *value) {
        *value = changed;
        transport->writeFCR1LE(transport->context, *value);
    }
}

kern_return_t
PEI2SSetCellStateCore(const PEKeyLargoTransport *transport,
    unsigned int cell, PEI2SCellState state)
{
    unsigned int shift;
    unsigned int cellBit;
    unsigned int resetBit;
    unsigned int clockBit;
    unsigned int interfaceBit;
    unsigned int value;

    if (!keylargo_transport_valid(transport) || cell > 1 ||
        state < kPEI2SCellDisabledReset || state > kPEI2SCellRunning)
        return KERN_INVALID_ARGUMENT;
    shift = cell == 0 ? 10 : 17;
    cellBit = 1U << shift;
    resetBit = 1U << (shift + 1);
    clockBit = 1U << (shift + 2);
    interfaceBit = 1U << (shift + 3);

    transport->lock(transport->context);
    value = transport->readFCR1LE(transport->context);
    fcr_set_bit(transport, &value, resetBit, TRUE);
    if (state == kPEI2SCellDisabledReset) {
        fcr_set_bit(transport, &value, interfaceBit, FALSE);
        fcr_set_bit(transport, &value, cellBit, FALSE);
        fcr_set_bit(transport, &value, clockBit, FALSE);
    } else {
        fcr_set_bit(transport, &value, clockBit, TRUE);
        fcr_set_bit(transport, &value, cellBit, TRUE);
        fcr_set_bit(transport, &value, interfaceBit, TRUE);
        if (state == kPEI2SCellRunning)
            fcr_set_bit(transport, &value, resetBit, FALSE);
    }
    transport->unlock(transport->context);
    return KERN_SUCCESS;
}

kern_return_t
PEKeyWestI2CTransfer(const PEKeyWestI2CRequest *request)
{
    if (request == 0 || request->buffer == 0 || request->length == 0 ||
        request->address < 0x08 || request->address > 0x77 ||
        request->port > 0x0f ||
        (request->direction != kPEKeyWestWrite &&
        request->direction != kPEKeyWestRead) ||
        BAD_TVALSPEC(&request->deadline))
        return KERN_INVALID_ARGUMENT;
    if (keylargo_transport == 0)
        return KERN_PE_KEYLARGO_NOT_READY;
    if (keylargo_transport->inInterruptContext(
        keylargo_transport->context))
        return KERN_INVALID_ARGUMENT;
    return PEKeyWestI2CTransferCore(keylargo_transport, request);
}

kern_return_t
PEAudioGPIORead(const PEAudioGPIO *gpio, boolean_t *active)
{
    if (gpio == 0 || active == 0 ||
        (gpio->activeHigh != FALSE && gpio->activeHigh != TRUE))
        return KERN_INVALID_ARGUMENT;
    if (keylargo_transport == 0)
        return KERN_PE_KEYLARGO_NOT_READY;
    if (keylargo_transport->inInterruptContext(
        keylargo_transport->context) ||
        !keylargo_transport->validOffset(keylargo_transport->context,
        gpio->offset, 1))
        return KERN_INVALID_ARGUMENT;
    return PEAudioGPIOReadCore(keylargo_transport, gpio, active);
}

kern_return_t
PEAudioGPIOWrite(const PEAudioGPIO *gpio, boolean_t active)
{
    if (gpio == 0 ||
        (gpio->activeHigh != FALSE && gpio->activeHigh != TRUE) ||
        (active != FALSE && active != TRUE))
        return KERN_INVALID_ARGUMENT;
    if (keylargo_transport == 0)
        return KERN_PE_KEYLARGO_NOT_READY;
    if (keylargo_transport->inInterruptContext(
        keylargo_transport->context) ||
        !keylargo_transport->validOffset(keylargo_transport->context,
        gpio->offset, 1))
        return KERN_INVALID_ARGUMENT;
    return PEAudioGPIOWriteCore(keylargo_transport, gpio, active);
}

kern_return_t
PEI2SSetCellState(unsigned int cell, PEI2SCellState state)
{
    if (cell > 1 || state < kPEI2SCellDisabledReset ||
        state > kPEI2SCellRunning)
        return KERN_INVALID_ARGUMENT;
    if (keylargo_transport == 0)
        return KERN_PE_KEYLARGO_NOT_READY;
    if (keylargo_transport->inInterruptContext(
        keylargo_transport->context))
        return KERN_INVALID_ARGUMENT;
    return PEI2SSetCellStateCore(keylargo_transport, cell, state);
}
