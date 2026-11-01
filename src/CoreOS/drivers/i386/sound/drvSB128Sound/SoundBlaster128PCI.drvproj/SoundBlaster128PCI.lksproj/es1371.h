#ifndef PCI_VENDOR_ID_ENSONIQ
#define PCI_VENDOR_ID_ENSONIQ        0x1274    
#endif

#ifndef PCI_VENDOR_ID_ECTIVA
#define PCI_VENDOR_ID_ECTIVA         0x1102
#endif

#ifndef PCI_DEVICE_ID_ENSONIQ_ES1371
#define PCI_DEVICE_ID_ENSONIQ_ES1371 0x1371
#endif

#ifndef PCI_DEVICE_ID_ENSONIQ_CT5880
#define PCI_DEVICE_ID_ENSONIQ_CT5880 0x5880
#endif

#ifndef PCI_DEVICE_ID_ECTIVA_EV1938
#define PCI_DEVICE_ID_ECTIVA_EV1938 0x8938
#endif

/* ES1371 chip ID */
/* This is a little confusing because all ES1371 compatible chips have the
   same DEVICE_ID, the only thing differentiating them is the REV_ID field.
   This is only significant if you want to enable features on the later parts.
   Yes, I know it's stupid and why didn't we use the sub IDs?
*/
#define ES1371REV_ES1373_A  0x04
#define ES1371REV_ES1373_B  0x06
#define ES1371REV_CT5880_A  0x07
#define CT5880REV_CT5880_C  0x02
#define ES1371REV_ES1371_B  0x09
#define EV1938REV_EV1938_A  0x00
#define ES1371REV_ES1373_8  0x08

#define ES1371_MAGIC  ((PCI_VENDOR_ID_ENSONIQ<<16)|PCI_DEVICE_ID_ENSONIQ_ES1371)

#define ES1371_EXTENT             0x40
#define JOY_EXTENT                8

#define ES1371_REG_CONTROL        0x00
#define ES1371_REG_STATUS         0x04 /* on the 5880 it is control/status */
#define ES1371_REG_UART_DATA      0x08
#define ES1371_REG_UART_STATUS    0x09
#define ES1371_REG_UART_CONTROL   0x09
#define ES1371_REG_UART_TEST      0x0a
#define ES1371_REG_MEMPAGE        0x0c
#define ES1371_REG_SRCONV         0x10
#define ES1371_REG_CODEC          0x14
#define ES1371_REG_LEGACY         0x18
#define ES1371_REG_SERIAL_CONTROL 0x20
#define ES1371_REG_DAC1_SCOUNT    0x24
#define ES1371_REG_DAC2_SCOUNT    0x28
#define ES1371_REG_ADC_SCOUNT     0x2c

#define ES1371_REG_DAC1_FRAMEADR  0xc30
#define ES1371_REG_DAC1_FRAMECNT  0xc34
#define ES1371_REG_DAC2_FRAMEADR  0xc38
#define ES1371_REG_DAC2_FRAMECNT  0xc3c
#define ES1371_REG_ADC_FRAMEADR   0xd30
#define ES1371_REG_ADC_FRAMECNT   0xd34

#define ES1371_FMT_U8_MONO     0
#define ES1371_FMT_U8_STEREO   1
#define ES1371_FMT_S16_MONO    2
#define ES1371_FMT_S16_STEREO  3
#define ES1371_FMT_STEREO      1
#define ES1371_FMT_S16         2
#define ES1371_FMT_MASK        3

