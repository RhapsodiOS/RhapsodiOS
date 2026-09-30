# 208 Openstep Dev Overview

## OpenStep Developer API and Framework Overview

Jordan Dea-Mattson, Senior Evangelist, Rhapsody Evangelism

## Yellow Box Technical Overview

Peter Graffagnino, Director, Yellow Box Engineering

## What We'll Cover

- What is this Yellow Box thing?
- Guiding Principles
- Functional Overview
- Comparisons
- Opportunities

## Rhapsody Architecture

*Diagram: Applications on top; Blue Box and Yellow Box side by side beneath; Operating System at the bottom.*

## You Are Here...

*Same diagram with Yellow Box highlighted.*

## Some History and Terminology

- "NEXTSTEP"--NeXT's Mach based OS and frameworks, last release NEXTSTEP 3.3
- "OpenStep"--second generation of NEXTSTEP application framework
- "OpenStep for Mach 4.X"--successor releases to NEXTSTEP 3.3
- "OpenStep for Windows"--OpenStep frameworks on Windows NT/95

## ...And Now

NeXT Technology:

- OpenStep APIs
- Distributed Objects
- Enterprise Objects
- Web Objects
- Display PostScript

Apple Technology:

- QTML
- ColorSync
- GX Typography
- Advanced Look and Feel

## Yellow Box

Cross-Platform Application Substrate

- 100% "Buzzword" compliant
- Cross platform
- Object oriented
- Scalable
- Enterprise ready
- Media-rich
- Client/Server
- World ready
- Java-enabled

## Yellow Box Platforms

Yellow Box as a "Meta Platform" is highly portable:

- Rhapsody (Mach + BSD Unix)
- Windows NT
- Windows 95...
- Mac OS
- ????

## Guiding Principles

- Make developers more productive
- Visual development tools
- Powerful and consistent APIs
- Factor out common code from apps
- Integrate industry standard technologies
- Enable "ComponentWare"
- Make apps work well together

## Visual Development Tools

- Interface Builder
- Project Builder
- Enterprise Objects Modeler
- 3rd party tools (e.g., Metrowerks, Symantec, Roaster Technologies, etc.)

More info: "Developing with Interface Builder and Project Builder", Friday, 10:50, Hall 1

## Powerful and Consistent APIs

- Keep paradigms simple and synergistic
- Keep simple things simple
- Make complex things possible
- No "walls" or "cliffs"
- Consistent, meaningful naming
  - WIN32: `ERROR_SUCCESS`, `IUnknown`
  - Java: 30 methods named `add()`
- "Reusability" of paradigms
- Autorelease strategy

## Factor Common Code from Apps

- Applications should leverage the platform for common services
- Copy/paste of sample code is not reuse
- Faster development cycles
- More consistent user experience across applications
- Reduce maintenance burden on developers
- Platform can evolve to add value to applications
  - Systemwide fax support

More info: "Designing Objects for Reuse and Extensibility", Wednesday, 5:50, A-1

## Technology Integration

*Diagram, built up in stages: industry technologies feeding into Yellow Box frameworks.*

- ColorSync and PostScript feed into AppKit
- RTF, HTML, TIFF, EPS, JPG, GIF feed into AppKit
- Unicode feeds into AppKit and EOF
- Relational Databases feed into EOF
- Java, CORBA, and ActiveX feed into the Object Runtime
- QuickTime, QuickDraw 3D, and MPEG are also shown

## Enable "ComponentWare"

- Allow developers to leverage each other
- `NSBundle` API allows cross-platform code packaging, including localized resources
- Interface Builder palettes allow drag and drop application "parts"
- Java Beans
- ActiveX (Windows only)
- Enable custom "plug-in" architectures for applications (e.g., JavaBundle)

## Make Apps Work Well Together

- Rich set of industry standard datatypes
  - EPS, TIFF, RTF, HTML, GIF, Unicode, MPEG
- Rich set of data transfer services
- Multiple pasteboards
- Cross-platform drag and drop
- Services architecture
  - Menu for standard operations on data
- Filter services can extend datatypes through translation
- Scriptability "built-in"

## Yellow Box Functional Overview

*Diagram: boxes for Application Framework, Java Platform (highlighted, overlapping the Application Framework box), Display PostScript, and Foundation Framework.*

## Application Kit

- Presentation layer widgets
- "Pluggable" and native look and feel
- International text system
- Rich set of fundamental datatypes
- Data transfer services
  - Drag and drop, pasteboard
- Application Framework
  - More info: "Intro to OpenStep Application Framework", Thursday, 1:50, Hall 1
- International text system
  - More info: "Rhapsody Text System and Localization", Wednesday, 4:30, A-1

## Foundation Kit

- Collection classes (strings, arrays, dictionaries, etc.)
- Automatic memory management
- Operating system insulation
- File I/O, threads, tasks, etc.
- RunLoop and notification services
- Loadable component packaging
- Distributed objects

More info: "Intro to OpenStep Foundation Framework", Wednesday, 4:30, Hall 1

## Display PostScript WindowServer

- Client/Server graphics server
- PostScript imaging model
- Compositing used as generalized `Blit()`
- EPS is the structured graphics standard
- Any `NSView` can print, fax, or generate EPS

## Graphics and Imaging

More info:

- "Imaging Under Rhapsody", Wednesday, 5:50, Hall 1
- "Printing Under Rhapsody", Thursday, 3:10, Hall 1

## Java Application Integration

- Fully support 100% Pure Java code
- High performance VM and AWT/JFC implementation
- Native Yellow Box APIs will also be made available in Java
  - AppKit, Foundation, ...
- Write once, run on any Yellow platform (Mac OS, Windows NT/95, Rhapsody, ???)

More info: "Building Java-based Applications for Rhapsody", Friday, 3:10, Hall A-2

## Java and Object Runtimes

More info:

- "Uncommon Object Model: The Rhapsody Runtime", Thursday, 9:50, Room C
- "Object-Oriented Programming and Languages", Thursday, 11:10, Room C

## Enterprise Objects Framework

- Relational database to object mapping
- Database independent
- Scales to multi-tier client/server model
- Flexible transaction management

More info: "Enterprise Object Frameworks Overview", Friday, 10:50, Hall A-1

## Comparisons

- Mac Toolbox
- WIN32/MFC
- JavaSoft's "Java Platform"
- Apple's "Yellow Box Platform"

## Microsoft's WIN32/MFC

- Lots of shrinkwrap
- Not cross-platform
- Procedural, low-level APIs
- Objects are an afterthought
- Java viewed as a language only
- Built-in datatypes not cross-platform (BMP, GDI Metafiles, character encoding, etc.)

## JavaSoft's Java Platform

- Object APIs only
- Cross-platform, processor independent
- Procedural C-based APIs "impure"
- Not mature technology
- Performance and scalability concerns
- Fundamental datatypes lacking in certain areas (Rich Text, Structured Graphics, ...)
- Not ready for shrinkwrap

## Apple's Yellow Box Platform

- Superset of Java platform
- Highly portable implementation
- Mature, proven technology
- Object APIs primarily
- Procedural APIs OK, too!
- Wide variety of cross-platform datatypes
- Ready for shrinkwrap today
- Great basis for future innovation

## Opportunities

Use the best technology for the job:

*Diagram, built up in stages: Presentation Logic (Objective-C) on top; Application Core Logic: Modeling and Document Management (C++) beneath it; then Rendering Package (C) and Plug-ins (Java) side by side at the bottom.*

## Summary...

- Yellow Box is a robust, cross-platform application substrate
- Ready for shrinkwrap today

## Q&A
