# Rhapsody QEMU VM (Windows + hecnet)

Phase 1: start the existing local QEMU stack and confirm networking / SSH.
Phase 2: use `rhap-vm.ps1` for sync and remote build over SSH (see below).

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
| hecnet can't open device | Stale NPF GUID; VMnet8 missing; run as Admin; install Npcap |
| Guest no NIC / no link | hecnet not running; wrong `-net` args; try `install2.cmd` + `nic.flp` once |
| Ping / SSH timeout | Wrong guest IP/netmask; Windows firewall; not on VMnet8 |
| Connection refused on :22 | `sshd` not running; `SSHSERVER` not `-YES-` in `/etc/hostconfig` |
| Auth failure | Fix password or `authorized_keys` via console |

## Legacy scripts

- `install.cmd` / `install3.cmd` — CD/floppy install + net
- `install2.cmd` — boot with `nic.flp`

Prefer `start-hecnet.cmd` + `start-vm.cmd` for daily use.

## Sync and remote build (Phase 2)

Requires PuTTY (`plink.exe`, `pscp.exe` on PATH) and a running guest with SSH
(see Quick start above). Known-good guest example: `10.10.0.241`.

1. Copy `vm.conf.example` → `vm.conf` (gitignored). Adjust `Host` / password if needed.
2. **One-time:** accept the SSH host key, e.g. run  
   `powershell -File vm\rhap-vm.ps1 ssh hostname`  
   and confirm the PuTTY host-key prompt. Later `sync`/`build` use `-batch`.
3. Ensure guest has `/build/source` parent writable as `root` (script runs `mkdir -p`).

```powershell
powershell -File vm\rhap-vm.ps1 sync
powershell -File vm\rhap-vm.ps1 build          # cd /build/source/ninja && make world
powershell -File vm\rhap-vm.ps1 build kernel
powershell -File vm\rhap-vm.ps1 ssh hostname
```

Default `SyncPaths` are `src` and `ninja` only (not `vm/` binaries, not `.git`).
Remote builds use **`gnumake`** (GNU Make) by default — Rhapsody’s BSD `make`
cannot parse `ninja/samurai`’s `ifeq` directives. Override with `Make=` in `vm.conf`
if needed.

Password is passed with PuTTY `-pw` from `vm.conf` — fine for a local lab VM; do not commit `vm.conf`.
