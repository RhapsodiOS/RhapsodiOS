# Native reconstruction tests

Run on the i386 Rhapsody snapshot with Apple cc and the DriverKit private headers:

```sh
CPPFLAGS="-I/path/to/System.framework/Versions/B/PrivateHeaders" sh verify.sh
CPPFLAGS="-I/path/to/System.framework/Versions/B/PrivateHeaders" sh verify-core.sh
```

`verify.sh` runs the buffer pool with mocked allocator/netbuf services and NXSpinLock, then checks every recovered ivar offset against the real IOEthernet superclass and all shared descriptor sizes/offsets. Pool cases include both 4096-byte test pages and the native 8192-byte page size.

`verify-core.sh` extracts the preamble and eight selected method bodies verbatim from the current Intel82556.m into a temporary compilation unit. It does not translate method logic or maintain a copied implementation. The selected methods are _waitScb, _waitCu:, acknowledgeInterrupts:, config, _initTcbList, _initRfdList, sendPacket:length:, and receivePacket:length:timeout:. A test subclass supplies channel attention, completion, buffer allocation, and restart hooks; kernel services and superclass allocation are mocked. It checks polling bounds, failure branches, independently specified configuration bytes, physical descriptor links and buffer ownership, and debugger packet copying and ring reuse.

The isolated engine harness suppresses incomplete-class warnings because it intentionally implements only selected methods and superclass stubs. This does not replace strict native compilation of all four production source files. It also does not exercise hardware DMA or interrupt delivery.

To check the old snapshot's selector contract, pass its source path to verify-core.sh. The baseline has only four of the eight reference selectors and must fail with status 3 before compilation. This is a selector-contract regression check, not a claim that the old code executed under the behavioral harness.

Adapter port traces can be run independently with `sh verify-adapters.sh` on the
native i386 guest. This compiles 19 unchanged production adapter methods and the
IRQ helper against a test-only port header; no privileged I/O executes. The
cases cover port widths/masks, IRQ tables, MAC reads, reset/DBRT timing, and
interrupt dispatch/early-return behavior. Probe and device-description setup
remain outside this harness. Native result: 9103 checks, 0 failures.
