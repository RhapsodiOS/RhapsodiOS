/*---------------------------------------------------------------------------*\
*	                                                                      *
*	Copyright (c) 2001-2020 by Jens Heise                                 *
*	                                                                      *
*	created: 11.01.2001	              	  modified: 20.05.2020        *
*									      *
*			Version: 1.2					      *
*-----------------------------------------------------------------------------*
*	                                                                      *
*	This program is free software; you can redistribute it and/or         *
*	modify it under the terms of the GNU General Public License as        *
*	published by the Free Software Foundation; either version 2 of        *
*	the License, or (at your option) any later version.                   *
*	                                                                      *
*	This program is distributed in the hope that it will be useful,       *
*	but WITHOUT ANY WARRANTY; without even the implied warranty of        *
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
*	General Public License for more details.                              *
*	                                                                      *
*	You should have received a copy of the GNU General Public License     *
*	along with this program; if not, write to the Free Software           *
*	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.             *
*	                                                                      *
\*---------------------------------------------------------------------------*/
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/interruptMsg.h>
#import <kernserv/prototypes.h>
#import <kernserv/sched_prim.h>
#import <kernserv/i386/spl.h>

#import "ac97.h"
#import "es1371.h"
#import "SoundBlaster128PCIDriver.h"
#import "pciconf.h"


static const char codecDeviceName[] = "SoundBlaster128PCI";
static const char codecDeviceKind[] = "Audio";

static struct es1371_state	*s=NULL;
static IOInterruptHandler	oldHandler=NULL;

@implementation SoundBlaster128PCIDriver

/*--------------------------------- ()probe: --------------------------------*\
*									      *
*	Probe and initialize new instance                                     *
*									      *
\*---------------------------------------------------------------------------*/

+ (BOOL) probe:deviceDescription
{
    SoundBlaster128PCIDriver	*dev;

    dev = [self alloc];
    if (dev == nil)
        return NO;

    return ([dev initFromDeviceDescription:deviceDescription] != nil);
} /* ()probe: */



/*------------------------ initFromDeviceDescription: -----------------------*\
*									      *
*	Initialize new instance by reading deviceDescription and              *
*	allocation control structures.                                        *
*									      *
\*---------------------------------------------------------------------------*/

