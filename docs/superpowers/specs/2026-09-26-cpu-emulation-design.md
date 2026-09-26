# Cross-architecture CPU emulation design (ppc on i386, i386 on ppc)

Date: 2026-09-26
Status: design; no code changed
Companion plan: `docs/superpowers/plans/2026-09-26-cpu-emulation.md`

## Problem

RhapsodiOS builds universal (`i386` + `ppc`) by default, but a lot of the
software a user will want to run is not universal: Rhapsody DR2 and Mac OS X
Server 1.x applications and tools that were shipped ppc-only, and OPENSTEP or
Rhapsody DR2/Intel binaries that were shipped i386-only. Today the kernel
refuses them:

- A fat file with no slice for the running CPU fails in `fatfile_getarch`
  with `LOAD_BADARCH` (`src/kernel-7/kern/mach_fat.c:137-165`), which `execve`
  turns into `EBADARCH`.
- A thin Mach-O for the other CPU reads as `MH_CIGAM` (the magic is
  byte-swapped, because the two CPUs are opposite-endian) and is rejected at
  `src/kernel-7/bsd/kern/kern_exec.c:303-305` with `EBADARCH`.

The goal is that such an executable runs anyway, transparently, the way a
`#!` script or a Rosetta binary does: the user or the Workspace Manager
execs it, and it runs under a CPU emulator.

## Goals

1. `execve` of a ppc-only executable on an i386 machine, and of an i386-only
   executable on a ppc machine, runs it under emulation with the same argv,
   environment, file descriptors, cwd, credentials (see set-id below), signals,
   exit status, and `fork`/`exec`/`wait` behaviour a native process has.
2. The emulated process uses the *foreign* slices of the installed universal
   system libraries (`/usr/lib/dyld`, `libSystem`, frameworks), which the
   universal build already installs. Nothing is duplicated or rebuilt.
3. The emulator is self-contained C that compiles with the in-tree compiler
   (`cc-1`, gcc 2.7.2.1) for the target, and with a modern compiler on a
   Linux, macOS or Windows host for unit tests.
4. Correctness before speed. An interpreter that runs ppc command-line tools at
   the speed of a 1999 PowerPC is the first target; a JIT is a later project.

## Non-goals (for this design)

- AltiVec, MMX, SSE, 16-bit or real-mode x86, x86 I/O instructions, ring 0.
- Emulating the kernel, drivers, or a whole machine. This is user-mode
  emulation of one process at a time.
- Debugging an emulated process with the native `gdb` (`ptrace` on the guest
  is refused). The emulator gets its own trace facility instead.
- GUI applications. AppKit and Foundation are not yet buildable in this tree
  (`src/Kits/*` are stubs under binary reconstruction), and the WindowServer
  protocol is not in the tree. Section 12 records what GUI support will need.
- Mixing architectures inside one process (loading a ppc bundle into an i386
  process). Everything in one process is one architecture.

## 1. Options considered

