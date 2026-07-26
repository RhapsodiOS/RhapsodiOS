# Objective-C root-class hosting probe (stage 2a Task 1 go/no-go gate)

Answers spec §2.3 / §3.2 step 1: will the guest's Objective-C runtime
dispatch through a root class supplied by us, in a process with no system
Foundation linked? This is the hard gate for stage 2a — if it fails, the 168
Objective-C methods in Tasks 7-10 cannot be behaviourally tested and the
stage's shape changes.

## RESULT: not hosted (for i386, the stage's target architecture)

Case 1 — missing runtime libraries. **But see "Important nuance" below**:
the deeper, more important sub-finding is that the runtime's *root-class
dispatch mechanism itself is sound* and does host a foreign root class, once
that class supplies the minimum a real `NSObject`/`Object` would already
supply. The blocker is an incomplete i386 link environment on this guest,
not a rejection of custom root classes.

## Probe sources (as given, with one required fix)

`probe_root.m` (verbatim from the brief):

```objc
/*  Minimal Objective-C root class, to establish whether the guest runtime
    will host one supplied by us rather than by Foundation.  */

#import <objc/objc.h>
#import <objc/Object.h>

@interface ProbeRoot
{
    Class isa;
}
+ alloc;
+ new;
- init;
- free;
- (int)answer;
@end

@implementation ProbeRoot

+ alloc       { return class_createInstance(self, 0); }
+ new         { return [[self alloc] init]; }
- init        { return self; }
- free        { return object_dispose(self); }
- (int)answer { return 42; }

@end
```

`probe_main.m` — **the brief's verbatim text does not compile**: it declares
`id probe;` but only imports `<stdio.h>`, not `<objc/objc.h>` (unlike
`probe_root.m`, which does). `cc1obj` reported `` `id' undeclared`` at line
11. This was confirmed to be exactly that omission, not an ObjC-frontend
problem: `probe_root.m` itself (which uses `@interface`/`@implementation`
and implicit-`id` method returns, but never an explicit `id`-typed variable)
compiled cleanly, proving `.m`/`cc1obj` recognition works correctly. One line
was added to `probe_main.m` to reach the actual test; this is the only
deviation from the brief's verbatim source:

```objc
#import <stdio.h>
#import <objc/objc.h>          /* added: brief's probe_main.m lacked this,
                                   so `id` was undeclared */

@interface ProbeRoot
+ new;
- free;
- (int)answer;
@end

int main(void)
{
    id probe;
    int value;

    probe = [ProbeRoot new];
    if (probe == 0) {
        printf("FAIL: +new returned nil\n");
        return 1;
    }
    value = [probe answer];
    [probe free];

    printf("%s: answer=%d\n", value == 42 ? "PASS" : "FAIL", value);
    return value == 42 ? 0 : 1;
}
```

## Environment

Guest `10.10.0.241` (native PowerPC Rhapsody 5.6, `cc-783.1`/gcc 2.7.2.1),
reached via `plink`/`pscp` using `/d/RhapsodiOS/vm/vm.conf` (untracked,
main-worktree-only). Probe built and run in an isolated, throwaway guest
directory (`/build/source/objc-hosting-probe-task1`, a sibling of the shared
`/build/source/src/Kits/Foundation`), deleted afterward along with every
scratch file it produced (`build*.log`, `run.log`, probe binaries, and
`/tmp` nm/verbose/gdb scratch files) — the guest was left exactly as found.

## Step 1: the exact command from the brief, as specified

```
cc -arch i386 -o probe probe_root.m probe_main.m -lobjc >& build.log
echo $status
```

Complete build log:

```
probe_root.m: In function `-[ProbeRoot free]':
probe_root.m:23: warning: passing arg 1 of `object_dispose' from incompatible pointer type
/usr/bin/ld: warning /lib/crt1.o cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (file not loaded)
/usr/bin/ld: can't locate file for: -lobjc
```

`EXIT=1`. This is a link failure, not a compile failure — both `.m` files
compiled to i386 object code without error (the `object_dispose` warning is
a pre-existing pointer-type mismatch in `<objc/Object.h>`'s declaration
versus the brief's usage, not fatal).

## Step 2: characterising the failure (brief's Case 1)

`find / -name 'libobjc*'` across the **entire guest filesystem** returned
**zero results** — for either architecture. There is no `libobjc.a` and no
`libobjc*.dylib` anywhere on this guest. This ruled out "missing symbols
inside a present library" (the brief's suggested diagnostic) in favour of
"the library itself does not exist here at all."

Following the brief's suggested check, `nm -g` was run on the closest
available analogue (`/usr/lib/libc_static.a`, the guest's static libc/System
archive) for both `i386` and `ppc`: zero occurrences of `class_createInstance`,
`objc_msgSend`, or `object_dispose` in either architecture slice.

However, `nm -g /System/Library/Frameworks/System.framework/System` (the
System framework's umbrella binary, native ppc) **does** export the ObjC
runtime — `class_createInstance` (6 matches) and `objc_msgSend` (28
matches) are present. The runtime lives inside the System umbrella
framework on this OS release, not in a separate `libobjc`.

Retrying the brief's suggested `-lobjc -lSystem` reproduced the identical
`can't locate file for: -lobjc` failure (there is no `-lSystem` archive
either; the correct default form is `-framework System`, which `cc` already
adds automatically when no libraries are given explicitly).

