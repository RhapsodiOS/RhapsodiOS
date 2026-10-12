# Where the commands in src/Commands came from

This maps every project and tool under `src/Commands` to its upstream source, using the version
tags in the sources themselves (`$NetBSD$`, `$OpenBSD$`, `$FreeBSD$`, `@(#)` sccsids, GNU version
files). Use it to find the right upstream when backporting a fix.

## Reading the tags

- **4.4BSD-Lite.** An `@(#) ... (Berkeley)` sccsid with version 8.x is 4.4BSD. A 1995 date means
  4.4BSD-Lite2; 1993-94 dates are "Lite/Lite2" because Lite2 kept files that did not change.
- **Apple-reworked trees.** In the Darwin 0.3 `.tproj` projects most `.c` files had their sccsid
  replaced by the 1999 APSL header. There the tag comes from the man page "(man)" or Makefile "(Mk)".
  `$Id: ... wsanchez $` tags are Apple's own CVS re-import and say nothing about origin.
- **Mixed tags.** An `$OpenBSD$` line above a `$NetBSD$` line means the file came from NetBSD by way
  of OpenBSD.
- **Release dates.** NetBSD 1.2 Oct 1996, 1.3 Jan 1998, 1.4 May 1999. OpenBSD 2.0 Oct 1996, 2.1
  Jun 1997, 2.2 Dec 1997.
- **"cur98" and "=1.3".** developer, doc, file, mail, misc, shell and text_cmds are one
  NetBSD-current snapshot; its newest tag is `ls/cmp.c 1.14 1998/10/09`, so the snapshot is
  NetBSD-current of about October 1998, between 1.3 and 1.4. "=1.3" marks a file whose revision
  predates December 1997 and so is also the 1.3 release revision (inferred). "cur98" marks a file
  changed after 1.3.
- "approx." and "inferred" mark releases worked out from dates rather than read from a tag.

## Summary

| Era | Projects |
|---|---|
| 4.4BSD-Lite2 (1995), Apple/NeXT maintained | adv_cmds, basic_cmds, diskdev_cmds, network_cmds, system_cmds (mostly) |
| NetBSD-current ~Oct 1998 | developer_cmds, doc_cmds, file_cmds, mail_cmds, misc_cmds, shell_cmds, text_cmds |
| OpenBSD 2.0-2.2 imports | sh, more, pax, the YP suite, makedbm, stdethers/stdhosts, revnetgroup, tcpdump/pcap, zic/zdump |
| CMU Mach / NeXT / Apple originals | at_cmds, bootstrap_cmds, md, ps, mach_init, hostinfo, vm_stat, disk, pdisk, ... |
| Third-party packages | bash, tcsh, zsh, GNU tar/gzip/grep/wget, less, rsync, nvi, pico, apk-tools |

Everything here was in the original Darwin 0.3 import (`19ffee9a5`) except **apk-tools-1**
(added `2a7f7682a`, 2026-07) and **pico-1** (added `6b3c3fb13`, 2026-09). Later commits only moved
directories.

`/bin/sh` is **not** NetBSD's sh directly: it is the Almquist shell from OpenBSD 2.0-2.1, which
OpenBSD took from NetBSD 1.1/1.2. RhapsodiOS has backported NetBSD's `-e` handling (NetBSD
`eval.c` 1.93, 2008) into it; see `sh.tproj/tests/errexit.sh`.

## Third-party packages

| Project | Upstream | Version (where read) | Notes |
|---|---|---|---|
| bash | GNU bash | 2.02.1 (CHANGES) | |
| tcsh | tcsh | 6.08.00, 1998-10-02 (patchlevel.h) | |
| zsh | zsh | 3.1.5, 1998-10-29 (Config/version.mk) | |
| gnutar-1 | GNU tar | 1.12 (configure.in) | |
| gnuzip-1 | GNU gzip | 1.2.4 (revision.h) | |
| grep-1 | GNU grep | 2.2 (configure.in) | |
| less-1 | less | v332, 1997-04-22 (version.c) | |
| rsync-1 | rsync | 2.1.1 (version.h) | |
| vi-1 | nvi | 1.79, 1996-10-23 (ex/version.h) | |
| wget-1 | GNU wget | 1.5.3 (src/version.c) | |
| pico-1 | pico from UW pine 4.50 | 4.3L (pico.h) | RhapsodiOS addition; see LOCAL-CHANGES |
| apk-tools-1 | Alpine apk-tools | 2.0_pre12 (Makefile) | RhapsodiOS addition; see PORTING.md |

