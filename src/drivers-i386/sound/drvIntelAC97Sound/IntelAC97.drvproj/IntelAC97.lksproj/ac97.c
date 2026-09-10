/*
 * ac97.c
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

#include <stdio.h>

#include "ac97var.h"
#include "ac97reg.h"

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

static const unsigned char ac97_output_regs[3] = {
    AC97_REG_MASTER_VOLUME,
    AC97_REG_AUX_OUT_VOLUME,
    AC97_REG_SURR_MASTER
};

static void
ac97_delay(struct ac97_codec_state *codec, unsigned int us)
{
    if (codec != NULL && codec->delay_us != NULL)
        codec->delay_us(codec->delay_context, us);
}

static void
ac97_copy_name(char *dst, const char *src)
{
    int i;

    for (i = 0; i < 31 && src[i] != '\0'; i++)
        dst[i] = src[i];
    dst[i] = '\0';
}

/*
 * ac97_read - Read AC97 register
 */
unsigned short
ac97_read(struct ac97_codec_state *codec, unsigned char reg)
{
    if (codec == NULL || codec->read_reg == NULL)
        return 0xffff;

    return codec->read_reg(codec->host_priv, reg);
}

/*
 * ac97_write - Write AC97 register
 */
void
ac97_write(struct ac97_codec_state *codec, unsigned char reg, unsigned short val)
{
    if (codec == NULL || codec->write_reg == NULL)
        return;

    codec->write_reg(codec->host_priv, reg, val);

    /* Cache the value if not reading from hardware */
    if ((codec->host_flags & AC97_HOST_DONT_READMIX) == 0)
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
        ac97_delay(codec, 1000);  /* Wait 1ms */
    }

    return -1;  /* Timeout */
}

/*
 * ac97_reset - Reset the AC97 codec
 */