- initFromDeviceDescription:deviceDescription
{
    IOReturn		irtn;
    IOPCIConfigSpace	configSpace;
    IORange 		portRange;
    unsigned long	*basePtr = 0;
    unsigned long	regLong;
    int                 i;

				/* PCIInfo der gefundenen Karte auslesen.    */
    bzero(&configSpace, sizeof(IOPCIConfigSpace));
    if (irtn = [IODirectDevice getPCIConfigSpace:&configSpace
		    withDeviceDescription:deviceDescription])
    {
	IOLog("%s: Can\'t get configSpace (%s); ABORTING\n",
		    DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
	return nil;
    } /* if */

				/* Allocate control structure for driver and
				   initialize PCI specific values.           */
    s = IOMalloc(sizeof(*s));
    s->magic = ES1371_MAGIC;
    s->vendor = configSpace.VendorID;
    s->device = configSpace.DeviceID;
    s->rev = configSpace.RevisionID;
				/* Allocate lock.                            */
    s->lock = simple_lock_alloc();
    simple_lock_init(s->lock);

				/* Test if card is supported by driver.      */
    if ((s->vendor != PCI_VENDOR_ID_ENSONIQ &&
	s->vendor != PCI_VENDOR_ID_ECTIVA) ||
	(s->vendor == PCI_VENDOR_ID_ENSONIQ &&
	(s->device != PCI_DEVICE_ID_ENSONIQ_ES1371 &&
    	s->device != PCI_DEVICE_ID_ENSONIQ_CT5880)) ||
	(s->vendor == PCI_VENDOR_ID_ECTIVA &&
	s->device != PCI_DEVICE_ID_ECTIVA_EV1938))
    {
	IOLog("%s: Unsupported Soundcard.\n", DRV_TITLE);
	return nil;
    } /* if */

				/* Read iobase for the card.                 */
    basePtr = configSpace.BaseAddress;
    for(i=0; i<PCI_NUM_BASE_ADDRESS; i++)
    {
	if (basePtr[i] & PCI_BASE_IO_BIT)
	{
	    s->io = PCI_BASE_IO(basePtr[i]);
	    break;
	} /* if */
    } /* for */

				/* Check if interrupt is available.          */
    if (!s->io || !(s->irq = configSpace.InterruptLine))
    {
	IOLog("%s: No I/O Port or IRQ found.\n", DRV_TITLE);
	return nil;
    } /* if */

    IOLog("%s: found chip, VID 0x%04x DID 0x%04x rev. 0x%02x\n",
    		DRV_TITLE, s->vendor, s->device, s->rev);
    IOLog("%s: I/O Port at 0x%lx   IRQ: %d\n", DRV_TITLE, s->io, s->irq);

				/* Register interrupt and portrange in
				   deviceDescription and kernel.             */
    irtn = [deviceDescription setInterruptList:&(s->irq) num:1];
    if(irtn)
    {
	IOLog("%s: Can\'t set interruptList to IRQ %d (%s)\n", DRV_TITLE,
		s->irq, [IODirectDevice stringFromReturn:irtn]);
	return nil;
    } /* if */

    portRange.start = s->io;
    portRange.size = ES1371_EXTENT;
    irtn = [deviceDescription setPortRangeList:&portRange num:1];
    if(irtn)
    {
	IOLog("%s: Can\'t set portRangeList to port 0x%x (%s)\n", DRV_TITLE,
		portRange.start, [IODirectDevice stringFromReturn:irtn]);
	return nil;
    } /* if */
				/* Enable busmastering.                      */
    if((irtn = [IODirectDevice getPCIConfigData:&regLong atRegister:0x04
    			withDeviceDescription:deviceDescription]) ||
    	(irtn = [IODirectDevice
			setPCIConfigData:(regLong|PCI_COMMAND_MASTER_ENABLE)
			atRegister:0x04
			withDeviceDescription:deviceDescription]))
    {
	IOLog("%s: Can\'t enable busmastering (%s)\n", DRV_TITLE,
		[IODirectDevice stringFromReturn:irtn]);
	return nil;
    } /* if */

				/* Initialize IOAudio.                       */
    if (![super initFromDeviceDescription:deviceDescription])
    {
	IOLog("%s: failed on [super init].\n", DRV_TITLE);
	return nil;
    } /* if */

    return self;
} /* initFromDeviceDescription: */



/*----------------------------------- free ----------------------------------*\
*									      *
*	Free driver.                                                          *
*									      *
\*---------------------------------------------------------------------------*/

- free
{
    [self releaseInterrupt:0];
    [self releasePortRange:0];

				/* Release lock and control structure.       */
    simple_lock_free(s->lock);
    IOFree(s, sizeof(*s));

    return [super free];
} /* free */



/*---------------------------------- reset ----------------------------------*\
*									      *
*	Reset hardware and set device name.                                   *
*									      *
\*---------------------------------------------------------------------------*/

- (BOOL)reset
{
    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    resetHardware(s);

    return YES;
} /* reset */



/*-------- ()createDMABufferFor:length:read:needsLowMemory:limitSize: -------*\
*									      *
*	Replaces original function since this is a PCI-card which does        *
*	busmaster DMA, but NeXT always assume normal EISA-DMA.                *
*									      *
\*---------------------------------------------------------------------------*/

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress length:(unsigned int)numBytes read:(BOOL)isRead needsLowMemory:(BOOL)lowerMem limitSize:(BOOL)limitSize
{
    IOReturn		irtn;
    unsigned int	physAddr;

				/* Get physical address of buffer to set it
				   to the card.                              */
    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), *physicalAddress, &physAddr);
    if (irtn)
    {
	IOLog("%s: Fatal, couldn\'t map memory.\n", DRV_TITLE);
	return NULL;
    } /* if */

				/* Prepare correct dmabuf in control
				   structure.                                */
    if (isRead)
	prepare_dmabuf_adc(s, physAddr, numBytes);
    else prepare_dmabuf_dac2(s, physAddr, numBytes);

    return (IOEISADMABuffer)physAddr;
} /* ()createDMABufferFor:length:read:needsLowMemory:limitSize: */



