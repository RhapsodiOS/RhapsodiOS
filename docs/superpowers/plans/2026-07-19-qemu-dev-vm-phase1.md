# QEMU Rhapsody Dev VM Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Formalize the existing Windows `vm/` + hecnet QEMU stack with thin start scripts and docs so networking and SSH can be confirmed; do not automate sync/build yet.

**Architecture:** Keep local binaries (`qemu.exe`, `hecnet.exe`, `rhapsody.vmdk`) untracked. Narrow `.gitignore` so scripts/docs under `vm/` can be committed. Add `start-hecnet.cmd` / `start-vm.cmd`, `bridge.conf.example`, `README.md`, and `GUEST-CHECKLIST.md`. Leave legacy `install*.cmd` with pointers to the new scripts.

**Tech Stack:** Windows CMD, existing QEMU/hecnet binaries, OpenSSH client on host, guest OpenSSH (`sshd`).

**Spec:** [docs/superpowers/specs/2026-07-19-qemu-dev-vm-phase1-design.md](../specs/2026-07-19-qemu-dev-vm-phase1-design.md)

---

## File structure

| Path | Responsibility |
|------|----------------|
| `.gitignore` | Ignore `vm/` binaries + machine-local `bridge.conf`; allow scripts/docs |
| `vm/start-hecnet.cmd` | Launch hecnet with `bridge.conf` |
| `vm/start-vm.cmd` | Boot `rhapsody.vmdk` with ne2k_pci + UDP socket net |
| `vm/bridge.conf.example` | Template for hecnet bridge config |
| `vm/README.md` | Host launch, networking, SSH smoke, failure guide, Approach 2 deferral |
| `vm/GUEST-CHECKLIST.md` | Console checklist for NIC/IP/sshd |
| `vm/install.cmd` | Legacy; comment → new scripts |
| `vm/install2.cmd` | Legacy; comment → new scripts |
| `vm/install3.cmd` | Legacy; comment → new scripts |

**Do not commit:** `qemu.exe`, `hecnet.exe`, `ethlist.exe`, `qemu-img.exe`, `SDL.dll`, `rhapsody.vmdk`, `nic.flp`, `bridge.conf`, `pc-bios/` blobs.

---

### Task 1: Allow tracking `vm/` scripts while ignoring binaries

**Files:**
- Modify: `.gitignore`
- Create: (none yet — only gitignore)

- [ ] **Step 1: Replace blanket `/vm` ignore**

In `.gitignore`, replace:

```
# vm testing directory
/vm
```

with:

```
# vm testing — local binaries and machine-specific config (scripts/docs are tracked)
/vm/*.exe
/vm/*.dll
/vm/*.vmdk
/vm/*.flp
/vm/*.iso
/vm/*.img
/vm/pc-bios/
/vm/bridge.conf
```

- [ ] **Step 2: Verify ignore behavior**

From repo root (Git Bash or PowerShell with git):

```bash
git check-ignore -v vm/qemu.exe vm/rhapsody.vmdk vm/bridge.conf vm/start-vm.cmd vm/README.md 2>&1 || true
```

Expected: `qemu.exe`, `rhapsody.vmdk`, and `bridge.conf` are ignored. `start-vm.cmd` / `README.md` are **not** ignored (they may not exist yet; if missing, `check-ignore` prints nothing for them — that is OK).

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
Allow tracking vm scripts while ignoring local QEMU binaries.

EOF
)"
```

---

### Task 2: Add `start-hecnet.cmd` and `bridge.conf.example`

**Files:**
- Create: `vm/start-hecnet.cmd`
- Create: `vm/bridge.conf.example`

- [ ] **Step 1: Create `vm/bridge.conf.example`**

```ini
# Copy to bridge.conf and edit.
# Run ethlist.exe to list NPF devices; pick the VMnet8 (or desired) adapter.
# Do not commit bridge.conf — it is machine-specific.

[bridge]
VMnet8 \Device\NPF_{YOUR-GUID-HERE}
update  127.0.0.1:5001