| Option | Verdict | Why |
|---|---|---|
| **A. User-space emulator process; the kernel only re-execs** (qemu-user / Rosetta 1 model) | **Chosen** | All the hard work is in one ordinary static binary that can be developed, tested and replaced without touching the kernel. The kernel change is ~60 lines. |
| B. In-kernel instruction emulation (trap on foreign code) | Rejected | The kernel would have to carry a second CPU's thread state, exception model, FPU, and the endianness bridge; every bug is a kernel panic; no host-side testing. |
| C. Library-boundary translation (native frameworks, thunks at the dylib boundary; Rosetta 2's shape) | Rejected | Every C and Objective-C call across the boundary would need argument and struct swapping; ObjC message dispatch, callbacks and shared data structures make this open-ended. |
| D. Port QEMU's user-mode emulation | Rejected | No Mach-O/Rhapsody target exists, the code base is GPL and C99/GNU C against a gcc 2.7.2.1 target compiler, and a TCG backend port plus a new OS layer is more work than a focused interpreter. Its *design* (identity-mapped guest memory, syscall translation) is the model used here. |
| E. Whole-system VM (run a ppc Rhapsody in QEMU on the i386 machine) | Different product | Does not make `./foo` work. |

Within A, an **interpreter with a pre-decoded instruction cache** is chosen
over a dynamic binary translator for the first implementation. Rationale: it is
portable, testable instruction by instruction, and a modern i386 host is
50-100x faster than the ppc machines these binaries were written for, so a
20-40x interpretive slowdown still gives a usable command line. The i386-on-ppc
direction on a real G3/G4 will be slow (386-class); that is stated up front and
is one reason to do ppc-on-i386 first.

## 2. Process model

```
 execve("ppc-only-tool")            kernel: fatfile_getarch -> LOAD_BADARCH
        |                                    (or MH_CIGAM thin header)
        v                                    find the foreign cputype
 kernel re-execs                             -> /usr/libexec/archemu/ppc
   /usr/libexec/archemu/ppc  ppc-only-tool  argv0 argv1 ...
        |
        v
 archemu (static, native i386, no dyld, no libSystem)
   - maps the guest Mach-O and the guest slice of /usr/lib/dyld
   - builds the guest's initial stack in guest byte order
   - runs the ppc interpreter from dyld's LC_UNIXTHREAD entry
   - guest `sc` -> BSD syscall or Mach trap bridge (swap, call, swap back)
   - native signals -> guest signal frames
   - guest thread_create/thread_set_state -> native threads running the
     interpreter
```

One emulated process is one native process. One guest thread is one native
thread. Guest memory is host memory at the same addresses (no address
translation). `fork` is the native `fork` (the whole emulator forks with the
guest). `execve` from the guest goes to the kernel, which routes the new image
through the arch handler again if it is foreign, or runs it natively if it is
native. Exit status, signals, process groups, controlling terminal, `wait4`
all behave natively because the native process *is* the guest process.

## 3. Kernel hook

`execve` (`src/kernel-7/bsd/kern/kern_exec.c`) already loops back on itself
for `#!` interpreters (the `indir` path at lines 306-346). The hook reuses that
shape:

1. Decide the foreign cputype:
   - fat: if `fatfile_getarch` returns `LOAD_BADARCH`, scan the (big-endian)
     `fat_arch` array for a cputype that has a handler;
   - thin `MH_CIGAM`: byte-swap `header->cputype`.
2. Look up the handler in a static table:
   `{ CPU_TYPE_POWERPC, "/usr/libexec/archemu/ppc" }`,
   `{ CPU_TYPE_I386,    "/usr/libexec/archemu/i386" }`.
   No sysctl or boot-arg in the first version (the path is fixed, like
   `init_program_name`). If the handler file does not exist, return the
   original `EBADARCH`, not `ENOENT`.
3. Re-run the lookup with the handler as the file and rebuild argv as
   `[handler, original-path, argv0, argv1, ...]`. Unlike `#!`, argv0 is kept:
   the guest must see its own argv exactly.
4. Only one redirect per `execve`; a handler that is itself foreign fails with
   `EBADARCH`.
5. **Set-id:** the redirect clears `VSUID`/`VSGID` from `origvattr`, so a
   set-id foreign binary runs with the caller's credentials. Honouring set-id
   through the emulator is possible later (the kernel applies `origvattr` of
   the first file, exactly what Rosetta relied on) but is a security decision
   that should be explicit.
6. `p_comm` keeps the original program's name so `ps`, `killall` and
   accounting show `foo`, not `ppc`.

No new proc flag. The emulator can be told apart by its argv when needed.

**Alternative without a kernel change:** make libc's `execve` a C wrapper
that retries through the handler on `EBADARCH`. It covers `execvp`, `system`,
`popen` and the shells, but not the raw syscall or anything statically linked,
and every caller would carry the policy. The kernel hook is the recommended
form; the libc wrapper is the fallback if a kernel change is unwanted.

The emulator also works with no kernel change at all:
`/usr/libexec/archemu/ppc ./foo args` is a valid invocation and is how the
first milestones are tested.

## 4. The emulator binary

- One project, `src/archemu-1/`, building **one** product per host CPU:
  on i386 the guest-ppc emulator, on ppc the guest-i386 emulator. `RC_ARCHS`
  selects the host; the product name is the *guest* architecture.
- **Static, freestanding.** `-static -nostdlib`, its own `_start`, raw
  syscall stubs, no `libSystem`, no `dyld`. Reason: the guest wants the same
  addresses the native libraries would take (`/usr/lib/dyld` is prebound at
  `0x41100000` on both CPUs, `libSystem` at `0x41300000`, see
  `src/cctools-2/dyld/Makefile:67` and `src/Libsystem-2/Makefile`), so the
  emulator must not load any native library.
- **Linked at `0xB0000000`** with a fixed 192 MB reservation
  `[0xB0000000, 0xBC000000)` for text, data, heap, per-thread native stacks and
  the decode cache. That sits below the stack region (`USRSTACK` is
  `0xC0000000` on both CPUs, `MAXSSIZ` 64 MB, so the stack can reach down to
  `0xBC000000`) and above every prebound library. The reservation is made with
  `vm_allocate` at a fixed address on startup so the kernel never hands those
  pages to the guest. On the ppc host `VM_MAX_ADDRESS` is `0xfffff000`, but the
  same address is used on both hosts so the layout has one description.
- Language: C89 syntax plus `long long` (needed for 64-bit and FP work; the
  target compiler supports it; the repo's kernel-only rule against it does not
  apply to userland). No `//`, declarations first, no `inline`, no VLAs.
  Host assembly only in `host/` (entry, syscall stubs, atomics, `bswap`).
- **Guest memory access:** direct loads and stores with a byte swap. Every
  guest/host pair in this project is cross-endian, so there is exactly one
  code path (always swap), never a same-endian fast path to keep correct.

## 5. Loading a guest image

The emulator reproduces what `execve` and `load_machfile` do for a native
image (`kern_exec.c:565-630`, `mach_loader.c`):

1. Open the path from argv[1]. Fat header: big-endian; pick the guest slice
   by cputype and best cpusubtype grade. Thin: byte-swap the header.
2. Map every `LC_SEGMENT` with `mmap(MAP_FIXED|MAP_PRIVATE)` from the file
   (`kern_mman.c` supports file-backed fixed private maps; `MAP_ANON` is
   `EINVAL` there, so zero-fill tails and `__PAGEZERO` use `vm_allocate` +
   `vm_protect`). Protections follow `initprot`.
3. `LC_LOAD_DYLINKER`: load the guest slice of `/usr/lib/dyld` the same way,
   sliding it if its address is taken (the kernel slides too,
   `load_dylinker`). The entry point is dyld's `LC_UNIXTHREAD`.
4. Initial stack, in guest byte order, at the top of the native stack the
   kernel gave the emulator (the strings are already there; only the pointer
   words are rebuilt): `[mach_header of the main image][argc][argv...][0]
   [envp...][0]`. This is the contract `dyld_start.s` reads for both CPUs
   (`src/cctools-2/dyld/dyld_start.s`: ppc reads `0(r1)` = mh, `4(r1)` =
   argc; i386 reads mh at the initial `%esp`).
5. Register state from `LC_UNIXTHREAD` (`srr0`/`eip` = entry; `r1`/`esp` =
   the stack pointer from step 4). Everything else zero.
6. The emulator switches to its own native stack inside the reservation and
   enters the interpreter loop.

The emulator itself is a static `MH_EXECUTE`, which the kernel loads with no
dylinker (`load_result.dynlinker` false, entry from `LC_UNIXTHREAD`).

## 6. Guest CPU cores

### 6.1 ppc (guest on i386 hosts)

- User-mode 32-bit PowerPC as used by gcc 2.7/2.95 output for the 603/604/
  750: Book I integer, branch, condition-register ops, rotate/shift, multiply/
  divide, load/store incl. update, byte-reversed, multiple and string forms,
  `lwarx`/`stwcx.` (implemented with a host atomic compare-and-swap),
  `sync`/`isync`/`eieio` (no-ops), `dcbz` (zero 32 bytes), `dcbf`/`icbi`
  (decode-cache invalidation; `dyld/cache_flush.s` uses exactly these after
  writing stubs), `mftb`/`mfspr` for TB and XER/LR/CTR, `sc`, `trap`/`tw`
  (SIGTRAP), and the double-precision FPU (`fadd`…`fmadd`, `fcmpu/o`,
  `frsp`, `fctiw[z]`, `mffs`/`mtfsf`, `fsel`).
- FPU on the x87: precision control set to 53 bits, rounding mode from
  FPSCR. Deviations, documented in the code: fused multiply-add is computed
  with two roundings; exponent range is the x87's (only affects values that
  would be subnormal/overflow in double after an intermediate). Non-trapping
  FPSCR exception bits are tracked; trapping FP exceptions are not supported.