## adv_cmds (4.4BSD, Apple/NeXT tree)

| Tool | Origin | Tag | Release |
|---|---|---|---|
| cap_mkdb | 4.4BSD | cap_mkdb.1 8.1 6/6/93 (man) | Lite/Lite2 |
| finger | 4.4BSD | extern.h 8.2 4/28/95 | Lite2 |
| fingerd | 4.4BSD | fingerd.c 8.1 6/4/93 | Lite/Lite2 |
| last | 4.4BSD | last.1 8.1 6/6/93 (man) | Lite/Lite2 |
| md | CMU Mach | Robert V. Baron 1986 | - |
| mklocale | 4.4BSD | ldef.h 8.1 6/6/93 | Lite/Lite2 |
| ps | CMU Mach / NeXT | ps.c, NeXT history to 1994 | Mach ps, not BSD ps |
| pstat | 4.4BSD | pstat.c 8.16 5/9/95 | Lite2 |
| sccs | 4.4BSD | sccs.c 8.1 6/6/93 | Lite/Lite2 |
| stty | 4.4BSD | stty.1 8.5 6/1/94 | Lite/Lite2 |
| tput | 4.4BSD | tput.1 8.2 3/19/94 | Lite/Lite2 |
| tset | 4.4BSD | tset.1 8.1 6/9/93 | Lite/Lite2 |
| tty | 4.4BSD | tty.1 8.1 6/6/93 | Lite/Lite2 |
| whois | 4.4BSD | whois.1 8.2 6/20/94 | Lite/Lite2 |

## at_cmds (Apple)

All AppleTalk tools are Apple originals with no BSD lineage: appleping, appletalk, at_cho_prn,
atlookup, atprint, atstatus, aurpd, chooser, dbgcom, router, setdbg, tuple_pr.

## basic_cmds

| Tool | Origin | Tag | Release |
|---|---|---|---|
| csh.tproj | 4.4BSD + NeXT | csh.c 8.4 4/29/95 | Lite2 |
| ls.tproj | 4.4BSD | stat_flags.c 8.2 7/28/94 | helper sources, not built as a tool |
| mesg | 4.4BSD + NeXT | mesg.c 8.2 1/21/94 | Lite/Lite2 |
| more | OpenBSD (4.3BSD-Reno more) | more.c `$OpenBSD$` 1.7 1997/01/17 | OpenBSD ~2.1 (approx.) |
| pico.tproj | UW pine | pico.h "2.3" | pico 2.3; separate from pico-1 |
| printf.tproj | 4.4BSD + NeXT | printf.c 8.2 3/22/95 | helper for csh, not built as a tool |
| sh.tproj | ash, NetBSD via OpenBSD | main.c `$OpenBSD$` 1.5 1996/10/20 over `$NetBSD$` 1.23 1995/11/19 | OpenBSD ~2.0-2.1 (approx.); NetBSD 5 errexit backport |
| uudecode, uuencode | 4.4BSD + NeXT | 8.2 4/2/94 | Lite/Lite2 |
| write | 4.4BSD + NeXT | write.c 8.2 4/27/95 | Lite2 |

## bootstrap_cmds

| Tool | Origin | Tag |
|---|---|---|
| config | 4.3BSD config, NeXT-modified | main.c 5.9 6/18/88 (pre-4.4) |
| decomment, relpath | NeXT/Apple | Apple header only |
| migcom (+ typd, untypd) | CMU Mach MIG, NeXT/Apple | CMU history 1989; bootstrap_cmds-13.2 |

## developer_cmds (NetBSD-current ~Oct 1998)

