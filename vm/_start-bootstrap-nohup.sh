#!/bin/sh
# Start bootstrap under nohup; safe to run over a short SSH session.
# Args: [SRC=/build/src] [TIME_ARG=yyyymmddHHMM.SS]
SRC="${1:-/build/src}"
TIME_ARG="$2"

rm -f /tmp/bootstrap-rerun.log /tmp/bootstrap-rerun.pid /tmp/bootstrap-nohup.out

if [ -n "$TIME_ARG" ]; then
  date "$TIME_ARG" || true
fi

# Helpers must already be on guest under /tmp (uploaded by host).
if [ -x /tmp/_install-ln.sh ]; then
  /tmp/_install-ln.sh || exit 1
fi
if [ -x /tmp/_restore-objs.sh ]; then
  /tmp/_restore-objs.sh /build/repo || true
fi
if [ -x /tmp/_seed-bootstrap-hdrs.sh ]; then
  /tmp/_seed-bootstrap-hdrs.sh "$SRC" || exit 1
fi

cat > /tmp/run-bootstrap.sh <<EOF
#!/bin/sh
cd $SRC || exit 1
mkdir -p /build/repo
rbuild bootstrap BootstrapManifest /build/repo /build/repo > /tmp/bootstrap-rerun.log 2>&1
echo EXIT:\$? >> /tmp/bootstrap-rerun.log
EOF
chmod a+x /tmp/run-bootstrap.sh
nohup /tmp/run-bootstrap.sh > /tmp/bootstrap-nohup.out 2>&1 &
echo $! > /tmp/bootstrap-rerun.pid
echo "started pid=$(cat /tmp/bootstrap-rerun.pid)"
sleep 2
wc -l /tmp/bootstrap-rerun.log 2>/dev/null
tail -5 /tmp/bootstrap-rerun.log 2>/dev/null