Dropping the explicit `-lobjc` and letting `cc`'s default `-framework
System` linkage take over (`cc -arch i386 -o probe probe_root.m
probe_main.m`, no explicit ObjC library flag) surfaced the deeper problem:

```
/usr/bin/ld: warning /lib/crt1.o cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (file not loaded)
/usr/bin/ld: warning /usr/lib/libcc_dynamic.a archive's cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (can't load from it)
/usr/bin/ld: warning /System/Library/Frameworks/System.framework/System cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (file not loaded)
/usr/bin/ld: Undefined symbols:
_class_createInstance
_objc_msgSend
_object_dispose
dyld_stub_binding_helper
_printf
```

**This guest has no i386 slice of `crt1.o`, `libcc_dynamic.a`, or the
System framework binary at all** — only native ppc versions exist. This is
not ObjC-specific: it would block linking *any* i386 executable on this
guest right now, not just ones using the Objective-C runtime. `-c`
compilation to i386 object files works fine (confirmed here and in the
stage 1 compile probe, `docs/superpowers/plans/notes/2026-07-26-foundation-compile-probe.md`)
— it is specifically the i386 **link** stage that has no runtime libraries
to draw on.

## Important nuance: the runtime *does* host a foreign root class (ppc)

Because the System framework's ppc slice does contain a working ObjC
runtime, the same probe was also tried as a native ppc build (`cc -o
probe_ppc probe_root.m probe_main.m`, no `-arch i386`, no explicit `-lobjc`
— letting the default `-framework System` resolve everything). This linked
cleanly (`EXIT=0`) but **crashed at run time**:

```
Abort
RUNEXIT=134
```

`gdb -batch -x <(echo run; echo bt; echo quit) ./probe_ppc` backtrace:

```
Program received signal SIGABRT, Aborted.
0x4134be48 in kill ()
#0  0x4134be48 in kill ()
#1  0x41343c34 in abort ()
#2  0x413c041c in _objc_fatal ()
#3  0x413c03b4 in __objc_error ()
#4  0x413c67fc in _objc_msgForward ()
#5  0x413c6798 in _objc_msgForward ()
#6  0x413be9d8 in class_initialize ()
#7  0x413027b8 in _class_lookupMethodAndLoadCache ()
#8  0x413024c4 in objc_msgSend ()
#9  0x3d84 in main ()
```

The verbatim error, recovered from `/var/log/system.log` (not printed to
the SSH session's stdout/stderr — this OS logs ObjC runtime fatal errors to
syslog):

```
objc: ProbeRoot: Does not recognize selector forward::
```

Diagnosis: before dispatching the first message to a class, this runtime
implicitly sends `+initialize`. `ProbeRoot` is a genuine root class (no
superclass) and does not implement `+initialize` itself, so there is no
inherited no-op to fall back on (a normal subclass of `Object`/`NSObject`
would inherit one). The runtime's fallback for an unimplemented method is
`forward::`, which `ProbeRoot` also does not implement — and unlike a
missing ordinary method (which raises `doesNotRecognizeSelector:`,
recoverable), a missing `forward::` at this bootstrap point is fatal
(`_objc_fatal`/`abort`).

**This was confirmed, not just theorised**: adding a single trivial
`+initialize { return self; }` to `ProbeRoot` (`probe_root_init.m`,
otherwise byte-identical to the brief's `probe_root.m`) and rebuilding for
ppc produced:

```
PASS: answer=42
RUNEXIT=0
```

So the runtime's root-class dispatch mechanism is sound: it will host a
class we supply as the literal root of the hierarchy, load its instances,
and dispatch to its methods correctly, with no second `NSObject`
implementation anywhere in the process. The only requirement is that the
class satisfy the same minimal contract any real root class (`Object` /
`NSObject`) already satisfies — at minimum, respond to `+initialize`. Our
real `NSObject` reconstruction already plans to implement `+initialize`
(stage 2a Task 8, "NSObject class methods"), so this is not expected to be
an obstacle for the actual reconstruction — it was only a gap in this
throwaway probe's deliberately minimal `ProbeRoot`.

## Verdict

- **RESULT: not hosted**, strictly as asked (`-arch i386`, the brief's
  exact command) — **Case 1: missing runtime libraries.** `-lobjc` does not
  exist anywhere on this guest for either architecture, and — discovered in
  the course of diagnosing that — the guest additionally has no i386 slice
  of `crt1.o`, `libcc_dynamic.a`, or the System framework binary, so no
  i386 executable can currently be linked on this guest at all, regardless
  of Objective-C.
- The **root-class-hosting question itself is answered positively** on
  native ppc, where the System framework's runtime is present and complete:
  a foreign root class, once it implements `+initialize` (something any
  real `NSObject` will do), is instantiated and dispatched through
  correctly with no interference from a second implementation.
- **Consequence for the stage:** this guest, as currently provisioned,
  cannot link i386 Objective-C (or any i386) executables. Either (a) the
  guest's i386 cross-link environment needs the missing runtime pieces
  (`crt1.o`, `libcc_dynamic.a`, System framework, and an ObjC runtime
  library or equivalent) installed before Tasks 7-10 can behaviourally test
  i386 binaries, or (b) behavioural testing proceeds on native ppc instead
  (where hosting is proven to work), or (c) testing is deferred until a
  linkable framework exists. This is a decision for the user, per the
  brief's gate instruction — Task 2 was not started.
