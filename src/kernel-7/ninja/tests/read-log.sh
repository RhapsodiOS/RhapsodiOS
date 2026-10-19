#!/bin/sh
set -eu
test -r "$1"
# Native tail maps regular files; keep growing logs off that path.
cat "$1" | tail -n "${2-20}"
