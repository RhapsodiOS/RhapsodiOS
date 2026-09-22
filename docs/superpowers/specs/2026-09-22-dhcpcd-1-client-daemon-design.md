# dhcpcd-1 — persistent DHCP client daemon

**Date:** 2026-09-22
**Status:** Design approved, pending implementation plan

## Summary

Port classic BSD dhcpcd (Hariguchi/Viznyuk lineage, ~1.3.x, BSD-licensed) into
a new `src/dhcpcd-1` project, giving the system a persistent DHCP client
daemon — initial lease acquisition plus RFC 2131 renewal/rebinding — in place
of the one-shot `bootpc` call `/etc/startup/0800_Network` currently makes for
`-AUTOMATIC-` interfaces in `/etc/iftab`. Raw pre-IP packet I/O goes through
BPF (`/dev/bpf*`), via the `drvBPF` driver another session owns; that driver's
readiness is an external precondition, not part of this work.

## Context / current state

- **`src/bootp-1/bootpc.tproj`** — the existing BOOTP/DHCP client. One-shot,
  no BPF (plain broadcast UDP socket — the classic CMU bootpc style), run
  exactly once at boot. It has no renewal path: if a lease expires or the
  interface bounces, nothing re-triggers it.
- **How `0800_Network` uses it today**: for each `-AUTOMATIC-` interface, the
  script brings the interface up unconfigured
  (`ifconfig "$if" 0.0.0.0 netmask 255.0.0.0 broadcast 255.255.255.255`),
  runs `config=$(bootpc "$if")`, and feeds bootpc's `key=value` stdout into
  `SetNetConfig "$if" $config`. Later sections of the same script call
  `GetNetConfig` to pull `ip_address`, `subnet_mask`, `host_name`, `router`,
  and `server_ip_address` back out, and use them to run the real `ifconfig`,
  set the hostname, and add the default route. This `SetNetConfig`/
  `GetNetConfig` protocol is the integration seam this port needs to stay
  compatible with.
- **`src/drvBPF`** — kernel BPF driver (`BPF.lksproj`) plus a userspace
  `PostLoad` helper that `mknod`s `/dev/bpf0`, `/dev/bpf1`, … after the driver
  loads. Owned by a concurrent session; its own
  `reconstruction/divergences.md` states it has never been built. Not touched
  by this work — treated purely as an external dependency this daemon links
  against once it exists.
- **Headers confirmed present**: `src/kernel-7/bsd/{sys/socket.h, net/if.h,
  net/bpf.h, netinet/in.h}`. Standard BSD `ioctl`-based interface
  configuration (`SIOCGIFCONF`/`SIOCSIFADDR`/`SIOCSIFNETMASK`/…) is already in
  live use in `bootplib/interfaces.c`, confirming the same API surface is
  available to this port.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| dhcpcd lineage | Classic Hariguchi/Viznyuk, ~1.3.x | Era-correct for a 1999 Darwin 0.3 fork; small, plain C, BSD-licensed; avoids modern dhcpcd's privsep/IPv6 baggage that doesn't fit this kernel |
| Packet I/O | BPF via `/dev/bpf*` | The only raw-Ethernet path in this tree; needed to receive a DHCPOFFER unicast to an address the interface doesn't own yet |
| `drvBPF` readiness | External precondition, not in scope | Owned by a concurrent session; this project must not touch `src/drvBPF` |
| Project location | `src/dhcpcd-1/` | Matches the tree's numbered-suffix convention for vendored projects (`bootp-1`, `apk-tools-1`) |
| Relationship to `bootp-1` | Self-contained; `bootplib` untouched | This is a source port of dhcpcd's own upstream code, not a `bootplib` extension. `bootpc`/`bootpd`/`bootplib` stay exactly as they are — just no longer invoked from the automatic-interface path |
| Boot integration | Replace the `bootpc` call in `0800_Network` | User's choice; dhcpcd owns the interface for its full lifetime afterward, so bootpc's one-shot role is fully superseded for `-AUTOMATIC-` interfaces |
| `0800_Network` diff size | Single command-name swap | dhcpcd's boot-mode wait flag emits the same `key=value` stdout protocol `SetNetConfig` already consumes, so no downstream script logic changes |

