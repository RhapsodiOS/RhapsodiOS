# driverLoader binary reconstruction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put `driverLoader` back into `src/driverkit-3` as source, build it fat (i386 + ppc) against libDriver's dylib, and drive both slices to function-level parity with Apple's DR2 i386 and MOSXS 1.2v3 ppc binaries. Then prove the i386 slice behaves like Apple's on a guest.

**Architecture:** A handwritten `driverLoader/` subproject in driverkit-3 compiles two owned files, `driverLoader.m` and `kl_com.m`. For each CPU it links `libDriver.A.dylib` from the same build plus `-lkernload`, then `lipo`s the slices. binrecon compares each thin slice with its reference, using IDA 9.2 (plus angr on i386). Rebuilds are universal `rbuild buildpackage` runs on a private `-snapshot` i386 guest. A side-by-side guest script and two guest boots check behaviour.

**Tech Stack:** Objective-C / C for NeXT gcc 2.x, GNU make 3.74, `lipo`, `mig`, rbuild, QEMU i386 DR2 guest, `tools/binrecon` (Python 3, IDA 9.2 `idat.exe`, angr 9.3.0), PowerShell `vm/*.ps1` over legacy OpenSSH.

**Spec:** [2026-09-27-driverloader-binary-reconstruction-design.md](../specs/2026-09-27-driverloader-binary-reconstruction-design.md)

## Global Constraints

- **References, never modified.** i386: `C:\Users\raynorpat\Downloads\test\DR2\usr\sbin\driverLoader`, SHA-256 `e005522ec2e4f107b8071a573ccda9208d49e64e2114d08b8868ee956a0e98b7`, 70132 bytes. ppc: `C:\Users\raynorpat\Downloads\test\MOSXS12v3\usr\sbin\driverLoader`, SHA-256 `cd8dd33035aae133ce4ab1d6a203807cbceabc3d5d300326ff105ad33d9d3e14`, 40776 bytes. If a SHA differs, stop.
- **Shared images, never written.** `D:\RhapsodiOS\vm\work\rhap-i386-bootstrapped.img` is only ever booted with `-snapshot` or opened `rb`. `C:\Users\raynorpat\Downloads\rhapsody.img` is only opened `rb`.
- **Guest discipline.** One private guest, one ssh session at a time, no polling loops. If the guest freezes, stop guest work and ask Pat.
- **Names.** Every function, static and global keeps Apple's symbol name. No invented names.
- **Link shape.** Link libDriver dynamically on both slices (`/usr/lib/libDriver.A.dylib` before System) and libkernload statically.
- **Install shape.** `/usr/sbin/driverLoader` mode `0555`, **not stripped**; `/usr/share/man/man8/driverLoader.8` mode `0444`.
- **No source-shape edit without evidence.** Every parity edit cites a `binrecon function --name` dump of the named function on the slice it targets. Fixing one slice must not regress the other.
- **Accepts** are compiler-shaped leftovers only (register allocation, instruction scheduling), recorded in `divergences.md` with the dump(s). Reviewer on ledger accepts: `Pat Raynor`.
- **Do not grind** `__text` size. `cfg_equal` is not a pass.
- **Legacy bytes.** Before editing any file copied from the tree, run `grep -P '[\x80-\xff]' <file>`. If it matches, edit through latin-1 (see memory `legacy-sources-mac-roman-bytes`), never the Edit tool.
- **Make 3.74.** No target-specific variables. A later duplicate rule wins silently.
- **Commits.** Subject prefix `driverkit: ` for driverkit-3 files, `kernload: ` for kernload-1, `binrecon: ` for profiles, `vm: ` for guest scripts, `docs: ` for docs. One or two lines, then the attribution line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage explicit paths only. Never commit `out/`, `tools/binrecon/out/`, rebuilt binaries, `vm/vm.conf`, or IDA databases.

## Review Focus

1. **`D=` for a driver name with no config directory.** Expect the same output and exit status as Apple's copy. It is the commonest typo at a shell, and it runs `prePostExec`, `loadDriver` and `configDriver` on missing files. Pinned by the `nodriver` behaviour case (Task 2).
2. **A Pre-Load that fails, or that names an absolute or `..` path.** Expect the abort message and exit 1 for the first, and a silent exit 1 for the second, both as Apple does. Pinned by `preload-fail` and `preload-abs` (Task 2).
3. **Interactive use answered "no" throughout.** `d=` and `i` must ask the same questions in the same order and change nothing. Pinned by `interactive-d` and `interactive-i` (Task 2).
4. **Running under our `libDriver.A.dylib` instead of DR2's static libDriver.** `IOConfigTable` reads tables through different code. Every behaviour case runs the rebuilt binary against our dylib, and the boot test (Task 8) runs `driverLoader a` with it.
5. **No display driver found at boot.** `main` falls back to loading `VGA`. The boot test's guest has a Cirrus display in `Active Drivers`, so the fallback must stay silent there. Task 8 checks the rebuilt boot log for any `No display driver added` line.

---

## File map

| File | Responsibility |
|---|---|
| `tools/binrecon/profiles/driverloader.json` | New. i386 profile: IDA + angr, Ghidra off. |
| `tools/binrecon/profiles/driverloader-ppc.json` | New. ppc profile: IDA only, with a rebuilt path. |
| `src/driverkit-3/driverLoader/reconstruction/nlist.md` | New. Both references' symbols, the owned set, and the linking finding. |
| `vm/driverloader-behaviour.sh` | New. Guest script: side-by-side behaviour cases. |
| `vm/build-driverkit-driverloader.sh` | New. Guest script: universal rbuild of driverkit, then split driverLoader's slices. |
| `vm/driverloader-boot.sh` | New. Guest script: install a driverLoader for the boot test, arm `Active Drivers`, reboot. |
| `vm/driverloader-boot-check.sh` | New. Guest script: collect post-boot evidence. |
| `src/driverkit-3/driverLoader/Makefile` | New. Per-CPU compile, link against libDriver's dylib and `-lkernload`, `lipo`, install. |
| `src/driverkit-3/driverLoader/driverLoader.m` | New. Owned group 1. |
| `src/driverkit-3/driverLoader/kl_com.m`, `kl_com.h` | New, copied from `Examples/loadable/User`. Owned group 2. |
| `src/driverkit-3/driverLoader/driverLoader.8` | New. Apple's man page, byte for byte. |
| `src/driverkit-3/Makefile` | `SUBDIR` and `INSTALL_SUBDIR` gain `driverLoader`. |
| `src/driverkit-3/PB.project` | `SUBPROJECTS` gains `driverLoader`. |
| `src/driverkit-3/apk/pkginfo` | `makedepends` gains `kernload-hdrs, kernload`. |
| `src/driverkit-3/driverLoader/reconstruction/{i386,ppc}/{ledger,source-map}.json` | Per-slice ledgers. |
| `src/driverkit-3/driverLoader/reconstruction/divergences.md`, `function-worklist.md` | Accepts, and campaign state. |
| `src/kernload-1/libkernload/*` | Only if a libkernload parity fix is needed (Task 6). |

## Paths and environment

The worktree root is `<W>` = `D:\RhapsodiOS\.claude\worktrees\ecstatic-haslett-27a306`. Run host commands from `<W>` in Git Bash unless a step says PowerShell.

```bash
export PYTHONPATH=tools/binrecon
PY=.venv-binrecon/Scripts/python.exe
REF_I386='C:\Users\raynorpat\Downloads\test\DR2\usr\sbin\driverLoader'
REF_PPC='C:\Users\raynorpat\Downloads\test\MOSXS12v3\usr\sbin\driverLoader'
NEW_I386="$PWD/out/driverloader/driverLoader.i386"
NEW_PPC="$PWD/out/driverloader/driverLoader.ppc"
```

binrecon reads `BINRECON_REFERENCE` and `BINRECON_REBUILT`. Set them per invocation:

```bash
i386() { BINRECON_REFERENCE="$REF_I386" BINRECON_REBUILT="$NEW_I386" "$@"; }
ppc()  { BINRECON_REFERENCE="$REF_PPC"  BINRECON_REBUILT="$NEW_PPC"  "$@"; }
```

### Private guest

The guest is `vm/work/rhap-i386-bootstrapped.img` booted with `-snapshot`. It has ssh on host port **2231**, telnet on **2331** and QMP on **4471**, so it collides with neither the shared box (2222/4463) nor the other sessions' 2221/4461. Before the first boot, check the ports are free:

```bash
netstat -ano | grep -E ':(2231|2331|4471) ' || echo PORTS_FREE
```

Write the launcher `$S/dlguest.py`, where `$S` is this session's scratchpad directory. It is not committed.

```python
import os, subprocess, sys
S = os.path.dirname(os.path.abspath(__file__))
tag = sys.argv[1] if len(sys.argv) > 1 else "run"
logs = os.path.join(S, "guest-" + tag); os.makedirs(logs, exist_ok=True)
qemu = r"C:\Program Files\qemu\qemu-system-i386.exe"
args = [qemu, "-M", "pc", "-m", "256", "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", r"file=D:\RhapsodiOS\vm\work\rhap-i386-bootstrapped.img,format=raw,if=ide,index=0,media=disk",
        "-snapshot",
        "-netdev", "user,id=n0,net=10.10.0.0/16,host=10.10.0.1,dns=10.10.0.3,"
                   "hostfwd=tcp:127.0.0.1:2231-10.10.0.240:22,hostfwd=tcp:127.0.0.1:2331-10.10.0.240:23",
        "-device", "ne2k_pci,netdev=n0,addr=03.0,mac=52:54:00:12:34:56",
        "-serial", "file:" + os.path.join(logs, "com1.log"),
        "-serial", "file:" + os.path.join(logs, "kernel.log"),
        "-rtc", "base=1998-05-08T12:00:00",
        "-qmp", "tcp:127.0.0.1:4471,server=on,wait=off"]
flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
p = subprocess.Popen(args, creationflags=flags, stdin=subprocess.DEVNULL,
                     stdout=open(os.path.join(logs, "qemu.out"), "wb"), stderr=subprocess.STDOUT)
print("qemu pid", p.pid, "logs", logs)
```