- Decoding: primary opcode plus extended opcode into a per-page decode cache
  of `{handler, operands}` entries, filled lazily and dropped on `icbi`,
  on `vm_protect`/`vm_deallocate`/`munmap` of the page, and on guest stores
  to a page that holds cached code.

### 6.2 i386 (guest on ppc hosts)

- 32-bit protected mode, flat segments, ring 3 only: all 386 integer
  instructions, 486 `bswap`/`cmpxchg`/`xadd`, Pentium `cpuid`/`rdtsc`/
  `cmpxchg8b`. `cpuid` reports a Pentium without MMX. Segment prefixes are
  accepted and ignored (flat model); `%fs`/`%gs` are not used by Rhapsody
  userland.
- Three call gates: `lcall $0x2b,$0` (BSD syscalls and negative-numbered Mach
  traps, `src/Libc-1/sys.subproj/i386.subproj/SYS.h`), `lcall $0x7,$0`
  (machdep) and `lcall $0x3b,$0` (cthreads self get/set,
  `src/Libc-1/threads.subproj/i386.subproj/thread.c:100-112`). `int3` →
  SIGTRAP, `int $n` otherwise → SIGSEGV as the kernel does.
- **x87 as 80-bit software floating point.** gcc of this era keeps
  intermediates in extended precision and `long double` is 96 bits on i386;
  mapping x87 to `double` silently changes results of `printf`/`strtod`
  loops. So: a clean-room extended-precision softfloat (add, sub, mul, div,
  sqrt, compare, int/float conversions, `fprem`, `fscale`, `frndint`) and the
  transcendental group (`fsin`, `fcos`, `fptan`, `fpatan`, `f2xm1`, `fyl2x`)
  computed through double with a documented error bound. This is the largest
  single piece of the i386 core.