## Approach

1. **Vendor** an upstream classic-dhcpcd (~1.3.x) source tree into
   `src/dhcpcd-1/dhcpcd.tproj/`, laid out like `bootpc.tproj`: `PB.project`
   with `PROJECTTYPE = Tool`, `Makefile`/`Makefile.preamble`/
   `Makefile.postamble` via `pb_makefiles`' `tool.make`,
   `NEXTSTEP_INSTALLDIR = /usr/sbin`. A top-level `src/dhcpcd-1/` aggregate
   wraps it the way `src/bootp-1/Makefile` wraps its tools, even though this
   project starts with a single tool.
2. **Portability pass** over the vendored source: audit for Linux-only
   headers/calls the way the `apk-tools-1` port did, and confirm every BSD
   ioctl the source expects (`SIOCSIFADDR`, `SIOCSIFNETMASK`, and the BPF set
   `BIOCSETIF`/`BIOCIMMEDIATE`/`BIOCSBLEN`/`BIOCSETF`) matches
   `src/kernel-7/bsd/net/{if,bpf}.h`. Self-contained — no dependency on
   `bootplib`.
3. **Boot-compat wait mode**: add a `-w` flag that blocks until the first
   DHCPACK is processed and the interface is configured, prints the same
   `key=value` fields bootpc's stdout produces today (exact field list
   confirmed against `bootpc.m` during implementation), then forks to the
   background and continues as the persistent renewal daemon — applying
   `ifconfig` itself on every subsequent RENEWING/REBINDING transition, since
   nothing else will touch the interface after boot.
4. **`0800_Network` change**: `if config=$(bootpc "${if}")` becomes
   `if config=$(dhcpcd -w "${if}")`. That is the only line that changes;
   every `SetNetConfig`/`GetNetConfig` consumer downstream is untouched.
5. **Leave `bootpc`/`bootpd`/`bootplib` in place**, unreferenced by the
   automatic-interface path but not deleted.

## Work items

1. Locate and vendor a classic dhcpcd (~1.3.x) source tarball.
2. `src/dhcpcd-1/{PB.project,Makefile,Makefile.preamble,Makefile.postamble}`
   plus `dhcpcd.tproj/`, mirroring `bootpc.tproj`.
3. Portability pass: header/ioctl audit against this tree, fix only what
   blocks the build (same discipline as the apk-tools-1 port — minimal shims,
   not a rewrite).
4. BPF I/O layer wired to `/dev/bpf*` and the `PostLoad` device-node
   convention.
5. Interface configuration via the standard `ioctl` calls, for both initial
   acquisition and every renewal.
6. `-w` boot-compat wait mode with bootpc-compatible `key=value` output.
7. One-line `0800_Network` change.
8. Lease-info persistence file for warm restart (secondary; not required for
   boot integration to work).

## Verification

- **Now (drvBPF not yet buildable)**: build-only — `dhcpcd-1` compiles,
  links, and installs a `Tool` binary to `/usr/sbin`. No claim of a working
  DHCP exchange until `drvBPF` exists.
- **Once `drvBPF` is ready** (separately, by the owning session): boot-test
  on a temporary/isolated disk image — confirm dhcpcd acquires a lease, that
  `0800_Network`'s existing `SetNetConfig`/`GetNetConfig` flow behaves
  identically to the current bootpc path (hostname, router, default route all
  still resolve), and that a renewal cycle (forced with a short lease time
  from a test DHCP server) re-applies the address without a reboot.

## Deliverables

- `src/dhcpcd-1/` — new project (vendored + adapted source, build files).
- `src/files-5/private/etc/startup/0800_Network` — one-line change.
- `bootpc`/`bootpd`/`bootplib` unchanged.

## Out of scope

- `src/drvBPF` itself — owned by a concurrent session, not touched here.
- IPv6, privilege separation, or any dhcpcd feature newer than the ~1.3.x
  line.
- The DHCP *server* side (`bootpd.tproj`/`dhcpd.m`) — unrelated to this
  client daemon.
- Retiring or deleting `bootpc` — left in the tree per the project's
  surgical-changes convention.
