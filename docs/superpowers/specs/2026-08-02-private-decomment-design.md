# Private Stage-Zero Decomment Design

## Goal

Build the source-owned `decomment` generator privately with the configured GCC-based build compiler, bind it only during bootstrap, and make kernel header export fail when its `unifdef` fallback cannot run. A missing generator must never produce an accepted incomplete header package.

## Ownership and existing behavior

`Commands/bootstrap_cmds/decomment.tproj` owns a single C source, `decomment.c`. Its historical Project Builder product installs at `/usr/local/bin/decomment`. Kernel generated makefiles currently hardcode that path and invoke it only when `unifdef` reports that it changed an exported header. Both machine-independent and machine-dependent export recipes ignore the outer loop status and continue after a failed fallback, allowing an empty `.strip` file to be treated as a deliberately unexported header.

## Design

The canonical rbuild phase compiles `decomment.c` directly to `ToolsDir/bin/decomment` with the selected profile's `build_cc`, using the same private stage-zero pattern as `relpath`. It immediately exercises block-comment, end-of-line-comment, and whitespace removal against a fixed input. Preflight requires the source file before any remote mutation.

The bootstrap phase exports `DECOMMENT=ToolsDir/bin/decomment` inline with `CONFIG_DIR`, `MIGCC`, `MIGARCH`, and `MIGCOM_DIR`. Kernel `Makefile.template` changes its historical assignment to `DECOMMENT ?= /usr/local/bin/decomment`, so the configured environment binding wins during bootstrap while unconfigured and later chroot builds retain the historical target default. No PATH lookup, live-host copy, sysroot fallback, or target install is added.

Both kernel export loops explicitly fail when fallback decommenting fails, propagate the header-directory subshell status to the outer loop, and no longer tell make to ignore the recipe result. `unifdef` status 1 remains expected and selects decomment; a successful fallback continues normally.

## Verification

PowerShell tests assert preflight source ownership, configured and alternate/spaced compiler builds, private product smoke, bootstrap-only binding, safe quoting, and absence of live/sysroot decomment selection in generated commands. Kernel source-contract tests cover the overrideable historical default and both export loops. A shell behavioral fixture exercises the same fallback/subshell contract with successful, missing, and failing decomment tools. Existing PowerShell, focused C, shell syntax, PowerShell parser, and diff gates must remain green. Remote bootstrap is outside this change.