Write `$S/dlqmp.py`, which sends one QMP command. It is not committed.

```python
import json, socket, sys
s = socket.create_connection(("127.0.0.1", 4471), timeout=30)
f = s.makefile("rw")
f.readline(); f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush(); f.readline()
cmd = sys.argv[1]
msg = {"execute": cmd} if cmd != "hmp" else {"execute": "human-monitor-command", "arguments": {"command-line": sys.argv[2]}}
f.write(json.dumps(msg) + "\n"); f.flush(); print(f.readline().strip())
```

Boot with `python "$S/dlguest.py" build`. The kernel is up in about a minute and sshd a couple of minutes later. Make one ssh attempt after 180 seconds (`sleep 180` in a background shell, then one command). Never loop on the port. Stop the guest with `python "$S/dlqmp.py" quit`. That kills only this QEMU. Never kill `qemu-system-i386.exe` by name.

The worktree's `vm/vm.conf` (gitignored) points the `vm/*.ps1` scripts at this guest. Create it once:

```bash
sed -e 's/^Port=.*/Port=2231/' -e 's|^RemoteRoot=.*|RemoteRoot=/build/dlr|' \
    -e 's|^# LocalRoot=.*|LocalRoot=D:\\RhapsodiOS\\.claude\\worktrees\\ecstatic-haslett-27a306|' \
    D:/RhapsodiOS/vm/vm.conf > vm/vm.conf
grep -E '^(Host|Port|RemoteRoot|LocalRoot)=' vm/vm.conf
```

Expected: `Host=127.0.0.1`, `Port=2231`, `RemoteRoot=/build/dlr`, and the worktree `LocalRoot`. It holds the guest password, so delete it in Task 9.

Guest commands:

- Run a script: `powershell -NoProfile -File vm/guest-remote.ps1 -Run <host path of script>`. The script's text is sent as the ssh command body and its output is printed at the end.
- Fetch a file: `MSYS_NO_PATHCONV=1 powershell -NoProfile -File vm/guest-remote.ps1 -Fetch /build/dlr/<file> -To out/driverloader/<file>`. `-To` must be a file path.
- Sync the driverkit source: `powershell -NoProfile -File vm/sync-src.ps1 -Path driverkit-3`. It writes `/build/dlr/src/driverkit-3`. `/build/dlr/src` must exist first.

Everything on a `-snapshot` guest disappears when QEMU exits. Fetch every build output as soon as it exists.

---

### Task 1: binrecon profiles, reference evidence and nlist

**Files:**
- Create: `tools/binrecon/profiles/driverloader.json`
- Create: `tools/binrecon/profiles/driverloader-ppc.json`
- Create: `src/driverkit-3/driverLoader/reconstruction/nlist.md`

**Interfaces:**
- Consumes: the two reference binaries.
- Produces: the profiles `driverloader.json` (output `tools/binrecon/out/driverloader`) and `driverloader-ppc.json` (output `tools/binrecon/out/driverloader-ppc`). Published reference analyses `published/analysis-reference-ida.json` under each output dir. Decompile dumps `tools/binrecon/out/driverloader/decompile/owned-{i386,ppc}.c` (ignored, used by Task 3).

- [ ] **Step 1: Link the binrecon venv into the worktree**

```bash
test -d .venv-binrecon || cmd //c mklink //J .venv-binrecon 'D:\RhapsodiOS\.venv-binrecon'
git check-ignore -v .venv-binrecon/x
.venv-binrecon/Scripts/python.exe -c "import angr; print(angr.__version__)"
```

Expected: the ignore rule comes from `.git/info/exclude`, and the version prints `9.3.0`.

- [ ] **Step 2: Confirm the reference hashes**

```bash
sha256sum "$REF_I386" "$REF_PPC"
```

Expected: `e005522e…0e98b7` and `cd8dd330…3e14` in full, as in Global Constraints. Stop if either differs.

- [ ] **Step 3: Write `driverloader.json`**

```json
{
  "schema_version": "profile-v1",
  "name": "driverLoader i386 reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/driverloader"
}
```

- [ ] **Step 4: Write `driverloader-ppc.json`**

```json
{
  "schema_version": "profile-v1",
  "name": "driverLoader ppc reconstruction",
  "architecture": "ppc",
  "endianness": "big",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": false,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/driverloader-ppc"
}
```

- [ ] **Step 5: Validate both profiles and analyze the references**

There is no rebuilt binary yet, so point `BINRECON_REBUILT` at the reference for these runs.

```bash
BINRECON_REFERENCE="$REF_I386" BINRECON_REBUILT="$REF_I386" $PY -m binrecon validate --profile tools/binrecon/profiles/driverloader.json
BINRECON_REFERENCE="$REF_PPC"  BINRECON_REBUILT="$REF_PPC"  $PY -m binrecon validate --profile tools/binrecon/profiles/driverloader-ppc.json
BINRECON_REFERENCE="$REF_I386" BINRECON_REBUILT="$REF_I386" $PY -m binrecon analyze --profile tools/binrecon/profiles/driverloader.json
BINRECON_REFERENCE="$REF_PPC"  BINRECON_REBUILT="$REF_PPC"  $PY -m binrecon analyze --profile tools/binrecon/profiles/driverloader-ppc.json
ls tools/binrecon/out/driverloader/published tools/binrecon/out/driverloader-ppc/published
```

Expected:
- `validate` prints each reference SHA.
- Each `run-summary.json` has `"complete": true`. An exit status of 1 is fine.
- `published/analysis-reference-ida.json` exists in both directories, and on i386 so does `analysis-reference-angr.json`.

- [ ] **Step 6: Dump both nlists and write the owned/imported split**

```bash
for side in i386:"$REF_I386" ppc:"$REF_PPC"; do
  name=${side%%:*}; path=${side#*:}
  $PY - "$path" > tools/binrecon/out/driverloader/nlist-$name.txt <<'EOF'
import sys
from pathlib import Path
from binrecon.macho import read_macho
m = read_macho(Path(sys.argv[1]))
for s in sorted(m['symbols'], key=lambda s: (s['address'], s['name'])):
    print('%-8s %-24s 0x%08x %s' % (s['binding'], s.get('section'), s['address'], s['name']))
EOF
  wc -l tools/binrecon/out/driverloader/nlist-$name.txt
done
```

Expected: 349 lines for i386 and 117 for ppc (one per symbol table entry). If `read_macho` names keys differently, print `m['symbols'][0]` and adjust the format keys. Do not change `binrecon`.

- [ ] **Step 7: Dump IDA decompiles of the owned functions on both slices**

Use the IDA MCP tools, with a scratch copy of each reference so IDA's `.i64` never lands in `Downloads\test`:

```bash
mkdir -p tools/binrecon/out/driverloader/decompile
cp "$REF_I386" tools/binrecon/out/driverloader/decompile/driverLoader.i386
cp "$REF_PPC"  tools/binrecon/out/driverloader/decompile/driverLoader.ppc
```

For each copy:
1. Open it with `mcp__plugin_ida-mcp_ida__open_database` using the absolute path.
2. Run this with `mcp__plugin_ida-mcp_ida__execute_python`, replacing `OUT` with `<W>/tools/binrecon/out/driverloader/decompile/owned-i386.c` or `owned-ppc.c`.
3. Close the database with `mcp__plugin_ida-mcp_ida__close_database`.

```python
import ida_hexrays, idc
OUT = r"OUT"
names = ["_main", "_usage", "_inquire", "_processDriverList", "_processDriver", "_loadDriver",
         "_unloadDriver", "_getInstanceFile", "_configDriver", "_securityCheck", "_securityCheckDir",
         "_prePostExec", "_kl_init", "_kl_com_log", "_print_string", "_ping", "_kl_com_add",
         "_kl_com_delete", "_kl_com_load", "_kl_com_unload", "_kl_com_get_state", "_kl_com_error",
         "_kl_com_wait"]
parts = []
for n in names:
    ea = idc.get_name_ea_simple(n)
    try:
        body = str(ida_hexrays.decompile(ea))
    except Exception as e:
        body = "/* decompile failed: %s */" % e
    parts.append("// ==== %s @ 0x%x\n%s\n" % (n, ea, body))
open(OUT, "w").write("\n".join(parts))
len(parts)
```

Expected: 23 on each slice, and neither file contains `decompile failed`.

- [ ] **Step 8: Write `nlist.md`**

Create `src/driverkit-3/driverLoader/reconstruction/nlist.md` with these sections, filled from Steps 5–7:

```markdown
# driverLoader reference nlists

Date: <today>

## References

| Slice | Path | SHA-256 | Size | `__text` |
|---|---|---|---|---|
| i386 (DR2) | `…\DR2\usr\sbin\driverLoader` | `e005522e…` (full) | 70132 | `0x3840`, 28940 |
| ppc (MOSXS 1.2v3) | `…\MOSXS12v3\usr\sbin\driverLoader` | `cd8dd330…` (full) | 40776 | `0x2acc`, 13080 |

## Owned code (both slices, same order)

<table: name, i386 address, ppc address, binding (global/static), for the 12
driverLoader functions, the 11 kl_com functions, and the globals/statics:
verbose, interactive, instruction, progName, kl_init_flag, kl_port,
kernel_task, reply_port, kern_loader_reply, ping_lock, strings.N>

## libkernload code (both slices)

<table: every kern_loader_* symbol, kern_loader_look_up,
kern_loader_reply_handler, error_message, with both addresses>

## libDriver

- ppc imports: <list the undefined libDriver symbols>
- i386 carries statically: <list every defined symbol from IOConfigTable
  through generalFuncs, with addresses>. These are the §3 accept set.

## Facts the source must reproduce

- `securityCheck` and `securityCheckDir` have no callers on either slice.
- `main`'s `D`/`d` case compares the option letter with `'u'`.
- `__cstring` holds `prePostExec: execString %s\n` and `   cwd %s\n`, but no
  decompiled code references them.
- ppc has a common `catch_exception_raise`; i386 does not.
```

