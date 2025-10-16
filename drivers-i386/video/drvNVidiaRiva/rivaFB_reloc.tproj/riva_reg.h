/*
 * NVIDIA Riva Hardware Register Definitions
 * Supports Riva 128, TNT, and TNT2 chipsets
 */

#ifndef _RIVA_REG_H_
#define _RIVA_REG_H_

/* NVIDIA PCI Device IDs */
#define PCI_DEVICE_ID_NVIDIA_RIVA128       0x0018    /* NV3 */
#define PCI_DEVICE_ID_NVIDIA_TNT           0x0020    /* NV4 */
#define PCI_DEVICE_ID_NVIDIA_TNT2          0x0028    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_TNT2_ULTRA    0x0029    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_VANTA         0x002A    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_TNT2_M64      0x002C    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_ALADDIN       0x002D    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_VANTA_LT      0x002E    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_RIVA_TNT2_PRO 0x002F    /* NV5 */
#define PCI_DEVICE_ID_NVIDIA_RIVA_TNT2     0x00A0    /* NV5 */

#define PCI_VENDOR_ID_NVIDIA               0x10DE

/* Basic PCI Configuration Space */
#define PCI_VENDOR_ID           0x00
#define PCI_DEVICE_ID           0x02
#define PCI_COMMAND             0x04
#define PCI_REVISION_ID         0x08
#define PCI_BASE_ADDRESS_0      0x10
#define PCI_BASE_ADDRESS_1      0x14

/* PCI Command register bits */
#define PCI_COMMAND_IO          0x0001  /* Enable IO access */
#define PCI_COMMAND_MEMORY      0x0002  /* Enable memory access */
#define PCI_COMMAND_MASTER      0x0004  /* Enable bus mastering */

/* Riva register base offsets */
#define NV_PMC_OFFSET           0x000000
#define NV_PBUS_OFFSET          0x001000
#define NV_PFIFO_OFFSET         0x002000
#define NV_PRAMIN_OFFSET        0x710000
#define NV_PEXTDEV_OFFSET       0x101000
#define NV_PRAMDAC_OFFSET       0x680000
#define NV_PFB_OFFSET           0x100000
#define NV_PGRAPH_OFFSET        0x400000
#define NV_PCRTC_OFFSET         0x600000

/* PMC - Master Control */
#define NV_PMC_BOOT_0                       0x00000000
#define NV_PMC_ENABLE                       0x00000200
#define NV_PMC_INTR_0                       0x00000100
#define NV_PMC_INTR_EN_0                    0x00000140

/* PEXTDEV - External Device Control */
#define NV_PEXTDEV_BOOT_0                   0x00000000

/* PFB - Framebuffer Control */
#define NV_PFB_CFG0                         0x00000200
#define NV_PFB_CFG1                         0x00000204
#define NV_PFB_CSTATUS                      0x0000020C
#define NV_PFB_BOOT_0                       0x00000000
#define NV_PFB_CONFIG_0                     0x00000200
#define NV_PFB_CONFIG_1                     0x00000204

/* PRAMDAC - RAMDAC Control */
#define NV_PRAMDAC_GENERAL_CONTROL          0x00000600
#define NV_PRAMDAC_VPLL_COEFF               0x00000508
#define NV_PRAMDAC_MPLL_COEFF               0x00000504
#define NV_PRAMDAC_PLL_COEFF_SELECT         0x0000050C
#define NV_PRAMDAC_TEST_CONTROL             0x00000608
#define NV_PRAMDAC_FP_HVALID_START          0x00000820
#define NV_PRAMDAC_FP_HVALID_END            0x00000824
#define NV_PRAMDAC_FP_VVALID_START          0x00000828
#define NV_PRAMDAC_FP_VVALID_END            0x0000082C

/* PCRTC - CRTC Control */
#define NV_PCRTC_INTR_0                     0x00000100
#define NV_PCRTC_INTR_EN_0                  0x00000140
#define NV_PCRTC_START                      0x00000800
#define NV_PCRTC_CONFIG                     0x00000804

