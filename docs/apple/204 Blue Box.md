# 204 Blue Box

## Mac OS Support in Rhapsody's Blue Box

Jeff Robbin, Technical Lead

## Mac OS Support in Rhapsody's Blue Box (Announcement)

- Andrew David Robbin
- Due: May 12, 1997
- Born: May 2, 1997
- 8 lbs. 2 oz., 21"

## Agenda

- Overview
- About the Blue Box
- User Experience
- Demo
- Implementation
- Summary
- Demo
- Q&A

## Overview of Rhapsody

- Yellow Box
  - Based on OpenStep++ (Java, Advanced Macintosh Look and Feel)
- Core OS
  - Based on Mach 2.6/BSD 4.4 with enhancements
- Blue Box
  - Mac OS as a Yellow Box application

## Rhapsody System Diagram

- Layers: Advanced Mac Look and Feel; Blue Box (Mac OS) beside Java and Yellow Box (OPENSTEP based); Core OS; PowerPC

## Mac OS and Rhapsody Timelines

- 1997: Mac OS 7.6; Rhapsody Developer Release; Mac OS 8
- 1998: Rhapsody Premier Release; Rhapsody Unified Release; Allegro

## What is the Blue Box?

- The Blue Box provides the ability to run most Mac OS software on a modern operating system
- Not an emulation. This is the real Mac OS running both 68K and PowerPC applications
- Supports the then-current Mac OS version
- Improved memory protection
- Improved performance

## Why is the Blue Box Important?

- Dual OS Strategy—Mac OS is going to be around for many years
- Customer have a significant investment in a large number of Mac OS applications
- Customers want to use Mac OS applications side by side with Yellow Box applications
- Customers need a smooth transition to adopt Rhapsody at their own pace

## Blue Box Goals

- Compatibility
  - Very high... much better than Copland
- Performance
  - Will meet or exceed then-current Mac OS; greater than 90% for raw CPU tasks
- Robustness
  - If the Blue Box crashes, Yellow Box doesn't
- Blue Box and Yellow Box integration
  - Provides an easy-to-use, integrated user experience

## Blue Box Advantages

- Improved I/O performance
- Protection for the rest of Rhapsody
  - Safe computing—Blue Box cannot adversely affect the Yellow Box
- Fast Blue Box startup
  - If the Blue Box restarts, it does so quickly
- Improved Virtual Memory (sparse)
  - Virtually unlimited running applications
  - Better application protection (guard pages)

## Blue Box Philosophy

- Only break what absolutely cannot be supported
  - Incompatibilities will be clearly communicated
- Blue Box applications cannot use Yellow APIs
  - AppleEvents will be provided for communication between Blue and Yellow applications
- Just another hardware platform

## What Will and Won't Work

- What won't work in the Blue Box
  - Software that touches hardware
  - Software that modifies or relies on the internals of system services that are shared with the Yellow Box or Core OS (e.g., file system)
- What will work in the Blue Box
  - Almost everything else
- Compatibility will improve over time

## A Sample of Working Stuff

- QuickTime, QuickTime VR, QuickDraw GX, QuickDraw 3D, OpenDoc, Mac OS Runtime for Java, Sound Manager, Serial DMA, Multiple Monitors, Display Manager, ADB Dongles, Language Kits, WorldScript, Drag & Drop, MacsBug, MPW, Apple Game Sprockets, and of course, SimpleText
- Lots of 3rd Party Applications

## User Experience

- Dual Boot between Mac OS and Rhapsody will be supported
- Within Rhapsody, the Blue Box and Yellow Box are two separate environments with some integration
  - Copy and Paste between Blue Box and Yellow Box will be supported
  - No Drag and Drop between Blue and Yellow
  - Shared process menu with Yellow

## User Experience (cont.)

- Compatibility vs. Integration
  - Full screen vs. Mac OS-in-a-Window
  - Shared vs. separate services
    - File system
    - Networking
    - Other devices (ADB, SCSI, etc.)
- User testing will help determine the experience
- More details at session 210: Rhapsody User Experience

## Demo

Rhapsody Blue Box

## Blue Box Implementation

- Video
- Runtime
- Virtual Memory
- New Memory Map
- File System
- Devices
- Networking

## Video

- Full Screen
  - Supports multiple monitors
  - Best performance (direct to screen)
- Mac OS-in-a-Window
  - Shares the palette with Yellow Box
  - Double buffered (slower)
