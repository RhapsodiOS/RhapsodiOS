#include <mach/mach.h>
#include <stdio.h>
#include <strings.h>
#include <string.h>
#include "Private/InterceptorIPC.h"

#ifdef INTERCEPTOR_IPC_TEST_TRANSPORT
extern int InterceptorTestMsgRPC(msg_header_t *, int, int, int, int);
extern int InterceptorTestMsgSend(msg_header_t *, int, int);
#define InterceptorMsgRPC InterceptorTestMsgRPC
#define InterceptorMsgSend InterceptorTestMsgSend
#else
#define InterceptorMsgRPC msg_rpc
#define InterceptorMsgSend msg_send
#endif

typedef struct {
    msg_header_t header;
    int words[13];
} InterceptorRPCMessage;

typedef struct {
    msg_header_t header;
    int words[62];
} InterceptorFrameBufferInfoMessage;

typedef struct {
    msg_header_t header;
    int words[8];
} InterceptorTableMessage;

static int InterceptorTypeDescriptor(int name, int size, int count)
{
    msg_type_t descriptor;
    int word;
    bzero((char *)&descriptor, sizeof(descriptor));
    descriptor.msg_type_name = name;
    descriptor.msg_type_size = size;
    descriptor.msg_type_number = count;
    descriptor.msg_type_inline = 1;
    memcpy(&word, &descriptor, sizeof(word));
    return word;
}

static int InterceptorCheckLongType(int *words, int name, int size,
                                    unsigned int count)
{
    msg_type_long_t descriptor;
    memcpy(&descriptor, words, sizeof(descriptor));
    return descriptor.msg_type_header.msg_type_inline == 1 &&
           descriptor.msg_type_header.msg_type_longform == 1 &&
           descriptor.msg_type_long_name == name &&
           descriptor.msg_type_long_size == size &&
           descriptor.msg_type_long_number == count;
}

static void InterceptorSetRPCHeader(InterceptorRPCMessage *message,
                                    port_t contextPort, port_t replyPort,
                                    int messageID, int messageSize,
                                    int simple)
{
    bzero((char *)message, sizeof(*message));
    message->header.msg_simple = simple;
    message->header.msg_size = messageSize;
    message->header.msg_type = 0x100;
    message->header.msg_local_port = replyPort;
    message->header.msg_remote_port = contextPort;
    message->header.msg_id = messageID;
}

static int InterceptorCheckRPCReply(InterceptorRPCMessage *message,
                                    int replyID, int successSize,
                                    int errorSize)
{
    int *words = message->words;
    if (message->header.msg_id != replyID)
        return Interceptor_mig_error(-301);
    if (message->header.msg_simple != 1 ||
        words[0] != InterceptorTypeDescriptor(2, 32, 1))
        return Interceptor_mig_error(-300);
    if ((message->header.msg_size == errorSize ||
         message->header.msg_size == successSize) && words[1] != 0) {
        Interceptor_mig_error(words[1]);
        return words[1];
    }
    if (message->header.msg_size != successSize)
        return Interceptor_mig_error(-300);
    return 0;
}

int Interceptor_mig_error(int error)
{
    char *description = mach_error_string(error);
    if (description)
        printf("Interceptor_client: mig error - %s\n", description);
    else
        printf("Interceptor_client: mig error - %d\n", error);
    return error;
}

int _InterceptorAddRect(port_t contextPort, port_t replyPort,
                        InterceptedRectangle *rectangle)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort, 0x1C23, 60, 1);
    words = message.words;
    words[0] = InterceptorTypeDescriptor(2, 32, 8);
    memcpy(&words[1], rectangle, sizeof(*rectangle));

    result = InterceptorMsgRPC(&message.header, 0, 76, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, 0x1C87, 76, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1) ||
        words[4] != InterceptorTypeDescriptor(2, 32, 8)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    memcpy(rectangle, &words[5], sizeof(*rectangle));
    return words[3];
}

int _InterceptorRemoveRect(port_t contextPort, port_t replyPort,
                           unsigned int uniqueID)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort, 0x1C24, 32, 1);
    words = message.words;
    words[0] = InterceptorTypeDescriptor(2, 32, 1);
    words[1] = (int)uniqueID;

    result = InterceptorMsgRPC(&message.header, 0, 40, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, 0x1C88, 40, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    return words[3];
}

