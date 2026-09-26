#include <stdio.h>
#include <stdlib.h>

#include <interrupts.h>

static void
expect_equal(const char *name, int actual, int expected)
{
	if (actual != expected) {
		fprintf(stderr, "%s: expected %d, got %d\n",
		    name, expected, actual);
		exit(EXIT_FAILURE);
	}
}

static PEMPICConfiguration
configuration(int featureControl, int passThrough, unsigned int mask,
    unsigned int count)
{
	PEMPICConfiguration value;

	value.useFeatureControl = featureControl;
	value.disablePassThrough = passThrough;
	value.destinationMask = mask;
	value.sourceCount = count;
	return value;
}

static void
test_policy(void)
{
	PEMPICConfiguration value;
	const PEMPICConfiguration *current;
	int configured;

	/* Unconfigured families keep the legacy sequence. */
	current = PEMPICGetConfiguration(&configured);
	expect_equal("legacy unconfigured", configured, 0);
	expect_equal("legacy feature control", current->useFeatureControl, 1);
	expect_equal("legacy pass-through", current->disablePassThrough, 1);

	value = configuration(0, 1, 1, 1);
	expect_equal("one source", PEMPICValidateConfiguration(&value), 1);
	value = configuration(0, 1, 1, 64);
	expect_equal("64 sources", PEMPICValidateConfiguration(&value), 1);
	value = configuration(0, 1, 1, 0);
	expect_equal("no sources", PEMPICValidateConfiguration(&value), 0);
	value = configuration(0, 1, 1, 65);
	expect_equal("65 sources", PEMPICValidateConfiguration(&value), 0);
	value = configuration(0, 1, 0, 64);
	expect_equal("no destination", PEMPICValidateConfiguration(&value), 0);
	value = configuration(0, 1, 0x10, 64);
	expect_equal("fifth CPU", PEMPICValidateConfiguration(&value), 0);
	value = configuration(0, 1, 0xf, 64);
	expect_equal("four CPUs", PEMPICValidateConfiguration(&value), 1);
	expect_equal("null configuration", PEMPICValidateConfiguration(0), 0);

	value = configuration(0, 1, 0, 64);
	expect_equal("reject invalid", PEMPICSetConfiguration(&value), 0);
	current = PEMPICGetConfiguration(&configured);
	expect_equal("still unconfigured", configured, 0);

	value = configuration(0, 1, 1, 64);
	expect_equal("accept valid", PEMPICSetConfiguration(&value), 1);
	current = PEMPICGetConfiguration(&configured);
	expect_equal("configured", configured, 1);
	expect_equal("feature control off", current->useFeatureControl, 0);
	expect_equal("pass-through independent",
	    current->disablePassThrough, 1);
	expect_equal("CPU 0 only", (int)current->destinationMask, 1);
	value = configuration(1, 0, 1, 38);
	expect_equal("flags independent", PEMPICSetConfiguration(&value), 1);
	current = PEMPICGetConfiguration(0);
	expect_equal("feature control on", current->useFeatureControl, 1);
	expect_equal("pass-through left", current->disablePassThrough, 0);

	expect_equal("source 63", PEMPICSourceInRange(63, 64), 1);
	expect_equal("source 64", PEMPICSourceInRange(64, 64), 0);
	expect_equal("spurious 0xff", PEMPICSourceInRange(0xff, 64), 0);
}

int
main(void)
{
	struct powermac_interrupt map[64];
	int i;

	for (i = 0; i < 64; i++)
		map[i].i_device = -1;
	map[8].i_device = PMAC_DMA_AUDIO_OUT;
	map[9].i_device = PMAC_DMA_AUDIO_IN;
	map[17].i_device = PMAC_DEV_AUDIO;
	map[40].i_device = 17;

	expect_equal("audio output DMA", PEMPIClogicalForSource(map, 64, 8),
	    PMAC_DMA_AUDIO_OUT);
	expect_equal("audio input DMA", PEMPIClogicalForSource(map, 64, 9),
	    PMAC_DMA_AUDIO_IN);
	expect_equal("audio device", PEMPIClogicalForSource(map, 64, 17),
	    PMAC_DEV_AUDIO);
	expect_equal("legacy logical device", PEMPIClogicalForSource(map, 64, 40),
	    17);
	expect_equal("reserved direct source",
	    PEMPIClogicalForSource(map, 64, 47),
	    PMAC_DEV_MPIC_DIRECT_BASE + 47);
	expect_equal("negative source", PEMPIClogicalForSource(map, 64, -1), -1);
	expect_equal("source at count", PEMPIClogicalForSource(map, 64, 64), -1);

	expect_equal("legacy OF conversion",
	    PEMPICsourceForInterrupt(map, 64, 64, 8 ^ 0x18), 8);
	expect_equal("direct conversion",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 47), 47);
	expect_equal("direct conversion mapped alias",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 8), -1);

	expect_equal("legacy registration source",
	    PEMPICsourceForDevice(map, 64, 17), 40);
	expect_equal("direct registration source",
	    PEMPICsourceForDevice(map, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 47), 47);
	expect_equal("direct registration callback identity",
	    PEMPIClogicalForSource(map, 64,
	    PEMPICsourceForDevice(map, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 47)),
	    PMAC_DEV_MPIC_DIRECT_BASE + 47);
	map[47].i_device = PMAC_DEV_MPIC_DIRECT_BASE + 47;
	expect_equal("existing direct registration source",
	    PEMPICsourceForDevice(map, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 47), 47);
	expect_equal("direct registration mapped alias",
	    PEMPICsourceForDevice(map, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 8), -1);

	expect_equal("enable direct base",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE), 0);
	expect_equal("enable last direct source",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 63), 63);
	expect_equal("enable first invalid direct source",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 64), -1);
	expect_equal("disable mapped direct alias",
	    PEMPICsourceForInterrupt(map, 64, 64,
	    PMAC_DEV_MPIC_DIRECT_BASE + 9), -1);

	test_policy();
	return EXIT_SUCCESS;
}
