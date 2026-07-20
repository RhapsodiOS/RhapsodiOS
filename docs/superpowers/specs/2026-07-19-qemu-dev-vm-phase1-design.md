# QEMU Rhapsody dev VM — Phase 1 (networking + SSH) design

**Date:** 2026-07-19  
**Status:** Approved  
**Phase:** 1 of N (Approach 1 — confirm networking/SSH before sync/build automation)

## Summary

Formalize the existing Windows `vm/` stack (old `qemu.exe`, `hecnet.exe`, `rhapsody.vmdk`, NE2000 via UDP socket bridged to VMware VMnet8) so it is reliably startable and SSH from the host into the guest can be confirmed. Keep automation thin; defer sync/build CLI (Approach 2) until SSH works.

## Goals

1. Reliable two-step start: hecnet bridge → QEMU guest on VMnet8.
2. Confirm guest networking and **SSH** login from the Windows host.
3. Document optional **RSH** enablement (not a success gate).
4. Leave an explicit handoff note for Approach 2 (SSH push sync + remote build).

## Non-goals

- Modern QEMU or cross-platform launchers.
- Automated `scp`/`rsync` sync or remote `make` wrappers.
- Rebuilding or replacing `rhapsody.vmdk`.
- PowerPC guest.
- Committing large binaries (`qemu.exe`, disk images, WinPcap helpers) to git.

## Decisions (from brainstorming)

| Topic | Choice |
|-------|--------|
| Guest role | Build **and** debug (one reusable VM) |
| Remote login | SSH primary; RSH optional/docs-only in this phase |
| Host focus | Windows-first; formalize existing `vm/` + hecnet |
| Source delivery (later) | SSH push (Approach 2); not automated here |
| Phase 1 approach | Document + thin launch scripts |

## Architecture

```
Windows host                     Guest (rhapsody.vmdk)
─────────────                    ────────────────────
hecnet.exe  ←→ UDP socket ←→  qemu.exe (-net nic,ne2k_pci)
     ↕                              ↕
  VMnet8  ←——————————————→  NE2k + TCP/IP + sshd (:22)
```

- Guest NIC model: **`ne2k_pci`** (in-tree driver: `src/drivers/x86/network/drvNE2k`).
- Host↔QEMU: existing **UDP socket** setup (ports **5000 / 5001**, vlan as in current scripts).
- LAN: **hecnet → VMnet8** (not user-mode/SLIRP in this phase).
- SSH: guest port **22** (`SSHSERVER=-YES-` already in `src/files-5/private/etc/hostconfig`; started from `1700_IPServices`).

## Deliverables

Under `vm/` (scripts and docs tracked in git; binaries remain local/ignored):

| Path | Role |
|------|------|
| `start-hecnet.cmd` | Start `hecnet` with `bridge.conf` (run first; leave running) |
| `start-vm.cmd` | Day-to-day boot from `rhapsody.vmdk` (based on `install3.cmd`) |
| `README.md` | Launch order, VMnet/hecnet notes, SSH smoke test, optional RSH, Approach 2 deferral |
| `bridge.conf.example` | Template for `[bridge]` / `[tcpip]`; real `bridge.conf` stays machine-local |
| `GUEST-CHECKLIST.md` | Console steps: NE2k, IP, sshd, keys/login |
| `install.cmd` / `install2.cmd` / `install3.cmd` | Kept as legacy; header comments point at new scripts |

### `.gitignore`

Replace blanket `/vm` ignore with patterns that ignore binaries and machine-local config (`*.exe`, `*.dll`, `*.vmdk`, `*.flp`, `*.iso`, `*.img`, `pc-bios/`, `bridge.conf`) while allowing the tracked scripts/docs above.

## Launch order

1. Ensure VMware **VMnet8** (or the adapter named in `bridge.conf`) exists; refresh NPF GUID via `ethlist.exe` if needed.
2. `start-hecnet.cmd`
3. `start-vm.cmd`
4. Guest console: confirm link + IP on the VMnet8 subnet.
5. Host: `ssh <user>@<guest-ip>`

### `start-vm.cmd` defaults

Derived from current `install3.cmd`:

- `-L pc-bios -m 512 -k en-us -rhapsodymouse`
- `-hda rhapsody.vmdk`
- `-net nic,model=ne2k_pci,vlan=5`
- `-net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000`
- `-boot c`

CD-ROM / install floppy are optional for day-to-day boot (omit unless reinstalling).

## Verification

| Step | Pass criteria |
|------|----------------|
| Hecnet | Starts without adapter errors |
| Guest boot | Reaches multi-user / login on console |
| L2/L3 | Guest has VMnet8-subnet address; ping host↔guest (or guest→gateway) |
| SSH | Host runs a remote command successfully |
| RSH | Optional only; not required for phase success |

### Failure guide (documented in README)

| Symptom | Likely cause |
|---------|----------------|
| hecnet can’t open device | Stale NPF GUID; VMnet8 missing; need Admin / WinPcap-Npcap |
| Guest no NIC / no link | Wrong net args; hecnet not running; may need `nic.flp` once |
| Ping/SSH timeout | Guest IP/netmask; Windows firewall; wrong VMnet |
| SSH refused | `sshd` / `SSHSERVER`; host keys |
| SSH auth fails | Fix user/password or keys via console |

## Success criteria

- Documented two-command start on this Windows setup.
- Confirmed SSH session from host into guest (manual smoke; not CI).
- README + guest checklist match what actually works.
- Explicit deferral of Approach 2 (sync/build CLI).

## Follow-on (out of scope)

**Approach 2:** Host orchestration (`sync` via scp/rsync, `ssh`, remote `make -C ninja world`) once Phase 1 SSH is proven.
