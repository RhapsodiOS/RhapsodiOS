/*
 * FloppyCnt.h - Floppy Controller class interface
 *
 * Floppy disk controller class for PC floppy controller hardware
 */

#ifdef DRIVER_PRIVATE

#ifndef _BSD_DEV_I386_FLOPPYCNT_H_
#define _BSD_DEV_I386_FLOPPYCNT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODevice.h>
#import <driverkit/machine/directDevice.h>
#import <driverkit/generalFuncs.h>
#import <sys/types.h>

/*
 * Floppy controller register addresses
 */
typedef struct {
	unsigned short statusRegA;      // SRA (read-only)
	unsigned short statusRegB;      // SRB (read-only)
	unsigned short digitalOutput;   // DOR (read/write)
	unsigned short mainStatus;      // MSR (read-only)
	unsigned short dataRate;        // DSR (write-only) / (read as MSR)
	unsigned short dataFifo;        // Data register
	unsigned short digitalInput;    // DIR (read-only)
	unsigned short configControl;   // CCR (write-only)
} fdcRegsAddrs_t;

/*
 * Floppy controller information
 */
@interface FloppyController : IODirectDevice
{
@private
	id                  _fcCmdLock;         // offset 0x128: Lock for controller access (NXConditionLock)
	id                  _requestQueue;      // offset 0x130: Request queue head pointer
	port_t              _fdcInterruptPort;  // offset 0x134: Interrupt port
	unsigned char       _flags;             // offset 0x138: Controller flags
	unsigned char       _field_139;         // offset 0x139: Unknown field
	unsigned char       _dorRegister;       // offset 0x13a: Digital Output Register (DOR) cache
	unsigned char       _field_13b;         // offset 0x13b: Unknown field
	void               *_dmaBuffer;         // offset 0x13c: DMA transfer buffer
	unsigned int        _field_140;         // offset 0x140: Unknown field (initialized to 0xffff)

	// Request queue (offset 300 / 0x12c)
	id                  _queueHead;         // Circular queue for I/O requests

	// Drive information
	id                  _drives[4];         // Array of IOFloppyDrive objects
	unsigned int        _numDrives;         // Number of attached drives

	fdcRegsAddrs_t      _fdcRegsAddrs;      // Register addresses
	port_t              _fdcDevicePort;     // Device port
	unsigned int        _interruptTimeOut;  // Interrupt timeout value
	unsigned char       _controllerNum;     // Controller number

	// DMA support
	unsigned char       _dmaChannel;        // DMA channel (typically 2)
	vm_address_t        _dmaBufferPhys;     // Physical address of DMA buffer
	unsigned int        _dmaBufferSize;     // Size of DMA buffer

	// Controller state
	BOOL                _motorOn[4];        // Motor on state for each drive
	unsigned char       _lastCommand;       // Last command sent
	unsigned char       _lastStatus;        // Last status received
}

/*
 * Exported methods
 */
+ (BOOL)probe:(IODeviceDescription *)devDesc;

/*
 * Initialization and cleanup
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/*
 * Controller operations
 */
- (IOReturn)_fcCmdXfr:(void *)cmdParams;

@end

/*
 * Thread category for FloppyController.
 * Contains methods that run in the controller thread context.
 */
@interface FloppyController(Thread)

/*
 * Execute a command transfer in the controller thread.
 * This is called by the controller thread to actually execute commands.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)fcCmdXfrExecute:(void *)cmdParams;

@end

/*
 * Forward declarations for external functions
 */
extern void *_alloc_cnvmem(unsigned int size, unsigned int align);
extern IOReturn _IOForkThread(void (*threadFunc)(void *), void *arg);
extern void _IOExitThread(void);

/*
 * Floppy drive detection functions
 */
extern int _numFloppyDrives(void);
extern int _floppyDriveType(int driveNum);

#endif // _BSD_DEV_I386_FLOPPYCNT_H_

#endif // DRIVER_PRIVATE

/* End of FloppyCnt.h */
