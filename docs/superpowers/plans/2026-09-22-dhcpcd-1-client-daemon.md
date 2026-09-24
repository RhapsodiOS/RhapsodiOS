# dhcpcd-1 Client Daemon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port dhcpcd 1.3.17-pl2 into `src/dhcpcd-1`, with a new BSD/BPF raw-packet backend replacing its Linux `SOCK_PACKET` layer, so it can replace the one-shot `bootpc` call in `0800_Network` with a persistent, lease-renewing DHCP client.

**Architecture:** Vendor dhcpcd's upstream C source largely unchanged (its DHCP state machine, option parsing, and UDP/IP header building are already portable). Replace only its Linux-specific raw-Ethernet I/O with a new `bpfif.c` module built on `/dev/bpf*`, following the same `AF_LINK`/`sockaddr_dl` idiom this tree's `bootplib/interfaces.c` already uses for reading a MAC address, and its Linux route ioctl with a new `rtsock.c` module that installs the default route through a `PF_ROUTE` socket the way `route(8)` does. Add a small `bootcompat.c` module so a new `-w` flag lets the boot script capture dhcpcd's first lease the same way it captures `bootpc`'s today.

**Tech Stack:** Plain K&R-ish C, `pb_makefiles`/`tool.make` (NeXT/Apple Project Builder build system), 4.4BSD `ioctl`s, 4.4BSD BPF (`net/bpf.h`).

## Global Constraints

- Vendored source: `dhcpcd_1.3.17pl2.orig.tar.gz`, 152368 bytes, SHA-1
  `418c0658b35ea3a2900ecb7812a3164bfe1f63e1`, from
  `https://snapshot.debian.org/file/418c0658b35ea3a2900ecb7812a3164bfe1f63e1`.
  Every task that touches vendored source must re-verify this checksum before
  trusting the content.
- GPLv2-licensed (per the file headers) — do not describe it as BSD-licensed
  anywhere (docs, commit messages, comments).
- `src/drvBPF` is owned by a concurrent session. No task in this plan touches
  any file under `src/drvBPF`.
- No local `cc`/`gcc`/WSL distro is available in this environment, and the
  real `rbuild`/VM build looks actively in use by another session (per
  `vm/_bootstrap-status*.txt`). No task compiles anything. Every "Verify" step
  is a structural/manual check against this tree's actual installed headers
  (already confirmed while researching this plan — see inline citations).
  Task 8 is the only point that touches the real build, and only after
  checking with the user.
- `bootpc`/`bootpd`/`bootplib` (`src/bootp-1/`) are never modified.
- Only the top-level files of the vendored tarball are used. Its bundled
  legacy `dhcpcd-0.70/` snapshot, `pcmcia/`, `rc.d/` directories, the prebuilt
  Linux ELF binary `dhcpcd`, the trivial `dhcpcd-eth0.exe` hook script, and
  `dhcpcd-1.3.17.lsm` are not vendored — they're Linux-distro packaging
  artifacts irrelevant to this port.
- Work happens in a git worktree. Every path in this plan is relative to the
  worktree root (`git rev-parse --show-toplevel`); never write into the main
  checkout. Shell state does not persist between separate commands, so set any
  variable you need in the same command that uses it.
- Scratch files go in the scratch directory the controller names as `SCRATCH`
  in the dispatch, never `/tmp` and never inside the repository.
- Commit messages are the single subject line shown in each task's commit
  step: no body, no `Co-Authored-By` or other trailer (`CLAUDE.md`: one to two
  lines, no metadata).

---

### Task 1: Vendor dhcpcd 1.3.17-pl2

**Files:**
- Create: `src/dhcpcd-1/dhcpcd.tproj/{arp.c,buildmsg.c,buildmsg.h,client.c,client.h,dhcpcd.c,dhcpcd.h,peekfd.c,pathnames.h,signals.c,signals.h,udpipgen.c,udpipgen.h,dhcpcd.8,README,Changes}`
- Create: `src/dhcpcd-1/PROVENANCE.md`

**Interfaces:**
- Produces: the vendored, not-yet-adapted source tree later tasks edit in
  place. `client.h` still declares `dhcpInterface`, `dhcpMessage`,
  `udpipMessage`, `dhcpOptions`, and the DHCP option-tag `enum` (`subnetMask
  = 1`, `routersOnSubnet = 3`, `hostName = 12`, `dhcpMessageType = 53`, …)
  exactly as upstream wrote them — later tasks rely on these names unchanged.

- [ ] **Step 1: Obtain and verify the tarball**

If `$SCRATCH/dhcpcd_1.3.17pl2.orig.tar.gz` already exists, the download is
skipped; either way the checksum is what decides.

```bash
cd "$SCRATCH"
[ -f dhcpcd_1.3.17pl2.orig.tar.gz ] || curl -sSL -o dhcpcd_1.3.17pl2.orig.tar.gz \
  "https://snapshot.debian.org/file/418c0658b35ea3a2900ecb7812a3164bfe1f63e1"
sha1sum dhcpcd_1.3.17pl2.orig.tar.gz
```

Expected: `418c0658b35ea3a2900ecb7812a3164bfe1f63e1  dhcpcd_1.3.17pl2.orig.tar.gz`.
Stop and do not proceed if this doesn't match exactly.

- [ ] **Step 2: Extract and copy only the top-level sources**

Run from the worktree root. The tarball is re-extracted fresh so Step 4
compares against a pristine copy.

```bash
WT=$(git rev-parse --show-toplevel)
cd "$SCRATCH"
rm -rf dhcpcd-1.3.17-pl2
tar xzf dhcpcd_1.3.17pl2.orig.tar.gz
mkdir -p "$WT/src/dhcpcd-1/dhcpcd.tproj"
cd dhcpcd-1.3.17-pl2
cp arp.c buildmsg.c buildmsg.h client.c client.h dhcpcd.c dhcpcd.h \
   peekfd.c pathnames.h signals.c signals.h udpipgen.c udpipgen.h \
   dhcpcd.8 README Changes \
   "$WT/src/dhcpcd-1/dhcpcd.tproj/"
```

- [ ] **Step 3: Write the provenance note**

Create `src/dhcpcd-1/PROVENANCE.md`:

```markdown
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

See `docs/superpowers/specs/2026-09-22-dhcpcd-1-client-daemon-design.md` for
the full design.
```

- [ ] **Step 4: Verify the copy is complete and untouched**

```bash
for f in arp.c buildmsg.c buildmsg.h client.c client.h dhcpcd.c dhcpcd.h \
         peekfd.c pathnames.h signals.c signals.h udpipgen.c udpipgen.h \
         dhcpcd.8 README Changes; do
  diff -q "$SCRATCH/dhcpcd-1.3.17-pl2/$f" \
          "src/dhcpcd-1/dhcpcd.tproj/$f" || echo "MISMATCH: $f"
done
```

Expected: no output (every file identical to the freshly extracted original;
no "MISMATCH" lines).

- [ ] **Step 5: Commit**

```bash
git add src/dhcpcd-1/
git commit -m "dhcpcd-1: vendor dhcpcd 1.3.17-pl2 (GPLv2)"
```

---

### Task 2: RhapsodiOS Tool + Aggregate project build files

**Files:**
- Create: `src/dhcpcd-1/PB.project`, `src/dhcpcd-1/Makefile`,
  `src/dhcpcd-1/Makefile.preamble`, `src/dhcpcd-1/Makefile.postamble`
- Create: `src/dhcpcd-1/dhcpcd.tproj/PB.project`,
  `src/dhcpcd-1/dhcpcd.tproj/Makefile`,
  `src/dhcpcd-1/dhcpcd.tproj/Makefile.preamble`,
  `src/dhcpcd-1/dhcpcd.tproj/Makefile.postamble`
- Reference (read-only, do not modify): `src/bootp-1/Makefile`,
  `src/bootp-1/Makefile.preamble`, `src/bootp-1/Makefile.postamble`,
  `src/bootp-1/PB.project`, `src/bootp-1/bootpc.tproj/Makefile`,
  `src/bootp-1/bootpc.tproj/Makefile.preamble`,
  `src/bootp-1/bootpc.tproj/Makefile.postamble`,
  `src/bootp-1/bootpc.tproj/PB.project`

**Interfaces:**
- Consumes: the file list vendored in Task 1.
- Produces: a `dhcpcd-1` aggregate project wrapping a `dhcpcd.tproj` Tool
  project that installs a `dhcpcd` binary to `/usr/sbin`, matching
  `src/bootp-1`'s two-level layout exactly.

- [ ] **Step 1: Copy the sibling boilerplate as a starting point**

```bash
cp src/bootp-1/Makefile.preamble src/dhcpcd-1/Makefile.preamble
cp src/bootp-1/Makefile.postamble src/dhcpcd-1/Makefile.postamble
cp src/bootp-1/bootpc.tproj/Makefile.preamble src/dhcpcd-1/dhcpcd.tproj/Makefile.preamble
cp src/bootp-1/bootpc.tproj/Makefile.postamble src/dhcpcd-1/dhcpcd.tproj/Makefile.postamble
```

`bootp-1`'s top-level `Makefile.preamble` is pure boilerplate and needs no
change. `bootpc.tproj`'s `Makefile.preamble` ends with two bootpc-specific
lines this project must not inherit:

```makefile
OTHER_LIBS=-lbootplib
AFTER_INSTALL=after_install
```

