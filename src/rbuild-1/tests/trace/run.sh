#!/bin/sh
# Command-trace comparison: Perl darwin-buildpackage vs rbuild buildpackage.
set -e

here=$(cd "$(dirname "$0")" && pwd)
proj=$(cd "$here/../.." && pwd)     # src/rbuild-1
shim="$here/shim"
perltool="$proj/../buildtools-2/tools/darwin-buildpackage.pl"
perllib="$proj/../buildtools-2/lib"
scriptlib="$proj/../dpkg_scriptlib-1/perl5"

src="$here/fixtures/pkgsrc/foo-1.0"
seed=/tmp/rb_trace_seed
dst=/tmp/rb_trace_dst
rm -rf "$seed" "$dst"; mkdir -p "$seed" "$dst"

# Both oracles expand the "build-base" meta-dependency to the same fixed
# basedeps list (Builder.pm:619-644 / builder.c:basedeps) and refuse to
# proceed past dependency resolution if any of them is missing from the
# repository. Seed stub dependency packages for both packaging conventions
# so each tool gets past makeroot() and actually reaches the chroot/make
# step we want to compare -- the stub files themselves are part of the
# packaging backend (dpkg .deb "name_version.deb" vs apk "name-version.apk"),
# which is out of scope for the compared subset, so their exact naming
# doesn't matter beyond satisfying each tool's own resolver.
basedeps="cc cctools gnumake pb-makefiles coreosmakefiles project-makefiles \
zsh tcsh file-cmds text-cmds shell-cmds developer-cmds awk grep gnutar \
libsystem libc-hdrs architecture-hdrs kernel-hdrs csu objc4-hdrs files \
basic-cmds bootstrap-cmds system-cmds"
for d in $basedeps; do
  : > "$seed/$d-1.0.apk"
  : > "$seed/${d}_1.0.deb"
done

# The Perl oracle's "use Dpkg::Package::Builder;" / "Dpkg::Package::Manifest"
# resolve against the SOURCE tree's flat lib/ layout, but Perl requires them
# under a Dpkg/Package/ subdirectory (that nesting only exists after
# buildtools-2's own `make install`, per its Makefile: "cp -p lib/*.pm
# $(d)/usr/lib/perl5/Dpkg/Package"). Recreate that install-time layout with
# symlinks in scratch space so the unmodified darwin-buildpackage.pl can run
# straight from the checked-out source tree.
perloverlay=/tmp/rb_trace_perllib
rm -rf "$perloverlay"; mkdir -p "$perloverlay/Dpkg/Package"
ln -s "$perllib/Builder.pm" "$perloverlay/Dpkg/Package/Builder.pm"
ln -s "$perllib/Manifest.pm" "$perloverlay/Dpkg/Package/Manifest.pm"

# Neither oracle overrides BUILDIT_DIR, so both fall to the hard-coded
# default "/private/tmp/roots" (normalize.sed assumes exactly this literal
# path). The mkdir shim actually creates directories there (see shim/mkdir),
# so reset that one project-specific subtree to a clean state before each
# run -- otherwise the second run would see build-root state (e.g. an
# already-populated var/adm/package-list) left over from the first.
projroot=/private/tmp/roots/foo-1.0-1.0.roots
rm -rf "$projroot"

# Both oracles reset $PATH to a fixed "/sbin:/usr/sbin:/bin:/usr/bin:
# /usr/local/bin" immediately before the chroot+make step (Builder.pm:849,
# builder.c run_make()) -- a deliberate, matching design choice, not a bug --
# so the shim dir is no longer first on PATH for that one exec and the REAL
# /usr/sbin/chroot runs (and fails: "Operation not permitted", since we are
# not root). That command is still fully captured, though: both oracles
# unconditionally print the exact argv (via exec_printcmd()/&printcmd()) to
# their own stdout right before running it. So tee each run's stdout+stderr
# into the same trace log alongside the shim-log lines from the earlier
# (still-shimmed) steps.

# --- rbuild trace ---
RBUILD_TRACE=/tmp/rb_trace_rbuild.log
export RBUILD_TRACE
: > "$RBUILD_TRACE"
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" buildpackage --dir "$src" "$seed" "$dst" ) 2>&1 \
    | tee -a "$RBUILD_TRACE" >/dev/null || true

rm -rf "$projroot"

# --- perl trace ---
RBUILD_TRACE=/tmp/rb_trace_perl.log
export RBUILD_TRACE
: > "$RBUILD_TRACE"
( cd "$here" && PATH="$shim:$PATH" PERL5LIB="$perloverlay:$scriptlib" \
    perl "$perltool" --dir "$src" "$seed" "$dst" ) 2>&1 \
    | tee -a "$RBUILD_TRACE" >/dev/null || true

rm -rf "$projroot"

# --- compare the backend-agnostic subset: the chroot/make invocation ---
# Match the shim-log form ("chroot ..." / "make ..." at start of line) as
# well as the printed-stdout form, which is prefixed with "UNAME_SYSNAME=
# Rhapsody PATH=... " (or, for Perl's "install" branch specifically, a
# same-effect but literally PATH=-less "UNAME_SYSNAME=Rhapsody /sbin:..."
# label -- a harmless print-string typo in the unmodified Perl itself; the
# $ENV{'PATH'} assignment right above it is unaffected). Extract from
# "chroot"/"make" onward so that cosmetic prefix never enters the diff.
#
# Both oracles' printcmd()/exec_printcmd() quote any argv word containing
# whitespace in double quotes and leave the rest bare (exec.c:exec_printcmd,
# Builder.pm:95 printcmd), with no embedded quotes/escaping in any flag
# value we ever produce. That makes the traced line exactly reversible: a
# quoted-or-bare-word tokenizer recovers the real argv, including
# multi-word values like RC_CFLAGS/RC_ARCHS whose internal spacing (e.g.
# the double space after "ppc") must be preserved, not collapsed, since
# collapsing it would hide the very thing being compared.
extract() {
  grep -oE '(chroot|make) .*' "$1" \
    | sed -f "$here/normalize.sed" \
    | perl -ne 'while (/"([^"]*)"|(\S+)/g) {
          my $t = defined($1) ? $1 : $2;
          print "$t\n" if $t =~ /=/;
        }' \
    | sort -u
}
extract /tmp/rb_trace_rbuild.log > /tmp/rb_trace_rbuild.flags
extract /tmp/rb_trace_perl.log   > /tmp/rb_trace_perl.flags

echo "=== make/chroot flag diff (rbuild vs perl) ==="
if diff -u /tmp/rb_trace_perl.flags /tmp/rb_trace_rbuild.flags; then
  echo "TRACE MATCH: make flags identical"
else
  echo "TRACE DIFF: make flags differ (review above)"
  exit 1
fi