| Tool | Tag | Release |
|---|---|---|
| asa | asa.c 1.11 1997/09/20 | =1.3 |
| cpp | usr.bin.cpp.sh 6.5 4/1/91 | 4.3BSD-Reno wrapper |
| ctags | ctags.c 1.6 1998/08/25 | cur98 |
| error | main.c 1.4 1997/10/18 | =1.3 |
| fpr | fpr.c 1.4 1997/10/18 | =1.3 |
| fsplit | fsplit.c 1.5 1997/10/18 | =1.3 |
| hexdump | hexdump.c 1.7 1997/10/19 | =1.3 |
| indent | indent.c 1.8 1998/09/06 | cur98 |
| lint | decl.c 1.15 1998/07/27 | cur98 |
| lorder | lorder.sh 1.7 1998/04/09 | cur98 |
| menuc | avl.c 1.1.1.1 1997/09/26 | =1.3 |
| mkdep | mkdep.sh 1.5 1998/04/09 | cur98 |
| mkstr | mkstr.c 1.8 1997/10/19 | =1.3 |
| msgc | main.c 1.4 1998/02/03 | cur98 |
| rpcgen | rpc_main.c 1.14 1997/10/18 (Sun RPCSRC) | =1.3 |
| unifdef | unifdef.c 1.5 1997/10/20 | =1.3 |
| vgrind | vgrindefs.c 1.6 1997/10/20 | =1.3 |
| what | what.c 1.6 1997/10/20 | =1.3 |
| xstr | xstr.c 1.8 1998/09/27 | cur98 |

## diskdev_cmds (4.4BSD, Apple/NeXT tree)

| Tool | Origin | Tag | Release |
|---|---|---|---|
| autodiskmount | Apple | Apple 1997 | - |
| bad144 | 4.4BSD | bad144.c 8.2 4/27/95 | Lite2 |
| badsect | 4.4BSD | badsect.8 8.1 (man) | Lite/Lite2 |
| clri | 4.4BSD + Apple | clri.8 8.2 4/19/94 (man) | Lite/Lite2 |
| dev_mkdb | 4.4BSD | dev_mkdb.c 8.1 6/6/93 | Lite/Lite2 |
| disk | NeXT | disk.c 1987 NeXT | NeXTSTEP |
| disklabel | 4.4BSD | disklabel.8 8.2 (man) | Lite/Lite2 |
| disklib | 4.4BSD headers | fsck.h 8.4 5/9/95 | shared sources, not a tool |
| diskpart | 4.4BSD | diskpart.c 8.3 11/30/94 | Lite2 (approx.) |
| dump | 4.4BSD | dump.8 8.3 5/1/95 (man) | Lite2 |
| dumpfs | 4.4BSD + Apple | dumpfs.8 8.1 (man) | Lite/Lite2 |
| dumplfs | 4.4BSD | extern.h 8.2 4/28/95 | Lite2 |
| edquota | 4.4BSD | edquota.c 8.3 4/27/95 | Lite2 |
| fdform | NeXT | 1996 | - |
| fdisk | Apple | 1998 | - |
| fsck | 4.4BSD | fsck.8 8.4 5/9/95 (man) | Lite2 |
| fsck_hfs | Apple | 1997 | - |
| fstat | 4.4BSD | fstat.1 8.3 2/25/94 (man) | Lite/Lite2 |
| lfs_cleanerd | 4.4BSD + one NetBSD file | cleanerd.c 8.5 6/10/95; lfs_cksum.c `$NetBSD$` 1.4 | Lite2 |
| mount | 4.4BSD | mount_ufs.c 8.4 4/26/95 | Lite2 |
| mount_cd9660 | 4.4BSD | mount_cd9660.c 8.7 5/1/95 | Lite2 |
| mount_fdesc, _kernfs, _lfs, _nfs, _null, _procfs, _umap, _union | 4.4BSD | man 8.2-8.7, 1994-95 | Lite2 |
| mount_portal | 4.4BSD | activate.c 8.3 4/28/95 | Lite2 |
| mount_swapfs | NeXT | 1991/1993 | - |
| mountd | 4.4BSD | mountd.8 8.4 4/28/95 (man) | Lite2 |
| mt | 4.4BSD | mt.1 8.1 (man) | Lite/Lite2 |
| newfs | 4.4BSD + Apple | newfs.8 8.6 5/3/95 (man) | Lite2 |
| newlfs | 4.4BSD | config.h 8.3 5/24/95 | Lite2 |
| pdisk | Apple (Eryk Vershen) | 1996-97 | - |
| quot | TooLs GmbH (NetBSD contrib) | Apple $Id only | NetBSD-era (inferred) |
| quota, quotacheck, quotaon, repquota | 4.4BSD | repquota.c 8.2 11/22/94 | Lite/Lite2 |
| restore | 4.4BSD | restore.8 8.4 5/1/95 (man) | Lite2 |
| scsiformat | 4.4BSD (hp300) | scsiformat.8 5.1 6/5/93 | Lite |
| sdform | NeXT | 1996 | - |
| showmount | 4.4BSD | showmount.8 8.3 3/29/95 | Lite2 |
| tunefs | 4.4BSD | tunefs.8 8.3 5/3/95 | Lite2 |
| umount | 4.4BSD | umount.8 8.2 5/8/95 | Lite2 |

