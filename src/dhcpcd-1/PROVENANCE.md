# dhcpcd-1 provenance

Vendored from `dhcpcd_1.3.17pl2.orig.tar.gz` (Sergei Viznyuk's classic
dhcpcd 1.3.x lineage, originally by Yoichi Hariguchi), sourced from Debian's
Potato-era archive:

- URL: https://snapshot.debian.org/file/418c0658b35ea3a2900ecb7812a3164bfe1f63e1
- Size: 152368 bytes
- SHA-1: 418c0658b35ea3a2900ecb7812a3164bfe1f63e1
- License: GNU GPL v2 (per each source file's header) — not BSD.

Only the top-level sources of the tarball are vendored here. Its bundled
legacy `dhcpcd-0.70/` snapshot, `pcmcia/` and `rc.d/` Linux-distro scripts,
the prebuilt Linux ELF binary `dhcpcd`, `dhcpcd-eth0.exe`, and
`dhcpcd-1.3.17.lsm` are Linux-distro packaging artifacts and were not
carried over.

Upstream's raw-packet layer (`arp.c`, and the socket/ioctl calls in
`client.c`) targets Linux `SOCK_PACKET`/`AF_PACKET`, and its default-route
code uses Linux's `SIOCADDRT` ioctl — there is no BSD variant of this lineage
to port instead. Three pairs of files in `dhcpcd.tproj/` are new to this
project, not part of upstream:

- `bpfif.c`/`bpfif.h` — BSD BPF raw-Ethernet backend replacing `SOCK_PACKET`.
- `rtsock.c`/`rtsock.h` — `PF_ROUTE` routing-socket default route replacing
  `SIOCADDRT`.
- `bootcompat.c`/`bootcompat.h` — bootpc-compatible `key=value` output for
  the `-w` flag.

Upstream files modified for this port (GPLv2 §2(a); see also the
RhapsodiOS entry at the top of `dhcpcd.tproj/Changes`): `arp.c`,
`buildmsg.c`, `client.c`, `client.h`, `dhcpcd.c`, `dhcpcd.8`,
`signals.c`, `udpipgen.h`. The new files are distributed under the
same GPLv2 terms as the rest of dhcpcd.

See `docs/superpowers/specs/2026-09-22-dhcpcd-1-client-daemon-design.md` for
the full design.
