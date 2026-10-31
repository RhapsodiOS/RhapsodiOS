#include <mach/mach.h>
#include <mach/task_special_ports.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <stdio.h>
#include <strings.h>
#include "Private/InterceptorIPC.h"

extern port_t name_server_port;
extern kern_return_t netname_look_up(port_t serverPort, char *hostName,
                                     char *portName, port_t *port);

typedef struct {
    msg_header_t header;
    msg_type_t portType;
    port_t port;
} InterceptorRendezvousMessage;

static port_t InterceptorRendezvousPort;

static port_t rendezVous(port_t replyPort, port_t serverPort, int timeout,
                         int packageID)
{
    InterceptorRendezvousMessage message;

    bzero((char *)&message, sizeof(message));
    message.header.msg_size = sizeof(message);
    message.header.msg_local_port = replyPort;
    message.header.msg_remote_port = serverPort;
    message.header.msg_id = packageID;
    message.portType.msg_type_name = MSG_TYPE_PORT;
    message.portType.msg_type_size = 32;
    message.portType.msg_type_number = 1;
    message.portType.msg_type_inline = 1;
    message.port = replyPort;

    if (msg_rpc(&message.header, 257, sizeof(message), timeout, timeout) !=
        KERN_SUCCESS)
        return PORT_NULL;
    return message.port;
}

static port_t getPSPort(char *hostName, char *portName, port_t replyPort,
                        int timeout, int packageID)
{
    port_t bootstrapPort;
    port_t contextPort = PORT_NULL;

    if (hostName == 0 && portName == 0 &&
        task_get_special_port(task_self(), TASK_BOOTSTRAP_PORT,
                              &bootstrapPort) == KERN_SUCCESS &&
        bootstrap_look_up(bootstrapPort, "WindowServer",
                          &InterceptorRendezvousPort) == KERN_SUCCESS)
        contextPort = rendezVous(replyPort, InterceptorRendezvousPort,
                                 timeout, packageID);

    if (contextPort == PORT_NULL) {
        if (hostName == 0) hostName = "";
        if (portName == 0) portName = "NextStep(tm) Window Server";
        if (netname_look_up(name_server_port, hostName, portName,
                            &InterceptorRendezvousPort) != KERN_SUCCESS) {
            printf("No WindowServer netname port\n");
            return PORT_NULL;
        }
        contextPort = rendezVous(replyPort, InterceptorRendezvousPort,
                                 timeout, packageID);
    }
    return contextPort;
}

port_t _rendezvousPort(void)
{
    return InterceptorRendezvousPort;
}

InterceptorClientContext *InterceptorCreateRemoteContext(char *hostName,
                                                          char *portName)
{
    InterceptorClientContext *context;

    context = (InterceptorClientContext *)malloc(sizeof(*context));
    bzero((char *)context, sizeof(*context));

    if (port_allocate(task_self(), &context->replyPort) != KERN_SUCCESS) {
        free(context);
        return 0;
    }

    context->contextPort = getPSPort(hostName, portName,
                                     context->replyPort, 15000,
                                     NX_INTERCEPTOR_PKGID);
    if (context->contextPort == PORT_NULL) {
        /* The reference frees the record here without deallocating replyPort. */
        free(context);
        return 0;
    }

    context->notifyPort = PORT_NULL;
    return context;
}

InterceptorClientContext *InterceptorCreateContext(void)
{
    return InterceptorCreateRemoteContext(PORT_NULL, PORT_NULL);
}

void InterceptorDestroyContext(InterceptorClientContext *context)
{
    if (!context)
        return;

    port_deallocate(task_self(), context->replyPort);
    port_deallocate(task_self(), context->contextPort);
    if (context->notifyPort != PORT_NULL)
        port_deallocate(task_self(), context->notifyPort);
    bzero((char *)context, sizeof(*context));
    free(context);
}
