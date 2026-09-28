#!/bin/sh
# Side-by-side driverLoader behaviour check for the i386 guest.
#
# Runs Apple's driverLoader and a candidate with the same arguments and stdin,
# on cases that load nothing into the kernel, and compares stdout+stderr and
# the exit status.  Rhapsody's /bin/sh is a 1999 Bourne shell: keep it plain.
#
# Environment overrides: REF (reference binary), CAN (candidate binary),
# CANLIB (the libDriver.A.dylib the candidate links).

REF=${REF:-/usr/sbin/driverLoader}
CAN=${CAN:-/build/dlr/x/usr/sbin/driverLoader}
CANLIB=${CANLIB:-/build/dlr/x/usr/lib/libDriver.A.dylib}
W=/tmp/dlbeh
D=/usr/Devices

for f in "$REF" "$CAN"; do
	if [ ! -f "$f" ]; then
		echo "driverloader-behaviour: missing $f"
		exit 2
	fi
done
# The rebuilt binary loads /usr/lib/libDriver.A.dylib, which DR2 lacks.
# Apple's DR2 binary needs nothing, so a missing CANLIB is not an error.
if [ ! -f /usr/lib/libDriver.A.dylib ] && [ -f "$CANLIB" ]; then
	cp "$CANLIB" /usr/lib/libDriver.A.dylib || exit 2
	chmod 555 /usr/lib/libDriver.A.dylib
fi

rm -rf $W
mkdir -p $W/ref $W/can $W/out
cp "$REF" $W/ref/driverLoader
cp "$CAN" $W/can/driverLoader
chmod 555 $W/ref/driverLoader $W/can/driverLoader

# mkcfg NAME PRELOAD [SCRIPT-BODY]: a scratch driver config with a Pre-Load.
mkcfg() {
	rm -rf $D/$1.config
	mkdir -p $D/$1.config
	printf '"Driver Name" = "%s";\n"Pre-Load" = "%s";\n' "$1" "$2" > $D/$1.config/Default.table
	if [ -n "$3" ]; then
		printf '#!/bin/sh\n%s\n' "$3" > $D/$1.config/$2
		chmod 555 $D/$1.config/$2
	fi
	chmod -R go-w $D/$1.config
}
mkcfg DLTestFail fail.sh 'exit 1'
mkcfg DLTestAbs /bin/false

fails=0
# run CASE STDIN ARGS...
run() {
	c=$1
	in=$2
	shift
	shift
	for s in ref can; do
		(cd $W/$s && printf "$in" | ./driverLoader "$@" > $W/out/$c.$s 2>&1
		 echo "exit=$?" >> $W/out/$c.$s)
	done
	if cmp -s $W/out/$c.ref $W/out/$c.can; then
		echo "PASS $c"
	else
		echo "FAIL $c"
		diff $W/out/$c.ref $W/out/$c.can
		fails=`expr $fails + 1`
	fi
}

run noargs ''
run badop '' x
run nodriver '' D=DLTestNone v
run preload-fail '' D=DLTestFail v
run preload-abs '' D=DLTestAbs v
run interactive-d 'n\nn\nn\nn\nn\n' d=BPF
run interactive-i 'n\nn\n' i

rm -rf $D/DLTestFail.config $D/DLTestAbs.config
echo "=== behaviour done fails=$fails ==="
if [ $fails = 0 ]; then
	exit 0
fi
exit 1
