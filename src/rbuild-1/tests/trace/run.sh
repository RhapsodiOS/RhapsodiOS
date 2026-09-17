#!/bin/sh
# rbuild dry-run: universal probes, thin RC_*, no live-host seeds, no build root.
set -e

here=$(cd "$(dirname "$0")" && pwd)
proj=$(cd "$here/../.." && pwd)
shim="$here/shim"
chmod a+x "$shim"/*
src="$here/fixtures/pkgsrc/foo-1.0"
thin_src="$here/fixtures/pkgsrc/thin-1.0"
seed=/tmp/rb_trace_seed
dst=/tmp/rb_trace_dst
rm -rf "$seed" "$dst"
mkdir -p "$seed" "$dst"

# Empty APKs are planning fixtures for rbuild -n, never validated artifacts.
basedeps="cc cctools gnumake pb-makefiles coreosmakefiles project-makefiles \
zsh tcsh file-cmds text-cmds shell-cmds developer-cmds awk grep gnutar \
patch-cmds libsystem libc-hdrs architecture-hdrs kernel-hdrs csu objc4-hdrs \
files basic-cmds bootstrap-cmds system-cmds"
for d in $basedeps; do
  : > "$seed/$d-1.0-universal.apk"
done

projroot=/private/tmp/roots/foo-1.0-1.0.roots
thinroot=/private/tmp/roots/thin-1.0-1.0.roots
rm -rf "$projroot" "$thinroot"

RBUILD_TRACE=/tmp/rb_trace_rbuild.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" -n buildpackage \
    --dir --target all "$src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1
if test -e "$projroot"; then
  echo "TRACE ERROR: rbuild dry-run created its build root"
  exit 1
fi
for forbidden in /usr/lib/dyld /lib/crt1.o /usr/bin/strip.real /build/bin; do
  if grep "$forbidden" "$RBUILD_TRACE" >/dev/null 2>&1; then
    echo "TRACE ERROR: rbuild referenced live-host bootstrap seed: $forbidden"
    exit 1
  fi
done
for arch in i386 ppc; do
  for stage in compile link; do
    grep "^probe $arch $stage$" "$RBUILD_TRACE" >/dev/null
  done
done

extract() {
  perl -ne 'if (/((?:chroot|make) .*\binstallhdrs)\s*$/) {
      print "$1\n"; exit;
    }' "$1" \
    | sed -f "$here/normalize.sed" \
    | perl -ne 'while (/"([^"]*)"|(\S+)/g) {
          my $t = defined($1) ? $1 : $2;
          print "$t\n" if $t =~ /=/;
        }'
}

RBUILD_TRACE=/tmp/rb_trace_thin.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" -n buildpackage \
    --dir --target all "$thin_src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1
extract "$RBUILD_TRACE" > /tmp/rb_trace_thin.flags
if test ! -s /tmp/rb_trace_thin.flags; then
  echo "TRACE ERROR: failed to extract thin project make flags"
  exit 1
fi
grep '^RC_ARCHS=i386$' /tmp/rb_trace_thin.flags >/dev/null
grep '^RC_i386=YES$' /tmp/rb_trace_thin.flags >/dev/null
grep '^RC_ppc=$' /tmp/rb_trace_thin.flags >/dev/null
expected='RC_CFLAGS=-arch i386  -Dunix -D__unix -D__unix__ -DNX_COMPILER_RELEASE_3_0=300 -DNX_COMPILER_RELEASE_3_1=310 -DNX_COMPILER_RELEASE_3_2=320 -DNX_COMPILER_RELEASE_3_3=330 -DNX_CURRENT_COMPILER_RELEASE=520 -DNS_TARGET=52 -DNS_TARGET_MAJOR=5 -DNS_TARGET_MINOR=2 -DNeXT -D__NeXT -D__NeXT__ -D_NEXT_SOURCE'
actual=$(grep '^RC_CFLAGS=' /tmp/rb_trace_thin.flags)
test "$actual" = "$expected"
grep '^probe i386 compile$' "$RBUILD_TRACE" >/dev/null
grep '^probe i386 link$' "$RBUILD_TRACE" >/dev/null
if grep '^probe ppc ' "$RBUILD_TRACE" >/dev/null || test -e "$thinroot"; then
  echo "TRACE ERROR: thin plan selected PPC or wrote its build root"
  exit 1
fi
echo "TRACE MATCH: universal probes and thin policy verified (rbuild APK dry-run)"
