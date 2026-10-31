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

## Remaining residue (classified, then one item recovered)

1. **`yylex` −552 B — RECOVERED on 2026-10-01, see next section.**
   *(Original classification, now known wrong: two more PS-state rules,
   textually between the PS-junk rule and the PSBOOLEAN rule, with the
   pattern text judged unrecoverable from the binary. It was recoverable.)*
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

## Recovery of the two lexer rules (2026-10-01, commit 6cb05cd5a)

The judgment that the pattern text was unrecoverable was wrong. The flex DFA
is the pattern: both binaries carry the full tables as `static const` data in
`__TEXT,__const`, and the skeleton order (`yy_acclist, yy_accept, yy_ec,
yy_meta, yy_base, yy_def, yy_nxt, yy_chk`) plus structural validation pins
every table length. The method:

1. Carve all eight tables from both binaries (`yy_ec`/`yy_meta` signatures
   anchor the layout; `nxt` fills to the `__data` boundary).
2. Decode the accept lists and align the DFAs state-by-state (BFS in
   lockstep over equal character classes). Ref's rule numbering maps
   `raw = ours` below the insertion point and `raw = ours + 2` above it:
   the two new rules sit **between the `<HEX>` error rule (49) and the
   self-delimiter rule (50)**, i.e. before PSBOOLEAN — the earlier
   "between PS-junk and PSBOOLEAN" placement was off by one rule.
3. Read the new acceptor states off the aligned DFA: ref 127 accepts
   `"<<"` (raw 50), ref 128 accepts `">>"` (raw 51); the junk rule gains a
   dedicated `'>'` first-char state (37) so `'>>'` is reachable before
   backing up, which explains the junk-rule accepting-state mismatch.
4. Add `<PS>"<<"` and `<PS>">>"` returning PSNAME (Level 2 dictionary
   constructs) with the executable-name action shape, regenerate
   `lexer.c` with the guest `lex -l`.

Proof: the regenerated tables are **byte-identical to the reference's in
all eight arrays**, and carving the rebuilt binary's `__const` with the
reference's anchors reproduces them exactly. `__const` is now 7304 bytes on
both sides; `__text` closed to 74746 vs 75259 (remaining −513 is the
glue/emit-region residue). All differential suites pass on the new tables,
including ten new dictionary-contraction probes (`<<`/`>>` inputs).

With the tables identical, `yylex` itself is **code-identical modulo
relocation**: both bodies are 20021 bytes, and a byte diff of the two
carved bodies has 786 differing runs with **every run ≤ 4 bytes** (the
2/3/4-byte relocation signature: branch targets, `lea`-chain
displacements, jump-table indices) — no structural difference. An
independent capstone linear disassembly of both bodies (3511 = 3511
instructions) yields **exactly equal mnemonic streams**. IDA's recursive
descent reports 5050 vs 5040 instructions and spurious `retn 28Bh` hits;
those are decoder/rendering artifacts, not code differences.
