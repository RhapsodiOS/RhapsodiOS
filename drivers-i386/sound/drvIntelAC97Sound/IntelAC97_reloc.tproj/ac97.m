/*
 * ac97.m
 *
 * AC97 (Audio Codec '97) codec implementation
 * Based on NetBSD's ac97.c and Intel's Audio Codec '97 specification
 *
 * Copyright (c) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

#import "ac97var.h"
#import "ac97reg.h"

/* Codec vendor/device identification table */
struct ac97_codec_id {
    unsigned int    id;
    const char      *vendor;
    const char      *codec;
};

static const struct ac97_codec_id ac97_codecs[] = {
    { 0x41445300, "Analog Devices",     "AD1819" },
    { 0x41445303, "Analog Devices",     "AD1819B" },
    { 0x41445340, "Analog Devices",     "AD1881" },
    { 0x41445348, "Analog Devices",     "AD1881A" },
    { 0x41445360, "Analog Devices",     "AD1885" },
    { 0x41445361, "Analog Devices",     "AD1886" },
    { 0x41445370, "Analog Devices",     "AD1980" },
    { 0x41445372, "Analog Devices",     "AD1981A" },
    { 0x41445374, "Analog Devices",     "AD1981B" },
    { 0x414B4D00, "Asahi Kasei",        "AK4540" },
    { 0x414B4D01, "Asahi Kasei",        "AK4542" },
    { 0x414B4D02, "Asahi Kasei",        "AK4543" },
    { 0x43525900, "Cirrus Logic",       "CS4297" },
    { 0x43525903, "Cirrus Logic",       "CS4297A" },
    { 0x43525913, "Cirrus Logic",       "CS4297A-EP" },
    { 0x43525920, "Cirrus Logic",       "CS4298" },
    { 0x43525928, "Cirrus Logic",       "CS4294" },
    { 0x43525930, "Cirrus Logic",       "CS4299" },
    { 0x43525948, "Cirrus Logic",       "CS4201" },
    { 0x43525958, "Cirrus Logic",       "CS4205" },
    { 0x45838308, "ESS Technology",     "ES1921" },
    { 0x49434511, "ICEnsemble",         "ICE1232" },
    { 0x4E534331, "National Semiconductor", "LM4549" },
    { 0x83847600, "SigmaTel",           "STAC9700" },
    { 0x83847604, "SigmaTel",           "STAC9701/9703/9704/9705" },
    { 0x83847605, "SigmaTel",           "STAC9704" },
    { 0x83847608, "SigmaTel",           "STAC9708" },
    { 0x83847609, "SigmaTel",           "STAC9721/9723" },
    { 0x83847644, "SigmaTel",           "STAC9744/9745" },
    { 0x83847652, "SigmaTel",           "STAC9752/9753" },
    { 0x574D4C00, "Wolfson",            "WM9701A" },
    { 0x574D4C03, "Wolfson",            "WM9703/9707" },
    { 0x574D4C04, "Wolfson",            "WM9704" },
    { 0x00000000, "Unknown",            "Unknown" }
};

/*
 * ac97_read - Read AC97 register
 */
unsigned short
ac97_read(struct ac97_codec_state *codec, unsigned char reg)
{
    if (!codec || !codec->read_reg)
        return 0xffff;

    return codec->read_reg(codec->host_priv, reg);
}

/*
 * ac97_write - Write AC97 register
 */
void
ac97_write(struct ac97_codec_state *codec, unsigned char reg, unsigned short val)
{
    if (!codec || !codec->write_reg)
        return;

    codec->write_reg(codec->host_priv, reg, val);

    /* Cache the value if not reading from hardware */
    if (!(codec->host_flags & AC97_HOST_DONT_READMIX))
        codec->regs[reg >> 1] = val;
}

/*
 * ac97_wait_ready - Wait for codec to become ready
 */
int
ac97_wait_ready(struct ac97_codec_state *codec, int timeout_ms)
{
    int i;
    unsigned short status;

    for (i = 0; i < timeout_ms; i++) {
        status = ac97_read(codec, AC97_REG_POWERDOWN);
        if ((status & (AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC)) ==
            (AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC))
            return 0;
        IODelay(1000);  /* Wait 1ms */
    }

    return -1;  /* Timeout */
}

