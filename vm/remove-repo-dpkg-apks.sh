#!/bin/sh
# Remove /build/repo APKs whose .PKGINFO pkgname is dpkg, dpkg-scriptlib,
# buildtools, or those names plus -hdrs / -obj. No full repo wipe.
set -e
repo=${1-/build/repo}
if test "$1" = "--self-test"; then
    t=/tmp/rb-remove-dpkg-apks-self
    rm -rf "$t"
    mkdir -p "$t"
    printf 'not gzip' > "$t/broken-1-universal.apk"
    if "$0" "$t" >/tmp/rb-remove-dpkg-ok.out 2>/tmp/rb-remove-dpkg-ok.err; then
        echo "self-test: expected fail on non-gzip APK" >&2
        exit 1
    fi
    test -f "$t/broken-1-universal.apk"
    rm -f "$t/broken-1-universal.apk"
    printf 'pkgname = dpkg\n' | gzip > "$t/dpkg-1.4.1.0.2-universal.apk"
    printf 'pkgname = grep\n' | gzip > "$t/grep-2.1-universal.apk"
    printf 'pkgname = buildtools-hdrs\n' | gzip > "$t/buildtools-hdrs-0.1-universal.apk"
    "$0" "$t" >/tmp/rb-remove-dpkg-ok.out
    test ! -f "$t/dpkg-1.4.1.0.2-universal.apk"
    test -f "$t/grep-2.1-universal.apk"
    test ! -f "$t/buildtools-hdrs-0.1-universal.apk"
    grep 'removed=2' /tmp/rb-remove-dpkg-ok.out >/dev/null
    rm -rf "$t"
    echo "self-test: PASS"
    exit 0
fi
if test ! -d "$repo"; then
    echo "remove-repo-dpkg-apks: missing directory $repo" >&2
    exit 1
fi
n=0
for f in "$repo"/*.apk; do
    test -f "$f" || continue
    case "$f" in
        *.apk.invalid) continue ;;
    esac
    name=`gzip -dc "$f" | tr '\000' '\012' | grep '^pkgname =' | sed -n '1p' | sed 's/^pkgname = //'`
    if test -z "$name"; then
        echo "remove-repo-dpkg-apks: cannot read pkgname from $f" >&2
        exit 1
    fi
    case "$name" in
        dpkg|dpkg-scriptlib|buildtools|dpkg-hdrs|dpkg-obj|dpkg-scriptlib-hdrs|dpkg-scriptlib-obj|buildtools-hdrs|buildtools-obj)
            rm -f "$f"
            echo "removed `basename "$f"`"
            n=`expr "$n" + 1`
            ;;
    esac
done
echo "remove-repo-dpkg-apks: removed=$n"
