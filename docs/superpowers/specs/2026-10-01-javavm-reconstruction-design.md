# DR2 JavaVM reconstruction for i386

Date: 2026-10-01

## Intent and approved scope

Create a maintained reconstruction project at
`src/Developer/Frameworks/JavaVM`, using the extracted DR2 JavaVM framework as
the behavior and ABI reference. The user approved staged reconstruction of
all fourteen native components, Java classes, headers, resources, command
scripts, and installation aliases, with an eventual rbuild-produced APK.
The first supported architecture is i386. PowerPC is outside this first scope.

Success means readable, buildable source and a demonstrated compatible guest
installation. Generated decompiler output is evidence requiring reconstruction
and review. Exact recovery of original source and byte-identical linked binaries
are not required; public and required private interfaces, installation layout,
and observable behavior must be preserved.

This specification defines the overall project and a bounded first milestone.
It does not claim the runtime is reconstructed or authorize skipping subsequent
implementation planning. Later subsystem milestones receive detailed plans as
their dependency boundaries are established.

## Inspected baseline

The primary reference is
`C:/Users/raynorpat/Downloads/test/DR2-Java-Kit`, extracted from
`D:/RhapsodiOS/vm/golden.img`. Its `extraction-manifest.json` records guest paths,
file hashes, modes, and symlinks. Preserve the image as a read-only reference.

The fourteen native files beneath
`System/Library/Frameworks/JavaVM.framework` are all 32-bit little-endian Intel
Mach-O. They comprise three executables, ten libraries, and the framework binary:

| Relative path | Bytes |
| --- | ---: |
| Commands/javah | 68020 |
| Commands/javai | 16704 |
| Commands/javap | 92384 |
| Libraries/libagent.A.dylib | 65396 |
| Libraries/libawt.A.dylib | 316984 |
| Libraries/libdebugit.A.dylib | 62380 |
| Libraries/libjava.A.dylib | 440640 |
| Libraries/libjpeg.A.dylib | 127232 |
| Libraries/libmath.A.dylib | 88020 |
| Libraries/libmmedia.A.dylib | 27744 |
| Libraries/libnet.A.dylib | 44664 |
| Libraries/libsysresource.A.dylib | 31144 |
| Libraries/libzip.A.dylib | 70404 |
| Versions/A/JavaVM | 30132 |

The Commands directory additionally contains shell launchers including java,
javac, javadoc, jar, appletviewer, jdb, javakey, native2ascii, rmic,
rmiregistry, serialver, java_g, java-rmi.cgi, and .java_command. They belong in
the installation inventory even though they do not require native decompilation.
Resolve all aliases from the extraction manifest, including Home and /usr/bin.
Do not infer guest links or executable modes from the Windows filesystem copy.

The Windows JDK reference and prior analysis are under
`C:/Users/raynorpat/Downloads/test/Sun-JDK-1.1.5-Windows`. Its README identifies
JDK 1.1.5. Its source archive is supporting material; DR2 controls behavior.

Prior archive comparison found 1,563 DR2 class paths versus 1,560 Windows class
paths. Of 1,484 shared paths, 1,432 had identical bytes and 52 differed. There
are 79 DR2-only and 76 Windows-only classes. CFR 0.152 produced 74 Java source
files from the 79 DR2-only class files, with inner classes incorporated into
parent files and no reported decompilation exceptions. This does not establish
that the sources compile or preserve behavior. In particular, the 79-class
subset alone is insufficient to rebuild the full DR2 class library.

The existing Ghidra pseudocode directory, explicitly supplied by the user, is:

`C:/Users/raynorpat/Downloads/test/Sun-JDK-1.1.5-Windows/decompilation/native-pseudocode`

It contains fourteen `*.pseudoc.txt` exports. The corresponding saved project is
under the sibling `decompilation/ghidra-project` directory. Reuse these artifacts
as the starting evidence; do not repeat whole-set decompilation merely to create
a new project. Associate each export with its original binary identity and
function addresses during inventory. Reanalyze only where missing types,
relocations, dependencies, disputed behavior, or required structured evidence
justify it, and record the reason and result.

The earlier Ghidra 12.1.4 pass exported pseudocode for 5,211 detected functions
across fourteen files, with no function-level export failures. Import produced
relocation and unresolved-dependency warnings. Function detection counts and
successful pseudocode generation do not establish reconstruction coverage or
correctness. Retain these exports and project databases as preliminary evidence.

