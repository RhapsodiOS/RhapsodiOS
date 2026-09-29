#include <mach/mach.h>
#include <stdio.h>
#include <strings.h>
#include <string.h>
#include "Private/InterceptorIPC.h"

#ifdef INTERCEPTOR_IPC_TEST_TRANSPORT
extern int InterceptorTestMsgRPC(msg_header_t *, int, int, int, int);
#define InterceptorMsgRPC InterceptorTestMsgRPC
#else
#define InterceptorMsgRPC msg_rpc
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
