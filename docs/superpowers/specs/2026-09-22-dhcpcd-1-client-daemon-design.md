# dhcpcd-1 — persistent DHCP client daemon

**Date:** 2026-09-22
**Status:** Design approved, pending implementation plan

## Summary

Port classic dhcpcd (Hariguchi/Viznyuk lineage, GPLv2-licensed — vendored
version pinned to 1.3.17-pl2, §Context) into a new `src/dhcpcd-1` project,
giving the system a persistent DHCP client daemon — initial lease acquisition
plus RFC 2131 renewal/rebinding — in place of the one-shot `bootpc` call
`/etc/startup/0800_Network` currently makes for `-AUTOMATIC-` interfaces in
`/etc/iftab`. This dhcpcd lineage's own raw-packet layer is Linux-specific
(`SOCK_PACKET`, not BPF); this port replaces that one layer with a new BSD/BPF
backend written for this tree, while porting the rest of the upstream source
(protocol state machine, DHCP option handling) largely as-is. Raw pre-IP
packet I/O goes through BPF (`/dev/bpf*`), via the `drvBPF` driver another
session owns; that driver's readiness is an external precondition, not part
of this work.

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
  net/bpf.h, net/if_arp.h, net/etherdefs.h, netinet/if_ether.h,
  netinet/in.h}`. Standard 4.4BSD BPF ioctls (`BIOCSETIF`, `BIOCIMMEDIATE`,
  `BIOCSBLEN`) and `struct bpf_hdr` are present in `net/bpf.h`. `struct
  ether_header` (`ether_dhost`/`ether_shost`/`ether_type`) is declared in
  `netinet/if_ether.h`, re-exported via `net/etherdefs.h` — there is no
  `net/ethernet.h` anywhere in the tree, which upstream dhcpcd's `client.h`
  expects; that's a one-line include swap. Standard BSD `ioctl`-based
  interface configuration (`SIOCGIFCONF`/`SIOCSIFADDR`/`SIOCSIFNETMASK`/…) is
  already in live use in `bootplib/interfaces.c`, including the `AF_LINK`/
  `struct sockaddr_dl` idiom for reading a interface's MAC address out of
  `SIOCGIFCONF` — the exact technique this port's BPF backend needs in place
  of Linux's `SIOCGIFHWADDR`.
- **Vendored source identified and verified**: `dhcpcd_1.3.17pl2.orig.tar.gz`,
  152368 bytes, SHA-1 `418c0658b35ea3a2900ecb7812a3164bfe1f63e1`, from
  Debian's Potato-era archive
  (`https://snapshot.debian.org/file/418c0658b35ea3a2900ecb7812a3164bfe1f63e1`).
  Downloaded and inspected: its raw-packet layer
  (`arp.c`, and the socket/ioctl calls in `client.c`) is written against
  Linux `SOCK_PACKET`/`AF_PACKET` and Linux-only ioctls
  (`SIOCGIFHWADDR`), confirmed by its own `README` ("Make sure your kernel is
  compiled with support for SOCK_PACKET"). Its DHCP/UDP/IP header-building
  code (`udpipgen.c`) and its `select()`-based timeout helper (`peekfd.c`) are
  plain portable C with no Linux dependency. Its interface-configuration
  ioctls (`SIOCSIFADDR`/`SIOCSIFNETMASK`/`SIOCSIFBRDADDR`/`SIOCSIFFLAGS`) are
  the same portable BSD-heritage ioctls `bootplib` already uses; only its
  route-add call (`SIOCADDRT`/`struct rtentry`) is Linux-specific.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| dhcpcd lineage | Classic Hariguchi/Viznyuk, pinned to 1.3.17-pl2 | Era-correct for a 1999 Darwin 0.3 fork (this exact release shipped in Debian Potato, 2000); small, plain C. GPLv2-licensed — not BSD as first assumed, but consistent with this tree's existing GPLv2 `apk-tools-1` vendoring precedent |
| Packet I/O | BPF via `/dev/bpf*`, **new code written for this port** | The only raw-Ethernet path in this tree; needed to receive a DHCPOFFER unicast to an address the interface doesn't own yet. Upstream 1.3.17-pl2's own raw-packet layer is Linux `SOCK_PACKET`-only — there is no BSD/BPF version of this lineage to port instead, so this port writes one, following the `AF_LINK`/`sockaddr_dl` and BPF-device conventions already proven elsewhere in this tree |
| `drvBPF` readiness | External precondition, not in scope | Owned by a concurrent session; this project must not touch `src/drvBPF` |
| Project location | `src/dhcpcd-1/` | Matches the tree's numbered-suffix convention for vendored projects (`bootp-1`, `apk-tools-1`) |
| Relationship to `bootp-1` | Self-contained; `bootplib` untouched | This is a source port of dhcpcd's own upstream code, not a `bootplib` extension. `bootpc`/`bootpd`/`bootplib` stay exactly as they are — just no longer invoked from the automatic-interface path |
| Boot integration | Replace the `bootpc` call in `0800_Network` | User's choice; dhcpcd owns the interface for its full lifetime afterward, so bootpc's one-shot role is fully superseded for `-AUTOMATIC-` interfaces |
| `0800_Network` diff size | Single command-name swap | dhcpcd's boot-mode wait flag emits the same `key=value` stdout protocol `SetNetConfig` already consumes, so no downstream script logic changes |
| Build verification | Manual cross-reference against this tree's actual headers now; real compile deferred | No local `cc`/`gcc`/WSL distro available in this environment, and the real `rbuild`/VM build looks actively in use by another session. Every fact this design and the plan rely on (struct fields, ioctl values, header paths) was confirmed by reading the actual installed headers, not assumed — but nothing here has been compiled. The maintainer runs the real build once the VM is free |

## Approach

1. **Vendor** dhcpcd 1.3.17-pl2 (§Context — exact tarball, checksum, and
   source URL confirmed) into `src/dhcpcd-1/dhcpcd.tproj/`, laid out like
   `bootpc.tproj`: `PB.project` with `PROJECTTYPE = Tool`,
   `Makefile`/`Makefile.preamble`/`Makefile.postamble` via `pb_makefiles`'
   `tool.make`, `NEXTSTEP_INSTALLDIR = /usr/sbin`. Only the top-level
   dhcpcd-1.3.17-pl2 sources are vendored — its bundled legacy `dhcpcd-0.70/`
   snapshot and Linux-distro `pcmcia/`/`rc.d/` scripts are Linux-distro
   artifacts, not needed here, and are dropped. A top-level `src/dhcpcd-1/`
   aggregate wraps it the way `src/bootp-1/Makefile` wraps its tools, even
   though this project starts with a single tool.
2. **Portability pass** over the vendored source, fixing only what's
   Linux-specific: the `<net/ethernet.h>` include (→ `<netinet/if_ether.h>`
   with the prerequisite headers userland code here includes before it, plus
   a fallback `ETHER_ADDR_LEN`, which this tree doesn't define), the headers
   `netinet/ip.h` needs in `udpipgen.h`, and the `SIOCADDRT`/`struct
   rtentry` route-add call in `dhcpConfig()` (→ a `PF_ROUTE` routing-socket
   message in a new `rtsock.c`, encoded the way `route(8)` encodes it, which
   also updates the route on renewal if the router changes). Everything
   else the source touches (`SIOCSIFADDR`/`SIOCSIFNETMASK`/`SIOCSIFBRDADDR`/
   `SIOCSIFFLAGS`, `struct ether_header` field names, `ARPHRD_ETHER`,
   `IFF_UP`/`IFF_BROADCAST`/`IFF_MULTICAST`/`IFF_NOTRAILERS`/`IFF_RUNNING`)
   is already confirmed present and BSD-compatible in this tree's headers —
   no change needed. Self-contained — no dependency on `bootplib`.
   Upstream's `/etc/resolv.conf` handling is kept as-is: dhcpcd saves the
   existing file as `resolv.conf.sv`, writes one from the DHCP server's DNS
   options, and restores the saved copy when it stops.
3. **New BSD/BPF backend** (`bpfif.c`/`bpfif.h`, new files) replacing the
   Linux-only raw-packet layer: opening `/dev/bpf*` and binding it to an
   interface via `BIOCSETIF`/`BIOCIMMEDIATE`, reading the interface's MAC
   address via the same `AF_LINK`/`struct sockaddr_dl`/`SIOCGIFCONF` idiom
   `bootplib/interfaces.c` already uses, and send/receive functions that
   replace the four `sendto`/`recvfrom` call sites in `client.c` and `arp.c`.
   `dhcpSocket` stays a plain `int` fd throughout — BPF fds support ordinary
   `read()`/`write()` plus `select()`, so `peekfd()` (already portable,
   `select()`-based) and the rest of the send/receive call shape need no
   change beyond swapping the four call sites themselves.
4. **Boot-compat wait mode**: add a `-w` flag that blocks until the first
   DHCPACK is processed and the interface is configured, prints the same
   `key=value` fields bootpc's stdout produces today (exact field list
   confirmed against `bootpc.m` during implementation), then forks to the
   background and continues as the persistent renewal daemon — applying
   `ifconfig` itself on every subsequent RENEWING/REBINDING transition, since
   nothing else will touch the interface after boot.
5. **`0800_Network` change**: `if config=$(bootpc "${if}")` becomes
   `if config=$(dhcpcd -w "${if}")`. That is the only line that changes;
   every `SetNetConfig`/`GetNetConfig` consumer downstream is untouched.
6. **Leave `bootpc`/`bootpd`/`bootplib` in place**, unreferenced by the
   automatic-interface path but not deleted.

## Work items

1. Vendor dhcpcd 1.3.17-pl2 (top-level sources only) into
   `src/dhcpcd-1/dhcpcd.tproj/`.
2. `src/dhcpcd-1/{PB.project,Makefile,Makefile.preamble,Makefile.postamble}`
   plus `dhcpcd.tproj/{PB.project,Makefile,Makefile.preamble,
   Makefile.postamble}`, mirroring `bootpc.tproj`.
3. Portability pass: `<net/ethernet.h>` → `<netinet/if_ether.h>` plus
   `ETHER_ADDR_LEN`, `netinet/ip.h`'s prerequisites in `udpipgen.h`, and the
   `SIOCADDRT` route-add call → a `PF_ROUTE` routing-socket message
   (`rtsock.c`).
4. New `bpfif.c`/`bpfif.h` BSD/BPF backend, wired to `/dev/bpf*` and the
   `PostLoad` device-node convention, replacing the Linux `SOCK_PACKET`
   layer in `client.c` and `arp.c`.
5. `-w` boot-compat wait mode with bootpc-compatible `key=value` output.
6. One-line `0800_Network` change.

## Verification

- **Now (drvBPF not yet buildable, no local compiler available)**: every
  changed or new line is checked by hand against this tree's actual installed
  headers (`src/kernel-7/bsd/...`) — the same way every struct field, ioctl
  value, and header path in this document was confirmed, not assumed. No
  compiler is available in this environment and the real `rbuild`/VM build
  looks actively in use by another session, so nothing here is claimed to
  compile yet.
- **Once the VM/`rbuild` flow is free and `drvBPF` is buildable** (both
  external, checked with the maintainer before either is used): real
  build verification — `dhcpcd-1` compiles, links, and installs a `Tool`
  binary to `/usr/sbin` — followed by a boot-test on a temporary/isolated
  disk image confirming dhcpcd acquires a lease, that `0800_Network`'s
  existing `SetNetConfig`/`GetNetConfig` flow behaves identically to the
  current bootpc path (hostname, router, default route all still resolve),
  and that a renewal cycle (forced with a short lease time from a test DHCP
  server) re-applies the address without a reboot.

## Deliverables

- `src/dhcpcd-1/` — new project (vendored + adapted source, build files).
- `src/files-5/private/etc/startup/0800_Network` — one-line change.
- `src/files-5/private/etc/Makefile` — creates an empty `/etc/dhcpc`, where
  dhcpcd keeps its lease cache and info file.
- `bootpc`/`bootpd`/`bootplib` unchanged.

## Out of scope

- `src/drvBPF` itself — owned by a concurrent session, not touched here.
- IPv6, privilege separation, or any dhcpcd feature newer than the ~1.3.x
  line.
- The DHCP *server* side (`bootpd.tproj`/`dhcpd.m`) — unrelated to this
  client daemon.
- Retiring or deleting `bootpc` — left in the tree per the project's
  surgical-changes convention.