- Unaligned guest accesses are routine in x86 code; on the ppc host they
  are done as byte accesses to avoid the kernel's alignment trap handler.
- Self-modifying code has no flush instruction on x86; the decode cache is
  invalidated by the page-store check in 6.1.

### 6.3 Shared interpreter properties

- Precise faults: the interpreter records the guest PC before each guest
  memory access so a native `SIGSEGV`/`SIGBUS` in the interpreter can be
  reported at the right guest instruction.
- Asynchronous events (pending guest signals, thread abort) are checked at
  instruction boundaries via one flag per thread.
- Time: `mftb`, `rdtsc` and `kern_timestamp` are derived from
  `gettimeofday` scaled to a fixed nominal frequency.

## 7. BSD syscall bridge

Calling conventions to reproduce exactly:

| | ppc guest | i386 guest |
|---|---|---|
| Number | `r0` | `%eax`; number 0 is indirect `syscall(n, ...)` on both |
| Arguments | `r3`..`r10`, positional into `uu_arg[]` (`src/kernel-7/machdep/ppc/systemcalls.c:329-337`) | words on the stack above the return address, copied by `sy_narg` (`src/kernel-7/machdep/i386/trap.c:676-684`) |
| Return | `r3` (and `r4` as `rval[1]`, used by `pipe`); success returns to `sc+8`, error to `sc+4` where libc branches to `cerror` (`systemcalls.c:358`, `ppc.subproj/SYS.h`) | `%eax`/`%edx`; error sets CF (`trap.c:686-706`) |
| Mach traps | negative `r0` (`mach/syscall_sw.h`) | negative `%eax` via the same gate |

Errno values are the same kernel's on both sides, so no error mapping.

Argument and result classes (the handler table, `harness/syscall.c`, has one
entry per number in `sys/syscall.h`, 146 defined):

- **Scalars only** (`getpid`, `close`, `dup2`, `kill`, `setsid`, ...): pass
  through. 64-bit arguments (`lseek`, `truncate`, `ftruncate`, `mmap`
  offset) occupy two words in the kernel's `*_args` struct; the guest and host
  compilers may pad them differently, so the layouts are verified by a probe
  program (plan Task 2) rather than assumed.
- **Byte buffers** (`read`, `write`, `readlink`, path strings, `sockaddr`
  whose `sa_len`/`sa_family` are bytes and whose port and address fields are
  network order already): pass through.