dhcpcd doesn't link `bootplib` and has no postinstall hook. Delete exactly
those two lines — the last two in the file — from
`src/dhcpcd-1/dhcpcd.tproj/Makefile.preamble`. Leave everything else as
copied, including the uncommented `OTHER_GENERATED_OFILES = $(VERS_OFILE)`
line, which the sibling Tool project also has.

```bash
diff src/bootp-1/bootpc.tproj/Makefile.preamble src/dhcpcd-1/dhcpcd.tproj/Makefile.preamble
```

Expected: exactly those two lines reported as deleted, nothing else.

- [ ] **Step 2: Write the top-level aggregate `Makefile`**

Create `src/dhcpcd-1/Makefile` (mirrors `src/bootp-1/Makefile`, trimmed to
one tool and no libraries):

```makefile
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = dhcpcd

PROJECTVERSION = 2.8
PROJECT_TYPE = Aggregate

TOOLS = dhcpcd.tproj

LIBRARIES =

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble PROVENANCE.md

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)


NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc
WINDOWS_OBJCPLUS_COMPILER = $(DEVDIR)/gcc
PDO_UNIX_OBJCPLUS_COMPILER = $(NEXTDEV_BIN)/gcc
NEXTSTEP_JAVA_COMPILER = /usr/bin/javac
WINDOWS_JAVA_COMPILER = $(JDKBINDIR)/javac.exe
PDO_UNIX_JAVA_COMPILER = $(NEXTDEV_BIN)/javac

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

- [ ] **Step 3: Write the top-level `PB.project`**

Create `src/dhcpcd-1/PB.project` (mirrors `src/bootp-1/PB.project`, one
subproject, no `NEXTSTEP_COMPILEROPTIONS` since there's no shared library to
point `-I` at):

```
{
    DYNAMIC_CODE_GEN = YES;
    FILESTABLE = {
        FRAMEWORKSEARCH = ();
        OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, PROVENANCE.md);
        SUBPROJECTS = (dhcpcd.tproj);
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = dhcpcd;
    PROJECTTYPE = Aggregate;
    PROJECTVERSION = 2.8;
    WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

- [ ] **Step 4: Write `dhcpcd.tproj/Makefile`**

Create `src/dhcpcd-1/dhcpcd.tproj/Makefile` (mirrors
`src/bootp-1/bootpc.tproj/Makefile`; `CFILES` instead of `MFILES` since this
is plain C, not Objective-C; no `NEXTSTEP_PB_CFLAGS` since there's no
sibling library directory to add to the include path):

```makefile
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = dhcpcd

PROJECTVERSION = 2.8
PROJECT_TYPE = Tool

CFILES = arp.c bootcompat.c bpfif.c buildmsg.c client.c dhcpcd.c peekfd.c rtsock.c signals.c udpipgen.c

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble \
	bootcompat.h bpfif.h buildmsg.h client.h dhcpcd.h pathnames.h \
	rtsock.h signals.h udpipgen.h dhcpcd.8 README Changes


MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = tool.make
NEXTSTEP_INSTALLDIR = /usr/sbin
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)


NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc
WINDOWS_OBJCPLUS_COMPILER = $(DEVDIR)/gcc
PDO_UNIX_OBJCPLUS_COMPILER = $(NEXTDEV_BIN)/gcc
NEXTSTEP_JAVA_COMPILER = /usr/bin/javac
WINDOWS_JAVA_COMPILER = $(JDKBINDIR)/javac.exe
PDO_UNIX_JAVA_COMPILER = $(NEXTDEV_BIN)/javac

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

Note: `rtsock.{c,h}`, `bpfif.{c,h}` and `bootcompat.{c,h}` are listed here
even though Tasks 3, 4 and 6 create them — this file only needs to exist
once, and the `CFILES` list is the complete, final list this Tool project
builds.

- [ ] **Step 5: Write `dhcpcd.tproj/PB.project`**

Create `src/dhcpcd-1/dhcpcd.tproj/PB.project` (mirrors
`src/bootp-1/bootpc.tproj/PB.project`; lists every vendored/new file so
Project Builder's file table matches the `Makefile`):

```
{
    DYNAMIC_CODE_GEN = YES;
    FILESTABLE = {
        FRAMEWORKS = ();
        FRAMEWORKSEARCH = ();
        OTHER_LINKED = (arp.c, bootcompat.c, bpfif.c, buildmsg.c, client.c, dhcpcd.c, peekfd.c, rtsock.c, signals.c, udpipgen.c);
        OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, bootcompat.h, bpfif.h, buildmsg.h, client.h, dhcpcd.h, pathnames.h, rtsock.h, signals.h, udpipgen.h, dhcpcd.8, README, Changes);
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_INSTALLDIR = /usr/sbin;
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = dhcpcd;
    PROJECTTYPE = Tool;
    PROJECTVERSION = 2.8;
    WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

- [ ] **Step 6: Verify structure against the sibling project**

```bash
diff <(grep -oE '^[A-Z_]+' src/bootp-1/Makefile) <(grep -oE '^[A-Z_]+' src/dhcpcd-1/Makefile)
diff <(grep -oE '^[A-Z_]+' src/bootp-1/bootpc.tproj/Makefile) <(grep -oE '^[A-Z_]+' src/dhcpcd-1/dhcpcd.tproj/Makefile)
```

Expected: only `MFILES` vs `CFILES` and `LIBRARIES`/`TOOLS` list differences
show up (both diffs should be short — a handful of lines, not wholesale
divergence). No compiler is available to actually build this yet (Global
Constraints) — this step only confirms the file shape matches the proven
sibling project.

- [ ] **Step 7: Commit**

```bash
git add src/dhcpcd-1/PB.project src/dhcpcd-1/Makefile \
        src/dhcpcd-1/Makefile.preamble src/dhcpcd-1/Makefile.postamble \
        src/dhcpcd-1/dhcpcd.tproj/PB.project src/dhcpcd-1/dhcpcd.tproj/Makefile \
        src/dhcpcd-1/dhcpcd.tproj/Makefile.preamble src/dhcpcd-1/dhcpcd.tproj/Makefile.postamble
git commit -m "dhcpcd-1: add RhapsodiOS project build files"
```

---

### Task 3: Portability pass on the vendored source

**Files:**
- Modify: `src/dhcpcd-1/dhcpcd.tproj/client.h`
- Modify: `src/dhcpcd-1/dhcpcd.tproj/udpipgen.h`
- Modify: `src/dhcpcd-1/dhcpcd.tproj/client.c`
- Create: `src/dhcpcd-1/dhcpcd.tproj/rtsock.h`
- Create: `src/dhcpcd-1/dhcpcd.tproj/rtsock.c`
- Reference (read-only): `src/Commands/network_cmds/route.tproj/route.c`

**Interfaces:**
- Consumes: `struct ether_header` from `<netinet/if_ether.h>` (this tree —
  confirmed fields `ether_dhost`/`ether_shost`/`ether_type`, identical names
  to what upstream already uses, in `src/kernel-7/bsd/netinet/if_ether.h:76-79`).
- Consumes: `struct rt_msghdr`, `RTM_VERSION`, `RTM_ADD`, `RTM_CHANGE`,
  `RTA_DST`/`RTA_GATEWAY`/`RTA_NETMASK`, `RTF_UP`/`RTF_GATEWAY`/`RTF_HOST`/
  `RTF_STATIC` from `src/kernel-7/bsd/net/route.h` (lines 144-220), and
  `sin_len` in `struct sockaddr_in` (`netinet/in.h:154`).
- Produces: `int rtsockAddDefault(unsigned int gateway, unsigned int ifaddr);`
  (`rtsock.h`) — both arguments are IPv4 addresses in network byte order, as
  `DhcpIface` stores them. Installs a default route via `gateway`; if the
  kernel answers `ENETUNREACH` (gateway off our subnet) it first adds a host
  route to `gateway` through our own address `ifaddr`, as upstream does, then
  retries; if a default route already exists (`EEXIST`, e.g. on renewal) it
  sends `RTM_CHANGE` so the route follows a changed router. Returns 0 on
  success, -1 after logging the failure. `dhcpConfig()` keeps setting the
  interface's address/netmask/broadcast via `SIOCSIFADDR`/`SIOCSIFNETMASK`/
  `SIOCSIFBRDADDR` (already portable, no change) and calls this in place of
  its Linux route code.

Beyond the header and `ETHER_ADDR_LEN` fixes below, everything else this
dhcpcd source touches (`SIOCSIFADDR`/`SIOCSIFNETMASK`/`SIOCSIFBRDADDR`/
`SIOCSIFFLAGS`, `ARPHRD_ETHER`, `ARPOP_REQUEST`/`ARPOP_REPLY`,
`ETHERTYPE_IP`/`ETHERTYPE_ARP`, `IPVERSION`/`IPDEFTTL`, `INADDR_BROADCAST`,
`IFF_UP`/`IFF_BROADCAST`/`IFF_MULTICAST`/`IFF_NOTRAILERS`/`IFF_RUNNING`) is
confirmed present with matching names in `src/kernel-7/bsd/{net,netinet}/`.

- [ ] **Step 1: Swap the ethernet header include**

In `client.h`, near the top:

Old:
```c
#include <net/ethernet.h>
```

New:
```c
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/if_ether.h>

#ifndef ETHER_ADDR_LEN
#define ETHER_ADDR_LEN		6
#endif
```

There is no `net/ethernet.h` in this tree. Userland code here reaches
`struct ether_header` through `<netinet/if_ether.h>`, which has no include
guard and no includes of its own: it needs `sys/types.h`, `sys/socket.h`,
`net/if.h` (which pulls in `net/if_arp.h` for `struct arphdr`) and
`netinet/in.h` first. That is the order `rarpd` uses
(`src/Commands/network_cmds/rarpd.tproj/rarpd.c:68-78`); `client.h` has to
supply it itself because `signals.c` includes `client.h` with no network
headers before it. The four prerequisite headers are all include-guarded, so
files that also include them directly are unaffected. `<net/etherdefs.h>` is
not used: it includes `<bsd/netinet/if_ether.h>`, a kernel-style path.

`ETHER_ADDR_LEN` is a Linux `<net/ethernet.h>` constant with no definition
anywhere in this tree (the tree's own name for it is `NUM_EN_ADDR_BYTES` in
`net/etherdefs.h`). `client.h`, `client.c` and `arp.c` use it for 6-byte
hardware addresses.

- [ ] **Step 2: Give `udpipgen.h` the headers `netinet/ip.h` needs**

In `udpipgen.h`:

Old:
```c
#include <netinet/ip.h>
```

New:
```c
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/in_systm.h>
#include <netinet/ip.h>
```

This tree's `netinet/ip.h` has no includes of its own. It uses `n_long` from
`netinet/in_systm.h` (`ip.h:163,166`), `struct in_addr` from `netinet/in.h`,
and `BYTE_ORDER` from `sys/types.h` (which includes `machine/endian.h`) to
lay out the `ip_hl`/`ip_v` bitfields (`ip.h:75-79`). Without `sys/types.h`,
`BYTE_ORDER` is undefined, `#if BYTE_ORDER == LITTLE_ENDIAN` is true, and
the header is silently wrong on ppc. `udpipgen.c` includes only
`<string.h>` before `udpipgen.h`, so the header must carry these itself.
`netinet/in_systm.h` and `netinet/ip.h` are unguarded, but nothing else in
this project includes them, and `udpipgen.h` is guarded.

- [ ] **Step 3: Write `rtsock.h`**

```c
/*
 * rtsock.h - BSD routing-socket default route for dhcpcd-1
 *
 * Replaces upstream dhcpcd's Linux SIOCADDRT/struct rtentry code in
 * dhcpConfig(). Addresses are in network byte order.
 */

#ifndef RTSOCK_H
#define RTSOCK_H

int rtsockAddDefault(unsigned int gateway, unsigned int ifaddr);

#endif /* RTSOCK_H */
```

- [ ] **Step 4: Write `rtsock.c`**

The message layout copies `route(8)` in
`src/Commands/network_cmds/route.tproj/route.c`: the same `ROUNDUP` macro
(`route.c:142-143`), sockaddrs appended in `RTA_*` bit order
(`route.c:1013-1049`), and for the default route a netmask whose `sa_len`
is 0, which `ROUNDUP` pads to `sizeof(long)` zero bytes — exactly what
`route add default GW` sends (`route.c:807-817`). Failures come back as
`write()`'s errno, which is also how `route(8)` sees `EEXIST` and
`ENETUNREACH`. The host-route fallback is the routing-socket form of
`route add -host GW MYIP -interface`: our own address as the gateway and no
`RTF_GATEWAY` flag (`route.c:666-670`).

```c
/*
 * rtsock.c - BSD routing-socket default route for dhcpcd-1
 *
 * See rtsock.h. Messages are laid out the way route(8) builds them in
 * src/Commands/network_cmds/route.tproj/route.c.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <syslog.h>

#include "rtsock.h"

#define ROUNDUP(a) \
	((a) > 0 ? (1 + (((a) - 1) | (sizeof(long) - 1))) : sizeof(long))

static int
rtsockSend(s,type,flags,dst,gateway,withmask)
int s,type,flags;
unsigned int dst,gateway;
int withmask;
{
  static int seq;
  struct
    {
      struct rt_msghdr	rtm;
      char		space[512];
    } msg;
  struct sockaddr_in sin;
  char *cp;

  memset(&msg,0,sizeof(msg));
  msg.rtm.rtm_type = type;
  msg.rtm.rtm_flags = flags;
  msg.rtm.rtm_version = RTM_VERSION;
  msg.rtm.rtm_seq = ++seq;
  msg.rtm.rtm_addrs = RTA_DST|RTA_GATEWAY;
  if ( withmask ) msg.rtm.rtm_addrs |= RTA_NETMASK;

  memset(&sin,0,sizeof(sin));
  sin.sin_len = sizeof(sin);
  sin.sin_family = AF_INET;

  cp = msg.space;
  sin.sin_addr.s_addr = dst;
  memcpy(cp,&sin,sizeof(sin));
  cp += ROUNDUP(sizeof(sin));
  sin.sin_addr.s_addr = gateway;
  memcpy(cp,&sin,sizeof(sin));
  cp += ROUNDUP(sizeof(sin));
  if ( withmask )
    cp += ROUNDUP(0);	/* zero-length netmask: the default route */

  msg.rtm.rtm_msglen = cp - (char *)&msg;
  if ( write(s,(char *)&msg,msg.rtm.rtm_msglen) == -1 ) return -1;
  return 0;
}

int
rtsockAddDefault(gateway,ifaddr)
unsigned int gateway,ifaddr;
{
  int s,rc;

  s = socket(PF_ROUTE,SOCK_RAW,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"rtsockAddDefault: socket: %m\n");
      return -1;
    }

  rc = rtsockSend(s,RTM_ADD,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
  if ( rc == -1 && errno == ENETUNREACH )
    {
      /* gateway is off our subnet: reach it through our own address first */
      if ( rtsockSend(s,RTM_ADD,RTF_UP|RTF_HOST|RTF_STATIC,gateway,ifaddr,0) == 0
	   || errno == EEXIST )
	rc = rtsockSend(s,RTM_ADD,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
    }
  if ( rc == -1 && errno == EEXIST )
    rc = rtsockSend(s,RTM_CHANGE,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
  if ( rc == -1 )
    syslog(LOG_ERR,"rtsockAddDefault: default route: %m\n");

  close(s);
  return rc;
}
```

- [ ] **Step 5: Replace the Linux default-route code with a call**

In `client.c`, `dhcpConfig()` uses `SIOCADDRT` (a Linux-only route ioctl
taking a `struct rtentry`) to install a default route via
`DhcpIface.giaddr`, with a fallback that first adds a host route to the
gateway if the direct attempt fails with `ENETUNREACH`. `DhcpIface.giaddr`
is always set: upstream falls back to the DHCP server's address when the
server sends no router option (`client.c:228-241`). That whole block — from
the `memset(&rtent,...)` right after the `SIOCSIFBRDADDR` call, through the
final `else syslog(...)` of the `ioctl(s,SIOCADDRT,&rtent)` error handling,
ending just before `close(s); arpInform();` — becomes one call.

Old (the whole block, verified against the vendored source in Task 1):
```c
  memset(&rtent,0,sizeof(struct rtentry));
  p			=	(struct sockaddr_in *)&rtent.rt_dst;
  p->sin_family		=	AF_INET;
  p->sin_addr.s_addr	=	0;
  p			=	(struct sockaddr_in *)&rtent.rt_gateway;
  p->sin_family		=	AF_INET;
  p->sin_addr.s_addr	=	DhcpIface.giaddr;
  p			=	(struct sockaddr_in *)&rtent.rt_genmask;
  p->sin_family		=	AF_INET;
  p->sin_addr.s_addr	=	0;
  rtent.rt_dev		=	IfName;
  rtent.rt_metric	=	1;
  rtent.rt_flags	=	RTF_UP|RTF_GATEWAY;
  if ( ioctl(s,SIOCADDRT,&rtent) == -1 )
    {
      if ( errno == ENETUNREACH )    /* possibly gateway is over the bridge */
        {                            /* try adding a route to gateway first */
          memset(&rtent,0,sizeof(struct rtentry));
          p                   =   (struct sockaddr_in *)&rtent.rt_dst;
          p->sin_family	      =	  AF_INET;
          p->sin_addr.s_addr  =	  DhcpIface.giaddr;
	  p		      =	  (struct sockaddr_in *)&rtent.rt_gateway;
	  p->sin_family	      =	  AF_INET;
	  p->sin_addr.s_addr  =   0;
          p		      =	  (struct sockaddr_in *)&rtent.rt_genmask;
          p->sin_family	      =   AF_INET;
          p->sin_addr.s_addr  =	  0xffffffff;
          rtent.rt_dev	      =	  IfName;
          rtent.rt_metric     =	  0;
          rtent.rt_flags      =	  RTF_UP|RTF_HOST;
          if ( ioctl(s,SIOCADDRT,&rtent) == 0 )
	    {
	      memset(&rtent,0,sizeof(struct rtentry));
	      p			     =	(struct sockaddr_in *)&rtent.rt_dst;
	      p->sin_family	     =	AF_INET;
	      p->sin_addr.s_addr     =	0;
	      p			     =	(struct sockaddr_in *)&rtent.rt_gateway;
	      p->sin_family	     =	AF_INET;
	      p->sin_addr.s_addr     =	DhcpIface.giaddr;
	      p			     =	(struct sockaddr_in *)&rtent.rt_genmask;
	      p->sin_family	     =	AF_INET;
	      p->sin_addr.s_addr     =	0;
	      rtent.rt_dev	     =	IfName;
	      rtent.rt_metric	     =	1;
	      rtent.rt_flags         =	RTF_UP|RTF_GATEWAY;
	      if ( ioctl(s,SIOCADDRT,&rtent) == -1 )
		syslog(LOG_ERR,"dhcpConfig: ioctl SIOCADDRT: %m\n");
            }
	}
      else
        syslog(LOG_ERR,"dhcpConfig: ioctl SIOCADDRT: %m\n");
    }
```

New:
```c
  rtsockAddDefault(DhcpIface.giaddr,DhcpIface.client_iaddr);
```

- [ ] **Step 6: Remove what the old route code leaves orphaned, include `rtsock.h`**

In `dhcpConfig()`'s declarations, at the top of the function:

Old:
```c
  int s;
  FILE *f;
  char	cache_file[48];
  struct ifreq		ifr;
  struct rtentry	rtent;
  struct sockaddr_in	*p = (struct sockaddr_in *)&(ifr.ifr_addr);
```

New:
```c
  int s;
  FILE *f;
  char	cache_file[48];
  struct ifreq		ifr;
  struct sockaddr_in	*p = (struct sockaddr_in *)&(ifr.ifr_addr);
```

(`rtent` was only ever referenced inside the block Step 5 replaced; `p`
stays — it's also used earlier in the function for `ifr.ifr_addr`.)

`#include <net/route.h>` (`client.c:31`) was only there for `struct
rtentry` and the `RTF_*` flags, so remove that line too; `rtsock.c` now owns
routing. Add `#include "rtsock.h"` after `#include "pathnames.h"`, the last
include in `client.c`.

- [ ] **Step 7: Verify**

```bash
grep -n "SIOCADDRT\|struct rtentry\|rt_dev\|RTF_GATEWAY\|RTF_HOST\|net/route.h" src/dhcpcd-1/dhcpcd.tproj/client.c
grep -n "rtsock" src/dhcpcd-1/dhcpcd.tproj/client.c
```

Expected: the first prints nothing; the second prints exactly the
`#include "rtsock.h"` line and the one `rtsockAddDefault(...)` call.

```bash
grep -n "struct rt_msghdr {\|RTM_VERSION\|RTM_ADD\|RTM_CHANGE\|RTA_DST\|RTA_GATEWAY\|RTA_NETMASK\|RTF_UP\|RTF_GATEWAY\|RTF_HOST\|RTF_STATIC" src/kernel-7/bsd/net/route.h
grep -n "sin_len" src/kernel-7/bsd/netinet/in.h
diff <(grep -A1 "define ROUNDUP" src/Commands/network_cmds/route.tproj/route.c) \
     <(grep -A1 "define ROUNDUP" src/dhcpcd-1/dhcpcd.tproj/rtsock.c)
```

Expected: every routing symbol `rtsock.c` uses shows up in `net/route.h`,
`sin_len` shows up in `netinet/in.h`, and the `diff` prints nothing (the
`ROUNDUP` macro is byte-for-byte `route(8)`'s).

```bash
grep -n "net/ethernet.h\|net/etherdefs.h" src/dhcpcd-1/dhcpcd.tproj/client.h
grep -n "netinet/if_ether.h\|ETHER_ADDR_LEN" src/dhcpcd-1/dhcpcd.tproj/client.h
grep -n "^#include" src/dhcpcd-1/dhcpcd.tproj/udpipgen.h
```

Expected: the first prints nothing; the second prints the new
`<netinet/if_ether.h>` include and the `#ifndef`/`#define ETHER_ADDR_LEN`
lines; the third prints exactly `sys/types.h`, `netinet/in.h`,
`netinet/in_systm.h`, `netinet/ip.h`, in that order.

- [ ] **Step 8: Commit**

```bash
git add src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/client.h \
        src/dhcpcd-1/dhcpcd.tproj/udpipgen.h src/dhcpcd-1/dhcpcd.tproj/rtsock.c \
        src/dhcpcd-1/dhcpcd.tproj/rtsock.h
git commit -m "dhcpcd-1: use this tree's ethernet and IP headers, set the default route through a routing socket"
```

#### Amendment after review (commit 8b806cccf)

The first review of this task found four problems the steps above cause or
miss. The user approved fixing all four, and the code now differs from the
steps above as follows:

- **No off-subnet fallback.** This kernel's route add looks up the
  destination, not the gateway (`net/route.c` `ifa_ifwithroute`), so the
  ENETUNREACH retry cannot succeed, and its host route black-holes the router.
  `rtsockAddDefault(unsigned int gateway)` takes one argument and only sends
  RTM_ADD, then RTM_CHANGE on EEXIST.
- **One SIOCAIFADDR.** `dhcpConfig()` deletes the old address with
  SIOCDIFADDR and sets address, netmask and broadcast with one SIOCAIFADDR
  (`struct ifaliasreq`), as `ifconfig` does. SIOCSIFADDR followed by
  SIOCSIFNETMASK leaves a classful subnet route on this kernel.
- **Route refreshed on every ACK.** `dhcpRequest()` takes `DhcpIface.giaddr`
  from the ACK's router option before `dhcpConfig()`, and `dhcpRenew()` and
  `dhcpRebind()` refresh it and call `rtsockAddDefault()` on success.
  Upstream never reconfigures on renew/rebind.
- **Include order.** `arp.c` and `buildmsg.c` gain `<sys/types.h>` and
  `dhcpcd.c` gains `<sys/socket.h>` ahead of their first system include that
  needs it.

---

### Task 4: New BSD/BPF backend

**Files:**
- Create: `src/dhcpcd-1/dhcpcd.tproj/bpfif.h`
- Create: `src/dhcpcd-1/dhcpcd.tproj/bpfif.c`

**Interfaces:**
- Consumes: `src/kernel-7/bsd/net/bpf.h` (`BIOCSETIF`, `BIOCIMMEDIATE`,
  `BIOCGBLEN`, `struct bpf_hdr` with `bh_caplen`/`bh_hdrlen`,
  `BPF_WORDALIGN`), `src/kernel-7/bsd/net/if_dl.h` (`struct sockaddr_dl`,
  `LLADDR()`), `src/kernel-7/bsd/net/if_types.h` (`IFT_ETHER`),
  `src/kernel-7/bsd/net/if.h` (`SIOCGIFCONF`, `SIOCSIFFLAGS`,
  `IFF_UP`/`IFF_BROADCAST`/`IFF_MULTICAST`/`IFF_NOTRAILERS`/`IFF_RUNNING`),
  and the `AF_LINK`/`IFT_ETHER` idiom already proven in
  `src/bootp-1/bootplib/interfaces.c:180,322-331`. `/dev/bpf0`..`/dev/bpfN`
  device nodes are created by `src/drvBPF`'s `PostLoad` helper (external
  dependency, not touched here).
- Produces:
  - `int bpfOpenForInterface(const char *ifname, unsigned char hwaddr[6]);`
    — opens the first available `/dev/bpf*`, binds it to `ifname`, enables
    immediate mode, brings the interface up, and fills `hwaddr` with its
    6-byte Ethernet address. Returns the open fd, or -1 on failure (with
    `errno`/syslog describing the last failure).
  - `int bpfSendFrame(int bpf_fd, const void *frame, int framelen);` —
    writes one raw Ethernet frame. Returns `framelen` on success, -1 on
    failure.
  - `int bpfRecvFrame(int bpf_fd, void *frame, int frame_max);` — returns
    one captured frame at a time (`bh_caplen` bytes, truncated to
    `frame_max`), even when a single underlying `read()` returned several
    BPF-framed records; buffers the remainder internally across calls.
    Returns the frame length, 0 if a read produced no data, -1 on failure.
  - Task 5 calls these three functions in place of `client.c`/`arp.c`'s
    Linux `socket(AF_PACKET,SOCK_PACKET,...)`/`sendto`/`recvfrom`/
    `ioctl(...,SIOCGIFHWADDR,...)` calls. `dhcpSocket` (declared in
    `client.c`, `extern`'d elsewhere) stays a plain `int` — nothing about
    its declaration changes.

- [ ] **Step 1: Write `bpfif.h`**

```c
/*
 * bpfif.h - BSD/BPF raw-Ethernet backend for dhcpcd-1
 *
 * Replaces dhcpcd's upstream Linux SOCK_PACKET raw-packet layer.
 * dhcpSocket stays a plain file descriptor after bpfOpenForInterface():
 * client.c and arp.c read()/write()/select() on it exactly as they did
 * on the Linux socket fd before this port.
 */

#ifndef BPFIF_H
#define BPFIF_H

int bpfOpenForInterface(const char *ifname, unsigned char hwaddr[6]);
int bpfSendFrame(int bpf_fd, const void *frame, int framelen);
int bpfRecvFrame(int bpf_fd, void *frame, int frame_max);

#endif /* BPFIF_H */
```

- [ ] **Step 2: Write `bpfif.c`**

```c
/*
 * bpfif.c - BSD/BPF raw-Ethernet backend for dhcpcd-1
 *
 * See bpfif.h. The MAC-address lookup below follows the same
 * AF_LINK/struct sockaddr_dl walk over SIOCGIFCONF that
 * src/bootp-1/bootplib/interfaces.c already uses on this tree.
 */

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <net/bpf.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

#include "bpfif.h"

#define BPFIF_DEVMAX 16

static unsigned char	*bpf_buf;	/* raw read buffer, BIOCGBLEN-sized */
static int		bpf_buflen;
static unsigned char	*bpf_next;	/* next unconsumed record, or NULL */
static int		bpf_avail;	/* bytes remaining from bpf_next */

static int
bpfGetHwAddr(ifname, hwaddr)
const char *ifname;
unsigned char hwaddr[6];
{
  int s;
  struct ifconf ifc;
  struct ifreq *ifr;
  char buf[8192];
  char *cp, *cplim;
  int found = 0;

  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 ) return -1;

  ifc.ifc_len = sizeof(buf);
  ifc.ifc_buf = buf;
  if ( ioctl(s,SIOCGIFCONF,&ifc) == -1 )
    {
      close(s);
      return -1;
    }

  cp = buf;
  cplim = buf + ifc.ifc_len;
  while ( cp < cplim )
    {
      ifr = (struct ifreq *)cp;
      cp += sizeof(ifr->ifr_name) +
	    (ifr->ifr_addr.sa_len > sizeof(struct sockaddr)
	     ? ifr->ifr_addr.sa_len : sizeof(struct sockaddr));
      if ( strncmp(ifr->ifr_name,ifname,sizeof(ifr->ifr_name)) != 0 )
	continue;
      if ( ifr->ifr_addr.sa_family != AF_LINK )
	continue;
      {
	struct sockaddr_dl *sdl = (struct sockaddr_dl *)&ifr->ifr_addr;
	if ( sdl->sdl_type == IFT_ETHER && sdl->sdl_alen == 6 )
	  {
	    memcpy(hwaddr,LLADDR(sdl),6);
	    found = 1;
	    break;
	  }
      }
    }

  close(s);
  return found ? 0 : -1;
}

int
bpfOpenForInterface(ifname,hwaddr)
const char *ifname;
unsigned char hwaddr[6];
{
  char dev[16];
  int fd,i,s;
  struct ifreq ifr;
  unsigned int enable = 1;

  fd = -1;
  for ( i = 0 ; i < BPFIF_DEVMAX ; i++ )
    {
      sprintf(dev,"/dev/bpf%d",i);
      fd = open(dev,O_RDWR);
      if ( fd != -1 ) break;
      if ( errno != EBUSY ) break;
    }
  if ( fd == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: no /dev/bpf* available: %m\n");
      return -1;
    }

  memset(&ifr,0,sizeof(ifr));
  strncpy(ifr.ifr_name,ifname,sizeof(ifr.ifr_name)-1);
  if ( ioctl(fd,BIOCSETIF,&ifr) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCSETIF %s: %m\n",ifname);
      close(fd);
      return -1;
    }

  if ( ioctl(fd,BIOCIMMEDIATE,&enable) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCIMMEDIATE: %m\n");
      close(fd);
      return -1;
    }

  if ( ioctl(fd,BIOCGBLEN,&bpf_buflen) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCGBLEN: %m\n");
      close(fd);
      return -1;
    }
  bpf_buf = malloc(bpf_buflen);
  if ( bpf_buf == NULL )
    {
      close(fd);
      return -1;
    }
  bpf_next = NULL;
  bpf_avail = 0;

  if ( bpfGetHwAddr(ifname,hwaddr) == -1 )
    {
      syslog(LOG_ERR,
	"bpfOpenForInterface: could not read %s's hardware address\n",ifname);
      close(fd);
      return -1;
    }

  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: socket: %m\n");
      close(fd);
      return -1;
    }
  memset(&ifr,0,sizeof(ifr));
  strncpy(ifr.ifr_name,ifname,sizeof(ifr.ifr_name)-1);
  ifr.ifr_flags = IFF_UP|IFF_BROADCAST|IFF_MULTICAST|IFF_NOTRAILERS|IFF_RUNNING;
  if ( ioctl(s,SIOCSIFFLAGS,&ifr) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: SIOCSIFFLAGS: %m\n");
      close(s);
      close(fd);
      return -1;
    }
  close(s);

  return fd;
}

int
bpfSendFrame(bpf_fd,frame,framelen)
int bpf_fd;
const void *frame;
int framelen;
{
  int n = write(bpf_fd,frame,framelen);
  if ( n == -1 )
    syslog(LOG_ERR,"bpfSendFrame: write: %m\n");
  return n;
}

int
bpfRecvFrame(bpf_fd,frame,frame_max)
int bpf_fd;
void *frame;
int frame_max;
{
  struct bpf_hdr *bh;
  int n, reclen;

  if ( bpf_avail <= 0 )
    {
      n = read(bpf_fd,bpf_buf,bpf_buflen);
      if ( n == -1 )
	{
	  syslog(LOG_ERR,"bpfRecvFrame: read: %m\n");
	  return -1;
	}
      bpf_next = bpf_buf;
      bpf_avail = n;
    }

  if ( bpf_avail <= 0 ) return 0;

  bh = (struct bpf_hdr *)bpf_next;
  n = bh->bh_caplen;
  if ( n > frame_max ) n = frame_max;
  memcpy(frame,bpf_next + bh->bh_hdrlen,n);

  reclen = BPF_WORDALIGN(bh->bh_hdrlen + bh->bh_caplen);
  bpf_next += reclen;
  bpf_avail -= reclen;
  if ( bpf_avail < 0 ) bpf_avail = 0;

  return n;
}
```

- [ ] **Step 3: Verify against the confirmed header facts**

```bash
grep -n "BIOCSETIF\|BIOCIMMEDIATE\|BIOCGBLEN\|bh_caplen\|bh_hdrlen\|BPF_WORDALIGN" src/kernel-7/bsd/net/bpf.h
grep -n "struct sockaddr_dl\|LLADDR" src/kernel-7/bsd/net/if_dl.h
grep -n "IFT_ETHER" src/kernel-7/bsd/net/if_types.h
grep -n "sa_len" src/kernel-7/bsd/sys/socket.h
```

Expected: every symbol `bpfif.c` uses (`BIOCSETIF`, `BIOCIMMEDIATE`,
`BIOCGBLEN`, `bh_caplen`, `bh_hdrlen`, `BPF_WORDALIGN`, `struct sockaddr_dl`,
`LLADDR`, `IFT_ETHER`, `sa_len`) appears in the corresponding grep output — confirming
nothing in the new file references an undeclared symbol. (This is a
structural check, not a compile — see Global Constraints.)

- [ ] **Step 4: Commit**

```bash
git add src/dhcpcd-1/dhcpcd.tproj/bpfif.c src/dhcpcd-1/dhcpcd.tproj/bpfif.h
git commit -m "dhcpcd-1: add BSD/BPF raw-Ethernet backend"
```

#### Amendment after review (Task 4 fix commit)

The review found two problems in the code above; both are fixed in a
follow-up commit:

- **Bring the interface up before binding BPF.** drvBPF's `bpf_setif`
  returns ENETDOWN for a down interface, and the code above called
  BIOCSETIF before SIOCSIFFLAGS. That fails at boot and on every restart
  after upstream's `dhcpStop()`, which takes the interface down.
  `bpfOpenForInterface()` now reads the hardware address, then sets IFF_UP
  with a read-modify-write (SIOCGIFFLAGS, `|= IFF_UP`, SIOCSIFFLAGS, so
  other flags such as IFF_PROMISC survive), then opens and binds
  `/dev/bpf*`. It frees the read buffer from a previous open, and logs a
  malloc failure.
- **`bpfPeek()`.** One `read()` can return several frames, and `select()`
  cannot see the ones left in `bpf_buf`. With the interface tapping our own
  sends, a reply can sit unread behind our echoed frame while `peekfd()`
  sleeps. `int bpfPeek(int bpf_fd, int tv_usec)` has `peekfd()`'s return
  convention (0 readable, 1 timeout, -1 error), but returns 0 at once when
  a frame is already buffered. `bpfif.c` includes `client.h` for
  `peekfd()`'s prototype. Task 5 uses it for every wait on `dhcpSocket`.

---

### Task 5: Wire the BPF backend into client.c and arp.c

**Files:**
- Modify: `src/dhcpcd-1/dhcpcd.tproj/client.c`
- Modify: `src/dhcpcd-1/dhcpcd.tproj/arp.c`

**Interfaces:**
- Consumes: `bpfOpenForInterface`, `bpfSendFrame`, `bpfRecvFrame`, and
  `int bpfPeek(int bpf_fd, int tv_usec)` (Task 4) — `bpfPeek` has
  `peekfd()`'s return convention (0 readable, 1 timeout, -1 error) but also
  counts frames already buffered in `bpfif.c`, which `select()` cannot see.
- Produces: `client.c` and `arp.c` with no remaining `socket(AF_PACKET,...)`,
  `SOCK_PACKET`, `sendto`, `recvfrom`, or `SIOCGIFHWADDR` references, and
  every wait on `dhcpSocket` going through `bpfPeek()` instead of
  `peekfd()`.
  `dhcpSocket`'s type and every other global/extern this file uses is
  unchanged, so Task 6 and any other consumer of `client.c` need no further
  adjustment.

- [ ] **Step 1: Add the include**

In `client.c`, alongside its existing includes (near the top, after
`#include "client.h"` or similar):

```c
#include "bpfif.h"
```

- [ ] **Step 2: Replace `dhcpStart()`'s socket setup**

Old (as vendored in Task 1):
```c
void *dhcpStart()
{
  int o = 1;
  struct ifreq	ifr;
  memset(&ifr,0,sizeof(struct ifreq));
  memcpy(ifr.ifr_name,IfName,IfName_len);
  dhcpSocket = socket(AF_PACKET,SOCK_PACKET,htons(ETH_P_ALL));
  if ( dhcpSocket == -1 )
    {
      syslog(LOG_ERR,"dhcpStart: socket: %m\n");
      exit(1);
    }
  if ( ioctl(dhcpSocket,SIOCGIFHWADDR,&ifr) )
    {
      syslog(LOG_ERR,"dhcpStart: ioctl SIOCGIFHWADDR: %m\n");
      exit(1);
    }
  if ( ifr.ifr_hwaddr.sa_family != ARPHRD_ETHER )
    {
      syslog(LOG_ERR,"dhcpStart: interface %s is not Ethernet\n",ifr.ifr_name);
      exit(1);
    }
  if ( setsockopt(dhcpSocket,SOL_SOCKET,SO_BROADCAST,&o,sizeof(o)) == -1 )
    {
      syslog(LOG_ERR,"dhcpStart: setsockopt: %m\n");
      exit(1);
    }
  ifr.ifr_flags = IFF_UP | IFF_BROADCAST | IFF_MULTICAST| IFF_NOTRAILERS | IFF_RUNNING;
  if ( ioctl(dhcpSocket,SIOCSIFFLAGS,&ifr) )
    {
      syslog(LOG_ERR,"dhcpStart: ioctl SIOCSIFFLAGS: %m\n");
      exit(1);
    }
  memcpy(ClientHwAddr,ifr.ifr_hwaddr.sa_data,ETHER_ADDR_LEN);
  return &dhcpInit;
}
```

New:
```c
void *dhcpStart()
{
  dhcpSocket = bpfOpenForInterface(IfName,ClientHwAddr);
  if ( dhcpSocket == -1 )
    {
      syslog(LOG_ERR,"dhcpStart: bpfOpenForInterface: %m\n");
      exit(1);
    }
  return &dhcpInit;
}
```

- [ ] **Step 3: Replace the send/receive pair in `dhcpSendAndRecv()`**

Old (the `struct sockaddr addr;` local declaration at the top of the
function is also removed — it becomes unused once both call sites below are
replaced, and nowhere else in this function references it):

```c
int dhcpSendAndRecv(xid,msg,buildUdpIpMsg)
unsigned xid,msg;
void (*buildUdpIpMsg)(unsigned);
{
  struct sockaddr addr;
  int i,len;
```

New:
```c
int dhcpSendAndRecv(xid,msg,buildUdpIpMsg)
unsigned xid,msg;
void (*buildUdpIpMsg)(unsigned);
{
  int i,len;
```

Old (the send call, further down the same function):
```c
      	  memset(&addr,0,sizeof(struct sockaddr));
      	  memcpy(addr.sa_data,IfName,IfName_len);
	  buildUdpIpMsg(xid);
      	  if ( sendto(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
		      sizeof(udpiphdr)+sizeof(dhcpMessage),0,
		      &addr,sizeof(struct sockaddr)) == -1 )
	    {
	      syslog(LOG_ERR,"sendto: %m\n");
	      return -1;
	    }
```

New:
```c
	  buildUdpIpMsg(xid);
      	  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
		      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
	    {
	      syslog(LOG_ERR,"bpfSendFrame: %m\n");
	      return -1;
	    }
```

Old (the receive call):
```c
	  memset(&UdpIpMsg,0,sizeof(udpipMessage));
      	  i=sizeof(struct sockaddr);
      	  len=recvfrom(dhcpSocket,&UdpIpMsg,sizeof(udpipMessage),0,
		     (struct sockaddr *)&addr,&i);
	  if ( len == -1 )
    	    {
      	      syslog(LOG_ERR,"recvfrom: %m\n");
      	      return -1;
    	    }
```

New:
```c
	  memset(&UdpIpMsg,0,sizeof(udpipMessage));
      	  len=bpfRecvFrame(dhcpSocket,&UdpIpMsg,sizeof(udpipMessage));
	  if ( len == -1 )
    	    {
      	      syslog(LOG_ERR,"bpfRecvFrame: %m\n");
      	      return -1;
    	    }
```

(`i` stays declared — `dhcpSendAndRecv` reuses it elsewhere, e.g.
`i=random();`, unrelated to this change.)

- [ ] **Step 4: Replace the send call in `dhcpRelease()`**

Old:
```c
void *dhcpRelease()
{
  struct sockaddr addr;
  deleteDhcpCache();
  if ( DhcpIface.client_iaddr == 0 ) return &dhcpInit;

  buildDhcpRelease(random());

  memset(&addr,0,sizeof(struct sockaddr));
  memcpy(addr.sa_data,IfName,IfName_len);
  if ( DebugFlag )
    syslog(LOG_DEBUG,"sending DHCP_RELEASE for %u.%u.%u.%u to %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3],
	   ((unsigned char *)&DhcpIface.server_iaddr)[0],
	   ((unsigned char *)&DhcpIface.server_iaddr)[1],
	   ((unsigned char *)&DhcpIface.server_iaddr)[2],
	   ((unsigned char *)&DhcpIface.server_iaddr)[3]);
  if ( sendto(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage),0,
	      &addr,sizeof(struct sockaddr)) == -1 )
    syslog(LOG_ERR,"dhcpRelease: sendto: %m\n");
  arpRelease(); /* clear ARP cache entries for client IP addr */
  return &dhcpInit;
}
```

New:
```c
void *dhcpRelease()
{
  deleteDhcpCache();
  if ( DhcpIface.client_iaddr == 0 ) return &dhcpInit;

  buildDhcpRelease(random());

  if ( DebugFlag )
    syslog(LOG_DEBUG,"sending DHCP_RELEASE for %u.%u.%u.%u to %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3],
	   ((unsigned char *)&DhcpIface.server_iaddr)[0],
	   ((unsigned char *)&DhcpIface.server_iaddr)[1],
	   ((unsigned char *)&DhcpIface.server_iaddr)[2],
	   ((unsigned char *)&DhcpIface.server_iaddr)[3]);
  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
    syslog(LOG_ERR,"dhcpRelease: bpfSendFrame: %m\n");
  arpRelease(); /* clear ARP cache entries for client IP addr */
  return &dhcpInit;
}
```

- [ ] **Step 5: Replace the send call in `dhcpDecline()`**

Old:
```c
#ifdef ARPCHECK
void *dhcpDecline()
{
  struct sockaddr addr;
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);
  buildDhcpDecline(random());
  udpipgen((udpiphdr *)&UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
  memset(&addr,0,sizeof(struct sockaddr));
  memcpy(addr.sa_data,IfName,IfName_len);
  if ( DebugFlag ) syslog(LOG_DEBUG,"broadcasting DHCP_DECLINE\n");
  if ( sendto(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage),0,
	      &addr,sizeof(struct sockaddr)) == -1 )
    syslog(LOG_ERR,"dhcpDecline: sendto: %m\n");
  return &dhcpInit;
}
#endif
```

New:
```c
#ifdef ARPCHECK
void *dhcpDecline()
{
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);
  buildDhcpDecline(random());
  udpipgen((udpiphdr *)&UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
  if ( DebugFlag ) syslog(LOG_DEBUG,"broadcasting DHCP_DECLINE\n");
  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
    syslog(LOG_ERR,"dhcpDecline: bpfSendFrame: %m\n");
  return &dhcpInit;
}
#endif
```

- [ ] **Step 6: Fix `arp.c`'s three call sites**

Add `#include "bpfif.h"` to `arp.c`'s includes.

`arpCheck()` (under `#ifdef ARPCHECK`) has one send and one receive. Old:
```c
      	  memset(&addr,0,sizeof(struct sockaddr));
      	  memcpy(addr.sa_data,IfName,IfName_len);
      	  if ( sendto(dhcpSocket,&ArpMsgSend,sizeof(arpMessage),0,
	   	&addr,sizeof(struct sockaddr)) == -1 )
	    {
	      syslog(LOG_ERR,"arpCheck: sendto: %m\n");
	      return -1;
	    }
```

New:
```c
      	  if ( bpfSendFrame(dhcpSocket,&ArpMsgSend,sizeof(arpMessage)) == -1 )
	    {
	      syslog(LOG_ERR,"arpCheck: bpfSendFrame: %m\n");
	      return -1;
	    }
```

Old:
```c
      	  memset(&ArpMsgRecv,0,sizeof(arpMessage));
      	  j=sizeof(struct sockaddr);
      	  if ( recvfrom(dhcpSocket,&ArpMsgRecv,sizeof(arpMessage),0,
		    (struct sockaddr *)&addr,&j) == -1 )
    	    {
      	      syslog(LOG_ERR,"arpCheck: recvfrom: %m\n");
      	      return -1;
    	    }
```

New:
```c
      	  memset(&ArpMsgRecv,0,sizeof(arpMessage));
      	  if ( bpfRecvFrame(dhcpSocket,&ArpMsgRecv,sizeof(arpMessage)) == -1 )
    	    {
      	      syslog(LOG_ERR,"arpCheck: bpfRecvFrame: %m\n");
      	      return -1;
    	    }
```

`arpRelease()`. Old:
```c
  memset(&addr,0,sizeof(struct sockaddr));
  memcpy(addr.sa_data,IfName,IfName_len);
  if ( sendto(dhcpSocket,&ArpMsgSend,sizeof(arpMessage),0,
	      &addr,sizeof(struct sockaddr)) == -1 )
    {
      syslog(LOG_ERR,"arpRelease: sendto: %m\n");
      return -1;
    }
  return 0;
}
```

New:
```c
  if ( bpfSendFrame(dhcpSocket,&ArpMsgSend,sizeof(arpMessage)) == -1 )
    {
      syslog(LOG_ERR,"arpRelease: bpfSendFrame: %m\n");
      return -1;
    }
  return 0;
}
```

`arpInform()`. Old:
```c
  memset(&addr,0,sizeof(struct sockaddr));
  memcpy(addr.sa_data,IfName,IfName_len);
  if ( sendto(dhcpSocket,&ArpMsgSend,sizeof(arpMessage),0,
	      &addr,sizeof(struct sockaddr)) == -1 )
    {
      syslog(LOG_ERR,"arpInform: sendto: %m\n");
      return -1;
    }
  return 0;
}
```

New:
```c
  if ( bpfSendFrame(dhcpSocket,&ArpMsgSend,sizeof(arpMessage)) == -1 )
    {
      syslog(LOG_ERR,"arpInform: bpfSendFrame: %m\n");
      return -1;
    }
  return 0;
}
```

Each of `arpCheck()`, `arpRelease()`, and `arpInform()` declares its own
`struct sockaddr addr;` local (not shared) — remove that declaration line
from each function too, once its body no longer references `addr`. In
`arpCheck()`, `j` is orphaned as well: its only uses were
`j=sizeof(struct sockaddr);` and the `&j` argument to the removed
`recvfrom()`. Its declaration changes from `int j,i=0;` to `int i=0;`.

- [ ] **Step 7: Wait with `bpfPeek()` instead of `peekfd()`**

`bpfRecvFrame()` hands back one frame at a time from a buffer that may hold
several, and `select()` inside `peekfd()` cannot see the buffered ones. Each
of the four waits on `dhcpSocket` changes only its function name; the
arguments and return-value tests stay as they are.

In `client.c`, `dhcpSendAndRecv()`:

Old:
```c
      while ( peekfd(dhcpSocket,j+i%200000) );
```

New:
```c
      while ( bpfPeek(dhcpSocket,j+i%200000) );
```

Old:
```c
      while ( peekfd(dhcpSocket,j/2) == 0 );
```

New:
```c
      while ( bpfPeek(dhcpSocket,j/2) == 0 );
```

In `arp.c`, `arpCheck()`:

Old:
```c
      while ( peekfd(dhcpSocket,50000) ); /* 50 msec timeout */
```

New:
```c
      while ( bpfPeek(dhcpSocket,50000) ); /* 50 msec timeout */
```

Old:
```c
      while ( peekfd(dhcpSocket,50000) == 0 );
```

New:
```c
      while ( bpfPeek(dhcpSocket,50000) == 0 );
```

- [ ] **Step 8: Verify no Linux raw-socket symbols remain**

```bash
grep -n "SOCK_PACKET\|AF_PACKET\|SIOCGIFHWADDR\|sendto(\|recvfrom(" \
  src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
```

Expected: no output.

```bash
grep -c "bpfSendFrame\|bpfRecvFrame\|bpfOpenForInterface" \
  src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
```

Expected: `client.c` reports at least 7 (dhcpStart's open, dhcpSendAndRecv's
send+recv, dhcpRelease's send, dhcpDecline's send, plus each function's own
error-message string also containing the name); `arp.c` reports at least 6
(arpCheck's send+recv, arpRelease's send, arpInform's send, plus matching
error strings). Exact counts aren't load-bearing — zero would mean the
substitution didn't happen.

```bash
grep -n "struct sockaddr addr" \
  src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
```

Expected: no output (every local `addr` declaration was removed along with
its only uses).

```bash
grep -n "peekfd(dhcpSocket" src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
grep -n "bpfPeek" src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
```

Expected: the first prints nothing; the second prints exactly four lines,
two in each file.

- [ ] **Step 9: Commit**

```bash
git add src/dhcpcd-1/dhcpcd.tproj/client.c src/dhcpcd-1/dhcpcd.tproj/arp.c
git commit -m "dhcpcd-1: wire the BPF backend into client.c and arp.c"
```

---

### Task 6: Boot-compat wait mode

**Files:**
- Create: `src/dhcpcd-1/dhcpcd.tproj/bootcompat.h`
- Create: `src/dhcpcd-1/dhcpcd.tproj/bootcompat.c`
- Modify: `src/dhcpcd-1/dhcpcd.tproj/dhcpcd.c`

**Interfaces:**
- Consumes: `extern dhcpInterface DhcpIface;` and
  `extern dhcpOptions DhcpOptions;` (both defined in `client.c:70-71`, per
  Task 1's vendored source), and the option-tag `enum` from `client.h`
  (`subnetMask = 1`, `routersOnSubnet = 3`, `hostName = 12`).
- Produces: `void bootcompatPrint(void);` — prints `ip_address`,
  `subnet_mask`, `router`, `host_name`, and `server_ip_address` as
  `key=value` lines to stdout, matching the exact key names
  `src/files-5/private/etc/startup/0800_Network` reads back via
  `GetNetConfig` (confirmed at `0800_Network:125,128,189,196,207`), and the
  exact `key=value`-per-line format `SetNetConfig`/`GetNetConfig` expect
  (confirmed in `src/files-5/private/etc/rc.common:60-142` — no `_count`
  suffix needed for a single-value field). `dhcpcd.c` calls this, guarded by
  a new `-w` flag, right before its existing fork-to-background call.

- [ ] **Step 1: Write `bootcompat.h`**

```c
/*
 * bootcompat.h - bootpc-compatible boot-time status output for dhcpcd-1
 *
 * 0800_Network captures dhcpcd's stdout via `config=$(dhcpcd -w "$if")`
 * exactly as it captures bootpc's today, then feeds it to SetNetConfig.
 * bootcompatPrint() reproduces the subset of bootpc's key=value output
 * 0800_Network actually reads back (ip_address, subnet_mask, router,
 * host_name, server_ip_address).
 */

#ifndef BOOTCOMPAT_H
#define BOOTCOMPAT_H

void bootcompatPrint(void);

#endif /* BOOTCOMPAT_H */
```

- [ ] **Step 2: Write `bootcompat.c`**

```c
/*
 * bootcompat.c - see bootcompat.h
 */

#include <stdio.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "client.h"
#include "bootcompat.h"

extern dhcpInterface	DhcpIface;
extern dhcpOptions	DhcpOptions;

void
bootcompatPrint()
{
  struct in_addr addr;

  addr.s_addr = DhcpIface.client_iaddr;
  printf("ip_address=%s\n",inet_ntoa(addr));

  if ( DhcpOptions.val[subnetMask] )
    {
      addr.s_addr = *(unsigned int *)DhcpOptions.val[subnetMask];
      printf("subnet_mask=%s\n",inet_ntoa(addr));
    }

  if ( DhcpOptions.val[routersOnSubnet] )
    {
      addr.s_addr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
      printf("router=%s\n",inet_ntoa(addr));
    }

  if ( DhcpOptions.val[hostName] )
    printf("host_name=%s\n",(char *)DhcpOptions.val[hostName]);

  addr.s_addr = DhcpIface.server_iaddr;
  printf("server_ip_address=%s\n",inet_ntoa(addr));

  fflush(stdout);
}
```

`fflush(stdout)` matters here specifically: this prints right before
`dhcpcd.c`'s existing `fork()`, and stdio is fully-buffered (not
line-buffered) when stdout is a pipe — which it is, under
`config=$(dhcpcd -w "$if")`. Without the explicit flush, the buffered output
would still be sitting in memory (duplicated into both the parent and child
after `fork()`) instead of having reached the shell.

- [ ] **Step 3: Add the `WaitFlag` global and `-w` option**

In `dhcpcd.c`, alongside the other globals near the top:

Old:
```c
int		ReplResolvConf	=	1;
int		SetDomainName	=	0;
int		SetHostName	=	0;
```

New:
```c
int		ReplResolvConf	=	1;
int		SetDomainName	=	0;
int		SetHostName	=	0;
int		WaitFlag	=	0;
```

In the `prgs:` flag-parsing `switch`, alongside the other boolean flags:

Old:
```c
	  case 'R':
	    s++;
	    ReplResolvConf=0;
	    goto prgs;
	  case 'c':
```

New:
```c
	  case 'R':
	    s++;
	    ReplResolvConf=0;
	    goto prgs;
	  case 'w':
	    s++;
	    WaitFlag=1;
	    goto prgs;
	  case 'c':
```

- [ ] **Step 4: Call `bootcompatPrint()` before backgrounding**

Add `#include "bootcompat.h"` to `dhcpcd.c`'s includes, alongside
`#include "client.h"`.

Old:
```c
#ifndef DEBUG
  if ( fork() ) exit(0); /* got into bound state. */
  setsid();
#endif
```

New:
```c
#ifndef DEBUG
  if ( WaitFlag ) bootcompatPrint();
  if ( fork() ) exit(0); /* got into bound state. */
  setsid();
#endif
```

- [ ] **Step 5: Update the usage string**

Old:
```c
usage:	    fprintf(stderr,"\
DHCP Client Daemon v."PROGRAM_VERSION"\n\
Copyright (C) 1996 - 1997 Yoichi Hariguchi <yoichi@fore.com>\n\
Copyright (C) January, 1998 Sergei Viznyuk <sv@phystech.com>\n\
Usage: dhcpcd [-dkrDHR] [-l leasetime] [-h hostname] [-t timeout]\n\
       [-i vendorClassID] [-I ClientID] [-c filename] [interface]\n");
```

New:
```c
usage:	    fprintf(stderr,"\
DHCP Client Daemon v."PROGRAM_VERSION"\n\
Copyright (C) 1996 - 1997 Yoichi Hariguchi <yoichi@fore.com>\n\
Copyright (C) January, 1998 Sergei Viznyuk <sv@phystech.com>\n\
Usage: dhcpcd [-dkrDHRw] [-l leasetime] [-h hostname] [-t timeout]\n\
       [-i vendorClassID] [-I ClientID] [-c filename] [interface]\n");
```

- [ ] **Step 6: Verify the key set matches what `0800_Network` reads**

```bash
grep -n 'printf("[a-z_]*=' src/dhcpcd-1/dhcpcd.tproj/bootcompat.c
grep -n "GetNetConfig" src/files-5/private/etc/startup/0800_Network
```

Expected: the first shows `ip_address=`, `subnet_mask=`, `router=`,
`host_name=`, `server_ip_address=` — exactly the five variable names the
second command's `GetNetConfig "${if}" <name> 1` calls in
`0800_Network` ask for (`ip_address`, `subnet_mask`, `host_name`, `router`;
`server_ip_address` is read via `GetNetConfig "${if}" server_ip_address`
without a count, in the progress-message `echo` right after
`SetNetConfig`).

```bash
grep -n "WaitFlag" src/dhcpcd-1/dhcpcd.tproj/dhcpcd.c
```

Expected: three matches — the global declaration, the `case 'w':` setting
it, and the `if ( WaitFlag )` guard before `fork()`.

- [ ] **Step 7: Commit**

```bash
git add src/dhcpcd-1/dhcpcd.tproj/bootcompat.c src/dhcpcd-1/dhcpcd.tproj/bootcompat.h \
        src/dhcpcd-1/dhcpcd.tproj/dhcpcd.c
git commit -m "dhcpcd-1: add -w boot-compat wait mode"
```

#### Amendment after review (commit c50259725)

- **Release stdout in the daemon.** After `fork()`, the background child kept
  fd 1, the write end of the pipe behind `config=$(dhcpcd -w "${if}")`.
  Command substitution waits for EOF, so the boot script would have hung for
  the daemon's whole life. The child now points stdout at `/dev/null` right
  after `setsid()`.
- **Check the host name.** `0800_Network` passes these lines unquoted to
  `rc.common`'s `SetNetConfig`, which `eval`s them as root. `host_name` comes
  from the DHCP server, so `bootcompatPrint()` prints it only if it is
  non-empty and contains nothing but alphanumerics, `-` and `.`. The other
  values come from `inet_ntoa()`.
- `bootcompat.c` includes `<sys/types.h>` first, and `dhcpcd.8` documents
  `-w`.

---

### Task 7: Boot integration: `0800_Network` and `/etc/dhcpc`

**Files:**
- Modify: `src/files-5/private/etc/startup/0800_Network`
- Modify: `src/files-5/private/etc/Makefile`

**Interfaces:**
- Consumes: `dhcpcd -w <ifname>` (Task 6), whose stdout is wire-compatible
  with `bootpc <ifname>`'s.
- Consumes: dhcpcd's hardcoded lease paths, `DHCP_CACHE_FILE`
  `/etc/dhcpc/dhcpcd-%s.cache` and `DHCP_HOSTINFO` `/etc/dhcpc/dhcpcd-%s.info`
  (`pathnames.h:30-31`). No `/etc/dhcpc` exists in `files-5` today.
- Produces: no change to any `SetNetConfig`/`GetNetConfig` consumer in this
  script — this is the single line the whole plan has been building toward —
  and an empty `/etc/dhcpc` (root:wheel, 755) in the installed tree.

- [ ] **Step 1: Make the change**

Old (`0800_Network:59-63`):
```sh
		# Start by getting bootpc data
		ifconfig "${if}" 0.0.0.0 netmask 255.0.0.0 broadcast 255.255.255.255 > /dev/null
		route add -net 255.255.255.255 -netmask 255.0.0.0 0.0.0.0 -iface     > /dev/null
		echo -n "    Trying BOOTP for interface ${if}:"
		if config=$(bootpc "${if}"); then
```

New:
```sh
		# Start by getting dhcpcd data
		ifconfig "${if}" 0.0.0.0 netmask 255.0.0.0 broadcast 255.255.255.255 > /dev/null
		route add -net 255.255.255.255 -netmask 255.0.0.0 0.0.0.0 -iface     > /dev/null
		echo -n "    Trying DHCP for interface ${if}:"
		if config=$(dhcpcd -w "${if}"); then
```

(The comment and progress message are updated too, since leaving them saying
"bootpc"/"BOOTP" next to a `dhcpcd -w` call would be actively misleading —
this is still a one-line-of-logic change, just with its neighboring text
kept honest.)

- [ ] **Step 2: Create `/etc/dhcpc` at install time**

`src/files-5/private/etc/Makefile` installs files and subdirectories with
their own Makefiles, but has no way to create an empty directory. Add one,
modelled on its existing empty-files loop.

After the `EMPTYFILES`/`EMPTYMODE` definitions:

Old:
```makefile
EMPTYFILES = find.codes hosts.equiv rmtab utmp xtab
EMPTYMODE = 644
```

New:
```makefile
EMPTYFILES = find.codes hosts.equiv rmtab utmp xtab
EMPTYMODE = 644

#	Directories that are created empty
EMPTYDIRS = dhcpc
```

In the `install:` recipe, right after the empty-files loop's closing
`echo "."` and before `echo -n "    Empty group-writeable files:"`, insert:

```makefile
	echo -n "    Empty directories:"
	for i in `echo ${EMPTYDIRS}` ; \
	  do \
		echo -n " $$i" ; \
		mkdir -p -m ${DSTMODE} ${DSTDIR}/$$i ; \
		chown ${OWNER}.${GROUP} ${DSTDIR}/$$i ; \
	  done
	echo "."
```

Whitespace matters here: every recipe line starts with one tab, the
`do`/`done` lines are a tab plus two spaces, and the loop body lines are two
tabs — the same layout as the empty-files loop directly above it.

```bash
s=$(grep -n 'Empty directories' src/files-5/private/etc/Makefile | cut -d: -f1)
sed -n "${s},$((s+7))p" src/files-5/private/etc/Makefile | cat -A
```

Expected: eight lines, each beginning `^I` (the loop body lines `^I^I`, the
`do`/`done` lines `^I  `), none containing a literal run of leading spaces
where the neighbouring loop has a tab.

- [ ] **Step 3: Verify no other reference to `bootpc` remains in this script**

```bash
grep -n "bootpc\|dhcpcd" src/files-5/private/etc/startup/0800_Network
```

Expected: only the new `dhcpcd -w "${if}"` line and its adjacent comment/echo
from Step 1 — no remaining `bootpc` reference anywhere in the file.

```bash
grep -c "SetNetConfig\|GetNetConfig" src/files-5/private/etc/startup/0800_Network
```

Expected: the same count as before this task's edit (this task changes
nothing about how `config` is consumed downstream — only run this before
and after Step 1 to confirm, or `git diff` the file and confirm the diff is
exactly the four changed words: `bootpc data`→`dhcpcd data`,
`BOOTP for`→`DHCP for`, `bootpc "${if}"`→`dhcpcd -w "${if}"`).

- [ ] **Step 4: Commit**

```bash
git add src/files-5/private/etc/startup/0800_Network src/files-5/private/etc/Makefile
git commit -m "boot: use dhcpcd for automatic interfaces and create /etc/dhcpc for its lease cache"
```

---

### Task 8: Real build verification (checkpoint, not autonomous)

**Files:** none — this task is a checkpoint, not an edit.

**Interfaces:** none.

- [ ] **Step 1: Ask the user whether the VM/`rbuild` flow is free**

Do not run or poll the VM/`rbuild` build automatically. Ask the user
directly whether the concurrent session's work in `vm/` has finished and the
guest is free to use. If they say yes, proceed to Step 2. If they say no or
don't know, stop here and leave this task unchecked — the plan's other seven
tasks are already complete and committed independently of this one.

- [ ] **Step 2: Run the real build, once confirmed free**

Follow `README.md`'s documented `rbuild` flow (sync `dhcpcd-1` to the guest,
build it there) — the exact commands depend on the state the user reports
the VM is in, so they aren't fixed in advance here. Confirm: `dhcpcd`
compiles, links, and installs to `/usr/sbin`.

- [ ] **Step 3: Boot-test on a temporary/isolated disk image**

Per `CLAUDE.md`'s debugging guidance, use a temporary disk image so this
doesn't collide with any other session's boot testing. Confirm: dhcpcd
acquires a lease, `0800_Network`'s hostname/router/default-route logic
still resolves correctly from dhcpcd's `-w` output, and a renewal (forced
with a short lease time from a test DHCP server) re-applies the address
without a reboot. This step also requires `drvBPF` (owned by another
session) to actually build and boot — check that separately before
expecting this to succeed.

- [ ] **Step 4: Report results**

Whatever the outcome, report it plainly — including partial failures (e.g.
"compiles but drvBPF isn't ready yet, so the DHCP exchange itself is
untested"). Do not mark this task's checkbox complete unless both Step 2 and
Step 3 actually succeeded.
