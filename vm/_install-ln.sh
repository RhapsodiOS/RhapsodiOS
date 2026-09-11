#!/bin/sh
# Install HFS-safe ln + tolerant strip into /build/bin (first on rbuild PATH).
# Also wrap /usr/bin/strip: many makefiles invoke it by absolute path.
mkdir -p /build/bin

install_strip_wrapper() {
  dest="$1"
  cat > "$dest" <<'EOF'
#!/bin/sh
# Bootstrap strip: full -s strip fails on some newly-linked binaries
# ("indirect symbol table entries that can't be stripped"); install -s
# then removes the target. Prefer -S; never fail the install.
REAL=/usr/bin/strip.real
if [ ! -x "$REAL" ]; then
  REAL=/bin/strip
fi
if [ ! -x "$REAL" ]; then
  exit 0
fi
if "$REAL" "$@" 2>/dev/null; then
  exit 0
fi
files=
for a in "$@"; do
  case "$a" in
    -*) ;;
    *) files="$files $a" ;;
  esac
done
if [ -n "$files" ]; then
  "$REAL" -S $files 2>/dev/null || true
fi
exit 0
EOF
  chmod a+x "$dest"
}

# Backup host strip once, then install wrapper at /usr/bin/strip
if [ -x /usr/bin/strip ] && [ ! -x /usr/bin/strip.real ]; then
  # Only backup if it does not look like our wrapper
  if ! grep -q 'Bootstrap strip' /usr/bin/strip 2>/dev/null; then
    cp -p /usr/bin/strip /usr/bin/strip.real
  fi
fi
install_strip_wrapper /build/bin/strip
install_strip_wrapper /usr/bin/strip
echo "installed strip wrappers (/build/bin/strip, /usr/bin/strip)"

cat > /build/bin/ln <<'EOF'
#!/bin/sh
# Usage mirrors ln(1) enough for install: ln [-f] [-s] source target
force=
symbolic=
while [ $# -gt 0 ]; do
  case "$1" in
    -f) force=1; shift ;;
    -s) symbolic=1; shift ;;
    --) shift; break ;;
    -*) shift ;; # ignore other flags
    *) break ;;
  esac
done
if [ $# -lt 2 ]; then
  echo "usage: ln [-f] [-s] source target" >&2
  exit 1
fi
# last arg is target; rest are sources (we only need 1:1 for bootstrap)
src=
while [ $# -gt 1 ]; do
  src="$1"
  shift
done
dst="$1"
if [ -n "$force" ] && [ -e "$dst" -o -L "$dst" ]; then
  rm -rf "$dst"
fi
if [ -n "$symbolic" ]; then
  if /bin/ln -s "$src" "$dst" 2>/dev/null; then
    exit 0
  fi
  # Install scripts often re-ln without -f; replace existing link/file.
  if [ -e "$dst" -o -L "$dst" ]; then
    rm -rf "$dst"
    /bin/ln -s "$src" "$dst" && exit 0
  fi
  exit 1
fi
if /bin/ln "$src" "$dst" 2>/dev/null; then
  exit 0
fi
# HFS / cross-device / directory: prefer symlink (make_links wants a name),
# else recursive copy.
if /bin/ln -s "$src" "$dst" 2>/dev/null; then
  exit 0
fi
if [ -d "$src" ]; then
  cp -Rp "$src" "$dst"
else
  cp -p "$src" "$dst"
fi
EOF
chmod a+x /build/bin/ln
echo "installed /build/bin/ln"
/build/bin/ln -f /bin/sh /tmp/ln-test-$$ && rm -f /tmp/ln-test-$$ && echo "ln ok"
# directory fallback smoke test
rm -rf /tmp/ln-dir-src-$$ /tmp/ln-dir-dst-$$
mkdir -p /tmp/ln-dir-src-$$/sub
echo x > /tmp/ln-dir-src-$$/sub/f
/build/bin/ln -f /tmp/ln-dir-src-$$ /tmp/ln-dir-dst-$$ && \
  test -f /tmp/ln-dir-dst-$$/sub/f && echo "ln dir ok"
rm -rf /tmp/ln-dir-src-$$ /tmp/ln-dir-dst-$$
