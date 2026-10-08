#!/bin/sh
# Exercise the actual wrapper before its configure boundary. A private child
# queries the vendor's real make rule, then stops before any compiler work.
set -e
wrapper=$1
vendor=$2
work=$3
test -f "$wrapper" && test -f "$vendor/MCONFIG.in"
test ! -e "$work"
mkdir -p "$work"
wrapper=`cd "\`dirname "$wrapper"\`" && pwd`/`basename "$wrapper"`
vendor=`cd "$vendor" && pwd`
work=`cd "$work" && pwd`
failures=0
for kind in older current; do
    source="$work/$kind"
    mkdir "$source"
    # Preserve the actual pinned upstream dependency and recipe, not a model.
    sed -n '/^$(top_srcdir)\/configure:/ { p; n; p; }' "$vendor/MCONFIG.in" > "$source/rule.mk"
    test -s "$source/rule.mk"
    echo 'echo i386-apple-rhapsody5.3' > "$source/config.guess"
    echo 'private configure input' > "$source/configure.in"
    cat > "$source/configure" <<'EOF'
source=`dirname "$0"`
/bin/gnumake -q -f "$source/rule.mk" top_srcdir="$source" "$source/configure"
status=$?
echo "$status" > "$source/question.status"
if test "$status" = 0; then exit 72; else exit 73; fi
EOF
    touch -t 200101010000 "$source/configure.in"
    if test "$kind" = older; then
        touch -t 200001010000 "$source/configure"
    else
        touch -r "$source/configure.in" "$source/configure"
    fi
    cksum "$source/configure" "$source/configure.in" > "$source/before.cksum"
    set +e
    /bin/sh "$wrapper" "$source" "$work/objects-$kind" "$work/destination-$kind" 'i386 ppc' > "$source/wrapper.log" 2>&1
    status=$?
    set -e
    cksum "$source/configure" "$source/configure.in" > "$source/after.cksum"
    if test "$status" = 72 && test "`cat "$source/question.status"`" = 0 && cmp "$source/before.cksum" "$source/after.cksum"; then
        echo "CONFIGURE_ORDER_PASS $kind wrapper=$status dependency=0 bytes_unchanged"
    else
        failures=`expr "$failures" + 1`
        echo "CONFIGURE_ORDER_FAIL $kind wrapper=$status expected=72"
        cat "$source/wrapper.log"
    fi
done
echo "CONFIGURE_ORDER cases=2 failures=$failures"
test "$failures" = 0
