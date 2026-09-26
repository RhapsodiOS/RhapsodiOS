# Cross-architecture CPU emulation — Implementation Plan

Date: 2026-09-26
Spec: `docs/superpowers/specs/2026-09-26-cpu-emulation-design.md`

**Goal:** A ppc-only executable runs on an i386 RhapsodiOS machine, and an
i386-only executable on a ppc machine, through a user-mode emulator that the
kernel execs transparently when a binary has no native slice.

**Architecture:** A static, freestanding emulator (`/usr/libexec/archemu/<guest>`)
made of a shared harness (Mach-O loader, memory, BSD syscall bridge, Mach IPC
bridge, signals, threads) plus one guest CPU core (`ppc/` or `i386/`) and its
ABI module. A ~60 line change in `execve` re-routes foreign images to it.
Everything guest-visible is byte-swapped at the syscall and IPC boundary,
because every guest/host pair here is cross-endian.

**Tech stack:** C89 + `long long`, host assembly only in `host/`; target build
with the in-tree `cc` (gcc 2.7.2.1) via a plain Makefile driven by `rbuild`;
host unit tests with a plain Makefile on Linux/macOS/Windows; guest tests
through the existing `vm/` QEMU and SSH loop.

## Decisions (confirmed 2026-09-26)

1. Kernel hook in `execve`; the libc `execve` retry wrapper is not built.
2. ppc-on-i386 first (Phases 1-5), i386-on-ppc second (Phase 6).
3. Set-id foreign binaries run with the caller's credentials.
4. Names: `src/archemu-1`, `/usr/libexec/archemu/{ppc,i386}`.
5. Interpreter with a decode cache first; any JIT is a separate later spec.
6. Plain Makefiles for the host tests, following
   `src/drivers-i386/ide/drvAHCI/tests/Makefile`.

## Ground rules

- Every task is one commit, prefix `archemu: ` (or `kernel: ` for
  `src/kernel-7`, `docs: ` for documentation). One to two lines, no metadata.
- C89 syntax; `long long` allowed; no `//`, no mixed declarations, no
  `inline`, no VLAs. Host assembly stays in `src/archemu-1/host/`.
- Clean room: instruction semantics come from the PowerPC Programming
  Environments Manual and the Intel SDM; no code from QEMU, Rosetta or any
  other emulator is copied or consulted line by line.
- Host tests run with `-Wall -Werror` (`-std=c89 -Wno-long-long` on modern
  compilers); the same sources must compile with the in-tree `cc`. Check the
  target compile on the guest at least once per phase.
- Guest-tier runs use a throwaway copy of the disk image, never the shared
  golden one (`vm/graft-kernel.py`, `-snapshot`).
- The emulator must always be runnable by hand as
  `/usr/libexec/archemu/ppc prog args...`; the kernel hook is convenience,
  not a dependency.
- Tables (syscall layouts, MIG swap tables) are generated or probe-verified,
  never hand-assumed. A layout without a checked-in probe result is a bug.

## File structure

```
src/archemu-1/
  Makefile, Makefile.preamble, apk/pkginfo   rbuild project; builds one guest per RC_ARCHS
  README.md                                   how to run, trace, and add a syscall/ioctl/MIG table entry
  include/archemu/*.h                         shared interfaces
  host/
    host_i386.s, host_ppc.s                   _start, raw syscall stubs, atomics, byte swap, signal entry
    host_syscall.h                            native syscall wrappers (no libc)
  harness/
    main.c                                    argv contract, reservation, dispatch to the core
    reserve.c                                 the 0xB0000000 region, native stacks, heap
    macho.c                                   fat/thin parsing, segment mapping, dyld load, initial stack
    guestmem.h                                swapped load/store helpers
    syscall.c, syscall_tab.c                  BSD syscall dispatcher and per-number handlers
    ioctl.c                                   ioctl swap table
    sysctl.c                                  sysctl MIB table and guest-arch overrides
    ipc.c                                     mach_msg bridge: header, descriptors, trailer, body tables
    ipc_kern.c                                semantic interceptions (host_info, thread state, exception ports)
    signal.c                                  native handlers, guest frame builders, sigreturn
    thread.c                                  guest thread bridge, per-thread context lookup
    log.c                                     trace facility (ARCHEMU_TRACE=syscall,ipc,signal,unknown-fatal)
  ppc/
    ppc_decode.c, ppc_exec.c, ppc_fpu.c       interpreter
    ppc_abi.c                                 syscall convention, signal frames, thread-state flavors
  i386/
    i386_decode.c, i386_exec.c, i386_x87.c, softfloat80.c
    i386_abi.c
  tables/
    mig_swap.c (generated), syscall_layout_{i386,ppc}.h (generated from probes)
  tools/
    migswap.py                                .defs -> swap table generator
    layoutprobe.c                             prints sizeof/offsetof of boundary structs
    vecgen_ppc.c, vecgen_i386.c               native instruction vector generators
  tests/
    Makefile, host unit tests, vectors/*.txt, layouts/{i386,ppc}.txt
    guest/                                    guest-tier test programs and expected transcripts
```