#define CTRL_SPDIFEN_B  0x04000000
#define CTRL_JOY_SHIFT  24
#define CTRL_JOY_MASK   3
#define CTRL_JOY_200    0x00000000  /* joystick base address */
#define CTRL_JOY_208    0x01000000
#define CTRL_JOY_210    0x02000000
#define CTRL_JOY_218    0x03000000
#define CTRL_GPIO_IN0   0x00100000  /* general purpose inputs/outputs */
#define CTRL_GPIO_IN1   0x00200000
#define CTRL_GPIO_IN2   0x00400000
#define CTRL_GPIO_IN3   0x00800000
#define CTRL_GPIO_OUT0  0x00010000
#define CTRL_GPIO_OUT1  0x00020000
#define CTRL_GPIO_OUT2  0x00040000
#define CTRL_GPIO_OUT3  0x00080000
#define CTRL_MSFMTSEL   0x00008000  /* MPEG serial data fmt: 0 = Sony, 1 = I2S */
#define CTRL_SYNCRES    0x00004000  /* AC97 warm reset */
#define CTRL_ADCSTOP    0x00002000  /* stop ADC transfers */
#define CTRL_PWR_INTRM  0x00001000  /* 1 = power level ints enabled */
#define CTRL_M_CB       0x00000800  /* recording source: 0 = ADC, 1 = MPEG */
#define CTRL_CCB_INTRM  0x00000400  /* 1 = CCB "voice" ints enabled */
#define CTRL_PDLEV0     0x00000000  /* power down level */
#define CTRL_PDLEV1     0x00000100
#define CTRL_PDLEV2     0x00000200
#define CTRL_PDLEV3     0x00000300
#define CTRL_BREQ       0x00000080  /* 1 = test mode (internal mem test) */
#define CTRL_DAC1_EN    0x00000040  /* enable DAC1 */
#define CTRL_DAC2_EN    0x00000020  /* enable DAC2 */
#define CTRL_ADC_EN     0x00000010  /* enable ADC */
#define CTRL_UART_EN    0x00000008  /* enable MIDI uart */
#define CTRL_JYSTK_EN   0x00000004  /* enable Joystick port */
#define CTRL_XTALCLKDIS 0x00000002  /* 1 = disable crystal clock input */
#define CTRL_PCICLKDIS  0x00000001  /* 1 = disable PCI clock distribution */


#define STAT_INTR       0x80000000  /* wired or of all interrupt bits */
#define CSTAT_5880_AC97_RST 0x20000000 /* CT5880 Reset bit */
#define STAT_EN_SPDIF   0x00040000  /* enable S/PDIF circuitry */
#define STAT_TS_SPDIF   0x00020000  /* test S/PDIF circuitry */
#define STAT_TESTMODE   0x00010000  /* test ASIC */
#define STAT_SYNC_ERR   0x00000100  /* 1 = codec sync error */
#define STAT_VC         0x000000c0  /* CCB int source, 0=DAC1, 1=DAC2, 2=ADC, 3=undef */
#define STAT_SH_VC      6
#define STAT_MPWR       0x00000020  /* power level interrupt */
#define STAT_MCCB       0x00000010  /* CCB int pending */
#define STAT_UART       0x00000008  /* UART int pending */
#define STAT_DAC1       0x00000004  /* DAC1 int pending */
#define STAT_DAC2       0x00000002  /* DAC2 int pending */
#define STAT_ADC        0x00000001  /* ADC int pending */

#define USTAT_RXINT     0x80        /* UART rx int pending */
#define USTAT_TXINT     0x04        /* UART tx int pending */
#define USTAT_TXRDY     0x02        /* UART tx ready */
#define USTAT_RXRDY     0x01        /* UART rx ready */

#define UCTRL_RXINTEN   0x80        /* 1 = enable RX ints */
#define UCTRL_TXINTEN   0x60        /* TX int enable field mask */
#define UCTRL_ENA_TXINT 0x20        /* enable TX int */
#define UCTRL_CNTRL     0x03        /* control field */
#define UCTRL_CNTRL_SWR 0x03        /* software reset command */

/* sample rate converter */
#define SRC_OKSTATE        1

#define SRC_RAMADDR_MASK   0xfe000000
#define SRC_RAMADDR_SHIFT  25
#define SRC_DAC1FREEZE     (1UL << 21)
#define SRC_DAC2FREEZE      (1UL << 20)
#define SRC_ADCFREEZE      (1UL << 19)