/*
 * ac97_reset - Reset the AC97 codec
 */
void
ac97_reset(struct ac97_codec_state *codec)
{
    int i;

    if (!codec)
        return;

    /* Call host-specific reset if available */
    if (codec->reset)
        codec->reset(codec->host_priv);

    /* Write reset to codec */
    ac97_write(codec, AC97_REG_RESET, 0);
    IODelay(1000);  /* Wait for reset to complete */

    /* Wait for codec to be ready */
    if (ac97_wait_ready(codec, 100) < 0) {
        IOLog("AC97: codec reset timeout\n");
        return;
    }

    /* Initialize cached register values */
    for (i = 0; i < AC97_REG_CNT; i++) {
        if (!(codec->host_flags & AC97_HOST_DONT_READMIX))
            codec->regs[i] = ac97_read(codec, i * 2);
    }
}

/*
 * ac97_identify_codec - Identify the codec and read capabilities
 */
void
ac97_identify_codec(struct ac97_codec_state *codec)
{
    unsigned short vendor_id1, vendor_id2;
    unsigned int vendor_id;
    unsigned short ext_id, reset_val;
    int i;

    if (!codec)
        return;

    /* Read vendor IDs */
    vendor_id1 = ac97_read(codec, AC97_REG_VENDOR_ID1);
    vendor_id2 = ac97_read(codec, AC97_REG_VENDOR_ID2);
    vendor_id = (vendor_id1 << 16) | vendor_id2;
    codec->vendor_id = vendor_id;

    /* Find codec in table */
    for (i = 0; ac97_codecs[i].id != 0; i++) {
        if ((vendor_id & AC97_VENDOR_ID_MASK) == ac97_codecs[i].id) {
            strncpy(codec->vendor_name, ac97_codecs[i].vendor, 31);
            strncpy(codec->codec_name, ac97_codecs[i].codec, 31);
            break;
        }
    }

    /* If not found, use unknown */
    if (ac97_codecs[i].id == 0) {
        strncpy(codec->vendor_name, "Unknown", 31);
        sprintf(codec->codec_name, "Unknown (0x%08x)", vendor_id);
    }

    /* Read reset register for basic capabilities */
    reset_val = ac97_read(codec, AC97_REG_RESET);
    codec->caps.bass_treble = (reset_val & 0x0004) ? 1 : 0;
    codec->caps.simulated_stereo = (reset_val & 0x0008) ? 1 : 0;
    codec->caps.headphone_out = (reset_val & 0x0010) ? 1 : 0;
    codec->caps.loudness = (reset_val & 0x0020) ? 1 : 0;
    codec->caps.bit18_dac = (reset_val & 0x0040) ? 1 : 0;
    codec->caps.bit20_dac = (reset_val & 0x0080) ? 1 : 0;
    codec->caps.bit18_adc = (reset_val & 0x0100) ? 1 : 0;
    codec->caps.bit20_adc = (reset_val & 0x0200) ? 1 : 0;

    /* Read extended audio ID if available */
    ext_id = ac97_read(codec, AC97_REG_EXT_AUDIO_ID);
    if (ext_id != 0 && ext_id != 0xffff) {
        codec->caps.vra_supported = (ext_id & AC97_EXT_AUDIO_VRA) ? 1 : 0;
        codec->caps.dra_supported = (ext_id & AC97_EXT_AUDIO_DRA) ? 1 : 0;
        codec->caps.spdif_supported = (ext_id & AC97_EXT_AUDIO_SPDIF) ? 1 : 0;
        codec->caps.vrm_supported = (ext_id & AC97_EXT_AUDIO_VRM) ? 1 : 0;
        codec->caps.center_dac = (ext_id & AC97_EXT_AUDIO_CDAC) ? 1 : 0;
        codec->caps.surround_dac = (ext_id & AC97_EXT_AUDIO_SDAC) ? 1 : 0;
        codec->caps.lfe_dac = (ext_id & AC97_EXT_AUDIO_LDAC) ? 1 : 0;
    }

    IOLog("AC97: %s %s (0x%08x)\n", codec->vendor_name, codec->codec_name, vendor_id);
    IOLog("AC97: Capabilities: %s%s%s%s%s%s%s\n",
          codec->caps.vra_supported ? "VRA " : "",
          codec->caps.dra_supported ? "DRA " : "",
          codec->caps.spdif_supported ? "S/PDIF " : "",
          codec->caps.surround_dac ? "Surround " : "",
          codec->caps.center_dac ? "Center " : "",
          codec->caps.lfe_dac ? "LFE " : "",
          codec->caps.bit20_dac ? "20-bit-DAC " : "");
}

