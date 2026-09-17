#!/bin/sh
# Rename /build/repo APKs from {name}-{ver}.apk to {name}-{ver}-{token}.apk.
# No rebuild. Abort if the destination exists. Skip *.apk.invalid.
set -e
repo=${1-/build/repo}
if test ! -d "$repo"; then
    echo "rename-repo-apk-arch: missing directory $repo" >&2
    exit 1
fi
n=0
for f in "$repo"/*.apk; do
    test -f "$f" || continue
    case "$f" in
        *.apk.invalid) continue ;;
    esac
    base=`basename "$f"`
    case "$base" in
        *-universal.apk|*-i386.apk|*-ppc.apk) continue ;;
    esac
    arch=`gzip -dc "$f" | tr '\000' '\012' | grep '^arch =' | sed -n '1p'`
    tok=
    case "$arch" in
        *universal-apple-rhapsody*) tok=universal ;;
        *i386-apple-rhapsody*) tok=i386 ;;
        *ppc-apple-rhapsody*) tok=ppc ;;
        *) echo "rename-repo-apk-arch: unknown arch in $base [$arch]" >&2; exit 1 ;;
    esac
    stem=`echo "$base" | sed 's/\.apk$//'`
    dest="$repo/$stem-$tok.apk"
    if test -e "$dest"; then
        echo "rename-repo-apk-arch: collision $dest" >&2
        exit 1
    fi
    mv "$f" "$dest"
    echo "renamed $base -> `basename "$dest"`"
    n=`expr "$n" + 1`
done
echo "rename-repo-apk-arch: renamed $n apks in $repo"