## Phase 1 — Foundations (host-testable, no guest yet)

### Task 1: Project skeleton and the Makefile that builds one guest per host

Files: `src/archemu-1/Makefile`, `Makefile.preamble`, `apk/pkginfo`,
`README.md`, `host/host_i386.s`, `host/host_ppc.s`, `host/host_syscall.h`,
`harness/main.c`, `tests/Makefile`.

- [ ] Makefile modelled on `src/rbuild-1/Makefile`: for `RC_ARCHS` containing
      `i386` build `archemu-ppc` (guest ppc), for `ppc` build `archemu-i386`;
      link `-static -nostdlib -seg1addr 0xB0000000` with `host/host_<cpu>.s`
      providing `start`; install as `/usr/libexec/archemu/<guest>`.
- [ ] `host_*.s`: `start` saves the kernel stack pointer, calls
      `archemu_main(argc, argv, envp, kernel_sp)`, raw syscall stubs
      (`lcall $0x2b,$0` / `sc` with the negative-number Mach trap form), `bswap`
      helpers, atomic compare-and-swap.
- [ ] `main.c` for now: print its argv with the raw `write`, exit 0.
- [ ] `tests/Makefile` (`CC = cc`, `-Wall -Werror`, one target per test,
      `check` runs them all) building the host-portable harness sources
      (none yet beyond `log.c` stubs) with a smoke test.
- Verify: on the i386 QEMU image, `rbuild buildpackage` of `archemu-1`
  produces `/usr/libexec/archemu/ppc`; `otool -hv` shows no
  `LC_LOAD_DYLINKER`, `__TEXT` at `0xB0000000`; running it prints its argv.

### Task 2: Layout probe and checked-in layouts

Files: `tools/layoutprobe.c`, `tests/layouts/i386.txt`, `tests/layouts/ppc.txt`,
`tests/layout_test.c`.

- [ ] `layoutprobe.c` prints `sizeof` and every `offsetof` for: every
      `struct *_args` with a 64-bit member (`lseek`, `truncate`, `ftruncate`,
      `mmap`), `stat`, `timeval`, `timespec`, `rusage`, `rlimit`, `sigaction`,
      `sigaltstack`, `sigcontext` (both CPUs), `sigregs`, `ppc_saved_state`,
      `ppc_float_state`, `i386_thread_state_t`, `i386_thread_fpstate_t`,
      `iovec`, `msghdr`, `cmsghdr`, `flock`, `dirent`, `statfs`, `termios`,
      `winsize`, `ifreq`, `mach_msg_header_t`, all four descriptor structs,
      `mach_msg_trailer_t`, `NDR_record_t`, `host_basic_info`, `task_basic_info`,
      `thread_basic_info`, `vm_region_basic_info`.
- [ ] Build it with `cc -arch i386` and `cc -arch ppc` on the guests, run
      each natively, check the outputs in.
- [ ] `layout_test.c` parses both files and asserts the constants the
      harness will use (`syscall_layout_*.h`) match. Generate those headers
      from the probe output with a tiny script rather than by hand.