#define SRC_WE             0x01000000  /* read/write control for SRC RAM */
#define SRC_BUSY           0x00800000  /* SRC busy */
#define SRC_DIS            0x00400000  /* 1 = disable SRC */
#define SRC_DDAC1          0x00200000  /* 1 = disable accum update for DAC1 */
#define SRC_DDAC2          0x00100000  /* 1 = disable accum update for DAC2 */
#define SRC_DADC           0x00080000  /* 1 = disable accum update for ADC2 */
#define SRC_CTLMASK        0x00780000
#define SRC_RAMDATA_MASK   0x0000ffff
#define SRC_RAMDATA_SHIFT  0

#define SRCREG_ADC      0x78
#define SRCREG_DAC1     0x70
#define SRCREG_DAC2     0x74
#define SRCREG_VOL_ADC  0x6c
#define SRCREG_VOL_DAC1 0x7c
#define SRCREG_VOL_DAC2 0x7e

#define SRCREG_TRUNC_N     0x00
#define SRCREG_INT_REGS    0x01
#define SRCREG_ACCUM_FRAC  0x02
#define SRCREG_VFREQ_FRAC  0x03

#define CODEC_PIRD        0x00800000  /* 0 = write AC97 register */
#define CODEC_PIADD_MASK  0x007f0000
#define CODEC_PIADD_SHIFT 16
#define CODEC_PIDAT_MASK  0x0000ffff
#define CODEC_PIDAT_SHIFT 0

#define CODEC_RDY         0x80000000  /* AC97 read data valid */
#define CODEC_WIP         0x40000000  /* AC97 write in progress */
#define CODEC_PORD        0x00800000  /* 0 = write AC97 register */
#define CODEC_POADD_MASK  0x007f0000
#define CODEC_POADD_SHIFT 16
#define CODEC_PODAT_MASK  0x0000ffff
#define CODEC_PODAT_SHIFT 0


#define LEGACY_JFAST      0x80000000  /* fast joystick timing */
#define LEGACY_FIRQ       0x01000000  /* force IRQ */

#define SCTRL_DACTEST     0x00400000  /* 1 = DAC test, test vector generation purposes */
#define SCTRL_P2ENDINC    0x00380000  /*  */
#define SCTRL_SH_P2ENDINC 19
#define SCTRL_P2STINC     0x00070000  /*  */
#define SCTRL_SH_P2STINC  16
#define SCTRL_R1LOOPSEL   0x00008000  /* 0 = loop mode */
#define SCTRL_P2LOOPSEL   0x00004000  /* 0 = loop mode */
#define SCTRL_P1LOOPSEL   0x00002000  /* 0 = loop mode */
#define SCTRL_P2PAUSE     0x00001000  /* 1 = pause mode */
#define SCTRL_P1PAUSE     0x00000800  /* 1 = pause mode */
#define SCTRL_R1INTEN     0x00000400  /* enable interrupt */
#define SCTRL_P2INTEN     0x00000200  /* enable interrupt */
#define SCTRL_P1INTEN     0x00000100  /* enable interrupt */
#define SCTRL_P1SCTRLD    0x00000080  /* reload sample count register for DAC1 */
#define SCTRL_P2DACSEN    0x00000040  /* 1 = DAC2 play back last sample when disabled */
#define SCTRL_R1SEB       0x00000020  /* 1 = 16bit */
#define SCTRL_R1SMB       0x00000010  /* 1 = stereo */
#define SCTRL_R1FMT       0x00000030  /* format mask */
#define SCTRL_SH_R1FMT    4
#define SCTRL_P2SEB       0x00000008  /* 1 = 16bit */
#define SCTRL_P2SMB       0x00000004  /* 1 = stereo */
#define SCTRL_P2FMT       0x0000000c  /* format mask */
#define SCTRL_SH_P2FMT    2
#define SCTRL_P1SEB       0x00000002  /* 1 = 16bit */
#define SCTRL_P1SMB       0x00000001  /* 1 = stereo */
#define SCTRL_P1FMT       0x00000003  /* format mask */
#define SCTRL_SH_P1FMT    0

/* codec constants */