[tcpip]
update
VMnet8
```

- [ ] **Step 2: Create `vm/start-hecnet.cmd`**

```bat
@echo off
setlocal
cd /d "%~dp0"

if not exist "hecnet.exe" (
  echo start-hecnet: hecnet.exe not found in %CD%
  exit /b 1
)
if not exist "bridge.conf" (
  echo start-hecnet: bridge.conf not found.
  echo Copy bridge.conf.example to bridge.conf and set the NPF device via ethlist.exe
  exit /b 1
)

echo Starting hecnet ^(leave this window open^)...
echo Bridge config: %CD%\bridge.conf
hecnet.exe
set ERR=%ERRORLEVEL%
echo hecnet exited with code %ERR%
exit /b %ERR%
```

- [ ] **Step 3: Sanity-check files exist and are not ignored**

```bash
git check-ignore -v vm/start-hecnet.cmd vm/bridge.conf.example || true
test -f vm/start-hecnet.cmd && test -f vm/bridge.conf.example
```

Expected: not ignored; both files present.

- [ ] **Step 4: Commit**

```bash
git add vm/start-hecnet.cmd vm/bridge.conf.example
git commit -m "$(cat <<'EOF'
Add hecnet start script and bridge.conf example for Rhapsody VM.

EOF
)"
```

---

### Task 3: Add `start-vm.cmd` and legacy install script pointers

**Files:**
- Create: `vm/start-vm.cmd`
- Modify: `vm/install.cmd`, `vm/install2.cmd`, `vm/install3.cmd` (add header comments; preserve existing qemu lines)

- [ ] **Step 1: Create `vm/start-vm.cmd`**

```bat
@echo off
setlocal
cd /d "%~dp0"

if not exist "qemu.exe" (
  echo start-vm: qemu.exe not found in %CD%
  exit /b 1
)
if not exist "rhapsody.vmdk" (
  echo start-vm: rhapsody.vmdk not found in %CD%
  exit /b 1
)
if not exist "pc-bios" (
  echo start-vm: pc-bios directory not found in %CD%
  exit /b 1
)

echo Starting Rhapsody QEMU ^(ne2k_pci + UDP socket 5001-^>5000^)...
echo Ensure start-hecnet.cmd is already running.
echo.

qemu -L pc-bios -m 512 ^
  -k en-us ^
  -rhapsodymouse ^
  -hda rhapsody.vmdk ^
  -net nic,model=ne2k_pci,vlan=5 ^
  -net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000 ^
  -boot c

exit /b %ERRORLEVEL%
```

- [ ] **Step 2: Prepend legacy headers to install scripts**

Ensure each of `install.cmd`, `install2.cmd`, `install3.cmd` begins with a remark block (keep all existing qemu argument lines unchanged after the header):

`install.cmd` / `install3.cmd` header:

```bat
@echo off
REM Legacy install/boot helper. Prefer:
REM   1) start-hecnet.cmd
REM   2) start-vm.cmd
REM This file kept for CD/floppy install workflows.
```

`install2.cmd` header:

```bat
@echo off
REM Legacy boot-with-nic.flp helper. Prefer start-hecnet.cmd then start-vm.cmd.
REM Use this if the guest needs nic.flp once for NE2k drivers.
```

If a file already starts with `qemu` and has no `@echo off`, insert the header **above** the existing `qemu` line without deleting arguments.

Canonical bodies to preserve (after headers):

`install.cmd`:

```bat
qemu -L pc-bios -m 128 ^
-k en-us ^
-rhapsodymouse ^
-hda rhapsody.vmdk ^
-cdrom rhapsody_dr2_x86.iso ^
-fda rhapsody_dr2_x86_InstallationFloppy.img ^
-net nic,model=ne2k_pci,vlan=5 ^
-net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000 ^
-boot a
```

`install2.cmd`:

```bat
qemu -L pc-bios -m 128 ^
-k en-us ^
-rhapsodymouse ^
-hda rhapsody.vmdk ^
-cdrom rhapsody_dr2_x86.iso ^
-fda nic.flp ^
-boot c
```

`install3.cmd`:

```bat
qemu -L pc-bios -m 512 ^
-k en-us ^
-rhapsodymouse ^
-hda rhapsody.vmdk ^
-cdrom rhapsody_dr2_x86.iso ^
-fda rhapsody_dr2_x86_InstallationFloppy.img ^
-net nic,model=ne2k_pci,vlan=5 ^
-net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000 ^
-boot c
```

- [ ] **Step 3: Commit**

```bash
git add vm/start-vm.cmd vm/install.cmd vm/install2.cmd vm/install3.cmd
git commit -m "$(cat <<'EOF'
Add start-vm.cmd and point legacy install scripts at it.

