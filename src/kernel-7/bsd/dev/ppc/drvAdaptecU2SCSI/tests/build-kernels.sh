#!/bin/sh
set -eu
test "$#" -eq 1 || { echo 'usage: build-kernels.sh SCRATCH' >&2; exit 1; }
work=$1
case "$work" in /*) ;; *) echo 'SCRATCH must be absolute' >&2; exit 1 ;; esac
case "$work" in *[!A-Za-z0-9_./-]*) echo 'SCRATCH contains unsupported characters' >&2; exit 1 ;; esac
here=`/bin/pwd`
case "$work/" in "$here/"*) echo 'SCRATCH must be outside the source tree' >&2; exit 1 ;; esac
test ! -e "$work" || { echo 'SCRATCH must be initially absent' >&2; exit 1; }
test -f build-ppc.ninja
: "${AU2_SOURCE_REVISION:?set the staged source Git revision}"
test "${#AU2_SOURCE_REVISION}" -eq 40
case "$AU2_SOURCE_REVISION" in *[!0-9A-Fa-f]*) exit 1 ;; esac
hash=${AU2_SHA256-sha256sum}
"$hash" /dev/null >/dev/null
mkdir -p "$work"
work=`CDPATH= cd "$work" && /bin/pwd`
case "$work/" in "$here/"*) echo 'resolved SCRATCH must be outside the source tree' >&2; exit 1 ;; esac
jstr()
{
    awk 'BEGIN { printf "\"" } { if (NR>1) printf "\\n"; for(i=1;i<=length($0);i++){c=substr($0,i,1); if(c=="\"" || c=="\\") printf "\\"; if(c=="\t") printf "\\t"; else printf "%s",c} } END {printf "\""}'
}
sha()
{
    hash_line=`"$hash" "$1"` || return 1
    printf '%s\n' "$hash_line" | awk 'length($1)==64 && $1 !~ /[^0-9A-Fa-f]/ {print toupper($1); ok=1} END {if(!ok) exit 1}'
}
{
    uname -a
    cc -v 2>&1 || :
    "${SAMU-samu}" --version
    gnumake --version
    ld -v 2>&1 || :
    file /usr/libexec/ppc/2.7.2.1/cc1 /usr/libexec/migcom_typd /usr/libexec/migcom_untypd
} > "$work/tools.log"
# The existing suite copies the private tree and checks both Samurai products.
printf '/bin/sh ninja/tests/ppc.sh build %s\n' "$work/samurai" > "$work/commands"
/bin/sh ninja/tests/ppc.sh build "$work/samurai" > "$work/samurai.log" 2>&1 || {
    /bin/sh ninja/tests/read-log.sh "$work/samurai.log" 20; exit 1;
}
cd "$work/samurai/tree"
mkdir "$work/make"
cp -Rp "$here" "$work/make/tree"
cd "$work/make/tree/conf"
printf '/bin/csh -f tools/doconf/doconf.csh -c -cpu ppc -d %s RELEASE DEBUG\n' "$work/make/tree/BUILD.make" >> "$work/commands"
/bin/csh -f tools/doconf/doconf.csh -c -cpu ppc -d "$work/make/tree/BUILD.make" RELEASE DEBUG > "$work/make-config.log" 2>&1
# doconf generates Makefiles but does not install their TOOLDIR/newvers input.
test -e "$work/make/tree/BUILD.make/newvers" || ln -s ../conf/tools/newvers/newvers.csh "$work/make/tree/BUILD.make/newvers"
printf 'ln -s ../conf/tools/newvers/newvers.csh %s\n' "$work/make/tree/BUILD.make/newvers" >> "$work/commands"
for config in RELEASE DEBUG; do
    cd "$work/make/tree/BUILD.make/${config}_PPC"
    printf "cd %s && gnumake MIG='mig -arch ppc' assym.h\n" "`/bin/pwd`" >> "$work/commands"
    gnumake MIG='mig -arch ppc' assym.h > "$work/$config-make-assym.log" 2>&1 || {
        /bin/sh "$here/ninja/tests/read-log.sh" "$work/$config-make-assym.log" 20; exit 1;
    }
    printf "cd %s && gnumake -j 2 MIG='mig -arch ppc' mach_kernel\n" "`/bin/pwd`" >> "$work/commands"
    gnumake -j 2 MIG='mig -arch ppc' mach_kernel > "$work/$config-make.log" 2>&1 || {
        /bin/sh "$here/ninja/tests/read-log.sh" "$work/$config-make.log" 20; exit 1;
    }
done
{
    printf '{"schema_version":1,"source_revision":'; printf '%s\n' "$AU2_SOURCE_REVISION" | jstr
    printf ',"source_root":'; printf '%s\n' "$here" | jstr
    printf ',"guest_output_root":'; printf '%s\n' "$work" | jstr
    printf ',"hash_algorithm":"SHA-256","tools":'; jstr < "$work/tools.log"
    printf ',"commands":'; jstr < "$work/commands"
    printf ',"builds":['
} > "$work/builds.json.tmp"
separator=
for system in samurai make; do
    output=BUILD.ninja
    test "$system" != make || output=BUILD.make
    for config in RELEASE DEBUG; do
        dir=$work/$system/tree/$output/${config}_PPC
        log=samurai/$config-build.log
        test "$system" != make || log=$config-make.log
        for product in mach_kernel mach_kernel.sys; do
            test -s "$dir/$product"
            otool -hv "$dir/$product" > "$work/$system-$config-$product.header"
            grep PPC "$work/$system-$config-$product.header" >/dev/null
            product_hash=`sha "$dir/$product"`
            {
                printf '%s{"system":"%s","configuration":"%s_PPC","product":"%s","path":' "$separator" "$system" "$config" "$product"
                printf '%s\n' "$system/tree/$output/${config}_PPC/$product" | jstr
                printf ',"sha256":"%s","log":' "$product_hash"; printf '%s\n' "$log" | jstr
                printf '}'
            } >> "$work/builds.json.tmp"
            separator=,
        done
    done
done
printf ']}\n' >> "$work/builds.json.tmp"
mv "$work/builds.json.tmp" "$work/builds.json"
echo "PASS: Make/Samurai RELEASE/DEBUG PPC in $work"
