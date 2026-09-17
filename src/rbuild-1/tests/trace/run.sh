#!/bin/sh
# Compare planned rbuild project flags with the legacy Perl header command.
set -e

here=$(cd "$(dirname "$0")" && pwd)
proj=$(cd "$here/../.." && pwd)
shim="$here/shim"
chmod a+x "$shim"/*
perltool="$proj/../buildtools-2/tools/darwin-buildpackage.pl"
perllib="$proj/../buildtools-2/lib"
scriptlib="$proj/../dpkg_scriptlib-1/perl5"
src="$here/fixtures/pkgsrc/foo-1.0"
thin_src="$here/fixtures/pkgsrc/thin-1.0"
seed=/tmp/rb_trace_seed
dst=/tmp/rb_trace_dst
rm -rf "$seed" "$dst"
mkdir -p "$seed" "$dst"

# Empty APKs are planning fixtures for rbuild -n, never validated artifacts.
# The unmodified Perl oracle uses .deb stubs and extraction shims to reach
# its first header command. Actual package validation has separate tests.
basedeps="cc cctools gnumake pb-makefiles coreosmakefiles project-makefiles \
zsh tcsh file-cmds text-cmds shell-cmds developer-cmds awk grep gnutar \
patch-cmds libsystem libc-hdrs architecture-hdrs kernel-hdrs csu objc4-hdrs \
files basic-cmds bootstrap-cmds system-cmds"
for d in $basedeps; do
  : > "$seed/$d-1.0-universal.apk"
  : > "$seed/${d}_1.0.deb"
done

# Reproduce buildtools' install-time Perl module layout in private scratch.
perloverlay=/tmp/rb_trace_perllib
rm -rf "$perloverlay"
mkdir -p "$perloverlay/Dpkg/Package"
ln -s "$perllib/Builder.pm" "$perloverlay/Dpkg/Package/Builder.pm"
ln -s "$perllib/Manifest.pm" "$perloverlay/Dpkg/Package/Manifest.pm"
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

# Perl has no -n. It prints the first project command before the real
# chroot fails in the stub root; absence of that command is a test failure.
RBUILD_TRACE=/tmp/rb_trace_perl.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" PERL5LIB="$perloverlay:$scriptlib" \
    perl "$perltool" --dir "$src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1 || true
rm -rf "$projroot"

# Select the project target, not the architecture: probe.o/probe commands
# cannot enter this comparison. Preserve whitespace inside quoted values.
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
extract /tmp/rb_trace_rbuild.log | sort -u > /tmp/rb_trace_rbuild.flags
extract /tmp/rb_trace_perl.log | sort -u > /tmp/rb_trace_perl.flags
if test ! -s /tmp/rb_trace_rbuild.flags || test ! -s /tmp/rb_trace_perl.flags; then
  echo "TRACE ERROR: failed to extract project make flags"
  exit 1
fi
echo "=== project header flag diff (rbuild plan vs Perl command) ==="
diff -u /tmp/rb_trace_perl.flags /tmp/rb_trace_rbuild.flags

# Independent exact assertions for an explicitly thin ordinary source.
RBUILD_TRACE=/tmp/rb_trace_thin.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" -n buildpackage \
    --dir --target all "$thin_src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1
extract "$RBUILD_TRACE" > /tmp/rb_trace_thin.flags
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
echo "TRACE MATCH: universal project flags identical; thin policy and dry-run verified"
