# 201 CoreOS Concepts

## Core OS: Kernel and Runtime

Speakers: John C. Signa (Rhapsody Core OS Evangelist); Brett R. Halle (Manager, Core OS Kernel Group).

## John's First Experience with the Mock Colonel

Photograph of the speaker posing with a Colonel Sanders statue.

## Rhapsody Core OS

Layered diagram, top to bottom: Advanced Mac Look and Feel; Mac OS Blue Box beside Yellow Box; Core OS; Hardware. A "You are here" arrow points at Core OS.

The Core OS is then expanded into: File Systems, Networking, POSIX / BSD, Mach, I/O, and a Runtime column. Callouts point to Session 202 (File Systems), Session 203 (I/O) and Session 220 (Networking).

## Core OS Kernel: Mach

- History/Overview
- Key features
  - Tasking (tasks and threads)
  - Interprocess communication
  - Virtual memory
  - Multi-processor architecture
- For more information
  - "Programming Under Mach"
  - Net resources...

### Mach Tasks, Threads

Diagram, built up over several slides: a Task containing Thread 1, Thread 2 ... Thread n, then a second Task with the same threads.

### Mach IPC

Diagram, built up over several slides: Task 1 and Task 2, each with Thread 1, Thread 2 ... Thread n and port icons, with arrows showing messages passing between the ports of the two tasks through Mach.

### Mach Memory Management

- Memory management
- VM paging/backing store
  - Lazy, dynamic (sparse) backing store allocation
  - Copy-on-write

## Core OS POSIX/BSD

BSD 4.4

- Provides the OS "personality" APIs and services
  - Filesystem access
  - Networking access
  - Security policy
- For more information...
  - Numerous books available
  - Net resources...

## Demo

## Core OS Runtime

- Architecture
  - Position independent code
  - Dynamic shared libraries
- Object runtime
  - Late bound
  - Be sure to see Session 415
- Packaging
  - Mach-O
  - App wrappers

## Core OS

- For 99% of you...
  - Use Foundation (see Session 207)
    - Portable
    - Thread safe
- For UNIX daemons, CLI tools
  - Use POSIX, BSD 4.4
  - Lots of free BSD compatible code out there
- For Debugger developers, monitoring tools, etc.
  - Use Mach and all of the above

## Demo

## Additional Sessions

- Rhapsody Core OS: File System
  - Tuesday, 6:10 pm, Hall 1
- Understanding Rhapsody Drivers
  - Thursday, 8:30 am, Room A1
- Rhapsody Networking APIs and Services
  - Friday, 5:50 pm, Room A1
- Uncommon Object Model: The Rhapsody Runtime
  - Wednesday, 9:50 am, Room A1
  - Thursday, 9:50 am, Room C
- Intro to the OpenStep Foundation Framework
  - Wednesday, 4:30 pm, Hall 1
  - Friday, 3:10 pm, Room B

## Core OS Feedback

- Rhapsody Core OS Feedback Forum
  - Thursday, 11:10 am, Room J4
- E-mail
  - `rhapsody-dev-feedback@apple.com`
