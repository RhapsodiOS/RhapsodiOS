# Explicit reconstruction rulings

## Optimized-away formal types

The exact eleven function identities in `interfaces.md` and
`tests/contracts.json`'s `input_erased` map have complete observable machine
contracts but no recoverable original C formal inputs. Eight are uncalled
HIM slots; three have neither call references nor stored-pointer occurrences.
Their bodies are not compiler-generated exemptions and remain in the original
SCB, Hardware, HIM, or API owner lists.

The controller explicitly authorized intentional legacy unspecified-argument
declarations for these eleven identities only. This preserves honest evidence:
the first two preserve r3, six return one, three return zero. Neither
`void(void)` nor any original formal count/return type is inferred. Historical
PPC witness compilation demonstrates that multiple distinct source prototypes
produce identical bodies. The cost is an intentionally weaker source-level
type check for these entries; matching original ABI headers could resolve it.
The remaining 381 CHIM signatures still require normal typed evidence.

A separate exact OSM set covers OSMSynchronizeRange (0x18a484),
OSMSaveInterruptState (0x18a50c), and OSMSetInterruptState (0x18a51c).
The controller approved the same explicit formal-erasure treatment after
complete slot/caller closure. SynchronizeRange's eight register-homing stack
writes remain part of its machine contract; calling it a no-op would lose
observable behavior. The exact three-entry audit and six frozen cases are
separate from the eleven CHIM entries, which remain unchanged.

## Runner aggregate boundary

The existing test runner rejects stack arguments and aggregates. Reference
callers prove that profile and IO-handle values cross r3..r10 into the stack.
Later required cases must extend the runner to model their exact PPC argument
placement; treating these as eight pointers/integers would execute a different
ABI. This is a pending test-infrastructure requirement, not a waiver or a
passing static substitute for required behavioral tests.

The current runner also observes r3 for every call and only distinguishes
scalar versus pointer results. Required later void-method/service cases need
an explicit void-result mode that does not compare unspecified r3 contents.
This differs from the approved erased machine contracts, which explicitly
observe r3 passthrough or a constant. Task 3 adds only bounded stack-byte and
stack-pointer observations needed to execute the register-homing contract;
it does not claim aggregate argument serialization or void-result support.

## Partly erased parameter positions

Typed machine-compatible declarations preserve observed argument slots even
when a particular slot is forwarded or discarded without interpretation.
The controller authorized an unsigned 32-bit opaque carrier for such a slot;
this does not assert its original source type, signedness, or formal grouping.
It does not permit replacing a dereferenced pointer or interpreted integer
with an opaque carrier, and does not expand the eleven unspecified-input
function declarations. Each occurrence remains indexed in interfaces.md.

Current public occurrences are SCSIPowerEvent's forwarded r4 and
SCSIReportAdjustableTargetProfile's discarded r3 before the proven profile
destination in r4. Both retain all observable input positions and return
behavior; there is no inferred pointer meaning for the unconsumed word.