/*
 * ac97_attach - Initialize and attach AC97 codec
 */
int
ac97_attach(struct ac97_codec_state *codec, int codec_type)
{
    unsigned short ext_ctrl;

    if (!codec)
        return -1;

    /* Set magic number */
    codec->magic = AC97_MAGIC;

    /* Reset codec */
    ac97_reset(codec);

    /* Identify codec */
    ac97_identify_codec(codec);

    /* Enable variable rate audio if supported */
    if (codec->caps.vra_supported) {
        ext_ctrl = ac97_read(codec, AC97_REG_EXT_AUDIO_CTRL);
        ext_ctrl |= AC97_EXT_CTRL_VRA;
        ac97_write(codec, AC97_REG_EXT_AUDIO_CTRL, ext_ctrl);
        codec->vra_enabled = 1;
        IOLog("AC97: Variable Rate Audio enabled\n");
    }

    /* Set default sample rates */
    codec->dac_rate = AC97_RATE_DEFAULT;
    codec->adc_rate = AC97_RATE_DEFAULT;
    codec->mic_rate = AC97_RATE_DEFAULT;

    /* Initialize mixer to reasonable defaults */
    ac97_set_master_volume(codec, 0, 0, 0);  /* 0dB, unmuted */
    ac97_set_pcm_volume(codec, 0, 0, 0);     /* 0dB, unmuted */
    ac97_set_record_source(codec, AC97_RECMUX_LINE);
    ac97_set_record_gain(codec, 0, 0);

    /* Power up all sections */
    ac97_power_up(codec);

    return 0;
}

/*
 * ac97_set_master_volume - Set master volume
 * Volume: 0 (0dB) to 31 (-46.5dB), mute: 0=unmuted, 1=muted
 */
void
ac97_set_master_volume(struct ac97_codec_state *codec,
                      unsigned char left, unsigned char right, int mute)
{
    unsigned short val;

    if (!codec)
        return;

    /* Clamp values */
    if (left > 31) left = 31;
    if (right > 31) right = 31;

    /* Build register value */
    val = ((left & 0x1f) << AC97_LEFTVOL_SHIFT) |
          ((right & 0x1f) << AC97_RIGHTVOL_SHIFT);

    if (mute)
        val |= AC97_MUTE;

    ac97_write(codec, AC97_REG_MASTER_VOLUME, val);

    /* Update cache */
    codec->master_vol_l = left;
    codec->master_vol_r = right;
    codec->master_mute = mute ? 1 : 0;
}

/*
 * ac97_get_master_volume - Get master volume
 */
void
ac97_get_master_volume(struct ac97_codec_state *codec,
                      unsigned char *left, unsigned char *right, int *mute)
{
    unsigned short val;

    if (!codec)
        return;

    val = ac97_read(codec, AC97_REG_MASTER_VOLUME);

    if (left)
        *left = (val >> AC97_LEFTVOL_SHIFT) & 0x1f;
    if (right)
        *right = (val >> AC97_RIGHTVOL_SHIFT) & 0x1f;
    if (mute)
        *mute = (val & AC97_MUTE) ? 1 : 0;
}

/*
 * ac97_set_pcm_volume - Set PCM output volume
 */
void
ac97_set_pcm_volume(struct ac97_codec_state *codec,
                   unsigned char left, unsigned char right, int mute)
{
    unsigned short val;

    if (!codec)
        return;

    /* Clamp values */
    if (left > 31) left = 31;
    if (right > 31) right = 31;

    /* Build register value */
    val = ((left & 0x1f) << AC97_LEFTVOL_SHIFT) |
          ((right & 0x1f) << AC97_RIGHTVOL_SHIFT);

    if (mute)
        val |= AC97_MUTE;

    ac97_write(codec, AC97_REG_PCMOUT_VOLUME, val);

    /* Update cache */
    codec->pcm_vol_l = left;
    codec->pcm_vol_r = right;
    codec->pcm_mute = mute ? 1 : 0;
}