## doc_cmds (NetBSD-current ~Oct 1998)

| Tool | Tag | Release |
|---|---|---|
| apropos | apropos.c 1.13 1998/07/06 | cur98 |
| catman | catman.c 1.9 1997/10/24 | =1.3 |
| checknr | checknr.c 1.5 1997/10/18 | =1.3 |
| colcrt | colcrt.c 1.4 1997/10/18 | =1.3 |
| getNAME | getNAME.c 1.14 1998/05/21 | cur98 |
| makewhatis | makewhatis.8 1.4 1997/11/02 | =1.3 |
| man | man.c 1.13 1998/08/25 | cur98 |
| soelim | soelim.c 1.6 1998/02/03 | cur98 |
| whatis | whatis.c 1.12 1998/07/06 | cur98 |

## file_cmds (NetBSD-current ~Oct 1998, except pax)

| Tool | Tag | Release |
|---|---|---|
| chflags | 1.5 1997/10/18 | =1.3 |
| chmod | 1.20 1998/07/28 | cur98 |
| chown | 1.15 1998/10/05 | cur98 |
| cksum | crc.c 1.8 1997/10/17 | helper for mtree, not a tool |
| compress | 1.16 1998/03/10 | cur98 |
| cp | 1.24 1998/08/19 | cur98 |
| csh | strpct.c 1.2 1998/05/08 | helper for df, not a tool |
| dd | 1.12 1998/08/19 | cur98 |
| df | 1.30 1998/07/28 | cur98 |
| du | 1.14 1998/02/15 | cur98 |
| file | file.c 1.14 1998/09/20 (Christos Zoulas file, ~3.26 inferred) | cur98 |
| install | xinstall.c 1.27 1998/10/01 | cur98 |
| ln | 1.15 1998/07/28 | cur98 |
| ls | ls.c 1.31 1998/08/19; cmp.c 1.14 1998/10/09 | cur98 |
| mkdir | 1.19 1998/07/28 | cur98 |
| mkfifo | 1.8 1997/10/19 | =1.3 |
| mknod | 1.15 1998/09/11 | cur98 |
| mtree | 1.9 1997/10/17 | =1.3 |
| mv | 1.19 1998/07/28 | cur98 |
| pax | **OpenBSD** pax.c 1.11 1997/09/01 over `$NetBSD$` 1.5 1996/03/26 | OpenBSD ~2.2 (approx.) |
| rm | 1.24 1998/07/28 | cur98 |
| rmdir | 1.16 1998/07/28 | cur98 |
| rmt | 1.9 1997/10/17 | =1.3 |
| shar | shar.1 1.6 1998/06/08 | cur98 |
| tcopy | 1.8 1998/08/25 | cur98 |
| touch | 1.22 1998/08/25 | cur98 |

## mail_cmds and misc_cmds (NetBSD-current ~Oct 1998)

| Tool | Tag | Release |
|---|---|---|
| biff | 1.6 1998/07/28 | cur98 |
| comsat | 1.14 1998/07/06 | cur98 |
| from | 1.8 1997/10/18 | =1.3 |
| mail | main.c 1.8 1997/10/19 | =1.3 |
| msgs | 1.12 1998/07/26 | cur98 |
| vacation | 1.15 1998/07/26 | cur98 |
| cal | 1.10 1998/07/28 | cur98 |
| calendar | 1.15 1998/07/28 | cur98 |
| leave | 1.7 1998/04/02 | cur98 |
| lock | 1.15 1998/07/26 | cur98 |
| tsort | 1.13 1998/08/25 | cur98 |
| units | 1.8 1998/02/03 | cur98 |