/*-------- ()startDMAForChannel:read:buffer:bufferSizeForInterrupts: --------*\
*									      *
*	Start the DMA for the specified channel.                              *
*									      *
\*---------------------------------------------------------------------------*/

- (BOOL)startDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead buffer:(IOEISADMABuffer)buffer bufferSizeForInterrupts:(unsigned int)bufferSize
{
    unsigned int	left;
    unsigned int	right;
    unsigned int	mute;
    unsigned int	encoding;
    unsigned int	mode=[self channelCount];

				/* Reenable PCM output.                      */
    get_attenuation(s, AC97_PCMOUT_VOL, &left, &right, &mute);
    set_attenuation(s, AC97_PCMOUT_VOL, left, right, NO);

				/* Get encoding and sample rate to program
				   dma-buffer and chips correct.             */
    encoding = [self dataEncoding];
    if (encoding == NX_SoundStreamDataEncoding_Linear16)
	set_dac2_mode(s, YES, mode==2);
    else if (encoding == NX_SoundStreamDataEncoding_Linear8)
	set_dac2_mode(s, NO, mode==2);
    [self updateSampleRate];

    (void)[self enableAllInterrupts];
    if (!isRead)
    {
				/* Program chip and initialize statitic
				   variables.                                */
	prog_dmabuf_dac2(s, bufferSize);
	simple_lock(s->lock);
	s->dma_dac2.intr = NO;
	s->dma_dac2.stop_dac = NO;
	s->dma_dac2.wait = YES;
	simple_unlock(s->lock);

				/* Start the dac for playback.               */
	start_dac2(s, NO);
    } /* if */
    else return NO;

    return YES;
} /* ()startDMAForChannel:read:buffer:bufferSizeForInterrupts: */



/*--------------------------------- doStop: ---------------------------------*\
*									      *
*	Stops the DMA on the next interrupt, after stop_dac is set.           *
*									      *
\*---------------------------------------------------------------------------*/

- (void)doStop:(BOOL)isRead
{
				/* Stop the dac.                             */
    if (isRead)
	stop_adc(s);
    else stop_dac2(s);

    (void)[self disableAllInterrupts];

				/* Turn off PCM volume.                      */
    if (!isRead)
    {
	unsigned int	left;
	unsigned int	right;
	unsigned int	mute;

	get_attenuation(s, AC97_PCMOUT_VOL, &left, &right, &mute);
	set_attenuation(s, AC97_PCMOUT_VOL, left, right, YES);
    } /* if */
    return;
} /* doStop: */



/*------------------------ ()stopDMAForChannel:read: ------------------------*\
*									      *
*	Stops the DAC.                                                        *
*									      *
\*---------------------------------------------------------------------------*/

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
				/* Set flag to stop DAC on next irq.         */
    simple_lock(s->lock);
    if (!isRead)
	s->dma_dac2.stop_dac = YES;
    else s->dma_adc.stop_dac = YES;
    simple_unlock(s->lock);

				/* Stop DAC now.                             */
//     [self doStop:isRead];

    return;
} /* ()stopDMAForChannel:read: */



/*---------------------------- clearInterrupts() ----------------------------*\
*									      *
*	Clear the interrupt flags (I think is only used by NeXTTime so        *
*	couldn't test).                                                       *
*									      *
\*---------------------------------------------------------------------------*/

static void clearInterrupts(void)
{
    clear_interrupt(s);
    return;
} /* clearInterrupts() */



/*--------------------------- ()interruptClearFunc --------------------------*\
*									      *
*	Return the clear function.                                            *
*									      *
\*---------------------------------------------------------------------------*/

- (IOAudioInterruptClearFunc)interruptClearFunc
{
    return clearInterrupts;
} /* ()interruptClearFunc */



