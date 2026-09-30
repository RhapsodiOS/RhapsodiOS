# 218  XPlatform Development

## Cross-Platform Development with Yellow Box

- Jordan Dea-Mattson
- Senior Evangelist, Rhapsody Evangelism

## Making the Move

- *Diagram: Mac OS has an arrow down to Allegro Tempo, which leads to Blue Box; a second arrow, labelled Latitude, leads to Rhapsody. A Yellow box, beside Blue Box, has an arrow to Yellow for Mac OS.*

## Cross-Platform Development Overview

- Frédéric Bonnard
- Yellow Box Product Manager

## Supported Platforms

- *Diagram: a Yellow Box bar above five platform boxes: Rhapsody, Rhapsody for Intel, Mac OS, Windows 95 and Windows NT.*

## Yellow Box Components

- *Diagram (built up over several slides): an empty yellow box, then red "books" slide in one at a time, each with its contents on the cover and a title on its spine:*
  - Distributed Computing: CORBA/IIOP
  - Database: Enterprise Objects Framework
  - Windows Support: OLE/COM (Windows only)
  - Prebuilt Objects: UI Components, Localization, App Services, Scripting, Multithreading, Memory Mgmt., File System Ops.
  - Graphics: Display PostScript, ColorSync
  - Multimedia: QuickTime, QuickDraw 3D, QuickTime VR
  - Web/Internet: Internet Mail, Messaging, Security, WebObjects
  - Java: 100% Pure
- *Diagram: the finished box has three round slots on top labelled "Components", which are then filled with plugs labelled Apple, ActiveX and Java Beans.*

## Why Cross-Platform?

- Leverage future investments
  - Write once, reap many
- Develop for mixed environments
- Reduce the risk of adopting Rhapsody

## Why Another Development Platform?

- Microsoft's Win32 Platform
  - Not cross-platform
  - Very low level API
  - Difficult to program
- Sun's Java Platform
  - LCD solution
  - Not designed to integrate with OS and desktop specific features (sand box)
  - Not ready for mainstream application development and deployment

## Cross-Platform Goals

- Rhapsody + Windows + Mac OS = 99% market share
- Same API on all platforms
  - Constrained by underlying OS (e.g. threads)
- Native look and feel
- Tight integration with other applications and system services
- Full functionality
  - Not an LCD solution
- Native performance

## Rhapsody Goals

- The best host for Yellow Box applications (e.g., user experience, speed...)
- Native frameworks
- Intel vs. PowerPC issues
  - MacOS compatibility
  - Plug and Play
- *Diagrams: on PowerPC, layers from bottom to top are PowerPC, Core OS, then Mac OS beside Java and Yellow Box (OPENSTEP based), under Advanced Mac Look and Feel. On Intel, they are Intel, Core OS, then Java and Yellow Box (OPENSTEP based), under Advanced Mac Look and Feel.*

## Windows Goals

- Full support for Windows NT and 95
- First class Windows citizen
  - Qualify for "Designed for Windows NT and Windows 95" Logo
- *Diagram: layers from bottom to top: Intel Based PC Hardware; Microsoft Windows 95/NT beside Java and Yellow Box (OPENSTEP based); Microsoft Windows Look and Feel across the top.*

## Windows Goals (cont.)

- True Windows look and feel
  - Windows dialog boxes
  - Drag & drop, cut & paste
  - TrueType fonts support
- OLE/COM and DCOM integration
- ActiveX support
- Use Yellow Box controls when they add value, otherwise use native controls

## Mac OS Goals

- First class Mac OS citizen
- True Mac OS look and feel
- Not completely defined yet! Stay tuned...
- *Diagram: layers from bottom to top: Power Macintosh, PowerPC Platform Hardware; Mac OS beside Java and Yellow Box (OPENSTEP based); Mac OS Look and Feel across the top.*

## Same Tools Across Platforms

- Project Builder
- Interface Builder
- EO Modeler
- Compilers

## The Development Cycle

- *Diagram: Code, with Mac UI, Rhapsody UI and Windows UI, leads to three Build steps. The left and right Builds are each followed by Bundle Yellow Box for Mac OS and Bundle Yellow Box for Windows respectively; the middle Build (Rhapsody UI) has no bundle step. All three merge into a Single SKU, which is Deployed to Mac OS, Rhapsody, Rhapsody for Intel, Windows 95 and Windows NT.*

## Distribution of Yellow Box Applications

- Applications easy to distribute
  - Single SKU for all platforms and all languages
- Yellow Box available everywhere
  - Yellow Box part of Rhapsody
  - Yellow Box free for Windows and Mac OS

## Avoiding the LCD Effect

- With other cross-platform solutions
  - Only a subset of native controls
  - Use of non-native controls
  - Applications work in a sand box
  - One UI often more prominent
  - Impact on speed

## Taking Advantage of Native Features

- Rhapsody/Mac OS
  - Integration with Finder
  - Support Mac file formats
- Windows
  - Pasteboard integration
  - OLE/COM
  - ActiveX
  - Access to Win32
  - Windows dialog boxes
  - Microsoft Windows logo

## Demo

- Build on Rhapsody for Intel
- Run on Rhapsody for Intel
- Build on Yellow Box for Windows
- Run on Windows NT
- Run on Windows 95

## Real World Demo

- *Caffeine Software TIFFany*
- Rhapsody for Intel
- Windows NT