## Approach and boundaries

Use small groups of reconstructed components, each with traceable binary
evidence and an independent acceptance result. This exposes ABI and dependency
problems before the full runtime is implemented. Whole-framework decompilation
alone cannot deliver source buildability. Packaging the original executables
would demonstrate layout but would not meet reconstruction acceptance.

The requested source directory exists but currently has no JavaVM project.
Follow the repository's historical Project Builder/pb_makefiles conventions and
rbuild's existing package interface. Avoid introducing another build system or
changing unrelated framework projects.

Proposed project responsibilities:

| Project area | Responsibility |
| --- | --- |
| Framework/ | JavaVM framework entry points and Objective-C/native integration |
| Libraries/ | One source group per native dylib, with documented internal dependencies |
| Commands/ | javah, javai, javap, and the shell wrappers |
| Java/ | Java sources and explicit class-library membership/build manifests |
| Headers/ | Public/private framework and developer-kit header installation inputs |
| Resources/ | Framework resources, properties, configuration, and class-library resources |
| reconstruction/ | Reference identities, coverage records, ABI inventory, and analysis notes |
| tests/ | Focused behavioral and installation checks for reconstructed components |
| apk/ | rbuild metadata and only those installation hooks actually required |

Place host analyzer profiles in `tools/binrecon/profiles/`, using a unique
`javavm-<component>-i386` name per binary. Keep original binaries, generated
decompiler dumps, IDA databases, Ghidra projects, and built products outside
Git or in already ignored output locations. Checked-in reconstruction records
must reference source hashes and tool versions without requiring a particular
user's Downloads path.

## Analysis and reconstruction workflow

1. Pin the fourteen reference hashes and audit the extraction manifest. Inventory
   every installed file, symbol, code section, import, export, initialization
   routine, framework version, dylib install name, and relevant Objective-C/JVM ABI.
2. Configure binrecon profiles for both IDA and Ghidra for each i386 component.
   Start reconstruction from the existing Ghidra exports and saved project, and
   add IDA analysis for independent comparison. Plain pseudocode is not a binrecon
   normalized snapshot: obtain missing structured evidence when needed for
   comparisons, documenting any required analyzer rerun. Use normalized evidence
   and disagreement reports to guide review. Angr is outside the initial workflow.
3. Recover types, calling conventions, structures, ownership rules, exceptions,
   callback relationships, and native registration before translating functions.
   Inspect disassembly wherever decompiler output is ambiguous or inconsistent.
4. Maintain function-to-source mappings and explicit unresolved items. Record
   imported stubs, aliases, compiler/runtime helpers, and unidentified code so
   auto-detected function totals cannot hide unaccounted executable bytes.
5. Implement and compile readable source using the historical compiler and ABI.
   Compare the rebuilt component to the reference, then exercise focused
   behavioral cases before advancing its coverage state.

The current binrecon Mach-O reader accepts MH_EXECUTE and MH_DYLIB as well as
its other supported types. Do not implement the obsolete parser limitation
described in older framework plans. Actual adapter behavior still needs a
bounded pilot on this reference set.

The Ghidra adapter currently requires the configuration version string `12.1`
and validates the exported analyzer version. The earlier standalone Ghidra
12.1.4 export has not established compatibility with that adapter contract.
Resolve and record a supported tool/version combination honestly; do not relabel
analyzer output to bypass validation. IDA profiles should use the actual installed
executable and reported version. Narrow tool fixes require a reproduced failure
and regression coverage; tool success is never substituted for manual parity review.

Recover the dependencies named by the native binaries from the matching DR2
reference where needed for analysis. Use repository-built compatible dependencies
for reconstruction builds. Record unresolved Foundation/System/JavaVM imports
and relocation failures; they block acceptance of affected behavior until resolved
or explicitly shown irrelevant by disassembly and runtime evidence.

## Java source and bootstrap strategy

Reconcile the complete DR2 classes.jar and awt.jar contents. Class membership,
resources, native method declarations, and package names are explicit inputs.
Use the reconstructed DR2-only sources as a starting point; audit the 52 changed
shared classes as well. Shared classes may reuse available JDK 1.1.5 source only
after confirming relevance to the DR2 bytecode. Keep provenance and applicable
notices per source group; do not assign a blanket license to recovered material.

Retain original bytecode as comparison and bootstrap evidence outside the final
source build. Windows-only peer and process classes are not added to DR2 simply
to eliminate comparison differences. Generated Java must preserve the historical
native interfaces and produce compatible class-file version 45.3.

