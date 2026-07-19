/*
 * Configuration keys for AMD SCSI driver.
 */

/*
 * These are accessible by SCSIInspector.
 */
#define SYNC_ENABLE		"Synchronous"
#define FAST_ENABLE		"Fast SCSI"
#define CMD_QUEUE_ENABLE	"Cmd Queueing"

/*
 * These are only accessible by Configure's Expert mode.
 */
#define EXTENDED_TIMING		"Extended Timing"
#define SCSI_CLOCK_RATE		"SCSI Clock Rate"	/* in MHz */