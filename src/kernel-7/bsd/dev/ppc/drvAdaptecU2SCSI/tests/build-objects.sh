#!/bin/sh
set -eu
test "$#" -ge 2 || { echo 'usage: build-objects.sh OUTDIR SOURCE...' >&2; exit 1; }
out=$1
shift
case "$out" in /*) ;; *) echo 'OUTDIR must be absolute' >&2; exit 1 ;; esac
case "$out" in *[!A-Za-z0-9_./-]*) echo 'OUTDIR contains unsupported characters' >&2; exit 1 ;; esac
here=`/bin/pwd`
case "$out/" in "$here/"*) echo 'OUTDIR must be outside the source tree' >&2; exit 1 ;; esac
test ! -e "$out" || { echo 'OUTDIR must be initially absent' >&2; exit 1; }
test -f build-ppc.ninja
: "${AU2_SOURCE_REVISION:?set the staged source Git revision}"
test "${#AU2_SOURCE_REVISION}" -eq 40
case "$AU2_SOURCE_REVISION" in *[!0-9A-Fa-f]*) exit 1 ;; esac
hash=${AU2_SHA256-sha256sum}
"$hash" /dev/null >/dev/null
mkdir -p "$out"
out=`CDPATH= cd "$out" && /bin/pwd`
case "$out/" in "$here/"*) echo 'resolved OUTDIR must be outside the source tree' >&2; exit 1 ;; esac

jstr()
{
    awk 'BEGIN { printf "\"" } { if (NR>1) printf "\\n"; for(i=1;i<=length($0);i++){c=substr($0,i,1); if(c=="\"" || c=="\\") printf "\\"; if(c=="\t") printf "\\t"; else printf "%s",c} } END {printf "\""}'
}
sha()
{
    hash_line=`"$hash" "$1"` || return 1
    printf '%s\n' "$hash_line" | awk 'length($1)==64 && $1 !~ /[^0-9A-Fa-f]/ {print toupper($1); ok=1} END {if(!ok) exit 1}'
}
"${SAMU-samu}" -f build-ppc.ninja configured generated > "$out/prepare.log" 2>&1 || {
    /bin/sh ninja/tests/read-log.sh "$out/prepare.log" 20; exit 1;
}
"${SAMU-samu}" -f build-ppc.ninja -t commands BUILD.ninja/RELEASE_PPC/locc.o > "$out/generated.commands"
sed -n '/obj=locc.o && /s/ && awk .*//p' "$out/generated.commands" > "$out/template.command"
test `wc -l < "$out/template.command"` -eq 1
{
    printf '{"schema_version":1,"source_revision":'; printf '%s\n' "$AU2_SOURCE_REVISION" | jstr
    printf ',"source_root":'; printf '%s\n' "$here" | jstr
    printf ',"guest_output_root":'; printf '%s\n' "$out" | jstr
    printf ',"hash_algorithm":"SHA-256","configuration":"RELEASE_PPC","objects":['
} > "$out/objects.json.tmp"
separator=
index=0
for source do
    case "$source" in ''|/*|*..*|*[!A-Za-z0-9_./-]*) echo "unsafe source path: $source" >&2; exit 1 ;; esac
    test -f "$source"
    index=`expr "$index" + 1`
    object=$out/$index-`basename "$source"`.o
    command_file=$out/$index.command
    sed "s@../../bsd/libkern/locc.c@../../$source@; s@-o locc.o@-o $object@" "$out/template.command" > "$command_file"
    /bin/sh -e "$command_file" > "$out/$index.log" 2>&1 || {
        /bin/sh ninja/tests/read-log.sh "$out/$index.log" 20; exit 1;
    }
    otool -hv "$object" > "$out/$index.header"
    grep PPC "$out/$index.header" >/dev/null
    source_hash=`sha "$source"`
    object_hash=`sha "$object"`
    {
        printf '%s{"source":' "$separator"; printf '%s\n' "$source" | jstr
        printf ',"source_sha256":"%s","path":' "$source_hash"; basename "$object" | jstr
        printf ',"sha256":"%s","cpu_type":18,"command":' "$object_hash"; jstr < "$command_file"
        printf ',"log":'; printf '%s\n' "$index.log" | jstr
        printf '}'
    } >> "$out/objects.json.tmp"
    separator=,
done
printf ']}\n' >> "$out/objects.json.tmp"
mv "$out/objects.json.tmp" "$out/objects.json"
echo "PASS: PPC objects in $out"
