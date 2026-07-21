# QEMU Rhapsody Dev VM Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `vm/rhap-vm.ps1` (PowerShell + PuTTY) to sync `src`/`ninja` to `/build/source` on the guest and run remote `make -C …/ninja world|kernel`, with credentials in untracked `vm.conf`.

**Architecture:** Single `rhap-vm.ps1` dispatcher; `Key=Value` `vm.conf`; `pscp -r` for sync; `plink` for mkdir/build/ssh. Extend `.gitignore` and Phase 1 README.

**Tech Stack:** PowerShell 5+, PuTTY `plink.exe`/`pscp.exe`, existing hecnet/QEMU guest.

**Spec:** [docs/superpowers/specs/2026-07-21-qemu-dev-vm-phase2-design.md](../specs/2026-07-21-qemu-dev-vm-phase2-design.md)

---

## File structure

| Path | Responsibility |
|------|----------------|
| `vm/rhap-vm.ps1` | Parse config; `sync` / `build` / `ssh` |
| `vm/vm.conf.example` | Template |
| `vm/vm.conf` | Local only (ignored) |
| `.gitignore` | Ignore `/vm/vm.conf` |
| `vm/README.md` | Phase 2 usage section |

---

### Task 1: Ignore `vm.conf` and add example config

**Files:**
- Modify: `.gitignore`
- Create: `vm/vm.conf.example`

- [ ] **Step 1: Append to `.gitignore`**

After the existing `/vm/bridge.conf` line, add:

```
/vm/vm.conf
```

- [ ] **Step 2: Create `vm/vm.conf.example`**

```
# Copy to vm.conf (gitignored). Local Rhapsody guest over hecnet/VMnet8.

Host=10.10.0.241
User=root
Password=abc123
RemoteRoot=/build/source
# LocalRoot=   (empty = parent directory of vm/)
Plink=plink.exe
Pscp=pscp.exe
SyncPaths=src;ninja
```

- [ ] **Step 3: Verify ignore**

```bash
git check-ignore -v vm/vm.conf vm/vm.conf.example
```

Expected: `vm.conf` ignored; `vm.conf.example` not ignored.

- [ ] **Step 4: Commit**

```bash
git add .gitignore vm/vm.conf.example
git commit -m "Add vm.conf example and ignore local VM credentials."
```

Do not stage unrelated dirty files.

---

### Task 2: Implement `rhap-vm.ps1`

**Files:**
- Create: `vm/rhap-vm.ps1`

- [ ] **Step 1: Write `vm/rhap-vm.ps1`**

Create the script with this full content:

