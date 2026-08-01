#!/bin/sh
# Install bootstrap_cmds tools from the last native DSTROOT onto the live host.
# Native rbuild packages into DSTROOT/.apk and does not update /usr/local/bin.
DST=`ls -d /private/tmp/roots/bootstrap-cmds-*.roots/bootstrap-cmds-*.dst/usr/local/bin 2>/dev/null | tail -1`
if [ -z "$DST" ]; then
  echo "install-bootstrap-tools: no DSTROOT yet"
  exit 0
fi
mkdir -p /usr/local/bin
for t in config relpath decomment; do
  if [ -x "$DST/$t" ]; then
    cp -p "$DST/$t" /usr/local/bin/$t
    chmod a+x /usr/local/bin/$t
    echo "installed /usr/local/bin/$t"
  fi
done
# migcom goes to /usr/libexec
LIBEX=`ls -d /private/tmp/roots/bootstrap-cmds-*.roots/bootstrap-cmds-*.dst/usr/libexec 2>/dev/null | tail -1`
if [ -n "$LIBEX" ]; then
  mkdir -p /usr/libexec
  for t in migcom migcom_typd migcom_untypd; do
    if [ -x "$LIBEX/$t" ]; then
      cp -p "$LIBEX/$t" /usr/libexec/$t
      chmod a+x /usr/libexec/$t
      echo "installed /usr/libexec/$t"
    fi
  done
fi
ls -la /usr/local/bin/config /usr/local/bin/relpath /usr/local/bin/decomment 2>&1
