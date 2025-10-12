/*
 * pdservd.h
 * Port Server Daemon - Header
 */

#ifndef _PDSERVD_H_
#define _PDSERVD_H_

#include <mach/mach.h>
#include <objc/objc.h>

// Device Master interface
typedef struct {
    id deviceMaster;
    int deviceCount;
    void *privateData;
} IODeviceMaster;

// Function prototypes
IODeviceMaster *IODeviceMaster_new(void);
void IODeviceMaster_free(IODeviceMaster *master);
int IODeviceMaster_lookupByDeviceName(IODeviceMaster *master, const char *deviceName, id *device);
int IODeviceMaster_lookupByObjectNumber(IODeviceMaster *master, int objectNumber, id *device);
int IODeviceMaster_getDeviceNames(IODeviceMaster *master, char ***names, int *count);
int IODeviceMaster_getDeviceValuesForParameter(IODeviceMaster *master, const char *parameter,
                                                int objectNumber, void **values, int *count);
int IODeviceMaster_setDeviceValuesForParameter(IODeviceMaster *master, const char *parameter,
                                                int objectNumber, void *values, int count);
int IODeviceMaster_getParameter(IODeviceMaster *master, const char *parameter,
                                int objectNumber, void *value);
int IODeviceMaster_setParameter(IODeviceMaster *master, const char *parameter,
                                int objectNumber, void *value);
int IODeviceMaster_createPort(IODeviceMaster *master, int objectNumber, mach_port_t *port);

// String buffer and conversion utilities
int NXStringBuffer_getString(void *buffer, char **string);
int NXStringBuffer_putString(void *buffer, const char *string);

// Object number utilities
int objc_getObjectNumber(id object);
id objc_getObjectFromNumber(int number);

// I/O control
int ioctl_thread_init(void);
int ioctl_thread_routine(void *arg);
int ioctl_msg_rpc(mach_port_t port, void *request, void *reply);
int ioctl_msg_send(mach_port_t port, void *msg);
int ioctl_openlog(const char *ident, int logopt, int facility);
int ioctl_syslog(int priority, const char *format, ...);
int ioctl_closelog(void);

// Error conversion
const char *strerror_iokit(int error);
const char *strerror_mach(kern_return_t error);

// Callback utilities
typedef void (*ioctl_callback_t)(void *context, int result);
int call_ioctl_callback(ioctl_callback_t callback, void *context, int result);

// Device lock utilities
int IODevice_lock(id device);
int IODevice_unlock(id device);
int IODevice_tryLock(id device);

// Port utilities
int port_mkmod_msg_rpc(mach_port_t port, void *request, void *reply);

// Localhost utilities
int localhost_ping(void);

#endif /* _PDSERVD_H_ */