int _InterceptorSetNotifyPort(port_t contextPort, port_t replyPort,
                              port_t notifyPort, port_t exceptionPort)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort, 0x1C25, 40, 0);
    words = message.words;
    words[0] = InterceptorTypeDescriptor(6, 32, 1);
    words[1] = (int)notifyPort;
    words[2] = InterceptorTypeDescriptor(6, 32, 1);
    words[3] = (int)exceptionPort;

    result = InterceptorMsgRPC(&message.header, 0, 40, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, 0x1C89, 40, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    return words[3];
}

static int InterceptorSimpleReplyRPC(port_t contextPort, port_t replyPort,
                                     int requestID, int replyID)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort,
                            requestID, sizeof(msg_header_t), 1);
    result = InterceptorMsgRPC(&message.header, 0, sizeof(message.header) +
                               4 * sizeof(int), 0, 0);
    words = message.words;
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, replyID, 40, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    return words[3];
}

int _InterceptorScreenCount(port_t contextPort, port_t replyPort)
{
    return InterceptorSimpleReplyRPC(contextPort, replyPort, 7207, 7307);
}

int _InterceptorHideCursor(port_t contextPort, port_t replyPort)
{
    return InterceptorSimpleReplyRPC(contextPort, replyPort, 7208, 7308);
}

int _InterceptorShowCursor(port_t contextPort, port_t replyPort)
{
    return InterceptorSimpleReplyRPC(contextPort, replyPort, 7209, 7309);
}

int _InterceptorShowCursorAsync(port_t contextPort)
{
    msg_header_t message;
    int result;

    bzero((char *)&message, sizeof(message));
    message.msg_simple = 1;
    message.msg_size = sizeof(message);
    message.msg_type = 0;
    message.msg_remote_port = contextPort;
    message.msg_local_port = PORT_NULL;
    message.msg_id = 7218;
    result = InterceptorMsgSend(&message, 0, 0);
    if (result != 0)
        Interceptor_mig_error(result);
    return result;
}

int InterceptorScreenCount(InterceptorClientContext *context)
{
    return _InterceptorScreenCount(context->contextPort, context->replyPort);
}

int InterceptorHideCursor(InterceptorClientContext *context)
{
    return _InterceptorHideCursor(context->contextPort, context->replyPort);
}

int InterceptorShowCursor(InterceptorClientContext *context)
{
    (void)_InterceptorShowCursorAsync(context->contextPort);
    return 0;
}

int _InterceptorMapFrameBuffer(port_t contextPort, port_t replyPort,
                               int screenNumber, port_t taskPort,
                               unsigned int *address)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort,
                            7198, 40, 0);
    words = message.words;
    words[0] = InterceptorTypeDescriptor(2, 32, 1);
    words[1] = screenNumber;
    words[2] = InterceptorTypeDescriptor(6, 32, 1);
    words[3] = (int)taskPort;

    result = InterceptorMsgRPC(&message.header, 0, 48, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, 7298, 48, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1) ||
        words[4] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    *address = (unsigned int)words[5];
    return words[3];
}