EOF
)"
```

---

### Task 4: Write host README and guest checklist

**Files:**
- Create: `vm/README.md`
- Create: `vm/GUEST-CHECKLIST.md`

- [ ] **Step 1: Create `vm/README.md`**

Write exactly this content (adjust only if a path name in-repo differs):

```markdown
# Rhapsody QEMU VM (Windows + hecnet)

Phase 1: start the existing local QEMU stack and confirm networking / SSH.
Sync/build automation is deferred (Approach 2).

## Prerequisites (local, not in git)

| File | Purpose |
|------|---------|
| `qemu.exe`, `SDL.dll`, `pc-bios/` | Rhapsody-tuned QEMU |
| `hecnet.exe`, `ethlist.exe` | Bridge QEMU UDP net to a host NIC |
| `rhapsody.vmdk` | Guest disk |
| `bridge.conf` | Copy from `bridge.conf.example`; set NPF device |
| VMware **VMnet8** (typical) | Host-only/NAT network hecnet attaches to |
| WinPcap / Npcap | Required by hecnet |

Optional: `nic.flp`, install ISO/floppy for reinstall (`install*.cmd`).

## Quick start

1. Copy `bridge.conf.example` → `bridge.conf` if needed. Run `ethlist.exe` and set the `\Device\NPF_{…}` line to your VMnet8 adapter.
2. Run **`start-hecnet.cmd`** (leave the window open).
3. Run **`start-vm.cmd`**.
4. On the guest console, follow [`GUEST-CHECKLIST.md`](GUEST-CHECKLIST.md).
5. From Windows: `ssh <user>@<guest-ip>`

## Networking contract

- NIC model: `ne2k_pci` (guest driver: `drvNE2k`)
- QEMU ↔ hecnet: UDP socket `0.0.0.0:5001` ↔ `127.0.0.1:5000` (vlan 5)
- LAN: hecnet bridges into VMnet8 (see `bridge.conf`)
- SSH: guest TCP port 22

## SSH smoke test

```bat
ping <guest-ip>
ssh <user>@<guest-ip> hostname
```

Success: interactive login or a printed hostname.

## Optional RSH

Not required for Phase 1. On the guest, `shell` / `login` in `/etc/inetd.conf` are commented out by default. Enable only after SSH works; restart inetd.

## Failure guide

| Symptom | Likely cause |
|---------|----------------|
| hecnet can’t open device | Stale NPF GUID; VMnet8 missing; run as Admin; install Npcap |
| Guest no NIC / no link | hecnet not running; wrong `-net` args; try `install2.cmd` + `nic.flp` once |
| Ping / SSH timeout | Wrong guest IP/netmask; Windows firewall; not on VMnet8 |
| Connection refused on :22 | `sshd` not running; `SSHSERVER` not `-YES-` in `/etc/hostconfig` |
| Auth failure | Fix password or `authorized_keys` via console |

## Legacy scripts

- `install.cmd` / `install3.cmd` — CD/floppy install + net
- `install2.cmd` — boot with `nic.flp`

Prefer `start-hecnet.cmd` + `start-vm.cmd` for daily use.

## Next (Approach 2 — out of scope here)

Host helpers to `scp`/`rsync` the source tree into the guest and run remote `make -C ninja world` over SSH.
```

- [ ] **Step 2: Create `vm/GUEST-CHECKLIST.md`**

```markdown
# Guest checklist (Rhapsody console)