## network_cmds (mixed)

| Tool | Origin | Tag | Release / notes |
|---|---|---|---|
| arp | 4.4BSD | arp.c 8.3 4/28/95 | Lite2 |
| bootparams | Apple | 1998 | NetInfo |
| domainname | Theo de Raadt 1992-93 | Apple $Id | NetBSD-era (inferred) |
| ftp | 4.4BSD | ftp_var.h 8.4 10/9/94 | Lite2 (approx.) |
| ftpd | 4.4BSD | ftpd.c 8.5 4/28/95 | Lite2 |
| identd | pidentd | version.c "2.1.2" | pidentd 2.1.2 |
| ifconfig | 4.4BSD + Apple | ifconfig.8 8.4 6/1/94 | Lite/Lite2 |
| inetd | 4.4BSD | inetd.c 8.4 4/13/94 | Lite/Lite2 |
| logger | 4.4BSD | man `$OpenBSD$` 1.2 1996 over `$NetBSD$` | Lite |
| makedbm | OpenBSD | makedbm.c 1.9 1997/08/18 | OpenBSD ~2.2 |
| named, nslookup | BIND 4.9.x, NeXT-modified | sccs 4.x 1990-91 | patchlevel not recorded |
| netstat | 4.4BSD | netstat.1 8.8 4/18/94 | Lite/Lite2 |
| newclient | NeXT/Apple | - | - |
| nfsd, nfsiod, nfsstat | 4.4BSD | nfsstat.c 8.2 3/31/95 | Lite2 |
| pcap | LBL libpcap via OpenBSD | pcap.c `$OpenBSD$` 1.4 1996/07/12 | OpenBSD 2.0 (approx.) |
| ping | 4.4BSD | ping.8 8.3 4/28/95 | Lite2 |
| popper | UCB popper | VERSION "1.831beta" | - |
| portmap | 4.4BSD (Sun RPCSRC 4.0) | portmap.c 8.1 6/6/93 | Lite/Lite2 |
| rarpd | LBL | 1990 | - |
| rbootd | 4.4BSD | rbootd.c 8.2 2/22/94 | Lite/Lite2 |
| rcp, rdist, rexecd, rlogin, rsh, rshd | 4.4BSD | 8.x 1993-94 | Lite/Lite2 |
| rlogind | 4.4BSD | rlogind.c 8.2 4/28/95 | Lite2 |
| revnetgroup | FreeBSD via OpenBSD | `$OpenBSD$` 1.1 1997/04/15 over `$FreeBSD$` 1.7 | OpenBSD ~2.1 |
| route, routed | 4.4BSD | 8.x 4/28/95 | Lite2 |
| rpc_bootparamd, rpc_mountd, rpc_ypupdated | Sun 4.1 NFSSRC | 1990-92 | - |
| rpc_lockd | Sun | hash.c 1.8 92/02/27 | - |
| rpc_rquotad, rpc_rstatd, rpc_rusersd, rpc_rwalld, rpc_sprayd, spray | NetBSD contrib | Apple $Id only | NetBSD-era (inferred) |
| rpc_yppasswdd | OpenBSD + one NetBSD file | 1.9 1997/08/19; passwd.c `$NetBSD$` 1.11 | OpenBSD ~2.2 |
| rpcinfo, rstat | Sun RPCSRC 4.0 | 1988 | - |
| ruptime, rwho, rwhod, wall | 4.4BSD + NeXT | 8.x 1993-94 | Lite/Lite2 |
| slattach, startslip, sliplogin | 4.4BSD | sliplogin.c 8.2 2/1/94 | Lite/Lite2 |
| stdethers, stdhosts | OpenBSD | 1997/09/11 | OpenBSD ~2.2 |
| syslogd | 4.4BSD | syslogd.c 8.3 4/4/94 | Lite/Lite2 |
| talk, talkd, tftp, tftpd, tn3270 | 4.4BSD | 8.x 1993-94 | Lite/Lite2 |
| tcpdump | LBL tcpdump via OpenBSD | version.c "3.2.0"; `$OpenBSD$` 1.4 1996/07/13 | tcpdump 3.2.0, OpenBSD 2.0 |
| telnet, telnetd | 4.4BSD | 8.4 5/30/95 | Lite2 |
| timed | 4.4BSD | timed.c 8.2 3/26/95 | Lite2 |
| traceroute, trpt, trsp, uucpd | 4.4BSD | 8.1 6/93 | Lite/Lite2 |
| ypbind, ypcat, ypmatch, yppoll, ypwhich | Theo de Raadt (NetBSD/OpenBSD) | ypbind.8 `$OpenBSD$` 1.8 1997/06/18 | OpenBSD ~2.1 (inferred) |
| ypinit | OpenBSD | 1.1 1997/04/20 | OpenBSD ~2.1 |
| yppush, ypserv | OpenBSD | 1997/11 | OpenBSD ~2.2 |
| ypset | NetBSD via OpenBSD | ypset.8 `$OpenBSD$` 1.3 1996/04/24 | OpenBSD ~2.0 |
| ypxfr | OpenBSD | 1.22 1997/07/30 | OpenBSD ~2.2 |

