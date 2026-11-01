#!/bin/sh
set -eu
work=$1
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
here=`CDPATH= cd "\`dirname "$0"\`" && /bin/pwd`
mkdir -p "$work/bin"
work=`CDPATH= cd "$work" && /bin/pwd`
cat > "$work/bin/samu" <<'EOF'
#!/bin/sh
pwd >> "$TRACE"
: > touched-by-test
exit 17
EOF
chmod +x "$work/bin/samu"
export SAMU="$work/bin/samu"
for item in config:quoting config:defines config:syntax config:compare \
    build:diagnostic build:objects build:link build:strip-idle; do
    script=${item%:*}
    mode=${item#*:}
    casework=$work/$script-$mode
    caller=$casework/caller
    mkdir -p "$caller/ninja/tests"
    cp "$here/$script.sh" "$caller/ninja/tests/$script.sh"
    cat > "$caller/ninja/check-config.sh" <<'EOF'
exec "$SAMU"
EOF
    for config in RELEASE DEBUG; do
        mkdir -p "$caller/BUILD.ninja/${config}_I386"
        echo fixture > "$caller/BUILD.ninja/${config}_I386/mach_kernel.sys"
        : > "$caller/BUILD.ninja/${config}_I386/Makefile"
    done
    export TRACE=$casework/trace
    # Stop at the first build-tool call; no native toolchain is required.
    /bin/sh "$caller/ninja/tests/$script.sh" "$mode" "$casework/scratch" > "$casework/run.log" 2>&1 || :
    test -s "$TRACE" || { cat "$casework/run.log"; echo "FAIL: $item did not reach Samurai" >&2; exit 1; }
    while read directory; do
        case "$directory/" in
        "$casework/scratch/tree/"*) ;;
        *) echo "FAIL: $item ran in caller checkout: $directory" >&2; exit 1 ;;
        esac
    done < "$TRACE"
    test ! -e "$caller/touched-by-test"
done
echo 'PASS: test isolation'
