/*
 * AMD53C974 bringup flags.
 */
#import "AMD_ddm.h"

#define AUTO_SENSE_ENABLE		1

/*
 * Section 6.7.1 of the spec says the DMA command register "must be written 
 * twice to ensure proper operation". As of 31 Oct 94, this has not been
 * necessary with the 79C974. Maybe it will be with the 53C974...
 */
#define WRITE_DMA_COMMAND_TWICE		0

/*
 * Force disconnects for single target testing.
 */
#define FORCE_DISCONNECTS		0

/*
 * Force really long timeout...
 */
#if	DDM_CONSOLE_LOG
#define LONG_TIMEOUT	1
#define OUR_TIMEOUT	200
#endif	DDM_CONSOLE_LOG

/*
 * Test interrupt latency elsewhere in the system.
 */
#define INTR_LATENCY_TEST		0

/*
 * Force a STAT_QUEUE_FULL condition.
 */
#define TEST_QUEUE_FULL			0