/*------------------ ()interruptOccurredForInput:forOutput: -----------------*\
*									      *
*	Second part of interrupt handling after passing the NeXT-part of      *
*	handling.                                                             *
*									      *
\*---------------------------------------------------------------------------*/

- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput
{
    BOOL	stop_dac=NO;
    BOOL	dac_wait=NO;

    *serviceOutput = NO;
    *serviceInput = NO;
    simple_lock(s->lock);
				/* Interrupt in playback?                    */
    if (s->dma_dac2.intr)
    {
				/* Get and reset statistic variables used for
				   controlling.                              */
	dac_wait = s->dma_dac2.wait;
	stop_dac = s->dma_dac2.stop_dac;
	s->dma_dac2.intr = NO;
				/* Force NeXT to fill buffer after interrupt
				   when no more data is pending.             */
	if (!stop_dac && (*serviceOutput = !s->dma_dac2.wait))
	{
				/* Reset number of transferred bytes to get
				   next interrupt correct.                   */
	    s->dma_dac2.count = 0;
	    s->dma_dac2.wait = YES;
	} /* if */
    } /* if */
    simple_unlock(s->lock);

				/* Restart dac if it should continue playback
				   else stop dac when buffer is empty.       */
    if (!stop_dac || dac_wait)
	start_dac2(s, NO);
    else if (stop_dac)
	[self doStop:NO];

    return;
} /* ()interruptOccurredForInput:forOutput: */



/*-------------------------------- clearInt() -------------------------------*\
*									      *
*	Clear the interrupt state on the card before calling original         *
*	NeXT-handler.                                                         *
*									      *
\*---------------------------------------------------------------------------*/

static void clearInt(void *identity, void *state,
                         unsigned int arg)
{
    if (clear_interrupt(s))
    {
				/* Call original NeXT-handler when
				   tranferCount is reached                   */
	if (s->dma_dac2.count >= s->dma_dac2.transferCount)
	    (*oldHandler)(identity, state, arg);
	else start_dac2(s, YES);
    } /* if */

				/* provide support for shared IRQ's          */
    IOEnableInterrupt(identity);
    return;
} /* clearInt() */



/*---------------- ()getHandler:level:argument:forInterrupt: ----------------*\
*									      *
*	Replace the NeXT-handler by our own or it will not work (got no       *
*	interrupts when not replacing the handler) but remember old           *
*	handler for forwarding after our own handling is done.                *
*									      *
\*---------------------------------------------------------------------------*/

- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)ipl argument:(unsigned int *)arg forInterrupt:(unsigned int)localInterrupt
{
				/* Get original handler for calling later    */
    [super getHandler:&oldHandler level:ipl argument:arg
    					forInterrupt:localInterrupt];
				/* Set our own handler.                      */
    *handler = clearInt;

    return YES;
} /* ()getHandler:level:argument:forInterrupt: */



/*---------------------------- ()timeoutOccurred ----------------------------*\
*									      *
*	Called when interrupts time out.                                      *
*									      *
\*---------------------------------------------------------------------------*/

- (void)timeoutOccurred
{
    IOLog("%s: Timeout waiting for interrupt\n", DRV_TITLE);
    return;
} /* ()timeoutOccurred */



/*---------------------------- ()updateSampleRate ---------------------------*\
*									      *
*	Update the sample rate of all chips on card.                          *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateSampleRate
{
    unsigned int	rate=[self sampleRate];

    set_adc_rate(s, rate);
    set_dac1_rate(s, rate);
    set_dac2_rate(s, rate);

    return;
} /* ()updateSampleRate */



/*--------------------- ()acceptsContinuousSamplingRates --------------------*\
*									      *
*	We can use every rate between 4000 and 48000 Hz.                      *
*									      *
\*---------------------------------------------------------------------------*/

- (BOOL)acceptsContinuousSamplingRates
{
    return YES;
} /* ()acceptsContinuousSamplingRates */



