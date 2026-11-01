#!/bin/sh
set -eu
mode=$1
config=$2
root=$3
arch=$4
shift 4
case "$config" in RELEASE|DEBUG) ;; *) echo "unsupported configuration: $config" >&2; exit 1 ;; esac
case "$arch" in i386) suffix=I386 ;; ppc) suffix=PPC ;; *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac
for file in conf/MASTER.local conf/MASTER.$arch.local conf/files.NEXT; do
    if test -e "$file"; then
        echo "${config}_$suffix: unsupported local configuration: $file" >&2
        exit 1
    fi
done
case "$mode" in
check) exit 0 ;;
prepare) ;;
*) echo "unknown preparation mode: $mode" >&2; exit 1 ;;
esac
mkdir -p "$root"
root=`CDPATH= cd "$root" && pwd`
outdir=$root/${config}_$suffix
mkdir -p "$outdir"
rm -f "$outdir/prepared"
tool=${CONFIG_DIR-/usr/local/bin}/config
test -x "$tool" || { echo "missing configuration tool: $tool" >&2; exit 1; }
for file do
    case "$file" in */prepared) ;; *) rm -f "$file" ;; esac
done
(cd conf && /bin/csh -f tools/doconf/doconf.csh -c -cpu "$arch" -d "$root" "$config")
for file do
    case "$file" in */prepared) ;; *) test -e "$file" || { echo "configuration did not produce $file" >&2; exit 1; } ;; esac
done
printf '%s: %s\n' "$1" "$tool" > "$outdir/configure.d"
date > "$outdir/prepared"
