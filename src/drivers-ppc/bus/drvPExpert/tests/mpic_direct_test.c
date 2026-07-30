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

	return EXIT_SUCCESS;
}