int _InterceptorUnmapFrameBuffer(port_t contextPort, port_t replyPort,
                                 int screenNumber, port_t taskPort,
                                 unsigned int address)
{
    InterceptorRPCMessage message;
    int *words;
    int result;

    InterceptorSetRPCHeader(&message, contextPort, replyPort,
                            7219, 48, 0);
    words = message.words;
    words[0] = InterceptorTypeDescriptor(2, 32, 1);
    words[1] = screenNumber;
    words[2] = InterceptorTypeDescriptor(6, 32, 1);
    words[3] = (int)taskPort;
    words[4] = InterceptorTypeDescriptor(2, 32, 1);
    words[5] = (int)address;

    result = InterceptorMsgRPC(&message.header, 0, 40, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    result = InterceptorCheckRPCReply(&message, 7319, 40, 32);
    if (result != 0)
        return words[3];
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    return words[3];
}

int InterceptorMapFrameBuffer(InterceptorClientContext *context,
                              int screenNumber, void **address)
{
    unsigned int mappedAddress = 0;
    int result = _InterceptorMapFrameBuffer(context->contextPort,
                                            context->replyPort, screenNumber,
                                            task_self(), &mappedAddress);
    if (result == 0)
        *address = (void *)(unsigned long)mappedAddress;
    return result;
}

int InterceptorUnmapFrameBuffer(InterceptorClientContext *context,
                                int screenNumber, void *address)
{
    return _InterceptorUnmapFrameBuffer(context->contextPort,
                                        context->replyPort, screenNumber,
                                        task_self(),
                                        (unsigned int)(unsigned long)address);
}

int _InterceptorFrameBufferInfo(port_t contextPort, port_t replyPort,
                                int screenNumber, char *driver,
                                int *deviceSlot, int *deviceUnit,
                                int *pixelsWide, int *pixelsHigh,
                                int *bitsPerPixel, int *bytesPerRow,
                                int *colorSpaceCode, char *pixelEncoding,
                                int *reserved)
{
    InterceptorFrameBufferInfoMessage message;
    int *words = message.words;
    int *outputs[7];
    int field;
    int result;

    bzero((char *)&message, sizeof(message));
    message.header.msg_simple = 1;
    message.header.msg_size = 32;
    message.header.msg_type = 0x100;
    message.header.msg_local_port = replyPort;
    message.header.msg_remote_port = contextPort;
    message.header.msg_id = 7201;
    words[0] = InterceptorTypeDescriptor(2, 32, 1);
    words[1] = screenNumber;

    result = InterceptorMsgRPC(&message.header, 0, 272, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    if (message.header.msg_id != 7301) {
        Interceptor_mig_error(-301);
        return words[3];
    }
    if (message.header.msg_simple != 1 ||
        words[0] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    if (message.header.msg_size == 32 && words[1] != 0) {
        Interceptor_mig_error(words[1]);
        return words[3];
    }
    if (message.header.msg_size != 272) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    if (words[1] != 0) {
        Interceptor_mig_error(words[1]);
        return words[3];
    }
    if (words[2] != InterceptorTypeDescriptor(2, 32, 1) ||
        !InterceptorCheckLongType(&words[4], 12, 640, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }

    strncpy(driver, (const char *)&words[7], 80);
    driver[79] = 0;
    outputs[0] = deviceSlot;
    outputs[1] = deviceUnit;
    outputs[2] = pixelsWide;
    outputs[3] = pixelsHigh;
    outputs[4] = bitsPerPixel;
    outputs[5] = bytesPerRow;
    outputs[6] = colorSpaceCode;
    for (field = 0; field < 7; field++) {
        int descriptorIndex = 27 + field * 2;
        if (words[descriptorIndex] != InterceptorTypeDescriptor(2, 32, 1)) {
            Interceptor_mig_error(-300);
            return words[3];
        }
        *outputs[field] = words[descriptorIndex + 1];
    }
    if (!InterceptorCheckLongType(&words[41], 12, 512, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    strncpy(pixelEncoding, (const char *)&words[44], 64);
    pixelEncoding[63] = 0;
    if (words[60] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    *reserved = words[61];
    return words[3];
}

int InterceptorFrameBufferInfo(InterceptorClientContext *context,
                               int screenNumber, char *driver,
                               int *deviceSlot, int *deviceUnit,
                               int *pixelsWide, int *pixelsHigh,
                               int *bitsPerPixel, int *bytesPerRow,
                               int *colorSpaceCode, char *pixelEncoding,
                               int *reserved)
{
    return _InterceptorFrameBufferInfo(context->contextPort,
                                       context->replyPort, screenNumber,
                                       driver, deviceSlot, deviceUnit,
                                       pixelsWide, pixelsHigh, bitsPerPixel,
                                       bytesPerRow, colorSpaceCode,
                                       pixelEncoding, reserved);
}

static int InterceptorGetShortTable(port_t contextPort, port_t replyPort,
                                    int requestID, int replyID,
                                    int descriptor, void **table)
{
    InterceptorTableMessage message;
    int *words = message.words;
    int result;

    bzero((char *)&message, sizeof(message));
    message.header.msg_simple = 1;
    message.header.msg_size = sizeof(msg_header_t);
    message.header.msg_type = 0x100;
    message.header.msg_local_port = replyPort;
    message.header.msg_remote_port = contextPort;
    message.header.msg_id = requestID;
    result = InterceptorMsgRPC(&message.header, 0, 48, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    if (message.header.msg_id != replyID) {
        Interceptor_mig_error(-301);
        return words[3];
    }
    if (message.header.msg_size == 32) {
        if (message.header.msg_simple != 1 ||
            words[0] != InterceptorTypeDescriptor(2, 32, 1)) {
            Interceptor_mig_error(-300);
            return words[3];
        }
        if (words[1] != 0) {
            Interceptor_mig_error(words[1]);
            return words[3];
        }
    }
    if (message.header.msg_size != 48 || message.header.msg_simple != 0 ||
        words[0] != InterceptorTypeDescriptor(2, 32, 1) || words[1] != 0 ||
        words[2] != InterceptorTypeDescriptor(2, 32, 1) ||
        words[4] != descriptor) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    *table = (void *)(unsigned long)(unsigned int)words[5];
    return words[3];
}

static int InterceptorGetLongTable(port_t contextPort, port_t replyPort,
                                   int requestID, int replyID,
                                   unsigned int tableCount, void **table)
{
    InterceptorTableMessage message;
    int *words = message.words;
    msg_type_long_t descriptor;
    int result;

    bzero((char *)&message, sizeof(message));
    message.header.msg_simple = 1;
    message.header.msg_size = sizeof(msg_header_t);
    message.header.msg_type = 0x100;
    message.header.msg_local_port = replyPort;
    message.header.msg_remote_port = contextPort;
    message.header.msg_id = requestID;
    result = InterceptorMsgRPC(&message.header, 0, 56, 0, 0);
    if (result != 0) {
        Interceptor_mig_error(result);
        return words[3];
    }
    if (message.header.msg_id != replyID) {
        Interceptor_mig_error(-301);
        return words[3];
    }
    if (message.header.msg_size == 32) {
        if (message.header.msg_simple != 1 ||
            words[0] != InterceptorTypeDescriptor(2, 32, 1)) {
            Interceptor_mig_error(-300);
            return words[3];
        }
        if (words[1] != 0) {
            Interceptor_mig_error(words[1]);
            return words[3];
        }
    }
    if (message.header.msg_size != 56 || message.header.msg_simple != 0 ||
        words[0] != InterceptorTypeDescriptor(2, 32, 1) || words[1] != 0 ||
        words[2] != InterceptorTypeDescriptor(2, 32, 1)) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    memcpy(&descriptor, &words[4], sizeof(descriptor));
    if (descriptor.msg_type_header.msg_type_inline != 0 ||
        descriptor.msg_type_header.msg_type_longform != 1 ||
        descriptor.msg_type_long_name != 1 ||
        descriptor.msg_type_long_size != 16 ||
        descriptor.msg_type_long_number != tableCount) {
        Interceptor_mig_error(-300);
        return words[3];
    }
    *table = (void *)(unsigned long)(unsigned int)words[7];
    return words[3];
}

int _InterceptorGetBM34ToBM35Table(port_t contextPort, port_t replyPort,
                                   void **table)
{
    return InterceptorGetLongTable(contextPort, replyPort, 7199, 7299,
                                   4096, table);
}

int _InterceptorGetBM35ToBM34Table(port_t contextPort, port_t replyPort,
                                   void **table)
{
    return InterceptorGetLongTable(contextPort, replyPort, 7206, 7306,
                                   32768, table);
}

int _InterceptorGetBM256ToBM38Table(port_t contextPort, port_t replyPort,
                                    void **table)
{
#if defined(__ppc__) || defined(__POWERPC__)
    return InterceptorGetShortTable(contextPort, replyPort, 7210, 7310,
                                    0x02201000, table);
#else
    return InterceptorGetShortTable(contextPort, replyPort, 7210, 7310,
                                    0x01002002, table);
#endif
}

int _InterceptorGetBM38ToBM256Table(port_t contextPort, port_t replyPort,
                                    void **table)
{
#if defined(__ppc__) || defined(__POWERPC__)
    return InterceptorGetShortTable(contextPort, replyPort, 7211, 7311,
                                    0x08084000, table);
#else
    return InterceptorGetShortTable(contextPort, replyPort, 7211, 7311,
                                    0x04000808, table);
#endif
}

int InterceptorGetBM34ToBM35Table(InterceptorClientContext *context,
                                  void **table)
{
#if defined(__ppc__) || defined(__POWERPC__)
    (void)context;
    (void)table;
    return 6;
#else
    return _InterceptorGetBM34ToBM35Table(context->contextPort,
                                           context->replyPort, table);
#endif
}

int InterceptorGetBM35ToBM34Table(InterceptorClientContext *context,
                                  void **table)
{
#if defined(__ppc__) || defined(__POWERPC__)
    (void)context;
    (void)table;
    return 6;
#else
    return _InterceptorGetBM35ToBM34Table(context->contextPort,
                                           context->replyPort, table);
#endif
}

int InterceptorGetBM256ToBM38Table(InterceptorClientContext *context,
                                   void **table)
{
    return _InterceptorGetBM256ToBM38Table(context->contextPort,
                                           context->replyPort, table);
}

int InterceptorGetBM38ToBM256Table(InterceptorClientContext *context,
                                   void **table)
{
    return _InterceptorGetBM38ToBM256Table(context->contextPort,
                                           context->replyPort, table);
}
