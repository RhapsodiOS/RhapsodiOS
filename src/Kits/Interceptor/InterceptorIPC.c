#include <mach/mach.h>
#include <stdlib.h>
#include <strings.h>
#include "Private/InterceptorIPC.h"

extern port_t getPSPort(port_t bootstrapPort, port_t rendezvousPort,
                        port_t replyPort, int timeout, int packageID);

InterceptorClientContext *InterceptorCreateRemoteContext(port_t bootstrapPort,
                                                          port_t rendezvousPort)
{
    InterceptorClientContext *context;

    context = (InterceptorClientContext *)malloc(sizeof(*context));
    bzero((char *)context, sizeof(*context));

    if (port_allocate(task_self(), &context->replyPort) != KERN_SUCCESS) {
        free(context);
        return 0;
    }

    context->contextPort = getPSPort(bootstrapPort, rendezvousPort,
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