- **Structs**: swapped field by field into a native temporary and back:
  `stat`/`fstat`/`lstat`, `gettimeofday`/`settimeofday`, `getrusage`, `wait4`
  (status and rusage), `select` (each `fd_mask` word), `sigaction`,
  `sigaltstack`, `getrlimit`/`setrlimit`, `readv`/`writev` (iovec array),
  `sendmsg`/`recvmsg` (msghdr, iovecs, cmsg headers), `getsockopt`/
  `setsockopt` (per option), `fcntl` `F_GETLK`/`F_SETLK` (`flock`),
  `getdirentries` (walk the records, swap `d_fileno` and `d_reclen`, and
  the `basep`), `getfsstat`/`statfs`, `mount` args, `sysctl` (the name array
  and the per-MIB result type), `adjtime`, `utimes`, `ktrace` off.
- **ioctl**: the request encodes size and direction, not the field widths, so
  a table covers the used set: termios (`TIOC[GS]ETA*`: four 32-bit words,
  `c_cc` bytes, two speeds), `TIOCGWINSZ` (four 16-bit), `TIOC[GS]PGRP`,
  `FION*`, `SIOC*` interface requests (name bytes plus sockaddr or int),
  `DKIOC*`. Unknown request: if the encoded size is 4 treat it as one int;
  otherwise pass through untouched and log it. Every unknown ioctl seen on a
  real workload gets added to the table.
- **Process control**: `fork`/`vfork` (native; the kernel's `vfork` is
  `fork1(DOVFORK)` with `P_PPWAIT`, a full Mach address-space copy, so the
  child emulator may keep interpreting), `execve` (argv/envp pointer arrays
  swapped into native vectors; the kernel hook decides what runs next),
  `exit`, `wait4`, `ptrace` (`EINVAL`), `sigreturn` (never reaches the kernel,
  see 9).
- **sysctl** specifics: `hw.machine`, `hw.model`, `hw.byteorder` report the
  guest architecture's values so `uname -m`, `arch` and `NXGetLocalArchInfo`
  see the guest CPU. `kern.proc` (`kinfo_proc`) is refused with `ENOTSUP`
  and logged in the first version.

## 8. Mach IPC bridge

This is the hard part and the one that shapes the schedule.

Facts from the tree:

- Messages are untyped MIG (NDR record plus descriptors, `mach/message.h`),
  generated by `migcom_untypd`. Generated server stubs copy `NDR_record` into
  replies but **never look at the request's `int_rep`**
  (`src/Commands/bootstrap_cmds/migcom_untypd.tproj/server.c`). So a
  big-endian request to a little-endian server is simply misread. The emulator
  must swap bodies in both directions; there is no receiver-side conversion
  to lean on.
- The kernel still accepts old typed messages (`MACH_MSGH_BITS_OLD_FORMAT`,
  `ipc/ipc_kmsg.c:643`), which are self-describing and can be swapped
  generically. No in-tree client uses them, but WindowServer-era clients might
  (section 12).
- Descriptors (`mach_msg_port_descriptor_t` and friends) mix 32-bit fields
  with C bitfields, so they must be re-packed field by field, not byte-swapped.
- Trailers exist (`mach_msg_trailer_t`, format 0, two words).

Design:

1. **Table-driven body swapping keyed by `msgh_id`.** A generator reads the
   `.defs` in the tree (`mach.defs` 117 routines, `mach_host.defs` 42,
   `mach_port.defs` 19, `mach_debug.defs` 27, `notify.defs`, `exc.defs`,
   `memory_object*.defs`, `bootstrap.defs`, `netname.defs`, `lookup.defs`,
   `dyld_debug.defs`, `dyld_event.defs`, the driverkit and kernserv ones
   later) and emits, per routine, the request and reply wire layout as a
   list of `{offset, element size, count or count-field}` steps. The element
   vocabulary is small in these interfaces: 32-bit words (ints, ports,
   addresses), 16-bit, bytes/`c_string`, 64-bit, and count-prefixed inline
   arrays of those. Reply id is request id + 100, and MIG subsystem bases do
   not overlap, so one table maps every id in both directions.
2. **Unknown id:** header and descriptors are still swapped (they are
   protocol-independent); the body is passed through and the id is logged
   once. The debug switch makes it fatal so unknown protocols surface in
   testing instead of silently misbehaving.