int
ac97_reset(struct ac97_codec_state *codec)
{
    int i;

    if (codec == NULL)
        return -1;

    /* Call host-specific reset if available */
    if (codec->reset != NULL)
        codec->reset(codec->host_priv);

    /* Write reset to codec */
    ac97_write(codec, AC97_REG_RESET, 0);
    ac97_delay(codec, 1000);  /* Wait for reset to complete */

    /* Wait for codec to be ready */
    if (ac97_wait_ready(codec, 100) < 0)
        return -1;

    /* Initialize cached register values */
    for (i = 0; i < AC97_REG_CNT; i++) {
        if ((codec->host_flags & AC97_HOST_DONT_READMIX) == 0)
            codec->regs[i] = ac97_read(codec, (unsigned char)(i * 2));
    }

    return 0;
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

    if (codec == NULL)
        return;

    /* Read vendor IDs */
    vendor_id1 = ac97_read(codec, AC97_REG_VENDOR_ID1);
    vendor_id2 = ac97_read(codec, AC97_REG_VENDOR_ID2);
    vendor_id = (vendor_id1 << 16) | vendor_id2;
    codec->vendor_id = vendor_id;

    /* Find codec in table */
    for (i = 0; ac97_codecs[i].id != 0; i++) {
        if (vendor_id == ac97_codecs[i].id) {
            ac97_copy_name(codec->vendor_name, ac97_codecs[i].vendor);
            ac97_copy_name(codec->codec_name, ac97_codecs[i].codec);
            break;
        }
    }

    /* If not found, use unknown */
    if (ac97_codecs[i].id == 0) {
        ac97_copy_name(codec->vendor_name, "Unknown");
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
}

/*
 * ac97_attach - Initialize and attach AC97 codec
 */
int
ac97_attach(struct ac97_codec_state *codec, int codec_type)
{
    unsigned short ext_ctrl;
    int i;

    if (codec == NULL)
        return -1;

    (void)codec_type;

    /* Set magic number */
    codec->magic = AC97_MAGIC;

    /* Reset codec */
    if (ac97_reset(codec) < 0)
        return -1;

    /* Identify codec */
    ac97_identify_codec(codec);

    /* Enable variable rate audio if supported */
    if (codec->caps.vra_supported) {
        ext_ctrl = ac97_read(codec, AC97_REG_EXT_AUDIO_CTRL);
        ext_ctrl |= AC97_EXT_CTRL_VRA;
        ac97_write(codec, AC97_REG_EXT_AUDIO_CTRL, ext_ctrl);
        ext_ctrl = ac97_read(codec, AC97_REG_EXT_AUDIO_CTRL);
        codec->vra_enabled = (ext_ctrl & AC97_EXT_CTRL_VRA) ? 1 : 0;
    }

    /* Set default sample rates */
    codec->dac_rate = AC97_RATE_DEFAULT;
    codec->adc_rate = AC97_RATE_DEFAULT;
    codec->mic_rate = AC97_RATE_DEFAULT;

    /* Initialize mixer to muted defaults */
    ac97_set_master_volume(codec, 0, 0, 1);
    ac97_set_pcm_volume(codec, 0, 0, 1);

    /* Measure output volume bit widths */
    for (i = 0; i < 3; i++) {
        unsigned short probe;

        probe = ac97_read(codec, ac97_output_regs[i]);
        codec->out_present[i] = (probe != 0xffff) ? 1 : 0;
        if (codec->out_present[i])
            codec->out_bits[i] = ac97_measure_volume_bits(codec,
                                                          ac97_output_regs[i]);
    }

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

    if (codec == NULL)
        return;

    /* Clamp values */
    if (left > 31)
        left = 31;
    if (right > 31)
        right = 31;

    /* Build register value */
    val = (unsigned short)(((left & 0x1f) << AC97_LEFTVOL_SHIFT) |
          ((right & 0x1f) << AC97_RIGHTVOL_SHIFT));

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

    if (codec == NULL)
        return;

    val = ac97_read(codec, AC97_REG_MASTER_VOLUME);

    if (left != NULL)
        *left = (unsigned char)((val >> AC97_LEFTVOL_SHIFT) & 0x1f);
    if (right != NULL)
        *right = (unsigned char)((val >> AC97_RIGHTVOL_SHIFT) & 0x1f);
    if (mute != NULL)
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

    if (codec == NULL)
        return;

    /* Clamp values */
    if (left > 31)
        left = 31;
    if (right > 31)
        right = 31;

    /* Build register value */
    val = (unsigned short)(((left & 0x1f) << AC97_LEFTVOL_SHIFT) |
          ((right & 0x1f) << AC97_RIGHTVOL_SHIFT));

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

    if (codec == NULL)
        return;

    val = ac97_read(codec, AC97_REG_PCMOUT_VOLUME);

    if (left != NULL)
        *left = (unsigned char)((val >> AC97_LEFTVOL_SHIFT) & 0x1f);
    if (right != NULL)
        *right = (unsigned char)((val >> AC97_RIGHTVOL_SHIFT) & 0x1f);
    if (mute != NULL)
        *mute = (val & AC97_MUTE) ? 1 : 0;
}

/*
 * ac97_set_record_source - Set recording source
 */
void
ac97_set_record_source(struct ac97_codec_state *codec, unsigned int source)
{
    if (codec == NULL)
        return;

    ac97_write(codec, AC97_REG_RECORD_SELECT, (unsigned short)source);
}

/*
 * ac97_set_record_gain - Set recording gain
 */
void
ac97_set_record_gain(struct ac97_codec_state *codec,
                    unsigned char left, unsigned char right)
{
    unsigned short val;

    if (codec == NULL)
        return;

    /* Clamp to 0-15 (0dB to +22.5dB) */
    if (left > 15)
        left = 15;
    if (right > 15)
        right = 15;

    val = (unsigned short)((left << 8) | right);
    ac97_write(codec, AC97_REG_RECORD_GAIN, val);
}

/*
 * ac97_set_rate - Set sample rate for DAC/ADC/MIC
 */
int
ac97_set_rate(struct ac97_codec_state *codec, int which, unsigned int rate)
{
    unsigned short reg;
    unsigned short readback;
    unsigned int *cache;

    if (codec == NULL)
        return -1;

    if (rate < AC97_RATE_MIN || rate > AC97_RATE_MAX)
        return -1;

    if (!codec->vra_enabled && rate != AC97_RATE_DEFAULT)
        return -1;

    /* Select appropriate register */
    switch (which) {
    case AC97_RATE_DAC:
        reg = AC97_REG_PCM_FRONT_DAC_RATE;
        cache = &codec->dac_rate;
        break;
    case AC97_RATE_ADC:
        reg = AC97_REG_PCM_LR_ADC_RATE;
        cache = &codec->adc_rate;
        break;
    case AC97_RATE_MIC:
        if (!codec->caps.vrm_supported)
            return -1;
        reg = AC97_REG_PCM_MIC_ADC_RATE;
        cache = &codec->mic_rate;
        break;
    default:
        return -1;
    }

    ac97_write(codec, reg, (unsigned short)rate);
    readback = ac97_read(codec, reg);
    if (readback != (unsigned short)rate)
        return -1;

    *cache = rate;
    return 0;
}

/*
 * ac97_get_rate - Get current sample rate
 */
unsigned int
ac97_get_rate(struct ac97_codec_state *codec, int which)
{
    if (codec == NULL)
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
    if (codec == NULL)
        return;

    ac97_write(codec, AC97_REG_POWERDOWN, AC97_PWR_D0);
    ac97_delay(codec, 100);

    /* Wait for sections to power up */
    ac97_wait_ready(codec, 100);
}

/*
 * ac97_power_down - Power down codec
 */
void
ac97_power_down(struct ac97_codec_state *codec)
{
    if (codec == NULL)
        return;

    ac97_write(codec, AC97_REG_POWERDOWN, AC97_PWR_D3);
}

/*
 * ac97_dump_registers - Dump all codec registers (for debugging)
 */
void
ac97_dump_registers(struct ac97_codec_state *codec)
{
    (void)codec;
}

/*
 * ac97_attenuation_field - Map attenuation to volume field value
 */
unsigned short
ac97_attenuation_field(int atten, int bits)
{
    int max_field;
    int clamped;

    if (atten > 0)
        atten = 0;
    if (atten < -84)
        atten = -84;

    max_field = (1 << bits) - 1;
    clamped = (-atten * max_field) / 84;
    return (unsigned short)clamped;
}

/*
 * ac97_measure_volume_bits - Probe volume register bit width
 */
int
ac97_measure_volume_bits(struct ac97_codec_state *codec, unsigned char reg)
{
    unsigned short saved;
    unsigned short probe;
    unsigned short mask;
    int bits;
    int i;

    saved = ac97_read(codec, reg);
    ac97_write(codec, reg, (unsigned short)(AC97_MUTE | 0x003f));
    probe = ac97_read(codec, reg);
    ac97_write(codec, reg, saved);

    mask = probe & 0x003f;
    bits = 0;
    for (i = 0; i < 6; i++) {
        if ((mask & (1U << i)) != 0)
            bits++;
    }

    if (bits < 5)
        bits = 5;
    if (bits > 6)
        bits = 6;

    return bits;
}

/*
 * ac97_apply_output - Apply attenuation to all present outputs
 */
void
ac97_apply_output(struct ac97_codec_state *codec,
                  int leftAtten, int rightAtten, int mute)
{
    int i;
    unsigned short left;
    unsigned short right;
    unsigned short val;
    unsigned short cur;
    int max_field;

    if (codec == NULL)
        return;

    for (i = 0; i < 3; i++) {
        if (!codec->out_present[i])
            continue;

        left = ac97_attenuation_field(leftAtten, codec->out_bits[i]);
        right = ac97_attenuation_field(rightAtten, codec->out_bits[i]);
        max_field = (1 << codec->out_bits[i]) - 1;

        val = (unsigned short)(((left & max_field) << AC97_LEFTVOL_SHIFT) |
              ((right & max_field) << AC97_RIGHTVOL_SHIFT));

        cur = ac97_read(codec, ac97_output_regs[i]);
        if (mute)
            val |= AC97_MUTE;
        else
            val |= (cur & AC97_MUTE);

        ac97_write(codec, ac97_output_regs[i], val);
    }
}
