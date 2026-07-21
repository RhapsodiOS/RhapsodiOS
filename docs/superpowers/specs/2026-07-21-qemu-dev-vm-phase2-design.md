# QEMU Rhapsody dev VM — Phase 2 (sync + remote build) design

**Date:** 2026-07-21  
**Status:** Approved  
**Depends on:** Phase 1 (`2026-07-19-qemu-dev-vm-phase1-design.md`) — hecnet/QEMU + SSH proven (`10.10.0.241`)

## Summary

Add Windows PowerShell helpers under `vm/` that use **PuTTY** (`pscp` / `plink`) to sync selected source trees to the guest at `/build/source` and run remote `make -C …/ninja world|kernel`. Credentials and host live in an untracked `vm.conf`.

## Goals

1. Sync `src` and `ninja` (configurable) from the repo to `root@10.10.0.241:/build/source/…`.
2. Remote build via `plink`: default `make -C /build/source/ninja world`; support `kernel` and other make targets.
3. Thin interactive/`one-shot` remote shell helper (`ssh` subcommand → `plink`).
4. Keep password out of git (`vm.conf` ignored; `vm.conf.example` tracked).

## Non-goals

- OpenSSH as the default automation client (PuTTY only for these helpers).
- NFS / shared folders / auto-start hecnet/QEMU.
- rsync incremental sync or encrypted secret store.
- CI.

## Decisions

| Topic | Choice |
|-------|--------|
| Host scripting | PowerShell (`rhap-vm.ps1`) |
| Transport | PuTTY `pscp` / `plink` |
| Auth | `root` / `abc123` in local `vm.conf` (`-pw`) |
| Remote tree | `/build/source` |
| Sync scope | Listed paths only (default `src;ninja`) — not whole repo, not `vm/` binaries |
| Build | `make -C <RemoteRoot>/ninja <target>` |

## Architecture

```
Windows (repo LocalRoot)              Guest Host
────────────────────────              ──────────
rhap-vm.ps1 sync  ──pscp -r -pw──►   RemoteRoot/src, RemoteRoot/ninja
rhap-vm.ps1 build ──plink -pw────►   make -C RemoteRoot/ninja world|kernel
rhap-vm.ps1 ssh   ──plink────────►   interactive or one-shot remote cmd
         ▲
      vm.conf
```

## Deliverables

| Path | Role |
|------|------|
| `vm/rhap-vm.ps1` | CLI: `sync`, `build`, `ssh` |
| `vm/vm.conf.example` | Template config |
| `vm/vm.conf` | Machine-local (gitignored) |
| `vm/README.md` | Document Phase 2 usage; keep Phase 1 launch docs |
| `.gitignore` | Add `/vm/vm.conf` |

## Config keys (`vm.conf`)

INI-style or simple `Key=Value` lines (implementation: `Key=Value`, `#` comments):

| Key | Example |
|-----|---------|
| `Host` | `10.10.0.241` |
| `User` | `root` |
| `Password` | `abc123` |
| `RemoteRoot` | `/build/source` |
| `LocalRoot` | empty = parent of `vm/` |
| `Plink` | `plink.exe` (or full path) |
| `Pscp` | `pscp.exe` (or full path) |
| `SyncPaths` | `src;ninja` |

## CLI

```text
pwsh -File vm\rhap-vm.ps1 sync
pwsh -File vm\rhap-vm.ps1 build [world|kernel|…]
pwsh -File vm\rhap-vm.ps1 ssh [remote-command…]
```

### `sync`

1. Load `vm.conf`; resolve tools on PATH if bare names.
2. Fail if any `SyncPaths` entry is missing under `LocalRoot`.
3. `plink -batch … "mkdir -p RemoteRoot"` (and per-path parents as needed).
4. For each path: `pscp -batch -r -pw … LocalRoot\<path> User@Host:RemoteRoot/<path>`.

### `build`

1. Default target `world` if none given.
2. `plink -batch … "make -C RemoteRoot/ninja <targets…>"`.
3. Exit with plink/make status.

### `ssh`

- No args: interactive `plink` (no `-batch`).
- With args: `plink -batch … <joined remote command>`.

### Host key

Document one-time interactive accept (PuTTY/plink). Scripts use `-batch` for non-interactive sync/build after that.

## Error handling

| Case | Behavior |
|------|----------|
| No `vm.conf` | Instruct copy from example; exit 1 |
| Tool missing | Error naming `Plink`/`Pscp`; exit 1 |
| Missing sync path | Fail fast; exit 1 |
| Remote failure | Propagate exit code |

## Verification

1. `rhap-vm.ps1 ssh hostname`
2. `rhap-vm.ps1 sync` → trees under `/build/source`
3. `rhap-vm.ps1 build world` → make output (full world may be long)
4. `git check-ignore -v vm/vm.conf` ignored; example tracked

## Success criteria

- Sync + build + ssh work against the known guest with PuTTY.
- Password only in untracked `vm.conf`.
- README covers host-key step and commands.
- Phase 1 start scripts unchanged in behavior.
