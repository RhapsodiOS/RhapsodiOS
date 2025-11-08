#ifndef _ISA_SERIAL_PORT_KERNEL_SUPPORT_H_
#define _ISA_SERIAL_PORT_KERNEL_SUPPORT_H_

/*
 * Legacy kernel support declarations for the ISA serial port driver.
 * These prototypes mirror the interfaces that were historically provided
 * to DriverKit loadable kernel servers on Rhapsody.  Modern kernel headers
 * (e.g. <kern/thread_call.h>) expose different signatures, so we keep these
 * declarations locally to avoid sprinkling ad-hoc extern statements in the
 * implementation file while we sort out a more complete API migration.
 */

#ifdef __cplusplus
extern "C" {
#endif

void *thread_call_allocate(void (*func)(void *), void *param);
void thread_call_enter(void *call);
void thread_call_enter_delayed(void *call, unsigned long long deadline);
void thread_call_cancel(void *call);
void thread_call_free(void *call);
unsigned long long deadline_from_interval(unsigned int interval_low,
                                          unsigned int interval_high);

void IOEnterCriticalSection(void);
void IOExitCriticalSection(void);

#ifdef __cplusplus
}
#endif

#endif /* _ISA_SERIAL_PORT_KERNEL_SUPPORT_H_ */


