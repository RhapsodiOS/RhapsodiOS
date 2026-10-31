# 200 Rhapsody

Speakers: Avadis Tevanian Jr. (Senior Vice President, Software Engineering, Apple Computer, Inc.); Ricardo Gonzalez (Senior Product Marketing Manager); Bertrand Serlet (Senior Director, Rhapsody Engineering); John Landwehr (demos); Ken Bereskin (Manager, Rhapsody Evangelism).

## Rhapsody Technical Strategy and Overview

## Rhapsody Marketing Overview

### What is Rhapsody?

The next generation operating system using Apple and NeXT technologies.

- Mature NEXTSTEP foundation
  - Mach, OpenStep, BSD, Distributed Objects
- Industry leading Apple technology
  - QuickTime Media Layer, ColorSync, AppleScript, etc.
- Cutting edge network technology
  - EOF
  - WebObjects

### Why Rhapsody?

- Direct response to customer needs
  - Improved stability
  - Higher throughput
  - High Mac OS compatibility
- Direct response to developer needs
  - Cross-platform
  - Efficient development
  - Java integration

### Rhapsody Target Markets

Establish Rhapsody as a volume software platform for desktop, mobile and servers.

- Publishing
- Multimedia
- Internet/Intranet
- Scientific/Engineering
- Higher Education
- Enterprise

## Rhapsody

## Rhapsody's Architecture

Layers, top to bottom: Advanced Mac Look and Feel; Mac OS Blue Box beside Yellow Box; Core OS; Power PC.

### Starting Point: NEXTSTEP

- NEXTSTEP represents
  - State of the art toolbox
  - Architecturally sound
  - Strong APIs at all layers
  - Rich feature set
  - Various hardware and software platforms
- Incremental approach
  - Incorporate new technologies
  - Replace subsystems as needed

## Starting Point: NEXTSTEP Demo

John Landwehr.

### Core OS

The Core OS layer: Microkernel, I/O, File System, Networking.

### Core OS

- Mach
  - Modern small proven kernel
  - VM, Tasks, Threads, Messaging, SMP
- Driver Architecture
  - Dynamic loading for Plug and Play
  - Easy to create drivers
- UNIX
  - Standard
  - Tools, Networking, File System, Servers
  - Hidden!

### Yellow Box

Yellow Box, OPENSTEP based.

### Yellow Box from OpenStep

- OpenStep: 2nd Generation OO Design
- Depth of features
- Fully international
- Display PostScript
- Substrate for WebObjects
- High developer productivity
- Cross-platform

### Yellow Box

- QuickTime Media Layer
  - QuickTime, QuickTime VR, QuickDraw 3D
- ColorSync, GX Typography, V-Twin, ...
- Scripting
  - Integrated into the frameworks
- More widgets
  - TabView, OutlineView, ...
- More standard data types
  - PICT, HTML, ...
- Enhanced Mac Look and Feel

### Yellow Box Look and Feel Demo

John Landwehr.

### Yellow Box and Java

Diagram: Java sits alongside Yellow Box (OPENSTEP based).

### Java Support

- JDK 1.1 Java VM
- AWT
- All 100% pure Java libraries

Diagram: 100% Pure Java enters the Java block; Yellow Box APIs and Dynamic Runtime sit beside it.

### Java Integration

- Objective-C to Java Bridge
- All Yellow Box APIs
- Applications in pure Java

Diagram: Accelerated Java enters through the Yellow Box APIs.

### Java Integration

The most advanced Java framework on Earth

### Java Choices

- Convenience/performance trade-off

Diagram: three entry points into the Yellow Box, from 100% Pure Java, Accelerated Java, and Native Yellow (C, C++, ObjC, etc.).

### Blue Box

Diagram: Mac OS Blue Box.

### Blue Box

- Not an emulator
  - Runs Mac OS
  - Highest compatibility and performance
- All unmodified Mac OS applications except
  - Applications that access hardware directly
  - Low level system patches that expect global effect (disk compression, etc.)
- Come check out compatibility at the Rhapsody "Hands-On" Lab

### User Experience

Diagram: Advanced Mac Look and Feel layer at the top of the stack.

### Advanced User Experience

- Mac OS 8 Finder rewritten in Yellow
  - NEXTSTEP features: Browser, Copy Engine
  - Extensible, replaceable
- Key elements of Advanced Human Interface
  - Live Widgets: Scrolling, window drag, animated icons
  - HTML-based Help
- Apple "Plug and Play"
  - Networking
  - Integration of subsystems HW/SW

### Rhapsody

Diagram: Advanced Mac Look and Feel over Mac OS beside Java and Yellow Box (OPENSTEP based), over Core OS, over PowerPC.

## Product Family: The Siblings

