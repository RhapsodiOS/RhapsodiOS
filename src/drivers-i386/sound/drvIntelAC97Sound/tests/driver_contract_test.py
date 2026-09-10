import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LINK = ROOT / "IntelAC97.drvproj" / "IntelAC97.lksproj"


class DriverContractTests(unittest.TestCase):
    def test_load_commands_wire_soundkit(self):
        text = (LINK / "Load_Commands.sect").read_text(encoding="utf-8")
        self.assertIn("SMAP", text)
        self.assertIn("audio0", text)
        self.assertIn("ADVERTISE", text)
        self.assertIn("WIRE", text)
        self.assertNotIn("sectcreate", text)

    def test_makefile_splits_c_and_objc(self):
        makefile = (LINK / "Makefile").read_text(encoding="utf-8")
        self.assertIn("CLASSES = IntelAC97Driver.m", makefile)
        self.assertIn("CFILES = ac97.c ICHAC97Controller.c", makefile)
        self.assertFalse((LINK / "ac97.m").exists())
        for name in ("ac97.c", "ICHAC97Controller.c"):
            source = (LINK / name).read_text(encoding="utf-8")
            self.assertNotIn("@interface", source)
            self.assertNotIn("<driverkit/", source)
            self.assertNotIn("outb(", source)
            self.assertNotIn("outw(", source)
            self.assertNotIn("outl(", source)

    def test_kernel_io_is_port_then_value(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        self.assertIn("outb((IOEISAPortAddress)port, value)", source)
        self.assertNotIn("outb(value, port)", source)
        self.assertNotIn("outw(value, port)", source)
        self.assertNotIn("outl(value, port)", source)
        self.assertIn("ICHAC97Controller controller;", source)
        self.assertNotIn("static struct ich_state", source)

    def test_playback_dma_and_irq_paths(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        create = source[source.index("createDMABufferFor:"):source.index("startDMAForChannel:")]
        start = source[source.index("startDMAForChannel:"):source.index("stopDMAForChannel:")]
        stop = source[source.index("stopDMAForChannel:"):source.index("interruptClearFunc")]
        self.assertIn("return NULL", create)
        self.assertNotIn("ICHAC97PrepareBDL", create)
        self.assertIn("ICHAC97PrepareBDL", start)
        self.assertIn("bufferSizeForInterrupts", start)
        self.assertIn("ICHAC97StartPlayback", start)
        self.assertIn("isRead", start)
        self.assertIn("ICHAC97StopPlayback", stop)
        self.assertNotIn("disableAllInterrupts", stop)
        self.assertGreaterEqual(source.count("IOEnableInterrupt"), 2)
        handler = source[source.index("static void clearInt"):]
        self.assertIn("IOEnableInterrupt(identity)", handler)

    def test_accepts_continuous_sampling_rates_uses_vra_enabled(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        body = source[
            source.index("acceptsContinuousSamplingRates")
            : source.index("getSamplingRatesLow:")
        ]
        self.assertIn("vra_enabled", body)
        self.assertNotIn("vra_supported", body)

    def test_get_sampling_rates_respects_vra(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        low_high = source[
            source.index("getSamplingRatesLow:")
            : source.index("getSamplingRates:count:")
        ]
        rates = source[
            source.index("getSamplingRates:count:")
            : source.index("getDataEncodings:count:")
        ]
        self.assertIn("vra_enabled", low_high)
        self.assertIn("vra_enabled", rates)
        self.assertIn("48000", rates)
        self.assertIn("*numRates = 1", rates)

    def test_update_sample_rate_dac_only(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        body = source[
            source.index("updateSampleRate")
            : source.index("acceptsContinuousSamplingRates")
        ]
        self.assertIn("ac97_set_rate", body)
        self.assertIn("AC97_RATE_DAC", body)
        self.assertNotIn("AC97_RATE_ADC", body)

    def test_update_output_attenuation_left_uses_apply_output(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        body = source[
            source.index("updateOutputAttenuationLeft")
            : source.index("updateOutputAttenuationRight")
        ]
        self.assertIn("ac97_apply_output", body)
        self.assertNotIn("* 31) / 13", body)
        self.assertNotIn("ac97_set_master_volume", body)

    def test_update_input_gain_left_has_no_ac97_calls(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        body = source[
            source.index("updateInputGainLeft")
            : source.index("updateInputGainRight")
        ]
        self.assertNotIn("ac97_", body)


if __name__ == "__main__":
    unittest.main()