#define CODEC_ID_DEDICATEDMIC    0x001
#define CODEC_ID_MODEMCODEC      0x002
#define CODEC_ID_BASSTREBLE      0x004
#define CODEC_ID_SIMULATEDSTEREO 0x008
#define CODEC_ID_HEADPHONEOUT    0x010
#define CODEC_ID_LOUDNESS        0x020
#define CODEC_ID_18BITDAC        0x040
#define CODEC_ID_20BITDAC        0x080
#define CODEC_ID_18BITADC        0x100
#define CODEC_ID_20BITADC        0x200

#define CODEC_ID_SESHIFT    10
#define CODEC_ID_SEMASK     0x1f

/* misc stuff */
#define POLL_COUNT   0x1000
#define FMODE_DAC         4           /* slight misuse of mode_t */

/* MIDI buffer sizes */

#define MIDIINBUF  256
#define MIDIOUTBUF 256

#define FMODE_MIDI_SHIFT 3
#define FMODE_MIDI_READ  (FMODE_READ << FMODE_MIDI_SHIFT)
#define FMODE_MIDI_WRITE (FMODE_WRITE << FMODE_MIDI_SHIFT)


#define u16	unsigned short
#define u8	unsigned char

struct es1371_state {
        /* magic */
        unsigned int magic;

        /* hardware resources */
        unsigned long io; /* long for SPARC */
        unsigned int irq;

        /* PCI ID's */
        u16 vendor;
        u16 device;
        u8 rev; /* the chip revision */

        /* mixer registers; there is no HW readback */
        struct {
                unsigned short codec_id;
                unsigned int modcnt;
        } mix;

        /* wave stuff */
        unsigned ctrl;
        unsigned sctrl;
        unsigned dac1rate, dac2rate, adcrate;

	/* locking stuff */
	simple_lock_t	lock;

        struct dmabuf {
                void 		*rawbuf;
                unsigned 	buforder;
                unsigned 	numfrag;
                unsigned 	fragshift;
                unsigned 	hwptr;
		unsigned	swptr;
                unsigned 	total_bytes;
                int 		count;
                unsigned 	error; /* over/underrun */
                /* redundant, but makes calculations easier */
                unsigned 	fragsize;
                unsigned 	dmasize;
                unsigned 	fragsamples;
		/* NeXT */
		unsigned int	transferCount; 
		BOOL		intr;
		BOOL		wait;
		BOOL		stop_dac;
        } dma_dac1, dma_dac2, dma_adc;
};


extern void set_adc_rate(struct es1371_state *s, unsigned rate);
extern void set_dac1_rate(struct es1371_state *s, unsigned rate);
extern void set_dac2_rate(struct es1371_state *s, unsigned rate);

extern void start_adc(struct es1371_state *s);
extern void start_dac1(struct es1371_state *s);
extern void start_dac2(struct es1371_state *s, BOOL noLock);
extern int clear_interrupt(struct es1371_state *s);
extern void stop_adc(struct es1371_state *s);
extern void stop_dac1(struct es1371_state *s);
extern void stop_dac2(struct es1371_state *s);

extern void prepare_dmabuf_adc(struct es1371_state *s, unsigned int addr, unsigned int dmasize);
extern void prepare_dmabuf_dac1(struct es1371_state *s, unsigned int addr, unsigned int dmasize);
extern void prepare_dmabuf_dac2(struct es1371_state *s, unsigned int addr, unsigned int dmasize);

extern int prog_dmabuf_adc(struct es1371_state *s, unsigned int transferCount);
extern int prog_dmabuf_dac1(struct es1371_state *s, unsigned int transferCount);
extern int prog_dmabuf_dac2(struct es1371_state *s, unsigned int transferCount);

extern void set_adc_mode(struct es1371_state *s, BOOL bit16, BOOL stereo);
extern void set_dac1_mode(struct es1371_state *s, BOOL bit16, BOOL stereo);
extern void set_dac2_mode(struct es1371_state *s, BOOL bit16, BOOL stereo);

extern void set_attenuation(struct es1371_state *s, unsigned int reg, int left, int right, int mute);
extern void get_attenuation(struct es1371_state *s, unsigned int reg, int *left, int *right, int *mute);

extern void resetHardware(struct es1371_state *s);
