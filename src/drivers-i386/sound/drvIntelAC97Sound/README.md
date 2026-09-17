# Intel ICH AC97 sound driver

PCI device `8086:2415` (Intel ICH AC97). Playback-only; no capture path.

## Host tests

From this directory:

```sh
make -C tests -f Makefile.host check
```

## Guest build

From this directory (driver root):

```sh
gnumake
```

## QEMU playback check

Boot a disposable working image with host audio via the q35 launcher:

```sh
vm/run-q35-ahci.sh --dry-run --ac97 dsound SOURCE.img vm/work/boot.img
# then without --dry-run when ready
vm/run-q35-ahci.sh --ac97 dsound SOURCE.img vm/work/boot.img
```

Play audio long enough for several DMA ring buffer wraps. There is no FIFO
depth reporting or playback timeout in this driver; sustained output is the
success signal.