Fill every `<…>` from the nlist files and decompiles. The committed file must contain no angle-bracket instructions.

- [ ] **Step 9: Commit**

```bash
git add tools/binrecon/profiles/driverloader.json tools/binrecon/profiles/driverloader-ppc.json \
        src/driverkit-3/driverLoader/reconstruction/nlist.md
git commit -m "binrecon: add driverLoader i386 and ppc profiles and the reference nlists

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Side-by-side behaviour harness (the test comes first)

**Files:**
- Create: `vm/driverloader-behaviour.sh`

**Interfaces:**
- Consumes: Apple's `/usr/sbin/driverLoader` on the guest, and a candidate binary with its `libDriver.A.dylib`.
- Produces: `vm/driverloader-behaviour.sh`. Its defaults are `REF=/usr/sbin/driverLoader`, `CAN=/build/dlr/x/usr/sbin/driverLoader` and `CANLIB=/build/dlr/x/usr/lib/libDriver.A.dylib`. It prints one `PASS <case>` or `FAIL <case>` per case, then `=== behaviour done fails=<n> ===`, and exits 0 only when every case passes.

- [ ] **Step 1: Write the harness**

POSIX Bourne shell only: no `local`, no `$(...)`, no `[[`. Use LF line endings.

```sh
#!/bin/sh
# Side-by-side driverLoader behaviour check for the i386 guest.
#
# Runs Apple's driverLoader and a candidate with the same arguments and stdin,
# on cases that load nothing into the kernel, and compares stdout+stderr and
# the exit status.  Rhapsody's /bin/sh is a 1999 Bourne shell: keep it plain.
#
# Environment overrides: REF (reference binary), CAN (candidate binary),
# CANLIB (the libDriver.A.dylib the candidate links).

REF=${REF:-/usr/sbin/driverLoader}
CAN=${CAN:-/build/dlr/x/usr/sbin/driverLoader}
CANLIB=${CANLIB:-/build/dlr/x/usr/lib/libDriver.A.dylib}
W=/tmp/dlbeh
D=/usr/Devices

for f in "$REF" "$CAN"; do
	if [ ! -f "$f" ]; then
		echo "driverloader-behaviour: missing $f"
		exit 2
	fi
done
# The rebuilt binary loads /usr/lib/libDriver.A.dylib, which DR2 lacks.
# Apple's DR2 binary needs nothing, so a missing CANLIB is not an error.
if [ ! -f /usr/lib/libDriver.A.dylib ] && [ -f "$CANLIB" ]; then
	cp "$CANLIB" /usr/lib/libDriver.A.dylib || exit 2
	chmod 555 /usr/lib/libDriver.A.dylib
fi

rm -rf $W
mkdir -p $W/ref $W/can $W/out
cp "$REF" $W/ref/driverLoader
cp "$CAN" $W/can/driverLoader
chmod 555 $W/ref/driverLoader $W/can/driverLoader

# mkcfg NAME PRELOAD [SCRIPT-BODY]: a scratch driver config with a Pre-Load.
mkcfg() {
	rm -rf $D/$1.config
	mkdir -p $D/$1.config
	printf '"Driver Name" = "%s";\n"Pre-Load" = "%s";\n' "$1" "$2" > $D/$1.config/Default.table
	if [ -n "$3" ]; then
		printf '#!/bin/sh\n%s\n' "$3" > $D/$1.config/$2
		chmod 555 $D/$1.config/$2
	fi
	chmod -R go-w $D/$1.config
}
mkcfg DLTestFail fail.sh 'exit 1'
mkcfg DLTestAbs /bin/false

fails=0
# run CASE STDIN ARGS...
run() {
	c=$1
	in=$2
	shift
	shift
	for s in ref can; do
		(cd $W/$s && printf "$in" | ./driverLoader "$@" > $W/out/$c.$s 2>&1
		 echo "exit=$?" >> $W/out/$c.$s)
	done
	if cmp -s $W/out/$c.ref $W/out/$c.can; then
		echo "PASS $c"
	else
		echo "FAIL $c"
		diff $W/out/$c.ref $W/out/$c.can
		fails=`expr $fails + 1`
	fi
}

run noargs ''
run badop '' x
run nodriver '' D=DLTestNone v
run preload-fail '' D=DLTestFail v
run preload-abs '' D=DLTestAbs v
run interactive-d 'n\nn\nn\nn\nn\n' d=BPF
run interactive-i 'n\nn\n' i

rm -rf $D/DLTestFail.config $D/DLTestAbs.config
echo "=== behaviour done fails=$fails ==="
if [ $fails = 0 ]; then
	exit 0
fi
exit 1
```

- [ ] **Step 2: Check its syntax on the host**

```bash
sh -n vm/driverloader-behaviour.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 3: Prove the harness on the guest with Apple against Apple**

Boot the private guest (see Private guest). Then run the harness with Apple's binary on both sides, which must pass, and against a missing candidate, which must refuse to run. Write the template `$S/beh-self.sh`:

```sh
mkdir -p /build/dlr/src
cat > /tmp/dlbeh.sh <<'EOH'
__HARNESS__
EOH
REF=/usr/sbin/driverLoader CAN=/usr/sbin/driverLoader sh /tmp/dlbeh.sh; echo "self rc=$?"
CAN=/build/dlr/none sh /tmp/dlbeh.sh; echo "missing rc=$?"
```

Splice the harness text into it:

```bash
python - "$S" <<'EOF'
import sys, pathlib
S = pathlib.Path(sys.argv[1])
h = pathlib.Path("vm/driverloader-behaviour.sh").read_text().replace("\r\n", "\n")
t = (S / "beh-self.sh").read_text().replace("__HARNESS__", h.rstrip("\n"))
(S / "beh-self.run.sh").write_text(t, newline="\n")
EOF
powershell -NoProfile -File vm/guest-remote.ps1 -Run "$S/beh-self.run.sh"
```

Expected:
- Seven `PASS` lines, `fails=0` and `self rc=0`.
- Then `driverloader-behaviour: missing /build/dlr/none` and `missing rc=2`.

If any case fails when Apple is compared with itself, the case is nondeterministic. Fix the case, not the binary, and re-run.

- [ ] **Step 4: Commit**

```bash
git add vm/driverloader-behaviour.sh
git commit -m "vm: add a side-by-side driverLoader behaviour check for the i386 guest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: driverLoader subproject, first universal build

**Files:**
- Create: `src/driverkit-3/driverLoader/Makefile`
- Create: `src/driverkit-3/driverLoader/driverLoader.m`
- Create: `src/driverkit-3/driverLoader/kl_com.m`, `src/driverkit-3/driverLoader/kl_com.h`
- Create: `src/driverkit-3/driverLoader/driverLoader.8`
- Modify: `src/driverkit-3/Makefile` (`SUBDIR`, `INSTALL_SUBDIR`)
- Modify: `src/driverkit-3/PB.project` (`SUBPROJECTS`)
- Modify: `src/driverkit-3/apk/pkginfo` (`makedepends`)
- Create: `vm/build-driverkit-driverloader.sh`

**Interfaces:**
- Consumes: Task 1's decompile dumps and nlist. Task 2's harness.
- Produces:
  - The driverkit apk `driverkit-139.1-<rel>-universal.apk`, which carries a fat `usr/sbin/driverLoader` and `usr/share/man/man8/driverLoader.8`.
  - Guest files `/build/dlr/driverLoader.i386` and `/build/dlr/driverLoader.ppc`, and the unpacked apk tree `/build/dlr/x`.
  - Host copies `out/driverloader/driverLoader.i386`, `driverLoader.ppc` and `driverkit-universal.apk`.

- [ ] **Step 1: Copy the kl_com module and the man page**

```bash
mkdir -p src/driverkit-3/driverLoader
cp src/driverkit-3/Examples/loadable/User/kl_com.m src/driverkit-3/driverLoader/kl_com.m
cp src/driverkit-3/Examples/loadable/User/kl_com.h src/driverkit-3/driverLoader/kl_com.h
cp 'C:\Users\raynorpat\Downloads\test\DR2\usr\share\man\man8\driverLoader.8' src/driverkit-3/driverLoader/driverLoader.8
sha256sum src/driverkit-3/driverLoader/driverLoader.8
grep -P '[\x80-\xff]' src/driverkit-3/driverLoader/kl_com.m src/driverkit-3/driverLoader/kl_com.h || echo ASCII
```

Expected: the man page SHA is `0049722e66fc99474a26134640c23664fe11f035719843c0669d46ce644c0b97`, and the grep prints `ASCII`.

Compare `kl_com.m` with `owned-i386.c` and `owned-ppc.c` function by function. Make only these edits, each backed by what both decompiles show:
- `kl_com_error` is local (binding `0e`) in both references. Make its definition `static void`, matching its prototype.
- Keep `kern_loader_reply`, `kl_port`, `kernel_task`, `reply_port` and `kl_init_flag` global, and `ping_lock` and `kl_init` static, as the nlist shows.

Leave the other functions as copied. Task 5 drives them to parity.

- [ ] **Step 2: Write `driverLoader.m`**

This is the first draft, written from `owned-i386.c` and `owned-ppc.c`. Where a comment says to check a dump, check it before the first build and adjust the line. The C shape, not the comment, is what gets compared.

```objc
/*
 * driverLoader.m - load or configure DriverKit drivers after boot.
 *
 * Reconstructed from Apple's Rhapsody DR2 (i386) and Mac OS X Server
 * 1.2v3 (ppc) binaries; see reconstruction/ in this directory.
 */

#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import <driverkit/driverServer.h>
#import <mach/mach.h>
#import <bsd/sys/types.h>
#import <bsd/sys/stat.h>
#import <bsd/sys/dir.h>
#import <bsd/libc.h>
#import <ansi/stdio.h>
#import <ansi/string.h>
#import "kl_com.h"

#define DEVICE_DIR	"/usr/Devices/"
#define CONFIG_EXT	".config"
#define RELOC_EXT	"_reloc"
#define TABLE_EXT	".table"
#define DEFAULT_TABLE	"Default.table"

/* prePostExec's return codes, as main/processDriver/configDriver test them */
#define PP_OK		0
#define PP_FAILED	2	/* the Pre-/Post-Load file returned non-zero */
#define PP_REFUSED	3	/* absolute or ".." path: never run */

int verbose = 0;		/* check width: byte or long accesses in the dumps */
int interactive = 0;
static int instruction = 0;
char *progName;

static void usage(char **argv);
static BOOL inquire(const char *question);
static int processDriverList(const char *list, BOOL isBoot, BOOL load);
static int processDriver(const char *driverName, BOOL isBoot, BOOL load);
static int loadDriver(const char *driverName);
static int unloadDriver(const char *driverName);
static int getInstanceFile(const char *driverName, char *path, int unit,
	struct stat *statBuf);
static int configDriver(const char *driverName, int unit, BOOL probe,
	BOOL runPreLoad);
static BOOL securityCheck(const char *driverName);
static BOOL securityCheckDir(char *dir);
static int prePostExec(const char *driverName, int unit, BOOL post);

int
main(int argc, char **argv)
{
	int i;
	const char *driverName = NULL;
	BOOL load = YES;
	id systemTable, deviceMaster;
	const char *list;
	BOOL haveDisplay;
	IOObjectNumber objectNumber;
	IOString deviceKind;

	if (argc <= 1)
		usage(argv);
	progName = argv[0];
	for (i = 1; i < argc; i++) {
		switch (argv[i][0]) {
		    case 'D':
		    case 'd':
			/* both references compare the letter with 'u' here;
			 * check the jump table in the dumps for a 'u' case */
			driverName = argv[i] + 2;
			interactive = (argv[i][0] == 'd');
			load = (argv[i][0] != 'u');
			break;
		    case 'a':
			continue;
		    case 'i':
			interactive = 1;
			break;
		    case 'v':
			verbose = 1;
			break;
		    default:
			usage(argv);
		}
	}
	if (driverName != NULL)
		return processDriver(driverName, NO, load);

	systemTable = [IOConfigTable newFromSystemConfig];
	if (systemTable == nil) {
		fprintf(stderr, "%s: can't get system config table\n", argv[0]);
		exit(1);
	}
	if (inquire("Configure Boot Drivers")) {
		list = [systemTable valueForStringKey:"Boot Drivers"];
		if (list == NULL) {
			fprintf(stderr, "%s: can't get Boot Driver list\n", argv[0]);
			exit(1);
		}
		processDriverList(list, YES, YES);
	}
	if (inquire("Configure Active Drivers")) {
		list = [systemTable valueForStringKey:"Active Drivers"];
		if (list == NULL) {
			fprintf(stderr, "%s: can't get Active Driver list\n", argv[0]);
			exit(1);
		}
		processDriverList(list, NO, YES);
	}
	if (interactive)
		return 0;

	deviceMaster = [IODeviceMaster new];
	haveDisplay = NO;
	if ([deviceMaster lookUpByDeviceName:"Display0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS
	    || [deviceMaster lookUpByDeviceName:"VGADisplay0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS
	    || [deviceMaster lookUpByDeviceName:"SVGADisplay0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS)
		haveDisplay = YES;
	if (haveDisplay)
		return 0;
	fprintf(stderr, "%s: No display driver added, trying VGA\n", argv[0]);
	return processDriver("VGA", NO, YES);
}

static void
usage(char **argv)
{
	printf("Usage: %s <operation> [v(verbose)]\n", argv[0]);
	printf("Operations:\n");
	printf("\ta               Configure All Devices\n");
	printf("\ti               Interactive mode\n");
	printf("\td=deviceName    Configure one device (implies interactive)\n");
	printf("\tD=deviceName    Configure one device (non-interactive)\n");
	exit(1);
}

static BOOL
inquire(const char *question)
{
	char answer[80];

	if (!interactive)
		return YES;
	if (!instruction) {
		printf("Answer queries with 'y' for 'yes', anything else is 'no'.\n");
		instruction = 1;
	}
	printf("%s? ", question);
	gets(answer);
	return (answer[0] == 'y');
}

static int
processDriverList(const char *list, BOOL isBoot, BOOL load)
{
	char name[100];
	char *p;
	BOOL inName;

	if (verbose)
		printf("Configuring %s Drivers\n", isBoot ? "Boot" : "Active");
	p = name;
	inName = NO;
	for (;;) {
		if (*list == ' ' || *list == '\0') {
			if (inName) {
				*p = '\0';
				processDriver(name, isBoot, load);
				p = name;
				inName = NO;
			}
			else if (*list == '\0')
				return 0;
		}
		else {
			inName = YES;
			*p++ = *list;
		}
		if (*list == '\0')
			break;
		list++;
	}
	return 0;
}

static int
processDriver(const char *driverName, BOOL isBoot, BOOL load)
{
	int rtn, unit;

	if (!load)
		return unloadDriver(driverName);
	rtn = prePostExec(driverName, 0, NO);
	if (rtn == PP_FAILED) {
		fprintf(stderr, "driverLoader: driver %s Pre-Load file returned "
			"non-zero status; aborting\n", driverName);
		return 1;
	}
	if (rtn)
		return 1;
	if (!isBoot) {
		rtn = loadDriver(driverName);
		if (rtn)
			return rtn;
	}
	unit = 0;
	do {
		rtn = configDriver(driverName, unit, !isBoot, unit > 0);
		switch (rtn) {
		    case PP_REFUSED:
			return 1;
		    default:
			break;
		}
		unit++;
	} while (rtn != 1);
	return 0;
}

static int
loadDriver(const char *driverName)
{
	char question[100];
	struct stat statBuf;
	char path[1024];
	id table;
	const char *serverName;

	sprintf(path, "%s%s%s/%s%s", DEVICE_DIR, driverName, CONFIG_EXT,
		driverName, RELOC_EXT);
	if (stat(path, &statBuf)) {
		if (verbose)
			printf("No Relocatable for %s\n", driverName);
		return 0;
	}
	sprintf(question, "Load driver %s", driverName);
	if (!inquire(question))
		return 0;
	if (verbose)
		printf("Loading %s for driver %s\n", path, driverName);
	if (kl_com_add(path, (char *)driverName)) {
		fprintf(stderr, "%s: kl_com_add() failed on %s\n", progName, path);
		return 1;
	}
	table = [IOConfigTable newForDriver:driverName unit:0];
	if (table == nil)
		table = [IOConfigTable newDefaultTableForDriver:driverName];
	if (table == nil) {
		fprintf(stderr, "%s: Can't get config table for %s\n",
			progName, driverName);
		return 1;
	}
	serverName = [table valueForStringKey:"Server Name"];
	if (serverName == NULL) {
		fprintf(stderr, "%s: No Server Name for %s\n", progName, driverName);
		return 1;
	}
	if (kl_com_load((char *)serverName)) {
		fprintf(stderr, "%s: kl_com_load() failed on %s\n", progName, path);
		[table free];
		return 1;
	}
	[table free];
	return 0;
}

static int
unloadDriver(const char *driverName)
{
	char path[1024];
	struct stat statBuf;
	char question[100];
	vm_offset_t data;
	int fd;
	IOReturn rtn;
	int krtn;

	if (verbose)
		printf("Unloading driver %s\n", driverName);
	if (getInstanceFile(driverName, path, 0, &statBuf)) {
		fprintf(stderr, "%s: couldn't get instance file for driver %s\n",
			progName, driverName);
		return 1;
	}
	sprintf(question, "Unload driver %s", driverName);
	if (!inquire(question))
		return 0;
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		if (verbose)
			printf("Can't open Instance file for %s instance %d "
				"(errno %d)\n", driverName, 0, errno);
		return 1;
	}
	if (map_fd(fd, 0, &data, TRUE, statBuf.st_size)) {
		if (verbose)
			printf("Can't read Instance file for %s instance %d "
				"(errno %d)\n", driverName, 0, errno);
		close(fd);
		return 1;
	}
	rtn = _IOUnloadDriver(device_master_self(), (IOConfigData)data,
		statBuf.st_size);
	vm_deallocate(task_self(), data, statBuf.st_size);
	close(fd);
	if (rtn) {
		fprintf(stderr, "%s: IOUnloadDriver() failed with code %d on %s\n",
			progName, rtn, driverName);
		return 1;
	}
	krtn = kl_com_unload((char *)driverName);
	if (krtn) {
		fprintf(stderr, "%s: kl_com_unload() failed with code %d on %s\n",
			progName, krtn, driverName);
		return 1;
	}
	krtn = kl_com_delete((char *)driverName);
	if (krtn) {
		fprintf(stderr, "%s: kl_com_delete() failed with code %d on %s\n",
			progName, krtn, driverName);
		return 1;
	}
	return 0;
}

static int
getInstanceFile(const char *driverName, char *path, int unit,
	struct stat *statBuf)
{
	sprintf(path, "%s%s%s/Instance%d%s", DEVICE_DIR, driverName, CONFIG_EXT,
		unit, TABLE_EXT);
	if (stat(path, statBuf) == 0)
		return 0;
	if (verbose)
		printf("No Instance file for %s instance %d\n", driverName, unit);
	if (unit)
		return 1;
	sprintf(path, "%s%s%s/%s", DEVICE_DIR, driverName, CONFIG_EXT,
		DEFAULT_TABLE);
	if (stat(path, statBuf)) {
		if (verbose)
			printf("No Default table for %s\n", driverName);
		return 1;
	}
	fprintf(stderr, "Using Default table for %s\n", driverName);
	return 0;
}

static int
configDriver(const char *driverName, int unit, BOOL probe, BOOL runPreLoad)
{
	struct stat statBuf;
	char path[1024];
	char question[100];
	vm_offset_t data;
	int fd, rtn, pp;
	IOReturn ioRtn;

	rtn = getInstanceFile(driverName, path, unit, &statBuf);
	if (rtn)
		return rtn;
	sprintf(question, "Configure driver %s unit %d", driverName, unit);
	if (!inquire(question))
		return 0;
	if (runPreLoad) {
		pp = prePostExec(driverName, unit, NO);
		switch (pp) {
		    case PP_OK:
			break;
		    case PP_REFUSED:
			return PP_REFUSED;
		    default:
			return 1;
		}
	}
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		if (verbose)
			printf("Can't open Instance file for %s instance %d "
				"(errno %d)\n", driverName, unit, errno);
		return 1;
	}
	if (probe) {
		if (map_fd(fd, 0, &data, TRUE, statBuf.st_size)) {
			if (verbose)
				printf("Can't read Instance file for %s instance %d "
					"(errno %d)\n", driverName, unit, errno);
			return 2;
		}
		ioRtn = _IOProbeDriver(device_master_self(), (IOConfigData)data,
			statBuf.st_size);
		if (ioRtn) {
			fprintf(stderr, "_IOProbeDriver: %s, device %s unit %d\n",
				[IODevice stringFromReturn:ioRtn], driverName, unit);
			rtn = 2;
		}
		vm_deallocate(task_self(), data, statBuf.st_size);
	}
	close(fd);
	if (rtn == 0 && prePostExec(driverName, unit, YES) == PP_REFUSED)
		return PP_REFUSED;
	return rtn;
}

/* Neither reference calls securityCheck; it is kept for parity. */
static BOOL
securityCheck(const char *driverName)
{
	char dir[1024];

	sprintf(dir, "%s%s%s", DEVICE_DIR, driverName, CONFIG_EXT);
	return securityCheckDir(dir);
}

static BOOL
securityCheckDir(char *dir)
{
	char cwd[MAXPATHLEN];
	struct direct **names = NULL;
	struct stat statBuf;
	char subdir[1024];
	char *name;
	int count, i;
	BOOL rtn;

	if (getwd(cwd) == NULL) {
		fprintf(stderr, cwd);
		fprintf(stderr, "driverLoader: getwd() failed\n");
		return YES;
	}
	chdir(dir);
	count = scandir(dir, &names, NULL, NULL);
	if (count < 0) {
		fprintf(stderr, "driverLoader: scandir(%s) error\n", dir);
		rtn = YES;
		goto out;
	}
	for (i = 0; names[i] != NULL; i++) {
		name = names[i]->d_name;
		name[names[i]->d_namlen] = '\0';
		if (strcmp(name, "..") == 0)
			continue;
		if (stat(name, &statBuf)) {
			fprintf(stderr, "Could not access %s/%s\n", dir, name);
			rtn = YES;
			goto out;
		}
		if (statBuf.st_uid != 0) {
			fprintf(stderr, "driverLoader: file %s/%s is not owned by "
				"root; aborting\n", dir, names[i]->d_name);
			rtn = YES;
			goto out;
		}
		if (statBuf.st_mode & (S_IWGRP | S_IWOTH)) {
			fprintf(stderr, "driverLoader: file %s/%s is writable; "
				"aborting\n", dir, names[i]->d_name);
			rtn = YES;
			goto out;
		}
		if (strcmp(name, ".") && (statBuf.st_mode & S_IFMT) == S_IFDIR) {
			sprintf(subdir, "%s/%s", dir, name);
			if (securityCheckDir(subdir)) {
				rtn = YES;
				goto out;
			}
		}
	}
	rtn = NO;
out:
	chdir(cwd);
	if (names != NULL) {
		for (i = 0; i < count; i++)
			free(names[i]);
		free(names);
	}
	return rtn;
}

static int
prePostExec(const char *driverName, int unit, BOOL post)
{
	id table;
	const char *file;
	const char *which;
	char question[100];
	char command[2048];
	char dir[1024];
	int rtn;

	table = [IOConfigTable newForDriver:driverName unit:unit];
	if (table == nil) {
		if (unit)
			return PP_OK;
		table = [IOConfigTable newDefaultTableForDriver:driverName];
		if (table == nil)
			return PP_OK;
	}
	file = [table valueForStringKey:post ? "Post-Load" : "Pre-Load"];
	if (file == NULL)
		return PP_OK;
	if (*file == '/' || strstr(file, "..") != NULL) {
		rtn = PP_REFUSED;
	}
	else {
		which = post ? "Post-Load" : "Pre-Load";
		sprintf(question, "Execute %s file (%s)", which, file);
		if (!inquire(question))
			return PP_OK;
		sprintf(dir, "%s%s%s", DEVICE_DIR, driverName, CONFIG_EXT);
		chdir(dir);
		sprintf(command, "%s/%s Instance=%d", dir, file, unit);
		/* __cstring holds "prePostExec: execString %s\n" and
		 * "   cwd %s\n" right here, but no code uses them: a debug
		 * printf the compiler removed.  Reproduce it the same way. */
		if (0) {
			printf("prePostExec: execString %s\n", command);
			printf("   cwd %s\n", dir);
		}
		rtn = PP_OK;
		if (system(command))
			rtn = PP_FAILED;
	}
	[table free];
	return rtn;
}
```

The source is draft-quality until Task 4 compiles it. Header names such as `<bsd/sys/dir.h>` may differ in this tree. On a compile error, fix the `#import` from the tree's headers under `/System/Library/Frameworks/System.framework/Versions/B/{Headers,PrivateHeaders}` on the guest. Never change a function body to get past a compile error without checking its dump.

- [ ] **Step 3: Write `driverLoader/Makefile`**

```make
#
# Makefile for driverLoader.
#
# Built after libDriver: each CPU slice links the libDriver.A.dylib that
# libDriver's lipoize step has just made, plus libkernload, and the slices
# are lipo'd together.  Apple's copies are not stripped, so neither is this.
#
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
include $(MAKEFILEDIR)/platform.make

PROGRAM=	driverLoader
BINDIR=		/usr/sbin
MANDIR=		/usr/share/man/man8
MFILES=		driverLoader.m kl_com.m
HFILES=		kl_com.h
MANPAGES=	driverLoader.8
SOURCEFILES=	Makefile $(MFILES) $(HFILES) $(MANPAGES)

ifneq "" "$(wildcard /bin/mkdirs)"
  MKDIRS = /bin/mkdirs
else
  MKDIRS = /bin/mkdir -p
endif

OBJROOT= .
SYMROOT= .
MACHINE_LIST= ppc i386
LIBDRIVER= $(SYMROOT)/../libDriver/syms/libDriver.A.dylib

HEADER_ROOT=$(HDRROOT)
ifeq "$(HEADER_ROOT)" ""
HEADER_ROOT=$(NEXT_ROOT)
endif
SYSTEM_FW= $(HEADER_ROOT)$(SYSTEM_LIBRARY_DIR)/Frameworks/System.framework/Versions/B

ARCHFULL_RC_CFLAGS = $(foreach X, $(RC_ARCHS),$(addprefix -arch , $(X)))
ARCHLESS_RC_CFLAGS = $(filter-out $(ARCHFULL_RC_CFLAGS), $(RC_CFLAGS))

CC= cc
CFLAGS= -g -O2 $(ARCHLESS_RC_CFLAGS) -Wformat -Wno-precomp -I.. \
	-I$(SYSTEM_FW)/PrivateHeaders -I$(SYSTEM_FW)/Headers \
	-I$(SYSTEM_FW)/PrivateHeaders/bsd -I$(SYSTEM_FW)/Headers/bsd
LIBS= $(LIBDRIVER) -lkernload

all: $(SYMROOT)/$(PROGRAM)

$(SYMROOT)/$(PROGRAM): ALWAYS
	@if [ -n "$(RC_ARCHS)" ]; then machines="$(RC_ARCHS)"; \
	else machines="$(MACHINE_LIST)"; fi; \
	slices=""; \
	for m in $$machines; do \
	    $(MKDIRS) $(OBJROOT)/$$m || exit 1; \
	    for f in $(MFILES); do \
		o=$(OBJROOT)/$$m/`basename $$f .m`.o; \
		echo $(CC) -arch $$m $(CFLAGS) -c $$f -o $$o; \
		$(CC) -arch $$m $(CFLAGS) -c $$f -o $$o || exit 1; \
	    done; \
	    echo $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) \
		$(OBJROOT)/$$m/driverLoader.o $(OBJROOT)/$$m/kl_com.o $(LIBS); \
	    $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) \
		$(OBJROOT)/$$m/driverLoader.o $(OBJROOT)/$$m/kl_com.o \
		$(LIBS) || exit 1; \
	    slices="$$slices $(OBJROOT)/$$m/$(PROGRAM)"; \
	done; \
	$(MKDIRS) $(SYMROOT); \
	echo lipo -create -o $@ $$slices; \
	lipo -create -o $@ $$slices

install: DSTROOT all install_only

install_only: DSTROOT
	$(MKDIRS) $(DSTROOT)$(BINDIR) $(DSTROOT)$(MANDIR)
	install -c -m 555 $(SYMROOT)/$(PROGRAM) $(DSTROOT)$(BINDIR)/$(PROGRAM)
	install -c -m 444 $(MANPAGES) $(DSTROOT)$(MANDIR)/$(MANPAGES)

installhdrs debug kern tags:

installsrc: SRCROOT
	$(MKDIRS) $(SRCROOT)
	gnutar cf - $(SOURCEFILES) | (cd $(SRCROOT); gnutar xpf -)

clean:
	rm -rf ppc i386 $(PROGRAM) *~

SRCROOT DSTROOT:
	@if [ -n "${$@}" ]; then exit 0; else echo Must define $@; exit 1; fi

ALWAYS:
```

Recipe lines start with a tab. Check with `grep -nP '^ {4,}\S' src/driverkit-3/driverLoader/Makefile`. Only the continuation lines inside the long recipe may match.

- [ ] **Step 4: Wire the subproject into driverkit-3**

In `src/driverkit-3/Makefile`, change exactly these two lines:

```make
SUBDIR=	libDriver driverkit driverLoader
```
```make
INSTALL_SUBDIR= libDriver driverkit driverLoader
```

In `src/driverkit-3/PB.project`, change the `FILESTABLE` line to:

```
    FILESTABLE = {OTHER_SOURCES = (Makefile); SUBPROJECTS = (driverkit, libDriver, driverLoader); }; 
```

In `src/driverkit-3/apk/pkginfo`, change `makedepends` to:

```
makedepends = build-base, machkit-hdrs, adv-cmds, libstreams-hdrs, driverkit-hdrs, kernload-hdrs, kernload
```

Before editing, check each file for high bytes with `grep -P '[\x80-\xff]'`. Afterwards, `git diff` must show only those lines changed.

- [ ] **Step 5: Write the guest build script**

Create `vm/build-driverkit-driverloader.sh`:

```sh
#!/bin/sh
# Universal rbuild of driverkit-3 (with driverLoader) in the private tree
# /build/dlr, then split driverLoader into thin slices for binrecon.
# Rhapsody's /bin/sh is a 1999 Bourne shell: keep it plain.

B=/build/dlr
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
TC=/build/src/rbuild-1/toolchains/gcc-darwin-universal.conf

rm -rf $B/out $B/x $B/driverLoader.i386 $B/driverLoader.ppc
mkdir -p $B/out $B/state $B/x
echo "======== rbuild buildpackage driverkit-3 (universal) ========"
rbuild buildpackage --state $B/state --toolchain $TC \
	$B/src/driverkit-3 /build/repo $B/out > $B/rbuild.log 2>&1
rc=$?
tail -40 $B/rbuild.log
echo "RBUILD_RC=$rc"
if [ $rc != 0 ]; then
	echo "FAILED: rbuild; the build root is under /private/tmp/roots/"
	exit 1
fi

APK=
for f in $B/out/driverkit-[0-9]*-universal.apk; do
	if [ -f "$f" ]; then APK=$f; fi
done
if [ -z "$APK" ]; then
	echo "FAILED: no driverkit universal apk in $B/out"
	ls -l $B/out
	exit 1
fi
cp $APK $B/driverkit-universal.apk
(cd $B/x && gzip -dc $APK | tar xf -) || exit 1
DL=$B/x/usr/sbin/driverLoader
for f in $DL $B/x/usr/share/man/man8/driverLoader.8 $B/x/usr/lib/libDriver.A.dylib; do
	if [ ! -f $f ]; then
		echo "FAILED: apk lacks $f"
		exit 1
	fi
done
lipo -info $DL
lipo -thin i386 -output $B/driverLoader.i386 $DL || exit 1
lipo -thin ppc -output $B/driverLoader.ppc $DL || exit 1
ls -l $DL $B/x/usr/share/man/man8/driverLoader.8 $B/driverLoader.i386 $B/driverLoader.ppc
echo "=== driverloader build done: $APK ==="
```

```bash
sh -n vm/build-driverkit-driverloader.sh && echo "syntax OK"
```

- [ ] **Step 6: Sync and build on the guest**

With the guest up, run each command as its own ssh session, one after another. Create a script file for the mkdir:

```bash
printf 'mkdir -p /build/dlr/src && echo MKDIR_OK\n' > "$S/mkdir.sh"
powershell -NoProfile -File vm/guest-remote.ps1 -Run "$S/mkdir.sh"
powershell -NoProfile -File vm/sync-src.ps1 -Path driverkit-3
powershell -NoProfile -File vm/guest-remote.ps1 -Run vm/build-driverkit-driverloader.sh
```

Run the last command with the Bash tool's `run_in_background` and wait for its completion notification. Do not check on it meanwhile.

Expected:
- `RBUILD_RC=0`
- `lipo -info` reports `Architectures in the fat file: ... are: ppc i386`, in either order
- `=== driverloader build done: … ===`

If rbuild fails on a compile or link error, iterate in the leftover root as memory `rbuild-failed-root-iteration` describes. Take the last `chroot … make -w … install` line from `/build/dlr/rbuild.log`, change it to `make -k -w`, and run it from `/` in one guest script. Fix the source on the host, re-sync `driverkit-3`, and repeat until it compiles. Then re-run the build script from scratch.

- [ ] **Step 7: Fetch the results to the host at once**

```bash
mkdir -p out/driverloader
for f in driverLoader.i386 driverLoader.ppc driverkit-universal.apk; do
  MSYS_NO_PATHCONV=1 powershell -NoProfile -File vm/guest-remote.ps1 -Fetch /build/dlr/$f -To out/driverloader/$f
done
xxd -l 4 out/driverloader/driverLoader.i386; xxd -l 4 out/driverloader/driverLoader.ppc
```

Expected: `cefa edfe` for i386 and `feed face` for ppc.

- [ ] **Step 8: Run the behaviour harness against the build**

```bash
powershell -NoProfile -File vm/guest-remote.ps1 -Run vm/driverloader-behaviour.sh
```

Expected: seven `PASS` lines and `fails=0`. For any `FAIL`, the diff names the difference. Fix `driverLoader.m`, `kl_com.m` or the Makefile from the dumps, then rebuild with Steps 6–7. Do not start Task 4 with a failing case.

- [ ] **Step 9: Commit**

```bash
git add src/driverkit-3/driverLoader/Makefile src/driverkit-3/driverLoader/driverLoader.m \
        src/driverkit-3/driverLoader/kl_com.m src/driverkit-3/driverLoader/kl_com.h \
        src/driverkit-3/driverLoader/driverLoader.8 src/driverkit-3/Makefile \
        src/driverkit-3/PB.project src/driverkit-3/apk/pkginfo vm/build-driverkit-driverloader.sh
git commit -m "driverkit: rebuild driverLoader from source as a fat subproject linking libDriver's dylib

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: First comparison, source maps and ledgers

**Files:**
- Create: `src/driverkit-3/driverLoader/reconstruction/i386/source-map.json`, `i386/ledger.json`
- Create: `src/driverkit-3/driverLoader/reconstruction/ppc/source-map.json`, `ppc/ledger.json`
- Create: `src/driverkit-3/driverLoader/reconstruction/function-worklist.md`
- Create: `src/driverkit-3/driverLoader/reconstruction/divergences.md`

**Interfaces:**
- Consumes: Task 3's `out/driverloader/driverLoader.{i386,ppc}`.
- Produces: per-slice ledgers with every owned and libkernload function `unexamined`. `function-worklist.md`, which Tasks 5 and 6 work down. `divergences.md` with the libDriver accept.

- [ ] **Step 1: parity_check both slices**

```bash
i386 $PY tools/binrecon/parity_check.py "$REF_I386" "$NEW_I386" | tee out/driverloader/parity-i386.txt
ppc  $PY tools/binrecon/parity_check.py "$REF_PPC"  "$NEW_PPC"  | tee out/driverloader/parity-ppc.txt
```

Expected:
- ppc: `missing_strings (0)` and `missing_symbols (0)`.
- i386: `missing_strings` lists only libDriver strings (for example `IOConfigTable: _IOGetSystemConfig: %s\n` and the `IOReturn` names). `missing_symbols` lists only the libDriver symbols from `nlist.md`'s i386-static list.
- Anything else missing is an owned or libkernload item. Fix it in source (Task 5 rules) before going on.

- [ ] **Step 2: Analyze the rebuilt slices**

```bash
i386 $PY -m binrecon analyze --profile tools/binrecon/profiles/driverloader.json
ppc  $PY -m binrecon analyze --profile tools/binrecon/profiles/driverloader-ppc.json
i386 $PY -m binrecon function --profile tools/binrecon/profiles/driverloader.json --list | tee out/driverloader/list-i386.txt
ppc  $PY -m binrecon function --profile tools/binrecon/profiles/driverloader-ppc.json --list | tee out/driverloader/list-ppc.txt
```

Expected: `complete: true` on both runs. `normalized-functions` fails until the campaign closes.

- [ ] **Step 3: Source maps**

```bash
for side in i386:driverloader:"$REF_I386" ppc:driverloader-ppc:"$REF_PPC"; do
  s=${side%%:*}; rest=${side#*:}; prof=${rest%%:*}; ref=${rest#*:}
  $PY -m binrecon source-map \
    --reference-analysis tools/binrecon/out/$prof/published/analysis-reference-ida.json \
    --binary "$ref" --source-dir src/driverkit-3/driverLoader \
    --source-dir src/kernload-1/libkernload --repo-root . \
    --output src/driverkit-3/driverLoader/reconstruction/$s/source-map.json
done
```

Expected: both files exist. Every owned function sits under `mapped` with a `source_path` in `src/driverkit-3/driverLoader/`. libkernload's MIG stubs are generated code with no tree source, so they sit under `unmapped`.

- [ ] **Step 4: Seed the ledgers**

```bash
for s in i386 ppc; do
  ref=$([ $s = i386 ] && echo "$REF_I386" || echo "$REF_PPC")
  $PY tools/binrecon/seed_ledger.py src/driverkit-3/driverLoader/reconstruction/$s/source-map.json \
      "$ref" src/driverkit-3/driverLoader/reconstruction/$s/ledger.json
done
```

Expected: `<n> entries` for each. On i386, n includes the libDriver-static functions. Seed with `rebuilt_sha256` as the tool writes it.

- [ ] **Step 5: Record the libDriver accept on the i386 ledger**

For each i386 ledger entry whose name is in `nlist.md`'s i386-static libDriver list:

```bash
$PY -m binrecon ledger --profile tools/binrecon/profiles/driverloader.json \
  --ledger src/driverkit-3/driverLoader/reconstruction/i386/ledger.json \
  --address <addr> --status intentional-mismatch \
  --reason "DR2 linked libDriver statically; MOSXS 1.2 links libDriver.A.dylib and this build follows 1.2" \
  --reviewer "Pat Raynor"
```

Take `<addr>` from the ledger itself. List the entries with this, and run the command once per libDriver address:

```bash
$PY -c "import json;[print(hex(e['address']),e['names']) for e in json.load(open('src/driverkit-3/driverLoader/reconstruction/i386/ledger.json'))['entries']]"
```

- [ ] **Step 6: Write `divergences.md` and `function-worklist.md`**

`divergences.md` starts with:

```markdown
# driverLoader divergences

References: DR2 i386 `e005522e…` (70132 bytes) and MOSXS 1.2v3 ppc
`cd8dd330…` (40776 bytes). See nlist.md.

## Accepted

### libDriver is linked dynamically (i386)

DR2's driverLoader carries libDriver's user-mode objects statically
(IOConfigTable, IODevice, IODeviceMaster, driverServerUser,
NXConditionLock, NXLock, generalFuncs). MOSXS 1.2v3 links
/usr/lib/libDriver.A.dylib instead, and this build follows 1.2 on both
slices. Every i386 reference function from those objects is
intentional-mismatch in i386/ledger.json, and parity_check's i386
missing_strings/missing_symbols list exactly those items:
<paste the two lists from out/driverloader/parity-i386.txt>

## Fixed Apple bugs

(none yet)
```

Replace the `<paste…>` line with the lists. The committed file has no angle brackets.

`function-worklist.md` holds one table per slice, with columns `Function | Group (owned/kl_com/libkernload) | --list result | Status`. There is one row per non-libDriver function from `list-i386.txt` and `list-ppc.txt`, sorted cheapest difference first, as `--list` prints them. The header also gives the date, and both rebuilt SHA-256 values from `sha256sum out/driverloader/driverLoader.*`.

- [ ] **Step 7: Commit**

```bash
git add src/driverkit-3/driverLoader/reconstruction/
git commit -m "driverkit: record driverLoader's first comparison, ledgers and the libDriver accept

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Owned-function parity on both slices

**Files:**
- Modify: `src/driverkit-3/driverLoader/driverLoader.m`, `kl_com.m`, `kl_com.h`, and `Makefile` (flags only)
- Modify: both ledgers, `divergences.md`, `function-worklist.md`

**Interfaces:**
- Consumes: Task 4's worklist, ledgers and profiles.
- Produces: every owned function (groups 1 and 2) at `raw_equal` or `masked_equal` on both slices, or accepted, with its ledger status set.

- [ ] **Step 1: Settle global compile flags first**

Take the three smallest owned functions from `list-i386.txt`, likely `usage`, `print_string` and `securityCheck`. Dump each on both slices:

```bash
for f in _usage _print_string _securityCheck; do
  i386 $PY -m binrecon function --profile tools/binrecon/profiles/driverloader.json --name $f
  ppc  $PY -m binrecon function --profile tools/binrecon/profiles/driverloader-ppc.json --name $f
done
```

If the difference is the prologue or epilogue (frame pointer, stack protector, register saves) or optimisation shape on every function, change `CFLAGS` in `driverLoader/Makefile`. `-O2` is libDriver's release setting. Try `-O`, then `-O3`, keeping one change per rebuild. Rebuild and fetch (Task 3 Steps 6–7), re-analyze (Task 4 Step 2), and keep the flag set that gives the most `raw_equal`/`masked_equal` rows over both slices together. Record the choice and the counts in `function-worklist.md`.

- [ ] **Step 2: Work the list, one batch per rebuild**

Repeat until every owned row is closed:
1. Take up to five open owned rows, cheapest first.
2. For each, dump `--name` on both slices.
3. Edit only what the dump shows: statement order, types (`int` or `BOOL` widths, signedness), variable lifetimes, expression shape (`if (x)` against `if (x != 0)`), switch shape, and the global widths of `verbose`, `interactive` and `instruction`.
4. Rebuild, fetch and re-analyze, then re-list both slices.
5. A row closes when it is `raw_equal` or `masked_equal` on **both** slices. Set both ledgers:

```bash
i386 $PY -m binrecon ledger --profile tools/binrecon/profiles/driverloader.json \
  --ledger src/driverkit-3/driverLoader/reconstruction/i386/ledger.json \
  --address <addr> --status assembly-matched \
  --source-path src/driverkit-3/driverLoader/<file> --source-line <line>
```

and the same for ppc with its own profile, ledger and address.
6. A one-sided win (better on one slice, worse on the other) is reverted.
7. After three rebuilds without progress on a row whose remaining difference is register allocation or scheduling, record an accept. Add a `divergences.md` entry with both `--name` dumps pasted in, and set both ledgers to `intentional-mismatch` with `--reason "compiler-shaped leftover: <what>" --reviewer "Pat Raynor"`.
8. Run the behaviour harness (Task 3 Step 8) after every rebuild. A behaviour change is a regression even if parity improves. Revert it.

Commit after each kept batch:

```bash
git add src/driverkit-3/driverLoader/
git commit -m "driverkit: match <functions> in driverLoader on i386 and ppc

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Close the owned groups**

```bash
$PY - <<'EOF'
import json
for s in ("i386", "ppc"):
    L = json.load(open(f"src/driverkit-3/driverLoader/reconstruction/{s}/ledger.json"))["entries"]
    open_rows = [e["names"] for e in L if e["status"] == "unexamined"]
    print(s, "unexamined:", open_rows)
EOF
```

Expected: only libkernload names are still `unexamined` (Task 6). No owned function is.

---

### Task 6: libkernload parity on both slices

**Files:**
- Modify (only if needed): `src/kernload-1/libkernload/*`, `src/kernload-1/include/kernserv/*.defs`
- Modify: both ledgers, `divergences.md`, `function-worklist.md`

**Interfaces:**
- Consumes: Task 5's state.
- Produces: every libkernload function in both ledgers closed.

- [ ] **Step 1: List and dump the libkernload rows**

For each open libkernload row in `function-worklist.md` (`kern_loader_*`, `kern_loader_look_up`, `kern_loader_reply_handler`), dump `--name` on both slices.

- [ ] **Step 2: Decide per function**

- **Already equal on both slices:** set both ledgers to `assembly-matched`. The generated stubs have no tree source, so use `--source-path src/kernload-1/include/kernserv/kern_loader.defs --source-line <line of the routine>`, and `kern_loader_reply.defs` for the reply handler.
- **Different because of MIG output or compiler flags:** the stubs come from the guest's `mig` and `libkernload/Makefile`'s `CFLAGS= -g -O …`. If a flag change in `libkernload/Makefile` would close it, first check that it does not change `kern_loader`, `kl_util` or anything else linking `libkernload.a`. List their users with `git grep -n "kernload" -- 'src/*Makefile*' 'src/**/Makefile*'`. Then rebuild kernload with Step 3. Otherwise record an accept: "libkernload generated by this tree's mig/cc; differs from Apple's 1998/1999 build in <what>", with both dumps, and set both ledgers to `intentional-mismatch`.

- [ ] **Step 3: Rebuilding kernload when a fix is made**

Only when Step 2 changed kernload-1. Write `$S/kl-build.sh`:

```sh
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
B=/build/dlr
rm -rf $B/kl-out $B/repo; mkdir -p $B/kl-out $B/repo $B/kl-state
rbuild buildpackage --state $B/kl-state --toolchain /build/src/rbuild-1/toolchains/gcc-darwin-universal.conf \
	$B/src/kernload-1 /build/repo $B/kl-out > $B/kl.log 2>&1
rc=$?; tail -20 $B/kl.log; echo "KL_RC=$rc"; [ $rc = 0 ] || exit 1
for f in /build/repo/*.apk; do
	case `basename $f` in kernload-*) ;; *) ln $f $B/repo/ ;; esac
done
ln $B/kl-out/*.apk $B/repo/
ls $B/repo | grep kernload
```

Sync `kernload-1`, then run it:

```bash
powershell -NoProfile -File vm/sync-src.ps1 -Path kernload-1
powershell -NoProfile -File vm/guest-remote.ps1 -Run "$S/kl-build.sh"
```

Then edit `vm/build-driverkit-driverloader.sh` so the repository is `$B/repo` when that directory exists:

```sh
REPO=/build/repo
if [ -d $B/repo ]; then REPO=$B/repo; fi
```

Use `$REPO` in the `rbuild buildpackage` line. Commit this script change with the kernload fix.

- [ ] **Step 4: Commit**

```bash
git add src/driverkit-3/driverLoader/reconstruction/ vm/build-driverkit-driverloader.sh
# plus src/kernload-1/... only if Step 2 changed it
git commit -m "driverkit: close driverLoader's libkernload functions on both slices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

If kernload-1 changed, commit it separately first, with the `kernload: ` prefix and a line saying what changed and why.

---

### Task 7: Parity close-out check

**Files:**
- Modify: `src/driverkit-3/driverLoader/reconstruction/function-worklist.md`, both ledgers (`rebuilt_sha256`)

**Interfaces:**
- Consumes: the last kept rebuild.
- Produces: a worklist that records the final counts. Ledgers whose `rebuilt_sha256` matches the kept slices.

- [ ] **Step 1: Final checks on the last kept rebuild**

```bash
sha256sum out/driverloader/driverLoader.i386 out/driverloader/driverLoader.ppc
i386 $PY tools/binrecon/parity_check.py "$REF_I386" "$NEW_I386"
ppc  $PY tools/binrecon/parity_check.py "$REF_PPC"  "$NEW_PPC"
$PY - <<'EOF'
import json
for s in ("i386", "ppc"):
    d = json.load(open(f"src/driverkit-3/driverLoader/reconstruction/{s}/ledger.json"))
    from collections import Counter
    print(s, d.get("rebuilt_sha256"), Counter(e["status"] for e in d["entries"]))
EOF
```

Expected:
- ppc: `missing_strings (0)` and `missing_symbols (0)`.
- i386: the missing lists equal exactly the libDriver lists in `divergences.md`.
- Neither ledger has an `unexamined` entry.
- Each ledger's `rebuilt_sha256` equals its slice's `sha256sum`. If not, re-run `analyze` for that slice with `--ledger <that ledger>` to refresh the evidence.

- [ ] **Step 2: Update `function-worklist.md`**

Add a final section with:
- the date
- both rebuilt SHA-256 values and sizes
- the `CFLAGS` settled in Task 5
- for each slice, the counts of `raw_equal`, `masked_equal`, `intentional-mismatch` (owned and libkernload) and libDriver accepts (i386)

- [ ] **Step 3: Commit**

```bash
git add src/driverkit-3/driverLoader/reconstruction/
git commit -m "driverkit: record driverLoader's final parity on i386 and ppc

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Packaging ownership and the i386 boot test

**Files:**
- Create: `vm/driverloader-boot.sh`
- Create: `vm/driverloader-boot-check.sh`
- Modify: `src/driverkit-3/driverLoader/reconstruction/divergences.md` (boot results, and any difference)

**Interfaces:**
- Consumes: the last kept build, which must still be on the guest (`/build/dlr/x`). If the guest was restarted since, rebuild with Task 3 Steps 6–7 first.
- Produces: boot evidence for Apple's binary and ours under `$S/guest-baseline/` and `$S/guest-rebuilt/`.

- [ ] **Step 1: Check that no other package ships `usr/sbin/driverLoader`**

Write `$S/owner.sh`:

```sh
for f in /build/repo/*.apk; do
	if gzip -dc $f 2>/dev/null | tar tf - 2>/dev/null | grep -q '^\.*/*usr/sbin/driverLoader$'; then
		echo "OWNER $f"
	fi
done
echo OWNER_SCAN_DONE
```

```bash
powershell -NoProfile -File vm/guest-remote.ps1 -Run "$S/owner.sh"
```

Expected: `OWNER_SCAN_DONE` with no `OWNER` lines, since `/build/repo` holds none of this branch's builds. If a package is listed, stop and report it. Removing a file from another package is a separate decision for Pat.

- [ ] **Step 2: Write the boot scripts**

`vm/driverloader-boot.sh`:

```sh
#!/bin/sh
# Arm a driverLoader boot test on the i386 guest, then reboot.
# MODE=baseline keeps Apple's driverLoader; MODE=rebuilt installs ours and
# its libDriver.A.dylib from the unpacked driverkit apk in /build/dlr/x.
# Either way BPF and PortServer are appended to "Active Drivers" so that
# 0300_Devices' `driverLoader a` loads them.

MODE=${MODE:-baseline}
T=/usr/Devices/System.config/Instance0.table
X=/build/dlr/x

if [ "$MODE" = rebuilt ]; then
	for f in $X/usr/sbin/driverLoader $X/usr/lib/libDriver.A.dylib; do
		if [ ! -f $f ]; then echo "missing $f"; exit 1; fi
	done
	cp /usr/sbin/driverLoader /usr/sbin/driverLoader.apple
	cp $X/usr/sbin/driverLoader /usr/sbin/driverLoader
	chmod 555 /usr/sbin/driverLoader
	cp $X/usr/lib/libDriver.A.dylib /usr/lib/libDriver.A.dylib
	chmod 555 /usr/lib/libDriver.A.dylib
fi
if grep 'BPF PortServer' $T > /dev/null; then
	:
else
	sed 's/^"Active Drivers" = "\(.*\)";/"Active Drivers" = "\1 BPF PortServer";/' $T > /tmp/i0 || exit 1
	cp /tmp/i0 $T || exit 1
fi
grep '"Active Drivers"' $T
ls -l /usr/sbin/driverLoader
echo "=== armed $MODE; rebooting ==="
/sbin/reboot
```

`vm/driverloader-boot-check.sh`:

```sh
#!/bin/sh
# Collect evidence after a driverLoader boot test.
echo "== driverLoader"; ls -l /usr/sbin/driverLoader /usr/lib/libDriver.A.dylib 2>&1
echo "== Active Drivers"; grep '"Active Drivers"' /usr/Devices/System.config/Instance0.table
echo "== bpf"; ls -l /dev/ | grep bpf
echo "== ttyd"; ls -l /dev/ | grep ttyd
echo "== pdservd"; ps -axww | grep pdservd | grep -v grep
echo "== Devices"; ls /usr/Devices/
echo "=== boot check done ==="
```

The `MODE` override is set by prefixing the script body. Make `$S/boot-baseline.sh` and `$S/boot-rebuilt.sh` from it:

```bash
sh -n vm/driverloader-boot.sh && sh -n vm/driverloader-boot-check.sh && echo "syntax OK"
for m in baseline rebuilt; do
  { echo "MODE=$m"; cat vm/driverloader-boot.sh; } > "$S/boot-$m.sh"
done
```

- [ ] **Step 3: Baseline boot (Apple's driverLoader)**

1. Stop any running guest (`python "$S/dlqmp.py" quit`).
2. Start `python "$S/dlguest.py" baseline` and wait 180 s.
3. Run `vm/guest-remote.ps1 -Run "$S/boot-baseline.sh"`. The ssh session drops at the reboot; that is expected.
4. Wait 240 s, then run `vm/guest-remote.ps1 -Run vm/driverloader-boot-check.sh > "$S/guest-baseline/check.txt"`.
5. `grep -a 'Registering:' "$S/guest-baseline/kernel.log" > "$S/guest-baseline/registering.txt"`.
6. Stop the guest with QMP `quit`. The guest has already rebooted cleanly once, so its snapshot overlay is simply discarded.

Expected in `check.txt`: `/dev/bpf*` lines, a `/dev/ttyd*` line, and a `pdservd` process.

- [ ] **Step 4: Rebuilt boot (ours)**

The rebuilt boot needs `/build/dlr/x`, which only exists after a build in this guest:

1. Start `python "$S/dlguest.py" rebuilt` and wait 180 s.
2. Re-run Task 3 Step 6's mkdir, sync and build commands, which leave `/build/dlr/x`.
3. Fetch `/build/dlr/driverLoader.i386` and `sha256sum` it. It must equal Task 7's i386 SHA; if not, stop, because the tree changed since Task 7.
4. Run `$S/boot-rebuilt.sh`, wait 240 s, then run the check into `"$S/guest-rebuilt/check.txt"`.
5. Extract `Registering:` lines as in Step 3.
6. `grep -a -i 'No display driver added\|error\|failed' "$S/guest-rebuilt/kernel.log"` and the same for the baseline log.
7. Stop the guest.

- [ ] **Step 5: Compare**

```bash
diff "$S/guest-baseline/registering.txt" "$S/guest-rebuilt/registering.txt" && echo REGISTERING_SAME
ev() { sed -n '/^== bpf/,/^=== boot check done/p' "$1" | grep -v pdservd; }
diff <(ev "$S/guest-baseline/check.txt") <(ev "$S/guest-rebuilt/check.txt") && echo EVIDENCE_SAME
grep -c pdservd "$S/guest-baseline/check.txt" "$S/guest-rebuilt/check.txt"
diff <(grep -a -i 'No display driver added\|error\|failed' "$S/guest-baseline/kernel.log") \
     <(grep -a -i 'No display driver added\|error\|failed' "$S/guest-rebuilt/kernel.log") && echo ERRORS_SAME
```

Expected:
- `REGISTERING_SAME`, `EVIDENCE_SAME` and `ERRORS_SAME`.
- A `pdservd` count of at least 1 in both files.

A real difference is a bug. Fix it (Task 5 rules: behaviour must match Apple's), rebuild, re-run parity for the touched functions, and redo Step 4.

- [ ] **Step 6: Record and commit**

Append to `divergences.md` a `## Boot test (i386)` section. It gives the date, the i386 slice SHA, the two `Registering:` lists (identical), the `/dev/bpf*` and `/dev/ttyda` presence, `pdservd` running, and "no new error lines".

```bash
git add vm/driverloader-boot.sh vm/driverloader-boot-check.sh src/driverkit-3/driverLoader/reconstruction/divergences.md
git commit -m "vm: add the driverLoader boot test and record that the rebuilt i386 slice boots like Apple's

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Close-out

**Files:**
- Modify: `docs/superpowers/specs/2026-09-27-driverloader-binary-reconstruction-design.md` (only where the build showed the spec wrong)
- Delete: `vm/vm.conf` (worktree copy, untracked)

- [ ] **Step 1: Correct the spec from what the build showed**

Compare the spec with what happened: the `CFLAGS` settled on, any header path or makedepends that differed, the behaviour cases, and the boot. Edit only statements that proved wrong, and add a dated `## As built` section of at most ten lines listing them. Commit it:

```bash
git add docs/superpowers/specs/2026-09-27-driverloader-binary-reconstruction-design.md
git commit -m "docs: correct the driverLoader spec to what the build showed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Clean up the private guest and secrets**

```bash
python "$S/dlqmp.py" quit 2>/dev/null || true
netstat -ano | grep -E ':(2231|2331|4471) ' || echo PORTS_FREE
rm -f vm/vm.conf
git status --short
```

Expected: `PORTS_FREE`, and `git status` clean apart from ignored files. Leave `.venv-binrecon` (a junction, ignored), `out/` and `tools/binrecon/out/` in place.

---

## Follow-ups (not in this plan)

- A ppc boot test, when a ppc guest exists.
- `rbuild buildpackage` of the whole world, which will pick up the new driverkit apk through `src/Manifest`.
