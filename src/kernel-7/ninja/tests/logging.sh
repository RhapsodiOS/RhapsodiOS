#!/bin/sh
set -eu
suite=$1
work=$2
case "$suite" in legacy|safe) ;; *) echo 'expected legacy or safe' >&2; exit 1 ;; esac
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
here=`CDPATH= cd "\`dirname "$0"\`" && pwd`
mkdir -p "$work"
cp "$here/logging.c" "$work/logging.c"
cd "$work"
/usr/bin/cc -O logging.c -o logging
./logging write control.log control.done
./logging check control.log unused
./logging write observed.log observed.done &
writer=$!
while test ! -f observed.done; do
    if test -s observed.log; then
        case "$suite" in
        legacy) tail -1 observed.log > /dev/null ;;
        safe) /bin/sh "$here/read-log.sh" observed.log 1 > /dev/null ;;
        esac
    fi
done
wait "$writer"
./logging check observed.log unused
echo "PASS: $suite log reader"
