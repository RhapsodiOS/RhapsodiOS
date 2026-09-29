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