- Ability to toggle between Full Screen and Mac OS-in-a-Window without restarting

## Runtime

- RAM-based ROM image
  - Does not require a hardware ROM
- 68K Emulator
  - Interpretive and Dynamic Recompilation
- Blue Abstraction Layer
  - Completely insulates Blue Box from Yellow Box and Core OS
  - Provides internal communication between Blue Box and both Yellow Box and Core OS
- Simulated Interrupts

## Virtual Memory

- Uses Rhapsody's Core OS virtual memory
- Mac OS virtual memory appears disabled inside the Blue Box
- We will be providing a new API for requesting held memory for real-time performance
- Will also be providing an option to start the Blue Box using only physical memory

## New Memory Map

- Looks like a really large virtual space
- Allows the user to run more applications at one time
- Application Heaps are allocated from the Core OS virtual memory, not Temporary Memory
- Application heaps are located between BufPtr and the System Heap for maximum compatibility

## New Memory Map (cont.)

- Option for guard pages surrounding application stacks and heaps
  - Don't walk between the heaps!
- Will be slightly less compatible
  - It can be disabled a la Modern Memory Manager

## Memory Map Changes

- Current Memory Map (bottom to top): LowMem, System Heap, Temp Mem containing two Applications, INIT/Other; BufPtr marks the top of Temp Mem and MemTop the top of INIT/Other
- New Memory Map (bottom to top): LowMem, System Heap, Temp Mem, four Applications, INIT/Other placed below BufPtr; MemTop is 1GB, above INIT/Other

## File System

- Supports HFS, HFS Plus, and more
- Disk Driver supports three modes
  1. Disk Partition as a Blue Box-only volume
     - Use existing partitions in the Blue Box
     - Very compatible
  2. Yellow Box visible file (disk image) as a Blue Box-only volume
     - For convenience
     - Very compatible

## File System (cont.)

3. Blue Box and Yellow Box share volumes (HFS/HFS Plus, UFS/NFS, etc.)
   - Looks like HFS, HFS Plus, or AppleShare volumes to Blue Box via new Core OS API's
   - Less compatible, but provides much better interoperability
   - Software that expects to see all file system requests through patches will NOT work for volumes in this mode
- Can mix and match multiple volumes with different modes simultaneously

## Devices

- No Native Device Drivers in the Blue Box
  - Model will NOT be available in the Blue Box
  - No `ndrv`, Name Registry, etc.
  - Some support for Native Drivers will be provided in the Core OS
- Communicating with Core OS Drivers
  - Will be providing a model for Blue Box driver communication with Core OS drivers
  - `DRVR`s will be supported for drivers and DAs that do not touch hardware

## Devices (cont.)

- SCSI Manager
  - For devices not currently in use by the Yellow Box (e.g., scanners)
  - Supports SCSI Manager 4.3 and "old" SCSI
- Serial Ports available through Open Transport and Serial Driver
  - Avoid direct SCC access
- No VIA access—it doesn't exist
- ADB Support
  - For devices not currently in use by the Yellow Box (e.g., dongles, joysticks, etc.)

## Networking

- Within the Blue Box, Open Transport will be available
- Includes the OT Classic AppleTalk compatibility services
- Highly compatible, but requires new low-level driver modules (just like any other new Mac OS-based computer)
- Both AppleTalk and TCP/IP will be supported
  - Provides Printing and AppleShare support

## Networking (cont.)

- Shared and Dual IP addresses
  - Dual IP is most compatible
- With shared IP address, cannot run services in both the Blue Box and Yellow Box simultaneously that use the same port numbers (e.g., Web Servers)
- Packets will be multiplexed at the driver level to both the Blue Box and the Core OS
  - Smart multiplexing and buffering will help improve performance

## Demo

Rhapsody Blue Box

## Summary

- The Blue Box provides a very compatible, high performance, robust, integrated experience
- The Blue Box will provide a number of advantages, including better I/O performance, protection for the Yellow Box, fast startup, and sparse memory
- Just another hardware platform, but don't touch hardware directly

## Q&A

- Rhapsody Hands-On Lab (Room K)
- Other Sessions of Interest
  - 200: Rhapsody Technical Overview (Tues)
  - 202: Rhapsody Core OS File System (Tues)
  - 210: Rhapsody User Experience (Thurs)
- Contact Information
  - email: bluebox@apple.com