/* VGA CRTC Registers (accessed via I/O) */
#define VGA_CRTC_INDEX          0x3D4
#define VGA_CRTC_DATA           0x3D5

/* VGA Sequencer Registers */
#define VGA_SEQ_INDEX           0x3C4
#define VGA_SEQ_DATA            0x3C5

/* VGA Graphics Controller Registers */
#define VGA_GFX_INDEX           0x3CE
#define VGA_GFX_DATA            0x3CF

/* VGA Attribute Controller Registers */
#define VGA_ATTR_INDEX          0x3C0
#define VGA_ATTR_DATA_W         0x3C0
#define VGA_ATTR_DATA_R         0x3C1

/* Miscellaneous Output Register */
#define VGA_MISC_WRITE          0x3C2
#define VGA_MISC_READ           0x3CC

/* Input Status Registers */
#define VGA_IS1_RC              0x3DA   /* Color */
#define VGA_IS1_RM              0x3BA   /* Mono */

/* DAC Registers */
#define VGA_PEL_IW              0x3C8   /* Palette Write Index */
#define VGA_PEL_IR              0x3C7   /* Palette Read Index */
#define VGA_PEL_D               0x3C9   /* Palette Data */
#define VGA_PEL_MSK             0x3C6   /* Pixel Mask */

/* Extended CRTC Indices */
#define NV_CIO_CRE_RPC0_INDEX   0x18
#define NV_CIO_CRE_RPC1_INDEX   0x19
#define NV_CIO_CRE_FF_INDEX     0x1B
#define NV_CIO_SR_LOCK_INDEX    0x1F
#define NV_CIO_CRE_PIXEL_INDEX  0x28
#define NV_CIO_CRE_HEB__INDEX   0x2D
#define NV_CIO_CRE_ENH_INDEX    0x2F
#define NV_CIO_CRE_FFLWM__INDEX 0x30
#define NV_CIO_CRE_SCRATCH0     0x38
#define NV_CIO_CRE_SCRATCH1     0x39
#define NV_CIO_CRE_SCRATCH2     0x3A
#define NV_CIO_CRE_SCRATCH3     0x3B

/* Extended Sequencer Indices */
#define NV_VIO_SR_LOCK_INDEX    0x06
#define NV_VIO_SR_UNLOCK_VALUE  0x57

/* Chip Detection Masks */
#define NV_BOOT0_CHIP_ID_MASK   0xFF000000
#define NV_BOOT0_CHIP_REV_MASK  0x00FF0000
#define NV_BOOT0_VENDOR_ID_MASK 0x0000FFFF

/* Chipset Identification */
#define NV3_CHIP_ID             0x03000000
#define NV4_CHIP_ID             0x04000000
#define NV5_CHIP_ID             0x05000000

#define NV_ARCH_03              0x03
#define NV_ARCH_04              0x04
#define NV_ARCH_05              0x05

/* Memory size calculation */
#define NV_PFB_BOOT_0_RAM_AMOUNT                        0x00000003
#define NV_PFB_BOOT_0_RAM_AMOUNT_4MB                    0x00000000
#define NV_PFB_BOOT_0_RAM_AMOUNT_8MB                    0x00000001
#define NV_PFB_BOOT_0_RAM_AMOUNT_16MB                   0x00000002
#define NV_PFB_BOOT_0_RAM_AMOUNT_32MB                   0x00000003

/* Pixel formats */
#define NV_PRMCIO_ARX_MODE_TEXT                         0x00
#define NV_PRAMDAC_GENERAL_CONTROL_VGA_STATE            0x00000001
#define NV_PRAMDAC_GENERAL_CONTROL_565_MODE             0x00000002
#define NV_PRAMDAC_GENERAL_CONTROL_PIXMIX_ON            0x00000010
#define NV_PRAMDAC_GENERAL_CONTROL_PIPE_LONG            0x00000004

#endif /* _RIVA_REG_H_ */