## shell_cmds (NetBSD-current ~Oct 1998)

| Tool | Tag | Release |
|---|---|---|
| apply | 1.6 1997/12/31 | ~1.3 |
| basename | 1.10 1997/10/18 | =1.3 |
| chroot | 1.7 1998/10/06 | cur98 |
| date | 1.25 1998/07/28 | cur98 |
| dirname | 1.7 1997/10/18 | =1.3 |
| echo | 1.8 1997/11/05 | =1.3 |
| env | 1.10 1997/10/18 | =1.3 |
| expr | 1.9 1998/07/28 | cur98 |
| false, true | man 1.5 1997/10 (scripts) | =1.3 |
| find | 1.11 1998/02/21 | cur98 |
| getopt | 1.5 1998/02/03 | cur98 |
| hostname | 1.13 1998/07/28 | cur98 |
| id | 1.10 1998/08/25 | cur98 |
| jot | 1.4 1997/10/19 | =1.3 |
| kill | 1.16 1998/07/28 | cur98 |
| lastcomm | 1.14 1998/04/02 | cur98 |
| locate | 1.8 1997/10/19 | =1.3 |
| logname | 1.7 1997/10/19 | =1.3 |
| machine | 1.4 1997/10/19 | =1.3 |
| nice | 1.10 1997/10/19 | =1.3 |
| nohup | 1.8 1997/12/23 | ~1.3 |
| printenv | 1.6 1997/10/19 | =1.3 |
| printf | 1.19 1998/02/03 | cur98 |
| pwd | 1.10 1998/07/28 | cur98 |
| renice | 1.5 1997/10/19 | =1.3 |
| script | 1.6 1998/04/02 | cur98 |
| shlock | 1.3 1998/01/09 | cur98 |
| sleep | 1.15 1998/07/28 | cur98 |
| su | 1.26 1998/08/25 | cur98 |
| tee | 1.6 1997/10/20 | =1.3 |
| test | 1.19 1998/07/28 | cur98 |
| time | 1.9 1997/10/20 | =1.3 |
| uname | 1.9 1997/10/20 | =1.3 |
| users | 1.7 1998/02/03 | cur98 |
| w | 1.30 1998/07/06 | cur98 |
| whereis | 1.8 1997/10/20 | =1.3 |
| which | which.1 1.4 1997/10/20 (csh script) | =1.3 |
| who | 1.6 1997/10/20 | =1.3 |
| window | main.c 1.8 1998/02/03 | cur98 |
| xargs | 1.10 1998/04/14 | cur98 |
| yes | 1.5 1997/10/19 | =1.3 |

## system_cmds (mixed)

