/*
 * Later New World G3/G4 machines: UniNorth with KeyLargo, Pangea or
 * Intrepid Mac-IO.  Every table here comes from the validated firmware
 * descriptor; nothing is assumed from the Sawtooth layout.
 */

/* The PExpert interrupts.h must win over machdep/ppc/interrupts.h. */
#include <interrupts.h>
#include <machdep/ppc/dbdma.h>
#include <families/macrisc.h>

#ifdef MACRISC_HOST_TEST
/* chips/mpic.h needs kernel headers; these mirror its INT_TBL encoding. */
#define EDGE     (0x00000000)
#define LVL      (0x00400000)
#define ACT_LOW  (0x00000000)
#define ACT_HI   (0x00800000)
#define MASKED   (0x80000000)
#else
#include <chips/keylargo.h>
#include <chips/mpic.h>
#include <sys/systm.h>
#include <macrisc_dt.h>
#endif

/* Legacy logical identities for sources existing kernel code names. */
static int
macrisc_logical(int role)
{
    switch (role) {
    case kPERoleNMI:        return PMAC_DEV_NMI;
    case kPERoleSCCA:       return PMAC_DEV_SCC_A;
    case kPERoleSCCATx:     return PMAC_DMA_SCC_A_TX;
    case kPERoleSCCARx:     return PMAC_DMA_SCC_A_RX;
    case kPERoleSCCB:       return PMAC_DEV_SCC_B;
    case kPERoleSCCBTx:     return PMAC_DMA_SCC_B_TX;
    case kPERoleSCCBRx:     return PMAC_DMA_SCC_B_RX;
    case kPERoleMESH:       return PMAC_DEV_SCSI0;
    case kPERoleMESHDMA:    return PMAC_DMA_SCSI0;
    case kPERoleFloppy:     return PMAC_DEV_FLOPPY;
    case kPERoleFloppyDMA:  return PMAC_DMA_FLOPPY;
    case kPERoleATA0:       return PMAC_DEV_IDE0;
    case kPERoleATA0DMA:    return PMAC_DMA_IDE0;
    case kPERoleATA1:       return PMAC_DEV_IDE1;
    case kPERoleATA1DMA:    return PMAC_DMA_IDE1;
    case kPERoleAudio:      return PMAC_DEV_AUDIO;
    case kPERoleAudioOut:   return PMAC_DMA_AUDIO_OUT;
    case kPERoleAudioIn:    return PMAC_DMA_AUDIO_IN;
    }
    /* The VIA cascade, PMU GPIO and anything else use direct identities. */
    return -1;
}

/* Same priorities as the Sawtooth table: DMA 4, devices 2, VIA 1. */
static unsigned long
macrisc_priority(int role)
{
    switch (role) {
    case kPERoleVIA:
        return 1;
    case kPERoleNMI:
        return 7;
    case kPERoleSCCATx: case kPERoleSCCARx: case kPERoleSCCBTx:
    case kPERoleSCCBRx: case kPERoleMESHDMA: case kPERoleFloppyDMA:
    case kPERoleATA0DMA: case kPERoleATA1DMA: case kPERoleAudioOut:
    case kPERoleAudioIn:
        return 4;
    }
    return 2;
}

/* OpenPIC sense cells, as Darwin's AppleMPIC and Linux decode them. */
static unsigned long
macrisc_sense(unsigned int sense)
{
    switch (sense) {
    case 0:
        return EDGE | ACT_HI;
    case 2:
        return LVL | ACT_HI;
    case 3:
        return EDGE | ACT_LOW;
    }
    return LVL | ACT_LOW;
}

int
PEMacRISCBuildMPIC(const PEMacRISCPlatform *platform,
    struct powermac_interrupt *interrupts, unsigned long *mapping)
{
    unsigned int source;
    int role;

    if (interrupts == 0 || mapping == 0 ||
        PEMacRISCValidate(platform) != kPEPlatformValid)
        return 0;
    for (source = 0; source < platform->mpicSources; source++) {
        role = platform->sourceRole[source];
        interrupts[source].i_handler = 0;
        interrupts[source].i_level = 0;
        interrupts[source].i_arg = 0;
        interrupts[source].i_device = macrisc_logical(role);
        mapping[source * 2] = MASKED |
            macrisc_sense(platform->sourceSense[source]) |
            (macrisc_priority(role) << 16) | source;
        mapping[source * 2 + 1] = 1;        /* CPU 0 only */
    }
    return 1;
}