3. **Semantic interceptions** (not just swapping), in `harness/ipc_kern.c`:
   - `host_info(HOST_BASIC_INFO)` reply: `cpu_type`/`cpu_subtype` rewritten
     to the guest's. This is what makes dyld (`dyld_init.c:170`,
     `images.c:847`) and `NXGetLocalArchInfo` pick guest slices.
   - `thread_set_state`/`thread_get_state` with a foreign flavor
     (`PPC_THREAD_STATE`, `PPC_FLOAT_STATE`, `i386_THREAD_STATE`,
     `i386_THREAD_FPSTATE`, `i386_THREAD_CTHREADSTATE`): see 10.
   - `task_set_exception_ports` and friends: accepted and recorded; see 9.
   - `vm_region`/`vm_read`/`vm_write`: pass through with swapping; addresses
     are plain words because guest and host share the address space.
4. **Out-of-line data** is bytes owned by the protocol, not the transport:
   `vm_read` results are raw memory (no swap); `lookupd` payloads are XDR
   (network order on both sides, no swap). The table marks the rare OOL
   payloads that are typed.
5. **Old typed format:** a generic walker over `mach_msg_type_t` descriptors
   (re-packing the bitfield word by field) is implemented only if section 12's
   survey shows a needed client uses it.

## 9. Signals and faults

The emulator installs its own handlers for every signal via the raw
`sigaction` syscall; the kernel calls the handler directly with `(sig, code,
scp)` on both CPUs (`machdep/{i386,ppc}/unix_signal.c`). Native handlers run
on a native alternate stack inside the emulator's reservation, never on guest
stacks.

- **Synchronous faults** while interpreting (native `SIGSEGV`/`SIGBUS` from a
  guest load/store, guest illegal opcode, integer divide by zero, `trap`/
  `int3`) become guest signals using the kernel's own exception-to-signal
  mapping (`src/kernel-7/uxkern/ux_exception.c:248-260`), delivered at the
  faulting guest instruction.
- **Asynchronous signals** are queued and delivered at the next instruction
  boundary; a native blocking syscall that returns `EINTR` surfaces as the
  guest's `EINTR`/restart exactly as the kernel would do for a native process.
- **Guest frames** are built exactly as the guest kernel would:
  ppc — `sigcontext` then `sigregs { ppc_saved_state, ppc_float_state }` below
  the red zone, `r3`=sig, `r4`=code, `r5`=&context, `srr0`=catcher, `r1`
  with parameter and linkage areas (`machdep/ppc/unix_signal.c:60-140`);
  i386 — `sigframe { sig, code, scp }` then `sigcontext` pushed on the guest
  stack, `eip`=catcher (`machdep/i386/unix_signal.c:61-150`). The catcher is
  whatever the guest passed to `sigaction`; for libc that is `_sigtramp`.
  `SA_ONSTACK` and the guest's `sigaltstack` are honoured for guest frames.
- **Guest `sigreturn`** never reaches the kernel: the emulator restores the
  guest registers from the guest-order frame and re-applies `sc_mask` with a
  native `sigprocmask`.
- **Mach exception ports:** the first version records them but keeps
  delivering signals; delivering `exception_raise` messages to a guest
  handler thread (what `gdb` and `exc_catcher.c` want) is a later task.

## 10. Threads

cthreads creates threads with `thread_create` on the task port and then
`thread_set_state` with the CPU's flavor (`src/Libc-1/threads.subproj/ppc.subproj/thread.c:75`,
`i386.subproj/thread.c:89`). The bridge:

1. `thread_create` passes through; the emulator records the new (suspended)
   native thread port.
2. `thread_set_state(port, PPC_THREAD_STATE | i386_THREAD_STATE, ...)` on a
   recorded port stores the foreign register file as that thread's initial
   guest context, allocates a native stack for it in the reservation, and sets
   the *native* state to enter the interpreter with that context.
   `thread_resume` passes through and the new native thread starts
   interpreting.
3. `thread_get_state` with a foreign flavor returns the emulated registers
   (meaningful only while suspended, same as native).
4. `mach_thread_self`, `thread_suspend`, `thread_abort`, `thread_terminate`,
   `thread_switch`, `swtch`, `swtch_pri` pass through: guest threads are
   native threads.
5. Per-CPU "self" mechanisms: ppc keeps `cthread self` in `r13`
   (`ppc.subproj/lock.s:116-127`), which is just a guest register; i386 keeps
   it in the PCB via call gate `0x3b` and `i386_THREAD_CTHREADSTATE`, which
   the i386 core emulates as a per-guest-thread word.
6. Thread-local emulator state is found from the native stack pointer: native
   thread stacks are fixed-size slots in the reservation, so the context is
   `slots[(sp - base) / SLOT_SIZE]`. No native TLS is needed.