```powershell
#Requires -Version 5.0
<#
.SYNOPSIS
  Sync source to Rhapsody QEMU guest and run remote builds (PuTTY plink/pscp).
.EXAMPLE
  pwsh -File vm\rhap-vm.ps1 sync
  pwsh -File vm\rhap-vm.ps1 build world
  pwsh -File vm\rhap-vm.ps1 ssh hostname
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('sync', 'build', 'ssh', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
$ConfPath = Join-Path $VmDir 'vm.conf'

function Write-Die([string]$Message) {
    Write-Error "rhap-vm: $Message"
    exit 1
}

function Get-VmConfig {
    if (-not (Test-Path -LiteralPath $ConfPath)) {
        Write-Die "missing $ConfPath — copy vm.conf.example to vm.conf and edit"
    }
    $cfg = @{
        Host       = ''
        User       = ''
        Password   = ''
        RemoteRoot = '/build/source'
        LocalRoot  = ''
        Plink      = 'plink.exe'
        Pscp       = 'pscp.exe'
        SyncPaths  = 'src;ninja'
    }
    Get-Content -LiteralPath $ConfPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        if ($cfg.ContainsKey($key)) { $cfg[$key] = $val }
    }
    foreach ($req in @('Host', 'User', 'Password')) {
        if ([string]::IsNullOrWhiteSpace($cfg[$req])) {
            Write-Die "vm.conf missing required key: $req"
        }
    }
    if ([string]::IsNullOrWhiteSpace($cfg.LocalRoot)) {
        $cfg.LocalRoot = Split-Path -Parent $VmDir
    }
    $cfg.RemoteRoot = $cfg.RemoteRoot.TrimEnd('/')
    return $cfg
}

function Resolve-Tool([string]$NameOrPath) {
    if (Test-Path -LiteralPath $NameOrPath) { return (Resolve-Path -LiteralPath $NameOrPath).Path }
    $cmd = Get-Command $NameOrPath -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Write-Die "tool not found: $NameOrPath (install PuTTY or set Plink/Pscp in vm.conf)"
}

function Invoke-Plink {
    param(
        [hashtable]$Cfg,
        [string[]]$RemoteArgs,
        [switch]$Batch
    )
    $plink = Resolve-Tool $Cfg.Plink
    $args = @()
    if ($Batch) { $args += '-batch' }
    $args += @('-pw', $Cfg.Password, "$($Cfg.User)@$($Cfg.Host)")
    $args += $RemoteArgs
    & $plink @args
    return $LASTEXITCODE
}

function Invoke-Sync([hashtable]$Cfg) {
    $pscp = Resolve-Tool $Cfg.Pscp
    $paths = @($Cfg.SyncPaths -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($paths.Count -eq 0) { Write-Die 'SyncPaths is empty' }

    foreach ($rel in $paths) {
        $local = Join-Path $Cfg.LocalRoot $rel
        if (-not (Test-Path -LiteralPath $local)) {
            Write-Die "sync path missing locally: $local"
        }
    }

    $mkdirCmd = "mkdir -p $($Cfg.RemoteRoot)"
    $ec = Invoke-Plink -Cfg $Cfg -Batch -RemoteArgs @($mkdirCmd)
    if ($ec -ne 0) { Write-Die "remote mkdir failed (exit $ec): $mkdirCmd" }

    foreach ($rel in $paths) {
        $local = Join-Path $Cfg.LocalRoot $rel
        $remoteSpec = "$($Cfg.User)@$($Cfg.Host):$($Cfg.RemoteRoot)/$($rel.Replace('\','/'))"
        Write-Host "rhap-vm: pscp $rel -> $remoteSpec"
        $pscpArgs = @('-batch', '-r', '-pw', $Cfg.Password, $local, $remoteSpec)
        & $pscp @pscpArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Die "pscp failed (exit $LASTEXITCODE) for $rel"
        }
    }
    Write-Host 'rhap-vm: sync complete'
}

function Invoke-Build([hashtable]$Cfg, [string[]]$Targets) {
    if (-not $Targets -or $Targets.Count -eq 0) { $Targets = @('world') }
    $targetStr = ($Targets -join ' ')
    $remote = "make -C $($Cfg.RemoteRoot)/ninja $targetStr"
    Write-Host "rhap-vm: $remote"
    $ec = Invoke-Plink -Cfg $Cfg -Batch -RemoteArgs @($remote)
    exit $ec
}

function Invoke-Ssh([hashtable]$Cfg, [string[]]$RemoteCmd) {
    if (-not $RemoteCmd -or $RemoteCmd.Count -eq 0) {
        $ec = Invoke-Plink -Cfg $Cfg -RemoteArgs @()
        exit $ec
    }
    $joined = ($RemoteCmd -join ' ')
    $ec = Invoke-Plink -Cfg $Cfg -Batch -RemoteArgs @($joined)
    exit $ec
}

$cfg = $null
switch ($Command) {
    'help' {
        Write-Host @"
Usage: pwsh -File vm\rhap-vm.ps1 <sync|build|ssh|help> [args...]

  sync              Upload SyncPaths to RemoteRoot via pscp
  build [targets]   Remote make -C RemoteRoot/ninja (default: world)
  ssh [command]     Interactive plink, or one-shot remote command

Config: vm\vm.conf (copy from vm.conf.example)
First connection: accept host key interactively once, then sync/build use -batch.
"@
        exit 0
    }
    'sync' {
        $cfg = Get-VmConfig
        Invoke-Sync $cfg
    }
    'build' {
        $cfg = Get-VmConfig
        Invoke-Build $cfg $Rest
    }
    'ssh' {
        $cfg = Get-VmConfig
        Invoke-Ssh $cfg $Rest
    }
}
```

