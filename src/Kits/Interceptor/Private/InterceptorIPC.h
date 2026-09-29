#ifndef _INTERCEPTOR_IPC_PRIVATE_H_
#define _INTERCEPTOR_IPC_PRIVATE_H_

#include "../Interceptor_types.h"

InterceptorClientContext *InterceptorCreateContext(void);
InterceptorClientContext *InterceptorCreateRemoteContext(port_t bootstrapPort,
                                                          port_t rendezvousPort);
void InterceptorDestroyContext(InterceptorClientContext *context);

int _InterceptorAddRect(port_t contextPort, port_t replyPort,
                        InterceptedRectangle *rectangle);
int _InterceptorRemoveRect(port_t contextPort, port_t replyPort,
                           unsigned int uniqueID);
int _InterceptorSetNotifyPort(port_t contextPort, port_t replyPort,
                              port_t notifyPort, port_t exceptionPort);

#endif