7. Locks inside the emulator are spin locks on host atomics; the decode cache
   is per thread in the first version so it needs no locking.

## 11. Testing

Two tiers, both automated.

**Host tier** (Linux/macOS/Windows, CMake, `src/archemu-1/tests/`), runs on
every change:

- Instruction known-answer tests: tables of `{initial registers, instruction
  words, expected registers and flags}` per instruction. Hand-written cases
  from the PowerPC and IA-32 manuals plus **vectors generated on real
  hardware**: a small generator program built with the in-tree toolchain runs
  natively on the ppc guest and on the i386 QEMU image and prints vectors that
  are checked in as data. Same idea as the pinned Xoodyak vectors: the vector
  is the truth, never the implementation.
- Loader tests against fixture Mach-O files (fat and thin slices of small
  in-tree binaries), including the initial stack bytes compared to a dump
  captured by a native probe program.
- Swap-table tests: generated tables for a handful of routines compared with
  hand-computed layouts, and swap-twice-is-identity property tests.
- Layout tests: a probe program compiled for both CPUs prints `sizeof`/
  `offsetof` for every struct that crosses the syscall or IPC boundary; the
  outputs are checked in and the emulator's tables are asserted against them.

**Guest tier** (the i386 QEMU image and the ppc guest, via the existing
`vm/` scripts), runs per milestone:

- A `ppc`-only (and later `i386`-only) test-program set installed under
  `/usr/local/libexec/archemu-tests/`: `hello`, argv/env echo, `stat`,
  `fork`/`exec`/`wait`, signals and `sigaltstack`, cthreads, a
  `bootstrap_look_up` round trip, `printf` of doubles, `getdirentries`, a
  tty ioctl. Each prints a known transcript; the harness diffs it.
- Then real binaries: the ppc slices of the built `Commands` (`ls`, `cat`,
  `sh`, `awk`, `perl`), run against the same inputs as their native slices.

## 12. GUI applications (recorded, not scheduled)

A ppc-only application needs, beyond this design: native AppKit/Foundation
(under reconstruction), the WindowServer and `pbs`, and the Display PostScript
client protocol. What is known: the DPS client side is only a stub in the tree
(`src/Kits/AppKit/NSDPSServerContext.m`), the WindowServer is not in the
tree, and its message format (untyped MIG vs. old typed vs. a byte stream over
a socket or shared memory) has not been surveyed. The survey is the first GUI
task; if the protocol is self-describing typed messages, section 8 item 5
covers it; if it is a private untyped protocol, its layouts must be recovered
from the binaries. Shared-memory event queues (`EventShmemLock`) will need
their layouts swapped too. None of this changes the process model above.

## 13. Risks and open questions

| Risk | Mitigation |
|---|---|
| Untyped MIG bodies: an unknown or mis-described layout corrupts a request silently | Generated tables from the `.defs`, fail-loud unknown-id mode in tests, guest-tier round-trip tests per subsystem. |
| Struct layout differences between the two compilers (64-bit members, bitfields) | Probe-generated layout files checked in; no layout is assumed. |
| x87 semantics on ppc hosts | 80-bit softfloat from the start; speed is second. |
| Performance of the interpreter is below usable for a workload | Measure at M4 with the pre-decode cache and block chaining; a JIT is a separate spec, not a hidden assumption. |
| The emulator's fixed region collides with a guest `vm_allocate` at a fixed address | The region is allocated first; the guest sees `KERN_NO_SPACE`, same as a native collision. |
| Set-id foreign binaries | Run unprivileged in the first version; explicit decision to change. |
| `map_fd`/`mmap` corner cases for guest mappings of files (`MAP_ANON` unsupported) | Loader uses `vm_allocate` for anonymous memory; fixture tests on the guest. |

Decisions that need the maintainer's confirmation before Task 1 (also listed
at the top of the plan):

1. Kernel hook (recommended) versus libc-only retry.
2. Order: ppc-on-i386 first (recommended), i386-on-ppc second.
3. Set-id foreign binaries run unprivileged (recommended).
4. Names: project `archemu-1`, products `/usr/libexec/archemu/{ppc,i386}`.
5. Interpreter first; JIT as a separate later spec.
6. Host tests built with CMake (matches the maintainer's tooling; the rest
   of the tree's host tests use plain Makefiles).