/*
 * ac97_get_pcm_volume - Get PCM output volume
 */
void
ac97_get_pcm_volume(struct ac97_codec_state *codec,
                   unsigned char *left, unsigned char *right, int *mute)
{
    unsigned short val;

    if (!codec)
        return;

    val = ac97_read(codec, AC97_REG_PCMOUT_VOLUME);

    if (left)
        *left = (val >> AC97_LEFTVOL_SHIFT) & 0x1f;
    if (right)
        *right = (val >> AC97_RIGHTVOL_SHIFT) & 0x1f;
    if (mute)
        *mute = (val & AC97_MUTE) ? 1 : 0;
}

/*
 * ac97_set_record_source - Set recording source
 */
void
ac97_set_record_source(struct ac97_codec_state *codec, unsigned int source)
{
    if (!codec)
        return;

    ac97_write(codec, AC97_REG_RECORD_SELECT, source);
}

/*
 * ac97_set_record_gain - Set recording gain
 */
void
ac97_set_record_gain(struct ac97_codec_state *codec,
                    unsigned char left, unsigned char right)
{
    unsigned short val;

    if (!codec)
        return;

    /* Clamp to 0-15 (0dB to +22.5dB) */
    if (left > 15) left = 15;
    if (right > 15) right = 15;

    val = (left << 8) | right;
    ac97_write(codec, AC97_REG_RECORD_GAIN, val);
}

/*
 * ac97_set_rate - Set sample rate for DAC/ADC/MIC
 */
int
ac97_set_rate(struct ac97_codec_state *codec, int which, unsigned int rate)
{
    unsigned short reg;

    if (!codec)
        return -1;

    /* Check if variable rate is supported */
    if (!codec->caps.vra_supported && rate != AC97_RATE_DEFAULT)
        return -1;

    /* Clamp rate */
    if (rate < AC97_RATE_MIN)
        rate = AC97_RATE_MIN;
    if (rate > AC97_RATE_MAX)
        rate = AC97_RATE_MAX;

    /* Select appropriate register */
    switch (which) {
    case AC97_RATE_DAC:
        reg = AC97_REG_PCM_FRONT_DAC_RATE;
        codec->dac_rate = rate;
        break;
    case AC97_RATE_ADC:
        reg = AC97_REG_PCM_LR_ADC_RATE;
        codec->adc_rate = rate;
        break;
    case AC97_RATE_MIC:
        if (!codec->caps.vrm_supported)
            return -1;
        reg = AC97_REG_PCM_MIC_ADC_RATE;
        codec->mic_rate = rate;
        break;
    default:
        return -1;
    }

    ac97_write(codec, reg, (unsigned short)rate);

    return 0;
}

/*
 * ac97_get_rate - Get current sample rate
 */
unsigned int
ac97_get_rate(struct ac97_codec_state *codec, int which)
{
    if (!codec)
        return 0;

    switch (which) {
    case AC97_RATE_DAC:
        return codec->dac_rate;
    case AC97_RATE_ADC:
        return codec->adc_rate;
    case AC97_RATE_MIC:
        return codec->mic_rate;
    default:
        return 0;
    }
}

/*
 * ac97_power_up - Power up all codec sections
 */
void
ac97_power_up(struct ac97_codec_state *codec)
{
    if (!codec)
        return;

    ac97_write(codec, AC97_REG_POWERDOWN, AC97_PWR_D0);
    IODelay(100);

    /* Wait for sections to power up */
    ac97_wait_ready(codec, 100);
}

/*
 * ac97_power_down - Power down codec
 */
void
ac97_power_down(struct ac97_codec_state *codec)
{
    if (!codec)
        return;

    ac97_write(codec, AC97_REG_POWERDOWN, AC97_PWR_D3);
}

/*
 * ac97_dump_registers - Dump all codec registers (for debugging)
 */
void
ac97_dump_registers(struct ac97_codec_state *codec)
{
    int i;
    unsigned short val;

    if (!codec)
        return;

    IOLog("AC97 Register Dump:\n");
    for (i = 0; i < 0x80; i += 2) {
        val = ac97_read(codec, i);
        if (val != 0 && val != 0xffff)
            IOLog("  [0x%02x] = 0x%04x\n", i, val);
    }
}