Use this after `start-vm.cmd` reaches a login prompt. Goal: SSH from the Windows host.

## 1. Network interface

- [ ] NE2000/PCI Ethernet is present (DriverKit / network prefs, or `ifconfig -a` if available).
- [ ] Interface has an address on the **VMnet8** subnet (same LAN as the host VMnet8 adapter).
- [ ] Default route / netmask look sane for that subnet.

If there is no NIC at all, shut down and try legacy `install2.cmd` with `nic.flp` once, then return to `start-vm.cmd`.

## 2. Connectivity

- [ ] Ping the host’s VMnet8 address (or the VMnet gateway).
- [ ] From the host, ping the guest IP.

## 3. SSH server

OpenSSH is intended to start when `SSHSERVER=-YES-` in `/etc/hostconfig` (see `files-5` sources; startup script `1700_IPServices`).

- [ ] Confirm `/etc/hostconfig` has `SSHSERVER=-YES-`.
- [ ] Confirm `sshd` is running (or start `/usr/sbin/sshd` once for testing).
- [ ] If prompted, allow host key generation under `/etc/ssh_host_key` / `/etc/ssh_host_dsa_key`.

## 4. Login from host

- [ ] From Windows: `ssh <user>@<guest-ip>`
- [ ] Run a trivial remote command (`hostname`, `uname`, or `ls`).

## 5. Optional RSH (after SSH works)

- [ ] Uncomment `shell` / `login` in `/etc/inetd.conf` if you need RSH.
- [ ] Restart inetd.
- [ ] Test `rsh` / `rlogin` from the host.

Phase 1 success = steps 1–4. RSH is optional.
```

- [ ] **Step 3: Commit**

```bash
git add vm/README.md vm/GUEST-CHECKLIST.md
git commit -m "$(cat <<'EOF'
Document Rhapsody QEMU hecnet launch and guest SSH checklist.

EOF
)"
```

---

### Task 5: Manual verification notes (no CI)

**Files:**
- Modify: `vm/README.md` only if smoke results require a factual correction (ports, adapter name, etc.)

- [ ] **Step 1: Dry-run script presence from `vm/`**

```bat
cd /d Z:\RhapsodiOS\RhapsodiOS\vm
dir start-hecnet.cmd start-vm.cmd bridge.conf.example README.md GUEST-CHECKLIST.md
```

Expected: all five listed.

- [ ] **Step 2: Attempt hecnet config presence**

```bat
if exist bridge.conf (echo bridge.conf OK) else (echo MISSING: copy bridge.conf.example)
if exist hecnet.exe (echo hecnet.exe OK) else (echo MISSING binary)
if exist qemu.exe (echo qemu.exe OK) else (echo MISSING binary)
if exist rhapsody.vmdk (echo vmdk OK) else (echo MISSING disk)
```

- [ ] **Step 3: Record outcome in commit message or README only if something was wrong**

If binaries/`bridge.conf` are present, try `start-hecnet.cmd` then `start-vm.cmd` and SSH smoke per README. If the environment cannot run the GUI VM in this agent session, document that Phase 1 **script/doc deliverables are complete** and **live SSH confirmation remains a human smoke test** — do not invent pass results.

- [ ] **Step 4: Final commit only if README/checklist needed edits after smoke**

```bash
git add vm/README.md vm/GUEST-CHECKLIST.md
git commit -m "$(cat <<'EOF'
Amend VM docs from Phase 1 smoke findings.

EOF
)"
```

If no doc changes: skip commit; note “no doc amendments” in the task report.

---

## Spec coverage (plan self-review)

| Spec requirement | Task |
|------------------|------|
| `start-hecnet.cmd` / `start-vm.cmd` | 2, 3 |
| `README.md` + failure guide + Approach 2 note | 4 |
| `bridge.conf.example` | 2 |
| `GUEST-CHECKLIST.md` | 4 |
| Legacy `install*.cmd` pointers | 3 |
| `.gitignore` binary vs script split | 1 |
| Manual SSH verification / no CI | 5 |
| Non-goals (no modern QEMU, no sync CLI) | Honored — not in any task |
