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

int _InterceptorScreenCount(port_t contextPort, port_t replyPort);
int _InterceptorHideCursor(port_t contextPort, port_t replyPort);
int _InterceptorShowCursor(port_t contextPort, port_t replyPort);
int _InterceptorShowCursorAsync(port_t contextPort);
int InterceptorScreenCount(InterceptorClientContext *context);
int InterceptorHideCursor(InterceptorClientContext *context);
int InterceptorShowCursor(InterceptorClientContext *context);
int _InterceptorCompositeBits(port_t contextPort, port_t replyPort,
                              int windowNumber, int x, int y,
                              int operation, const void *bits,
                              int width, int height, int depth,
                              int bytesPerRow, int colorSpaceCode);
int InterceptorCompositeBits(InterceptorClientContext *context,
                             int windowNumber, int x, int y, int operation,
                             const void *bits, int width, int height,
                             int depth, int bytesPerRow, int colorSpaceCode);

int _InterceptorMapFrameBuffer(port_t contextPort, port_t replyPort,
                               int screenNumber, port_t taskPort,
                               unsigned int *address);
int _InterceptorUnmapFrameBuffer(port_t contextPort, port_t replyPort,
                                 int screenNumber, port_t taskPort,
                                 unsigned int address);
int InterceptorMapFrameBuffer(InterceptorClientContext *context,
                              int screenNumber, void **address);
int InterceptorUnmapFrameBuffer(InterceptorClientContext *context,
                                int screenNumber, void *address);
int _InterceptorFrameBufferInfo(port_t contextPort, port_t replyPort,
                                int screenNumber, char *driver,
                                int *deviceSlot, int *deviceUnit,
                                int *pixelsWide, int *pixelsHigh,
                                int *bitsPerPixel, int *bytesPerRow,
                                int *colorSpaceCode, char *pixelEncoding,
                                int *reserved);
int InterceptorFrameBufferInfo(InterceptorClientContext *context,
                               int screenNumber, char *driver,
                               int *deviceSlot, int *deviceUnit,
                               int *pixelsWide, int *pixelsHigh,
                               int *bitsPerPixel, int *bytesPerRow,
                               int *colorSpaceCode, char *pixelEncoding,
                               int *reserved);
int _InterceptorGetDeviceAccessTokens(port_t contextPort, port_t replyPort,
                                      int screenNumber, port_t *masterPort,
                                      int *ioObjectNumber, port_t *devicePort);
int InterceptorGetDeviceAccessTokens(InterceptorClientContext *context,
                                     int screenNumber, port_t *masterPort,
                                     int *ioObjectNumber, port_t *devicePort);

int _InterceptorGetBM34ToBM35Table(port_t contextPort, port_t replyPort,
                                   void **table);
int _InterceptorGetBM35ToBM34Table(port_t contextPort, port_t replyPort,
                                   void **table);
int _InterceptorGetBM256ToBM38Table(port_t contextPort, port_t replyPort,
                                    void **table);
int _InterceptorGetBM38ToBM256Table(port_t contextPort, port_t replyPort,
                                    void **table);
int InterceptorGetBM34ToBM35Table(InterceptorClientContext *context,
                                  void **table);
int InterceptorGetBM35ToBM34Table(InterceptorClientContext *context,
                                  void **table);
int InterceptorGetBM256ToBM38Table(InterceptorClientContext *context,
                                   void **table);
int InterceptorGetBM38ToBM256Table(InterceptorClientContext *context,
                                   void **table);

#endif
