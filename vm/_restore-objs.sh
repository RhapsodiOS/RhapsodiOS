#!/bin/sh
# Unpack harvested *-obj.apk into /usr/local/lib/objs (lost across reboot/tmp cleanup).
REPO="${1:-/build/repo}"
mkdir -p /usr/local/lib/objs
for apk in "$REPO"/*-obj-*.apk; do
  [ -f "$apk" ] || continue
  echo "extract $apk"
  # apk is gzip'd tar with paths like usr/local/lib/objs/...
  (cd / && gnutar xzf "$apk" 2>/dev/null) || (cd / && tar xzf "$apk" 2>/dev/null) || {
    # try as plain tar
    (cd /tmp && rm -rf _objx && mkdir _objx && cd _objx && \
      gzip -dc "$apk" 2>/dev/null | tar xf - 2>/dev/null || tar xf "$apk") && \
      cp -Rp /tmp/_objx/usr/local/lib/objs/. /usr/local/lib/objs/ 2>/dev/null
  }
done
echo "=== /usr/local/lib/objs ==="
ls /usr/local/lib/objs 2>&1 | head -40