| Tool | Origin | Tag | Release / notes |
|---|---|---|---|
| ac | Demetriou / Gerraty 1994 | Apple $Id | NetBSD-era (inferred) |
| accton | 4.4BSD | 8.1 6/6/93 | Lite/Lite2 |
| arch | NeXT/Apple | - | - |
| at, atrun | Thomas Koenig / David Parsons at | Apple $Id | as in Net/FreeBSD (inferred) |
| chkpasswd | Apple | 1998 | - |
| chpass | 4.4BSD | chpass.h 8.4 4/2/94 | Lite/Lite2 |
| cron, crontab | Vixie cron | 1988-94 | Vixie cron 3.0 (inferred) |
| dmesg, fastboot, getty, kdump, ktrace, kgmon, makekey, nologin, pagesize, reboot, swapon, sync, update | 4.4BSD | 8.x 1993-94 | Lite/Lite2 |
| fbalert | Apple | 1997 | - |
| fbshow | NeXT | 1996 | - |
| halt | 4.3BSD-Reno | halt.c 5.10 4/3/91 | pre-4.4 |
| hostinfo, mach_init, mach_swapon, nvram | NeXT | 1989-96 | Mach |
| init | 4.4BSD + Apple | init.8 8.6 5/26/95 | Lite2, heavily Apple-modified |
| iostat | 4.4BSD | iostat.c 8.3 4/28/95 | Lite2 |
| kvm_mkdb | 4.4BSD | kvm_mkdb.c 8.3 5/4/95 | Lite2 |
| login | 4.4BSD + Apple | login.1 8.2 5/5/94 | Lite/Lite2 |
| mkfile | Apple | 1997 | - |
| passwd | Apple (NetInfo) | 1998 | - |
| pwd_mkdb | 4.4BSD | pwd_mkdb.c 8.5 4/20/94 | Lite/Lite2 |
| shutdown | 4.4BSD | shutdown.8 8.2 4/27/95 | Lite2 |
| sysctl | 4.4BSD | sysctl.c 8.5 5/9/95 | Lite2 |
| top | William LeFebvre top, NeXT/Apple machine module | patchlevel.h | top 3.5beta12 |
| vipw | 4.4BSD | pw_util.c 8.4 4/28/95 | Lite2 |
| vm_stat, zprint | NeXT / Apple | 1996 / 1997 | Mach |
| zdump, zic | tzcode via OpenBSD | zic.c 7.80, `$OpenBSD$` 1997/01 | OpenBSD ~2.1 |

## text_cmds (NetBSD-current ~Oct 1998, except sort)

| Tool | Tag | Release |
|---|---|---|
| banner | 1.3 1997/10/18 | =1.3 |
| cat | 1.18 1998/07/28 | cur98 |
| cksum | 1.10 1997/10/17 | =1.3 |
| cmp | 1.12 1998/01/12 | cur98 |
| col | 1.9 1997/10/18 | =1.3 |
| colrm | 1.5 1997/10/18 | =1.3 |
| column | 1.8 1998/07/28 | cur98 |
| comm | 1.11 1997/10/18 | =1.3 |
| cut | 1.12 1998/08/25 | cur98 |
| ed | main.c 1.9 1998/07/28 (Andrew Moore ed) | cur98 |
| expand | 1.6 1997/10/18 | =1.3 |
| fmt | 1.8 1998/02/12 | cur98 |
| fold | 1.8 1997/10/20 | =1.3 |
| head | 1.10 1998/01/31 | cur98 |
| join | 1.13 1998/08/25 | cur98 |
| lam | 1.3 1997/10/19 | =1.3 |
| look | 1.10 1998/02/20 | cur98 |
| mail | head.c 1.7 1997/10/19 | helper sources for fmt, not a tool |
| paste | 1.5 1998/02/03 | cur98 |
| pr | 1.6 1998/04/02 | cur98 |
| rev | 1.6 1997/10/19 | =1.3 |
| rs | 1.4 1997/10/19 | =1.3 |
| sed | main.c 1.10 1997/10/19 | =1.3 |
| sort | **GNU** sort (FSF 1988, 1991) | GNU textutils 1.x era (inferred) |
| split | 1.6 1997/10/19 | =1.3 |
| tail | 1.7 1998/08/25 | cur98 |
| tr | 1.6 1997/10/20 | =1.3 |
| ul | 1.6 1997/10/20 | =1.3 |
| unexpand | 1.6 1997/10/20 | =1.3 |
| uniq | 1.8 1997/10/20 | =1.3 |
| unvis | 1.7 1998/02/03 | cur98 |
| vis | 1.5 1997/10/20 | =1.3 |
| wc | 1.13 1997/10/20 | =1.3 |
