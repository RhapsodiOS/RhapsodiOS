/* The C types behind zone.defs; the installed System headers lack mach_debug.
 * They match mach_debug/zone_info.h (80-byte name, 9-word info). */
#ifndef ZONE_TYPES_H
#define ZONE_TYPES_H
#include <mach/mach.h>

typedef struct { char zn_name[80]; } zone_name_t;
typedef zone_name_t *zone_name_array_t;
typedef struct {
	integer_t zi_count;
	integer_t zi_other[8];
} zone_info_t;
typedef zone_info_t *zone_info_array_t;

/* mach_msg stubs the generated code calls; the installed headers lack them */
mach_port_t mig_get_reply_port();
void mig_dealloc_reply_port();
#endif
