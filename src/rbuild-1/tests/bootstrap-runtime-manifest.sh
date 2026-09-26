#!/bin/sh
set -e
root=`dirname "$0"`/../../..
full="$root/src/BootstrapManifest"
runtime="$root/src/BootstrapRuntimeManifest"
if test ! -f "$full" || test ! -f "$runtime"; then
    echo "bootstrap-runtime-manifest: missing manifest" >&2
    exit 1
fi
# Strip comments/blank lines to a three-column stream.
flat() { awk '$1=="dir" { print $1, $2, $3 }' "$1"; }
start=`flat "$runtime" | awk 'NR==1 { print $2, $3; exit }'`
test "$start" = "Csu-1 all" || {
    echo "bootstrap-runtime-manifest: must start at Csu-1 all" >&2
    exit 1
}
end=`flat "$runtime" | tail -1 | awk '{ print $2, $3 }'`
test "$end" = "Libsystem-2 all" || {
    echo "bootstrap-runtime-manifest: must end at Libsystem-2 all" >&2
    exit 1
}
awk -v runtime="$runtime" '
    BEGIN {
        while ((getline line < runtime) > 0) {
            n = split(line, f, /[ \t]+/)
            if (f[1] != "dir") continue
            r[++rc] = f[1] " " f[2] " " f[3]
        }
        close(runtime)
        if (rc < 2) { print "bootstrap-runtime-manifest: runtime too short" > "/dev/stderr"; exit 1 }
    }
    $1=="dir" { f[++fc] = $1 " " $2 " " $3 }
    END {
        for (i = 1; i <= fc; i++) if (f[i] == r[1]) { s = i; break }
        if (!s) { print "bootstrap-runtime-manifest: Csu-1 all missing from BootstrapManifest" > "/dev/stderr"; exit 1 }
        for (j = 1; j <= rc; j++) {
            if (f[s + j - 1] != r[j]) {
                print "bootstrap-runtime-manifest: not a contiguous subsequence at " r[j] > "/dev/stderr"
                exit 1
            }
        }
        print "bootstrap-runtime-manifest: PASS"
    }
' "$full"
