# Interceptor build and analysis environment

Host tools found during Task 2:

- IDA Professional 9.4: `C:\Program Files\IDA Professional 9.4\idat.exe`. Its reference exports contain 392 PowerPC and 419 i386 function records.
- Ghidra 12.1.2 at `D:\ghidra\support\analyzeHeadless.bat`, with Java 21. A synthetic i386 dylib fixture succeeds. A real DR2 run succeeds when its scratch directory is outside the hidden `.codex` path.
- angr 9.3.0 in `D:\RhapsodiOS\.venv-binrecon`. A synthetic i386 dylib fixture succeeds.
- Binrecon now accepts 32-bit MH_DYLIB images in either byte order.

The historical Rhapsody SDK, Project Builder make, MIG, and guest build routes are not yet verified. Record exact compiler and runtime findings in the build task before claiming either slice builds.

## Analyzer agreement limit

All three i386 exporters individually accepted the DR2 image. They produced 419 IDA, 416 Ghidra, and 1085 angr function records. IDA and Ghidra relocation encodings also differ. Running all three through the current consensus publisher fails with `relocation 0 has missing or conflicting width`. The committed i386 profile therefore uses IDA for its stable address inventory. Ghidra and angr outputs remain independent review evidence under `C:\Users\raynorpat\Downloads\test\Interceptor-evidence\adapters-i386` and are not committed.

A Ghidra run whose project directory was under the managed checkout failed because `.codex` is not permitted in a Ghidra project path. Moving analyzer output to the external evidence directory resolved that path constraint; it was not a binary loader failure.
