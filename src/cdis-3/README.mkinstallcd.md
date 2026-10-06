# mkinstallcd.sh

**This is a legacy CD builder, and it does not make an installer that
works.** It packs a staging tree and runs `mkisofs`, but it predates
`sysinstall`: it copies no `sysinstall`, no sets and no apks, and it expects
an `image.tar.gz` that nothing in the installer reads any more. The
install media is built by `vm/instmedia` (`docs/build/sysinstall.md`), and
phase 6 of the install-media design adds the real El Torito CD. Keep the
script only as a reference for the staging layout and the `mkisofs` flags.

## What it does

`./mkinstallcd.sh [-o OUTPUT] [-s SRCROOT] [-d DSTROOT] [-i IMAGE] [-p PKGDIR] [-b] [-c] [-v]`

1. With `-b`, builds `boot-2/i386` and `cdis-3` into the staging directory.
2. Creates `System/Installation/{CDIS,Data,Packages}`, `usr/standalone/i386`
   and `private/etc` in the staging directory (`-d`, default `iso_staging`).
3. Copies `boot0`, `boot1`, `boot` and the boot bitmaps to
   `usr/standalone/i386`.
4. Copies `cdis-3/rc.cdrom` to `private/etc/rc.cdrom`, the English strings,
   `fixdisk`, the `.pl` helpers, the old CDIS tools (`getpath`, `findroot`,
   `checkflop`, `pickdisk`, `gc`, `slamloaderbits`, `sgmove`, `popconsole`,
   `ditto`) and `install_tools`.
5. Copies the tarball given with `-i` to `Data/image.tar.gz`, and `.pkg`
   directories from `-p` to `Packages`.
6. Runs `mkisofs` or `genisoimage` with `boot1` as the El Torito image
   (`-no-emul-boot -boot-load-size 4 -boot-info-table`), then `isohybrid` if
   it is installed.

It needs `mkisofs` or `genisoimage`, and the built booter and CDIS tools.

## What is out of date

- `rc.cdrom` is now one line that runs
  `/System/Installation/CDIS/sysinstall` and falls back to a shell. The
  script doesn't copy `sysinstall`, so the CD would drop to a shell.
- `rc.cdrom.x86`, `rc.cdrom.PPC`, the French, German and Japanese strings,
  and the perl installer no longer exist in `cdis-3`.
- The installer installs the apks listed in `sets/*.set` from
  `/System/Installation/Packages`, not `image.tar.gz` or `.pkg` directories.
- Only English strings remain, and the installer is English only.
- The CD's El Torito boot image, 2048-byte reads and `rootdev=cdrom` are
  phase 6 work in `vm/instmedia` and `bootefi`, not this script.