/*----------------------- ()getSamplingRatesLow:high: -----------------------*\
*									      *
*	We can use every rate between 4000 and 48000 Hz.                      *
*									      *
\*---------------------------------------------------------------------------*/

- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate
{
    *lowRate = 4000;
    *highRate = 48000;

    return;
} /* ()getSamplingRatesLow:high: */



/*------------------------ ()getSamplingRates:count: ------------------------*\
*									      *
*	Provide a set of standard sample rates.                               *
*									      *
\*---------------------------------------------------------------------------*/

- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates
{
    rates[0] = 4000;
    rates[1] = 8000;
    rates[2] = 11025;
    rates[3] = 22050;
    rates[4] = 44100;
    *numRates = 5;

    return;
} /* ()getSamplingRates:count: */



/*------------------------ ()getDataEncodings:count: ------------------------*\
*									      *
*	Return the available encodings.                                       *
*									      *
\*---------------------------------------------------------------------------*/

- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)numEncodings
{
    encodings[0] = NX_SoundStreamDataEncoding_Linear8;
    encodings[1] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = 2;

    return;
} /* ()getDataEncodings:count: */



/*--------------------------- ()channelCountLimit ---------------------------*\
*									      *
*	We support stereo playback.                                           *
*									      *
\*---------------------------------------------------------------------------*/

- (unsigned int)channelCountLimit
{
    return 2;
} /* ()channelCountLimit */



/*------------------------- updateOutputAttenuation -------------------------*\
*									      *
*	Update the attenuation. We always change the master volume and        *
*	don't touch the specific setting for the other sources.               *
*									      *
\*---------------------------------------------------------------------------*/

- updateOutputAttenuation
{
    unsigned int	left=([self outputAttenuationLeft]*(-10))/13;
    unsigned int	right=([self outputAttenuationRight]*(-10))/13;
    unsigned int	mute=[self isOutputMuted];

    set_attenuation(s, AC97_MASTER_VOL_STEREO, left, right, mute);

    return self;
} /* updateOutputAttenuation */



/*---------------------------- ()updateOutputMute ---------------------------*\
*									      *
*	Update mute status.                                                   *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateOutputMute
{
    [self updateOutputAttenuation];
    return;
} /* ()updateOutputMute */



/*---------------------- ()updateOutputAttenuationLeft ----------------------*\
*									      *
*	Updates the left attenuation.                                         *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateOutputAttenuationLeft
{
    [self updateOutputAttenuation];
    return;
} /* ()updateOutputAttenuationLeft */



/*---------------------- ()updateOutputAttenuationRight ---------------------*\
*									      *
*	Updates the right attenuation.                                        *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateOutputAttenuationRight
{
    [self updateOutputAttenuation];
    return;
} /* ()updateOutputAttenuationRight */



/*----------------------------- updateInputGain -----------------------------*\
*									      *
*	Update the input gain. We just mute all inputs as recording is        *
*	not supported.                                                        *
*									      *
\*---------------------------------------------------------------------------*/

- updateInputGain
{
    set_attenuation(s, AC97_MIC_VOL, 0, 0, 1);
    set_attenuation(s, AC97_LINEIN_VOL, 0, 0, 1);
    set_attenuation(s, AC97_CD_VOL, 0, 0, 1);
    set_attenuation(s, AC97_AUX_VOL, 0, 0, 1);
    set_attenuation(s, AC97_RECORD_GAIN, 0, 0, 1);
    set_attenuation(s, AC97_RECORD_GAIN_MIC, 0, 0, 1);
    return self;
} /* updateInputGain */



/*-------------------------- ()updateInputGainLeft --------------------------*\
*									      *
*	Updates the left input gain.                                          *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateInputGainLeft
{
    [self updateInputGain];
    return;
} /* ()updateInputGainLeft */



/*-------------------------- ()updateInputGainRight -------------------------*\
*									      *
*	Updates the right input gain.                                         *
*									      *
\*---------------------------------------------------------------------------*/

- (void)updateInputGainRight
{
    [self updateInputGain];
    return;
} /* ()updateInputGainRight */



@end