int
PEMacRISCBuildDBDMA(const PEDBDMAChannels *source,
    struct powermac_dbdma_channels *destination)
{
    if (source == 0 || destination == 0)
        return 0;
    destination->dbdma_channel_curio = source->curio;
    destination->dbdma_channel_mesh = source->mesh;
    destination->dbdma_channel_floppy = source->floppy;
    destination->dbdma_channel_ethernet_tx = source->ethernetTx;
    destination->dbdma_channel_ethernet_rx = source->ethernetRx;
    destination->dbdma_channel_scc_xmit_a = source->sccATx;
    destination->dbdma_channel_scc_recv_a = source->sccARx;
    destination->dbdma_channel_scc_xmit_b = source->sccBTx;
    destination->dbdma_channel_scc_recv_b = source->sccBRx;
    destination->dbdma_channel_audio_out = source->audioOut;
    destination->dbdma_channel_audio_in = source->audioIn;
    destination->dbdma_channel_ide0 = source->ata0;
    destination->dbdma_channel_ide1 = source->ata1;
    return 1;
}

#ifndef MACRISC_HOST_TEST

extern vm_offset_t PEMapSegment(vm_offset_t address, vm_size_t length);

static powermac_dbdma_channels_t macrisc_dbdma_channels;

powermac_init_t macrisc_init = {
	configure_macrisc,		// configure_machine
	mpic_interrupt_initialize,	// machine_initialize_interrupts
	NO_ENTRY,			// machine_initialize_network
	macrisc_initialize_bats,	// machine_initialize_processors
	rtc_init,			// machine_initialize_rtclock
	&macrisc_dbdma_channels,	// struct for dbdma channels
};

static struct powermac_interrupt macrisc_interrupts[PE_MACRISC_MAX_SOURCES];
static u_long macrisc_int_mapping_tbl[PE_MACRISC_MAX_SOURCES * 2];

/* The KeyLargo-family VIA, cascaded into one MPIC source. */
static struct powermac_interrupt
    macrisc_via1_interrupts[PE_MACRISC_MAX_CASCADE] = {
	{ 0,	0,	0,	-1},			/* Cascade */
	{ 0,	0,	0,	PMAC_DEV_HZTICK},
	{ 0,	0,	0,	PMAC_DEV_VIA1},
	{ 0,	0,	0,	PMAC_DEV_VIA2},         /* VIA Data */
	{ 0,	0,	0,	PMAC_DEV_VIA3},         /* VIA CLK Source */
	{ 0,	0,	0,	PMAC_DEV_TIMER2},
	{ 0,	0,	0,	PMAC_DEV_TIMER1}
};

void configure_macrisc(void)
{
  const PEMacRISCPlatform *platform;
  PEMPICConfiguration configuration;
  kern_return_t result;

  platform = PEMacRISCGetPlatform();
  if (platform == 0 ||
      !PEMacRISCBuildMPIC(platform, macrisc_interrupts,
			  macrisc_int_mapping_tbl) ||
      !PEMacRISCBuildDBDMA(&platform->dbdma, &macrisc_dbdma_channels))
    panic("MacRISC: no validated platform descriptor\n");

  macrisc_interrupts[platform->cascadeSource].i_handler = mpic_via1_interrupt;

  mpic_interrupts = macrisc_interrupts;
  mpic_via1_interrupts = macrisc_via1_interrupts;
  mpic_int_mapping_tbl = macrisc_int_mapping_tbl;
  nmpic_interrupts = platform->mpicSources;
  nmpic_via_interrupts = platform->cascadeWidth;
  mpic_via_cascade = platform->cascadeSource;

  /* No Fat Man here, and only CPU 0 takes interrupts. */
  configuration.useFeatureControl = 0;
  configuration.disablePassThrough = 1;
  configuration.destinationMask = 1;
  configuration.sourceCount = platform->mpicSources;
  if (!PEMPICSetConfiguration(&configuration))
    panic("MacRISC: bad MPIC configuration\n");

  /* The VIA1 cascade child, in DriverKit's XOR form. */
  powermac_info.viaIRQ = (platform->mpicSources + 2) ^ 0x18;

  result = PEKeyLargoInitialize();
  if (result != KERN_SUCCESS)
    printf("KeyLargo audio services unavailable (0x%x)\n", result);
}

/*
 * initialize_bats() has already mapped RAM, the 0xf0000000 segment (which
 * holds the flash NVRAM) and the boot framebuffer; only the Mac-IO segment
 * is left, and the MPIC sits inside it.
 */
void macrisc_initialize_bats(boot_args *args)
{
#ifndef UseOpenFirmware
  const PEMacRISCPlatform *platform;

  platform = PEMacRISCGetPlatform();
  if (platform == 0 ||
      PEMapSegment(platform->macIO.base & 0xf0000000, 0x10000000) == 0)
    panic("MacRISC: cannot map the Mac-IO segment\n");
#endif
}

#endif /* !MACRISC_HOST_TEST */
