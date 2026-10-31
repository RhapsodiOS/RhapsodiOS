set -eu
export PATH=/build/build/tools/bin:/build/bin:/usr/local/bin:/build/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/build/out/drvATIMach64-rbuild-setvgamode-v27-2026-10-04
PACKAGE=`find "$OUT" -name '*.apk' -type f | head -1`
RELOC="$OUT/ATIMach64DisplayDriver_reloc"
mkdir -p /build/build/out/i386/drvATIMach64/ATIMach64DisplayDriver.config-setvgamode-v27-2026-10-04
mkdir -p /build/build/out/i386/drvATIMach64/packages-setvgamode-v27-2026-10-04
gzip -dc "$PACKAGE" | tar xOf - ./private/Drivers/i386/ATIMach64DisplayDriver.config/ATIMach64DisplayDriver_reloc > "$RELOC"
file "$RELOC"
cp -p "$RELOC" /build/build/out/i386/drvATIMach64/ATIMach64DisplayDriver.config-setvgamode-v27-2026-10-04/
cp -p "$PACKAGE" /build/build/out/i386/drvATIMach64/packages-setvgamode-v27-2026-10-04/
printf 'reloc bytes: '; wc -c < "$RELOC"