Specify and demonstrate a historical compiler/runtime bootstrap before depending
on rebuilt javac. The host's Java 21 used by analysis tools is not an assumed
Java 1.1 source compiler. Document the bootstrap tool provenance and inputs,
and distinguish bootstrap execution from final rebuilt compiler acceptance.
The final package cannot silently substitute untouched reference class libraries
for an unfinished Java reconstruction.

## Build and installation contract

Create one rbuild source package with `apk/pkginfo`, explicitly setting
`arch = i386-apple-rhapsody`. Use a reconstruction-specific version and truthful
description/attribution. Resolve build and runtime package names against the
repository inventory before encoding dependencies. Do not inherit universal
architecture by leaving arch unset.

The project must support the make/install targets and RC_* variables used by
rbuild, including header staging and separate build/output roots. Stage into
DSTROOT rather than directly replacing files in the development guest.

The staged image installs the versioned framework at
`/System/Library/Frameworks/JavaVM.framework`, its Commands/Libraries/Classes/Home
layout and aliases, the selected `/usr/bin` command entries, developer Java
headers, and `/System/Library/Java/JavaConfig.plist`, following the audited
manifest. Record the exact relationship between versioned files and top-level
links before writing install rules. Reproduce permissions and relative link
targets in a Unix staging environment; exclude host paths and analysis artifacts.

The final runtime APK contains reconstructed native products, rebuilt class
libraries, and the required scripts/resources. Use rbuild's existing header and
object companion package conventions where applicable. A partial milestone may
produce a staged development artifact, but it must fail full-package acceptance
when required components or behavior remain incomplete.

## Milestones and acceptance

### 1. Project inventory, analysis pipeline, and pilot

Establish the fourteen component identities, complete installation/class
inventories, source provenance, ABI/dependency graph, coverage schema, and IDA +
Ghidra profiles. Inspect runtime initialization dependencies before selecting
the pilot. Prefer libzip if its dependency closure permits a bounded harness;
otherwise select the smallest isolated component and record why. The small javai
launcher is not automatically an independent pilot because it starts the runtime.

Reconstruct the selected pilot's complete agreed scope, compile for i386, and
compare meaningful normal, boundary, and error cases against DR2. Inventory and
analysis scaffolding alone do not pass the pilot milestone. This milestone is
the subject of the first implementation plan; the remaining milestones are
subsequent scoped reconstruction efforts.

### 2. Runtime and framework integration

Recover libjava and framework initialization, class loading/verification,
interpreter execution, threading, exceptions, memory management, process and
system services, and Java/native/Objective-C integration. Preserve measured
contracts with Foundation and System. Validate javai startup and representative
non-GUI Java programs with the appropriate dependency closure.

### 3. Libraries, tools, and Java class closure

Complete remaining math, network, archive, image/media, agent/debugger, and AWT
components in dependency order. Reconstruct javah and javap and all launcher
behavior. Complete the full Java source/library build, including Apple AWT peers
and debugger integration. Native declarations alone do not satisfy their native
implementations. Use a graphical guest for AWT behavior and existing compatible
system services for dependent features.

### 4. APK installation and integrated behavior

Build the package with rbuild and inspect the actual APK contents, architecture,
dependency metadata, paths, modes, symlinks, and absence of reconstruction inputs.
Install it in a disposable i386 guest cloned from a known reference, retaining
an untouched reference guest/image for comparison. Do not replace frameworks in
another task's active guest or modify golden.img.

Check JVM startup and properties; compile/run a small Java program; archive and
tool operations; class loading and exceptions; native bridging; threading and GC;
file/process/network behavior; and representative AWT event, drawing, clipboard,
and media paths where their component scope requires them. Add focused cases
for recovered edge conditions rather than relying only on a hello-world smoke
test. Check installation replacement and removal on disposable state.

Record build, package, and runtime acceptance separately. Successful compilation,
successful decompilation, or an APK file existing cannot imply runtime parity.
Incomplete coverage, unavailable dependencies, analyzer disagreement, compiler
limitations, and missing guest evidence remain visible blockers to the affected
milestone. Byte differences may be accepted only with a reviewed explanation and
evidence that the required ABI and behavior remain compatible.

## Design review status

The user approved the staged scope and i386-first architecture in conversation.
This written specification requires review before the writing-plans stage.
No reconstruction source or project scaffolding is created by this specification.
