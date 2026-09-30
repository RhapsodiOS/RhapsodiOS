# 210 Rhapsody User Exp

## Rhapsody User Experience

Kurt Piersol, Rhapsody UE Lead

## The Rhapsody Look and Feel

The best of all worlds.

- Much like Mac OS look and feel
- New ideas from OpenStep
- A few ideas from other platforms

## Rhapsody Windows, Menus, Controls

Demo.

## Key Points

- Scrolling much improved
  - Live scroll, proportional thumbs
- Mac menu bars, with additions
  - Tear-offs, context menus
- Window behavior improved
  - Layers
  - Resize
  - Live drag

Screenshot: an UNTITLED.rtf window reading "Kurt: Hey! This thing looks a lot like a Mac! How'd they do that?" "Arlo: The scroll bars look a little different, but overall the thing looks pretty nice." "Ali: You're surprised? Hey, why did you buy us if you thought we couldn't deliver?"

## Rhapsody Finder

No demo.

## Rhapsody Finder Features

Mostly, the Mac OS Finder

- Multiple windows
- Drag to the desktop
- Icon view
  - Pixel level positioning
  - 32x32 icons
- List view
  - Twisty triangles
  - Resizable, reorderable columns

## Rhapsody Finder Features

An OpenStep style browser

- Browsers are cool too
- Much like today's OpenStep browser
  - Multiple panes
  - Shelf
  - Path
- Available as a menu item

## Rhapsody Finder Features

Extensible and replaceable

- Why settle for Apple's browsers?
- You can write plug-ins
  - No current schedule for a specification
  - Feature in Unified release
- Viewers will be separate applications
  - Not for just the file system anymore

## Finder for Developer and Premier Releases

- For Developer
  - Small delta from OpenStep Workspace
- For Premier
  - Incremental changes
- Unified
  - The full, extensible experience

## Other Experience Elements

A grab bag

## File Types and Creators

Buttons shown: Type and Creator, Extension.

- We will preserve this experience
  - Files will have the equivalent of types and creators, but some file systems simply can't support this
- File extensions (.txt, .html) will be a fall back position
  - Better than Mac OS experience, though
- Limited support in Premier, full by Unified

## Help System

- HTML Based
  - Build with relative references
  - Links to Internet based help, other sources
- Powerful navigation
  - Link or search
- Incremental approach to task-based help
  - Layered on HTML
- Basic system in place by Premier

## Internet/Intranet Integration

- Integrated with Rhapsody Finder architecture
  - Extensible and replaceable
  - Desktop URLs, etc.
- Includes Internet, intranet, and LAN
- Internet data types as first class citizens
  - Text object handles HTML
- First instances by Premier

## Installation

- Rhapsody has its own SDK and installer
- Rhapsody has built-in uninstall
- Upgrader capability as well

## Mac OS Integration

The hard part

## The Big Picture

There's two computers in there

- Mac OS and Rhapsody almost completely separate
- We've argued about this
  - We think there is no ideal solution
  - We made the tough call

Diagram: an Advanced Mac Look and Feel bar across the top; below it Mac OS Blue Box on the left, and Yellow Box on the right with Java as a notch at its lower left; then Core OS; then Power PC.

## Why Separate the Environments?

Rule #1: Avoid Hidden Modes!

- If you can't provide seamless integration
- Make the mode switch obvious

## Basic Rules for Integration

- Don't change modes unexpectedly
- Don't hide differences that make a difference
- Don't make the user guess what changed

## Shared System Elements

- Shared
  - The file system (partial)
  - The clipboard
  - The screen (partial)
  - The fonts
- Not shared
  - The Finder

## The File System

- Mac OS sees a series of volumes: shared, disk image, partitions
- Shared
  - Each side can see all files in shared directories
  - Tend to hide inappropriate files
    - Separate directories for the different environments
    - Other directories made less obvious

## The File System (cont.)

- Special compatibility modes for Mac OS
  - Mac OS partitions, disk images
    - Files not shared with Rhapsody in general
    - More compatible with direct SCSI manager calls, disk utilities, etc.
  - A setup panel will let users choose how to share file systems

## Screen Sharing

Two modes

- Mac OS takes over screen
  - Hot key switching
  - Rhapsody entry appears on process menu
  - Switching is never a "side effect"
  - Fastest, most compatible mode
- Mac OS "in a box"
  - Box is a Rhapsody window
  - Dragging stops at box boundary

## Other Shared Elements

As few as possible

- Still some important ones
  - System time
  - Fonts
  - Clipboard

## Two Finders

One in each environment

- The only way to get both compatibility and stability
  - Many applications, extensions, and scripts depend on Mac OS Finder
  - Mac OS Finder vulnerable to other program's mistakes
- Two Finders reinforces the separated model
  - Separate icons depending on which Finder sees item

## The Network

- Each environment presents its own view
  - Not all network protocols there on each side
  - Rhapsody won't have a Chooser

## Summary

- New advanced look and feel for Rhapsody
  - Best of all worlds
  - Stable, extensible, high performance
- Mac OS compatibility
  - Highly compatible
  - Distinctly separate