- [ ] **Step 2: Syntax check**

```powershell
pwsh -NoProfile -Command "& { $null = [System.Management.Automation.Language.Parser]::ParseFile('vm/rhap-vm.ps1', [ref]$null, [ref]$errs); if ($errs) { $errs; exit 1 } else { 'OK' } }"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add vm/rhap-vm.ps1
git commit -m "Add rhap-vm.ps1 for PuTTY sync and remote ninja builds."
```

---

### Task 3: Create local `vm.conf` and update README

**Files:**
- Create: `vm/vm.conf` (local only — do **not** `git add`)
- Modify: `vm/README.md`

- [ ] **Step 1: Copy example to local config**

```powershell
Copy-Item -Force vm\vm.conf.example vm\vm.conf
```

Confirm `git check-ignore -v vm/vm.conf` shows ignored. Do not commit `vm.conf`.

- [ ] **Step 2: Update `vm/README.md`**

Replace the final “Next (Approach 2…)” section with Phase 2 docs, and adjust the intro line so Phase 1+2 are both covered. Append (or replace the Approach 2 stub with) this section:

```markdown
## Sync and remote build (Phase 2)

Requires PuTTY (`plink.exe`, `pscp.exe` on PATH) and a running guest with SSH
(see Quick start above). Known-good guest example: `10.10.0.241`.

1. Copy `vm.conf.example` → `vm.conf` (gitignored). Adjust `Host` / password if needed.
2. **One-time:** accept the SSH host key, e.g. run  
   `pwsh -File vm\rhap-vm.ps1 ssh hostname`  
   and confirm the PuTTY host-key prompt. Later `sync`/`build` use `-batch`.
3. Ensure guest has `/build/source` parent writable as `root` (script runs `mkdir -p`).

```powershell
pwsh -File vm\rhap-vm.ps1 sync
pwsh -File vm\rhap-vm.ps1 build          # make -C /build/source/ninja world
pwsh -File vm\rhap-vm.ps1 build kernel
pwsh -File vm\rhap-vm.ps1 ssh hostname
```

Default `SyncPaths` are `src` and `ninja` only (not `vm/` binaries, not `.git`).

Password is passed with PuTTY `-pw` from `vm.conf` — fine for a local lab VM; do not commit `vm.conf`.
```

Also change the top blurb from “Sync/build automation is deferred” to mention Phase 2 helpers exist (`rhap-vm.ps1`).

- [ ] **Step 3: Commit README only**

```bash
git add vm/README.md
git commit -m "Document rhap-vm.ps1 sync and remote build workflow."
```

---

### Task 4: Smoke verification

**Files:** none required unless docs need factual fixes

- [ ] **Step 1: Dry checks**

```powershell
cd Z:\RhapsodiOS\RhapsodiOS
Test-Path vm\rhap-vm.ps1, vm\vm.conf, vm\vm.conf.example
git check-ignore -v vm\vm.conf
pwsh -File vm\rhap-vm.ps1 help
```

- [ ] **Step 2: Live smoke (guest must be up)**

```powershell
pwsh -File vm\rhap-vm.ps1 ssh hostname
# optional if host key already accepted:
# pwsh -File vm\rhap-vm.ps1 sync
```

If the guest is down or host key blocks `-batch`, report **DONE_WITH_CONCERNS** with what passed locally; do not invent SSH success. Amend README only if a real factual error is found, then commit.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `rhap-vm.ps1` sync/build/ssh | 2 |
| `vm.conf.example` + ignore `vm.conf` | 1, 3 |
| SyncPaths default src;ninja | 2 |
| Remote make -C …/ninja | 2 |
| README + host-key note | 3 |
| Manual verification | 4 |
| No OpenSSH default / no NFS | Honored |
