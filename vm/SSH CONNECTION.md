# SSH to the legacy PPC build box

Rhapsody DR2 / Mac OS X Server 1.x `sshd` only negotiates weak SSH-2 algorithms.
A modern client that offers only current defaults will see the server close the
socket (`Remote side unexpectedly closed network connection`).

## Interactive login (OpenSSH)

```bat
ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-dss -o Ciphers=3des-cbc -o MACs=hmac-sha1 root@10.10.0.241
```

Password / host / user come from `vm/vm.conf` (`Password=`, `Host=`, `User=`).
Prefer those values when they differ from the example above.

## Shared helper (`rhap-remote.ps1`)

`sync-src.ps1` and `build-src.ps1` both dot-source `vm/rhap-remote.ps1`, which:

- Passes the same legacy `-o` options as the interactive login line
- Supplies the password non-interactively via `SSH_ASKPASS` (OpenSSH has no `-pw`)
- Uses `StrictHostKeyChecking=no` and a throwaway known_hosts under `%TEMP%`
  (Windows OpenSSH often fails to update `~/.ssh/known_hosts` for this guest’s
  `ssh-dss` host key, which aborts sessions under `accept-new`)
- Returns only a numeric SSH exit code to callers — build logs go through
  `Write-Host` so PowerShell does not treat `make` stdout as the exit status

## Syncing source (`sync-src.ps1`)

Modern `scp` drops the connection against this guest even with `-O`. The sync
script streams a ustar archive over SSH instead (`tar | ssh` via `cmd.exe` for
a binary-safe pipe on Windows PowerShell 5.x).

```bat
powershell -File vm\sync-src.ps1 -All
powershell -File vm\sync-src.ps1 -Path drivers-i386/bus/drvPCMCIABus
```

Lands under `RemoteRoot/src` (see `RemoteRoot=` in `vm.conf`; example default
is `/build/source`, so sources appear at `/build/source/src`).

## Guest builds (`build-src.ps1`)

Same SSH path as sync. Typical fresh-box order after a sync:

```bat
powershell -File vm\build-src.ps1 -Rbuild
powershell -File vm\build-src.ps1 -Bootstrap
powershell -File vm\build-src.ps1 -Kernel
powershell -File vm\build-src.ps1 -KernelDrivers
powershell -File vm\build-src.ps1 -World
```

| Flag | What it runs on the guest |
|------|---------------------------|
| `-Rbuild` | Build/install `rbuild` from `RemoteRoot/src/rbuild-1` |
| `-Bootstrap` | `rbuild bootstrap BootstrapManifest` → `RepoDir` |
| `-Kernel` | `rbuild kernel` (driverkit through kernel-7) |
| `-KernelDrivers` | `rbuild kerneldrivers` for remaining `drivers-<arch>` packaged drivers, minus the JSON blacklist |
| `-World` | `rbuild buildall Manifest` |

`RepoDir` / `BuiltDir` / `Make` are also in `vm.conf` (defaults `/build/repo`,
`/build/built`, `gnumake`).

More detail: `README.md` sections “Syncing src/ to the guest” and “Guest builds”.

## What does not work (without extra setup)

- **Modern PuTTY `plink` / `pscp`** — defaults omit these algorithms; expect
  `FATAL ERROR: Remote side unexpectedly closed network connection` unless you
  load a saved session that re-enables them.
- **OpenSSH `scp`** (even `scp -O`) — often ends in `lost connection` after
  auth; use `sync-src.ps1` (`tar | ssh`) instead.

After each sync, `sync-src.ps1` restores `+x` on `configure` / autotools
helpers / `*.sh` / `*.pl` under the synced tree (Windows tar drops execute
bits, which breaks bootstrap).
