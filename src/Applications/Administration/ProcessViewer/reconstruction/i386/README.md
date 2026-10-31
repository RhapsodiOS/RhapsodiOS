# i386 reference and validation status

No i386 ProcessViewer reference binary was found in the searched local
applications. The PowerPC binary remains the behavioral reference; its bytes
are not an i386 instruction-comparison oracle.

The shared sources passed the i386 ABI probe, focused process, process-type,
table, controller, inspector, live argv/sysctl, and two-scan process enumeration
with stale-process removal tests on the disposable Rhapsody DR2 guest. Direct
linking produced a Mach-O i386 executable.
The application and a minimal `NSApplicationMain` bundle both SIGBUS in the
headless guest after failing to reach the distributed notification server;
GUI integration is therefore unverified. Full details and reproducible test
commands are in `../validation.md` and `../build-environment.md`.