### Rhapsody for Intel

Diagram: Advanced Mac Look and Feel over Java and Yellow Box (OPENSTEP based), over Core OS, over Intel.

### Yellow Box for Windows

Deployment platform.

Diagram: Microsoft Windows Look and Feel over Microsoft Windows 95/NT with Java and Yellow Box (OPENSTEP based) on top of it, over Intel Based PC Hardware.

### Yellow Box for Mac OS

Deployment platform.

Diagram: Mac OS Look and Feel over Mac OS with Java and Yellow Box (OPENSTEP based) on top of it, over Power Macintosh, PowerPC Platform Hardware.

### Rhapsody Product Family

- Complete software platform with OS
  - Rhapsody
  - Rhapsody for Intel
- Deployment platform
  - Yellow Box for Windows
  - Yellow Box for Mac OS
- Your Yellow-based applications will run everywhere!

## Roadmap

### Rhapsody Roadmap

Timeline across 1997 and 1998. Rhapsody Developer Release in 1997 (after Mac OS 7.6 and before Mac OS 8); Rhapsody Premier Release early 1998; Rhapsody Unified Release in 1998 (before Allegro).

### The Last Three Months

- Feb 4: Merging of the teams
- Feb 24: The PPC kernel compiles and links
- April 9: UNIX prompt
- April 14: Blue Box Macsbug
- April 16: Display PostScript on screen
- April 28: Blue Box Finder and applications
- April 30: Java VM
- May 2: Multi-user UNIX prompt
- May 2: First Yellow application on PPC!

### Prelude to Rhapsody

- Now for all attendees!
- What is it?
  - OpenStep Mach 4.2 Prerelease 2
  - OpenStep NT 4.2
  - Enterprise Objects Framework
  - WebObjects
- What should you do with it?
  - Verify our cross-platform commitment!
  - Learn OpenStep and jump start your Rhapsody development!

### Developer Release

- Summer '97
  - Seeding to Apple Developer Program
- For whom?
  - Not for users
  - All developers except DD developers
- Quality goal
  - Prerelease, but developers can live on it
- First support Power Macs
  - Only 8500 and 8600 supported

### Premier Release

- Early '98
- For all developers (including DDD)
  - Final APIs (Java, DDK)
  - Cross-Platform Multimedia (QTML)
- Certain classes of users
  - OS server-ready (SMP)
  - Blue Box running Productivity Apps
- Runs on modern PPCs, PowerBooks
- UI Polish at least as good as NEXTSTEP's

### Unified Release

- Mid '98
- For most high-end Mac users
  - Drivers available for most PPC devices
  - Tuning: I/O performance
  - Best performing Java
  - Full Blue Box runs most Mac Apps
  - Advanced UE
- There will be many customers for your products in this timeframe!

## Developer Opportunities

Ken Bereskin (Manager, Rhapsody Evangelism).

### Yellow Box: The Platform

It's more than just Rhapsody.

- Develop "best of breed" solutions
- Deliver across multiple platforms
- Shorten the development cycle
- Bring the benefits of Java to all solutions

### Yellow Developer Platform

Diagram: Developers (ISVs, Web Developers, VARs/System Integrators, Corporate Developers) feed the Development Platform (Yellow Box), which targets User Environments: Rhapsody, Rhapsody for Intel, Mac OS, Windows 95, Windows NT.

### Yellow Box Platform Demo

Ken Bereskin.

### How Can You Start

- Learn OpenStep with Prelude to Rhapsody
  - Full suite of current tools
  - Great documentation on CD
  - Get started today!
- Rhapsody Hands-On Lab
  - OpenStep Tutorial
  - Try out your software on the Blue Box

### Rhapsody Evangelism and Support

- Rhapsody Evangelism Team
  - Covering all aspects of Rhapsody Technology
- Rhapsody DTS team
  - Ramping up for developer release
  - Broad range of services will be provided
- No direct support for Prelude
  - Detailed configuration guide
  - `http://devworld.apple.com/dev/Prelude.html`
- Installation of OpenStep/Mach for Intel can be an adventure

### Feedback

- Developer feedback
  - `rhapsody-dev-feedback@apple.com`
- Feedback is essential
  - Decision making
  - FAQ
  - Future directions
- Not a vehicle for Technical Support

### Rhapsody Session Roadmap

- 21 Sessions in Rhapsody Track
  - And Feedback Forums
- Internet Track
  - 405 Building Java-based applications for Rhapsody
  - 415 Uncommon Object Model: Rhapsody Runtime
  - All WebObjects sessions
- Hardware Track
  - 505 Multiprocessing Strategies
- Rhapsody Hands-On Lab
  - Late Night is "Thursday" until 1:00 am
