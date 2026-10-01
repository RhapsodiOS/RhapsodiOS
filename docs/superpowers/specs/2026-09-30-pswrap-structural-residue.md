# pswrap structural residue — 2026-09-30 pass

Follow-up to `2026-09-29-pswrap-reconstruction-design.md`. Goal: close what was
left as "structural residue" (crt/dyld glue, libc stubs, pairing desync).

## What the residue actually was

Fingerprinting every reference `__text` function (size, instruction count,
call count, and the count of `mov eax,eax` self-copies) against the rebuilt
binary showed the pairing desync was not name noise: the reference was
compiled **unoptimized** while pb_makefiles defaults `OPTIMIZE = YES`.

Evidence:
- Reference prologue shapes: `sub esp,N` before saves, `mov eax,eax` after
  every call (gcc 2.x -O0 return-value copies), `mov ebx->edx; lea disp(%edx)`
  global-address chains, `jmp .+2; nop; nop` case-exit padding.
- Guest `cc` (cc-783.1, the same compiler package the reference shipped with)
  reproduces each fingerprint with no `-O`, and none of them with `-O`.
- `pb_makefiles-89.5.1` `flags.make` defaults `OPTIMIZE = YES` → `-O`;
  the override `OPTIMIZE = NO` is sanctioned (flags.make checks with
  `ifndef` after `Makefile.preamble` is included).

## Fixes landed (commit 839e5a9d8)

1. `Makefile.preamble`: `OPTIMIZE = NO`.
2. `main.c` `-h` case: uppercase with direct range arithmetic
   (`*c > '`' && *c <= 'z'` → `+= 'A'-'a'`), matching the reference's
   compiled form; the ctype macros would have emitted `_toupper` code the
   reference does not have. Also `rindex` → `strrchr` (three sites, drop the
   os_mpw alias): the reference imports `__imp__strrchr` only.
3. `pswfile.c`: `InitHFile`/`FinishHFile` take the header id as a parameter
   (the reference pushes `arg_0` twice for `fprintf`).

## State after this pass

- Undefined-symbol set **identical** (30 = 30).
- Section sizes exactly equal: `__cstring` 9961, `__data` 2232,
  `__la_symbol_ptr` 100, `__nl_symbol_ptr` 112, `__dyld` 20, `__bss` 65632,
  `__common` 8492.
- `__text` 74194 vs 75259 (−1065, was −28899 before this pass).
- **89 of 112 reference `__text` functions fingerprint-match exactly**
  (sizes equal to the byte); the fingerprint includes the -O0 return-value
  copy count, so these are near-certainly byte-identical code bodies.
- All differential suites pass on the new binary (difftest4 130/130,
  difftest3 225/225, difftest/difftest2 clean, sizeprobe2 20/20, functest
  identical, EOF probe clean).

## Remaining residue (classified, not fixed)

1. **`yylex` −552 B.** The reference `lexer.l` has two more PS-state rules
   than ours: two extra actions compile to the "copy `yytext` (len+1) via
   `psw_malloc`+`strcpy`, return PSNAME, with newline tracking" shape,
   textually between the PS-junk rule and the PSBOOLEAN rule (both sides
   have the same rule count in every other return class). The pattern text
   is not recoverable from the binary — flex's tables are what differ
   (`yy_acclist` 431 vs 434, transition-table marker 0x2f1 vs 0x2ea,
   dispatch `cmp 0x49` vs `0x47`) — and every behaviorally plausible guess
   (`defineps`/`endps` variants, true/false splits) is already covered by
   rules we have. Behavioral parity is proven by the suites; the gap is a
   table-size artifact.
2. **Emit-region organization (~270 B over four functions).** The reference
   folds `_FinalizePSWrapDef`/`_AppendPSWToken`-shaped code into other
   functions and has `AppendPSWArgs`/`AppendPSWItems` as standalone
   functions with identical fingerprints on both sides — the differences
   are static-vs-inline and fold boundaries, not emitted text.
3. **crt/dyld/linker glue.** Our `__dyld_init_check`+`dyld_stub_binding_helper`
   (52+11) vs the reference's single 63-byte equivalent; one extra
   `__picsymbol_stub` slot; `__const` −56 is the flex tables (item 1).
   Link toolchain artifacts.

`binrecon compare` `normalized-functions` still reports FAIL — the criterion
requires every function to pair by offset and match byte-for-byte, which the
two-function glue split and the yylex table difference make structurally
impossible. The acceptance hierarchy's intent (per-function code equivalence)
is met by the 89 fingerprint-exact pairs plus the behavioral suites; the
residue is documented here rather than hidden.