- Verify: host test passes; the two files differ only where the design
  expects (record any surprise in the spec's risk table).

### Task 3: Mach-O loader on the host

Files: `harness/macho.c`, `include/archemu/macho.h`, `tests/macho_test.c`,
`tests/fixtures/` (fat and thin slices of `/bin/echo` and `/usr/lib/dyld`
copied from a built tree, small).

- [ ] Parse fat headers (big-endian), pick a slice by cputype and subtype
      grade (reuse the grading order from `mach_fat.c`); parse a thin,
      byte-swapped `mach_header`; walk `LC_SEGMENT`, `LC_UNIXTHREAD`,
      `LC_LOAD_DYLINKER`.
- [ ] Mapping is done through a small `mapper` interface (`map_file_fixed`,
      `alloc_fixed`, `protect`) so the host test can use a fake that records
      calls, and the target uses `mmap`/`vm_allocate`/`vm_protect`.
- [ ] Initial-stack builder writes `[mh][argc][argv...][0][envp...][0]` in
      guest byte order into a caller-supplied buffer; the `ppc` and `i386`
      variants differ only in the initial register file they return.
- Verify: `macho_test` checks segment addresses, protections, slide handling
  when the dyld address is taken, entry point, and byte-exact stack contents
  against a dump produced by a native probe (add `tools/stackprobe.c`, run
  on the guests, check the dumps in).

### Task 4: Trace facility and the unknown-fatal switch

Files: `harness/log.c`, `include/archemu/log.h`.

- [ ] `ARCHEMU_TRACE` environment variable with comma-separated classes
      (`syscall`, `ipc`, `signal`, `thread`, `unknown`) and `fatal-unknown`;
      writes to fd 2 with the raw `write`; number formatting without libc.
- Verify: host unit test; the switch is honoured by every later task.

## Phase 2 — ppc core (host-testable)

### Task 5: ppc decoder and integer/branch execution

Files: `ppc/ppc_decode.c`, `ppc/ppc_exec.c`, `include/archemu/ppc.h`,
`tests/ppc_kat_test.c`, `tests/vectors/ppc_int.txt`.

- [ ] Register file, CR/XER semantics, decode into `{handler, operands}`,
      per-page decode cache with invalidation API.
- [ ] Integer, logical, rotate/shift, multiply/divide (incl. `mulhw[u]`,
      `divw[u]` overflow cases), compare, branch (all `bc` forms, `bclr`,
      `bcctr`, CTR decrement), CR logical ops, `mfcr`/`mtcrf`, `mfspr`/
      `mtspr` for XER/LR/CTR, loads/stores incl. update, indexed, byte-reversed,
      `lmw`/`stmw`, `lswi`/`stswi`, `lwarx`/`stwcx.`, `sync`/`isync`/`eieio`,
      `dcbz`, `dcbf`/`icbi` (cache invalidation hook), `tw`/`twi`, `sc` (stops
      the loop and reports to the caller), `mftb`.
- [ ] Hand-written vectors from the manual for every mnemonic.
- Verify: KAT test passes; all vectors from Task 6 also pass once generated.

### Task 6: Native ppc vector generator

Files: `tools/vecgen_ppc.c`, `tests/vectors/ppc_native.txt`.

- [ ] A table of instruction words and input register sets; the program
      executes each on real hardware (self-modifying a scratch page, with
      `icbi`) and prints the outputs. Runs on the ppc guest.
- [ ] Check the output in; the host KAT test reads it.
- Verify: the ppc core matches every native vector.

### Task 7: ppc FPU

Files: `ppc/ppc_fpu.c`, `tests/vectors/ppc_fp.txt` (add FP cases to `vecgen_ppc`).

- [ ] Load/store single/double, `fmr`, `fneg`, `fabs`, `fnabs`, `fadd[s]`,
      `fsub[s]`, `fmul[s]`, `fdiv[s]`, `fmadd`/`fmsub`/`fnmadd`/`fnmsub`
      (`[s]`), `frsp`, `fctiw`, `fctiwz`, `fcmpu`, `fcmpo`, `fsel`, `mffs`,
      `mtfsf`, `mtfsfi`, `mtfsb0/1`, `mcrfs`; FPSCR rounding mode and
      non-trapping status bits (FI, FR, FX, VX*, OX, UX, ZX, XX).
- [ ] Host implementation in `double` with the rounding mode applied via the
      host FP environment; the deviations (two-rounding FMA, exponent range)
      are asserted in a test so they are known, not accidental.
- Verify: native vectors for the FP group, including NaN propagation,
  `fctiwz` saturation, and denormals.

## Phase 3 — Running a ppc process on i386 (guest tier begins)

### Task 8: Kernel exec hook

Files: `src/kernel-7/bsd/kern/kern_exec.c`, `src/kernel-7/kern/mach_fat.c`.

- [ ] `mach_fat.c`: `fatfile_getarch_foreign(header, cputype_out)` returns the
      first slice cputype that is not the running CPU's.
- [ ] `kern_exec.c`: static handler table by cputype; on `LOAD_BADARCH` from
      the fat path or on `MH_CIGAM` (swap `cputype`), and when no redirect has
      happened yet, set the handler as the file, rebuild argv as
      `[handler, fname, argv0, argv1...]`, clear `VSUID`/`VSGID`, `goto again`.
      Missing handler → the original `EBADARCH`. Keep `p_comm` as the
      original name.
- [ ] Host-side: none possible; keep the change small enough to read in one
      screen.
- Verify: on a throwaway i386 image with `/usr/libexec/archemu/ppc` being the
  Task 1 argv-printer, `exec` of a ppc-only `hello` prints
  `/usr/libexec/archemu/ppc hello hello`; a thin ppc binary does the same; a
  set-id ppc binary runs as the caller; a native binary is unaffected;
  removing the handler restores `EBADARCH`. Reboot the image.

### Task 9: Reservation, guest memory and the static-binary milestone

Files: `harness/reserve.c`, `harness/guestmem.h`, `harness/main.c`,
`harness/syscall.c` (only `exit`, `write`), `ppc/ppc_abi.c` (syscall
convention only), `tests/guest/hello_static.c`.

- [ ] `reserve.c`: `vm_allocate` the 192 MB region at `0xB0000000`, carve the
      native main stack, switch stacks, allocate the decode cache.
- [ ] `ppc_abi.c`: on `sc`, read `r0`/`r3..r10`, return `r3`/`r4`, and set the
      `+4`/`+8` return PC for error/success.
- [ ] Guest test program built `-arch ppc -static`; the harness loads it
      (no dyld), runs it, and its `write(1, ...)` and `exit(3)` reach the
      kernel.
- Verify: `/usr/libexec/archemu/ppc hello_static` prints and exits 3 on the
  i386 image, with and without the kernel hook.

### Task 10: Mach traps and the kernel MIG bridge

Files: `tools/migswap.py`, `tables/mig_swap.c`, `harness/ipc.c`,
`harness/ipc_kern.c`, `tests/migswap_test.py`, `tests/ipc_test.c`.

- [ ] `migswap.py` parses `.defs` (subsystem base, routine order, argument
      types incl. `array[] of`, `c_string`, `inout`, `out`, port dispositions,
      `mach_msg_type_number_t` counts) for `mach.defs`, `mach_host.defs`,
      `mach_port.defs`, `mach_debug.defs`, `notify.defs`, `exc.defs`,
      `memory_object.defs`, `memory_object_default.defs`, `bootstrap.defs`,
      `netname.defs`, `lookup.defs`, `dyld_debug.defs`, `dyld_event.defs`;
      emits request and reply step lists keyed by `msgh_id`.
- [ ] `ipc.c`: swap header, `mach_msg_body_t`, each descriptor (repacked by
      field), trailer; apply the body steps; copy in/out through a native
      buffer; `mach_msg_trap` argument handling (send, receive, both,
      timeouts, `MACH_RCV_LARGE`); the old traps `mach_reply_port`,
      `mach_task_self`, `mach_thread_self`, `mach_host_self`, `task_self`,
      `thread_self`, `host_self`, `map_fd`, `kern_timestamp`, `swtch`,
      `swtch_pri`, `thread_switch`, `_lookupd_port*`, `init_process` (refuse),
      `mach_swapon` (refuse), `msg_*_trap` (refuse until a client needs them).
- [ ] `ipc_kern.c`: `host_info(HOST_BASIC_INFO)` guest cputype/subtype
      rewrite.
- [ ] Unknown id: header/descriptors swapped, body untouched, logged once;
      fatal under `fatal-unknown`.
- Verify: `migswap_test.py` compares generated layouts for `vm_allocate`,
  `host_info`, `thread_set_state`, `bootstrap_look_up`, `_lookup_all` with
  hand-computed ones; `ipc_test` round-trips synthetic messages; on the guest
  a ppc test program that calls `vm_allocate`, `host_info` and
  `bootstrap_look_up("NetMessage")` prints expected results.

### Task 11: Dynamic milestone — dyld and libSystem

Files: `harness/macho.c` (dyld load path enabled), `harness/syscall.c`
(`open`, `close`, `read`, `fstat`, `lseek`, `mmap`, `getpid`, `getuid`,
`obreak`, `sigprocmask`, `sigaction` recording, `ioctl` TIOCGETA for `isatty`),
`harness/sysctl.c` (`hw.machine`, `hw.byteorder`, `hw.pagesize`, `kern.osrelease`).

- [ ] Everything dyld and `libSystem` initialisation touches, discovered by
      running with `ARCHEMU_TRACE=syscall,ipc,fatal-unknown` and adding
      handlers until a dynamically linked ppc `hello` (`printf`) works.
- Verify: `hello` with `printf("%d %s %f")` prints correctly; `uname -m`
  (ppc slice) prints the ppc value; `arch` prints `ppc`.

## Phase 4 — A complete ppc process

### Task 12: BSD syscall table, structs and ioctls

Files: `harness/syscall_tab.c`, `harness/ioctl.c`, `tests/syscall_swap_test.c`,
`tests/guest/{stat,dirent,select,rlimit,socket,tty}.c`.

- [ ] Every number in `sys/syscall.h` has an entry: pass-through, struct
      swap, or refuse-with-log. Struct swaps use the Task 2 layouts.
- [ ] ioctl table for termios, winsize, pgrp, `FION*`, `SIOC*`, `DKIOC*`;
      unknown with size 4 → int; otherwise pass through and log.
- Verify: host tests for each swapper (swap twice = identity, offsets from
  the layout files); guest transcripts for the test programs match native.

### Task 13: Signals

Files: `harness/signal.c`, `ppc/ppc_abi.c` (frame builder, `sigreturn`),
`tests/guest/{signals,altstack,fault}.c`, `tests/sigframe_test.c`.

- [ ] Native handlers on a native alternate stack; guest `sigaction`
      bookkeeping; pending-signal flag checked by the interpreter; frame
      builder byte-exact to `machdep/ppc/unix_signal.c`; `sigreturn`;
      `sigaltstack`; fault mapping per `ux_exception.c`.
- Verify: host test compares a built frame to a dump captured on the ppc
  guest (`tools/sigframeprobe.c`); guest tests: `SIGALRM` handler runs,
  `SIGSEGV` on a null deref is catchable, `longjmp` out of a handler,
  `SIGCHLD`, `SIGINT` from the tty, `sigaltstack` frames land on the alt stack.

### Task 14: fork, exec, wait, and the shells

Files: `harness/syscall_tab.c` (`fork`, `vfork`, `execve`, `wait4`, `exit`,
`kill`, process groups, `setsid`, `dup*`, `pipe`), `tests/guest/spawn.c`.

- [ ] `execve` swaps argv/envp vectors; `vfork` is native (`P_PPWAIT` copy
      semantics verified on the guest before relying on it; fall back to
      `fork` if a guest write is visible in the parent).
- Verify: the ppc slice of `/bin/sh` runs a script that pipes, backgrounds,
  traps signals and execs both ppc and i386 programs; exit codes match the
  native run.

### Task 15: Threads

Files: `harness/thread.c`, `harness/ipc_kern.c` (thread-state flavors),
`tests/guest/threads.c`.

- [ ] `thread_create` recording, foreign-flavor `thread_set_state`/
      `thread_get_state`, native stack slots, context-from-`sp` lookup,
      per-thread decode cache, spin locks.
- Verify: a cthreads program with four threads and a mutex prints in the
  expected order; `thread_suspend`/`resume` from another thread works;
  `exit` from a non-main thread ends the process.

### Task 16: Real workloads and the trace-driven backlog

- [ ] Run the ppc slices of `ls -lR /usr`, `cat`, `grep`, `awk`, `sed`,
      `make`, `perl -e`, `tar`, `gzip` under the emulator with
      `ARCHEMU_TRACE=unknown`; fix every logged unknown syscall, ioctl, sysctl
      MIB and MIG id. Each fix is its own commit with a guest test.
- Verify: outputs byte-identical to the native i386 slices for the same
  inputs.

## Phase 5 — Speed and polish

### Task 17: Measurement and the decode cache

- [ ] `tests/guest/bench/` with three loops (integer, memory, FP) and one
      real workload (`gzip` of a fixed file). Record native i386 time, native
      ppc time on the ppc guest, and emulated time; put the table in
      `README.md`.
- [ ] Block chaining inside the decode cache (a decoded block knows its
      successor); measure again.
- Verify: the table is in the README; no correctness regression in the KATs.

### Task 18: Exception ports (optional, for gdb on ppc binaries later)

- [ ] `task_set_exception_ports`/`thread_set_exception_ports` honoured:
      guest faults are sent as `exception_raise` to the registered port with
      guest thread state available via `thread_get_state`.
- Verify: `exc_catcher`-style guest program receives its own fault.

## Phase 6 — i386 guests on ppc hosts

### Task 19: i386 decoder and integer execution

Files: `i386/i386_decode.c`, `i386/i386_exec.c`, `tests/vectors/i386_int.txt`,
`tools/vecgen_i386.c`.

- [ ] ModRM/SIB decoding, prefixes, all 386 integer forms, 486 and Pentium
      additions, flags semantics (lazy flag evaluation is allowed but must be
      exact), `cpuid` model, `rdtsc`, the three call gates, `int3`.
- [ ] Vector generator runs natively on the i386 QEMU image; outputs checked
      in.
- Verify: KATs pass against native vectors, especially flag results of
  `add`/`sub`/`adc`/`sbb`/`imul`/`shl`/`shr`/`sar`/`shld`/`shrd`/`bt*`.

### Task 20: Extended-precision softfloat and the x87

Files: `i386/softfloat80.c`, `i386/i386_x87.c`, `tests/vectors/i386_x87.txt`.

- [ ] 80-bit add/sub/mul/div/sqrt/compare/round/convert with all four
      rounding modes and precision control; the x87 register stack, tag word,
      status word (C0-C3), `fprem`/`fprem1`, `fscale`, `frndint`, `fxch`,
      `fld`/`fst` for all widths, `fist*`, `fbld`/`fbstp`, `fldcw`/`fnstcw`,
      `fnstsw`, `fnstenv`/`fldenv`, `fnsave`/`frstor`; transcendentals via
      double with an asserted error bound.
- Verify: native x87 vectors (generated on the i386 image) match bit for
  bit for the arithmetic group; transcendental results within the bound.

### Task 21: i386 ABI module and the i386-on-ppc milestone

Files: `i386/i386_abi.c` (stack-argument syscalls, CF error return,
`sigframe`/`sigcontext` builder per `machdep/i386/unix_signal.c`,
`i386_THREAD_STATE`/`FPSTATE`/`CTHREADSTATE`), `host/host_ppc.s` completed.

- [ ] Rebuild the guest test set `-arch i386` and run every Phase 3-4 guest
      test on the ppc guest.
- Verify: the same transcripts as Phase 4, produced on the ppc guest.

## Phase 7 — Documentation and packaging

### Task 22: Docs and manifest

- [ ] `src/archemu-1/README.md`: invocation, trace classes, how to add a
      syscall, ioctl, sysctl MIB or MIG table entry, the benchmark table, the
      known deviations list (FMA rounding, transcendental error, unsupported
      traps).
- [ ] Add `archemu-1` to `src/Manifest`; package metadata in `apk/pkginfo`;
      `docs/build/` note on the per-host product.
- [ ] Update the spec with anything the implementation changed.

## Out of scope, recorded for later specs

- JIT / dynamic translation.
- GUI: WindowServer protocol survey (spec §12), old typed message walker,
  shared-memory event queue swapping.
- Honouring set-id through the emulator; a sysctl to point at a different
  handler; `ptrace`/gdb of emulated processes.
- AltiVec, MMX, SSE.
