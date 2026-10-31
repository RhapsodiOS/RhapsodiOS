# 211 Application Framework

## Introduction to Yellow Box Application Framework

Ali Ozer, Manager, Yellow Box Application Frameworks

## Where Does It Fit?

Diagram: Application Framework on top of two boxes side by side, Display PostScript and Foundation Framework (the lower two are dimmed in the second build).

## What Is It?

- A full-featured, object-oriented, platform-independent framework for building applications
- AKA "AppKit"

## Topics

- Design principles
- Paradigms for extensibility
- Conventions for APIs
- Overview of classes
- What's there in 4.2
- What's coming up

## Design Principles

Simple things simple, complex things possible.

- Things should "just work"
- Factor common code out from applications
- Provide extensible and reusable objects
- Make the APIs easy to use
- Get the layers right
- Be pragmatic...

## Paradigms for Extensibility

- Subclassing
  - Basic way to extend most objects
  - Define primitives, override points
- Delegation
  - Allows one object to act on behalf of another
  - Extension without subclassing
  - Examples:
    - `NSWindow`'s `windowShouldClose:`
    - `NSSavePanel`'s `panel:shouldShowFilename:`
- Notification
  - Allows broadcasting of events to any interested object
  - Objects register for notifications based on type and posting object
  - Examples:
    - `NSWindowWillMiniaturize`, `NSWindowDidMiniaturize`
    - `NSApplicationWillTerminate`
  - Notifications are often available as delegate methods as well

## Conventions for APIs

- Return autoreleased objects
- Reuse concepts wherever possible
- Choose clarity over brevity
  - No abbrevs
- Make instance variables private
- Use exceptions for exceptional situations or programming errors

## Overview

- Drawing
- Event handling
- User interface
- Standard panels
- Data types and abstractions
- Services
- Internationalization

## Drawing

- `NSView`
  - Abstract class to handle drawing
  - Also provides event handling, dragging, printing/pagination, keyboard navigation, context sensitive menus, mouse tracking
  - Lives in hierarchies, one per window
  - Override `drawRect:` to customize drawing
  - Drawing often done buffered
- `NSWindow`
- AppKit abstractions, enough for most situations
  - `NSCell` `drawWithFrame:inView:`
  - `NSImageRep`, `NSString`, `NSAttributedString` `drawAtPoint:`, `drawInRect:`
  - `NSImage` `compositeToPoint:operation:`
  - `NSBezierPath` `stroke`, `fill`, `clip` (New in DR)
  - `NSColor`, `NSFont` `set`
- PostScript
  - `PSmoveto()`, `PSlineto()`

## Event Handling

- `NSEvent`, for low-level access
  - Look at the event stream or override `mouseDown:`, `keyDown:`, etc. in `NSView`
- Target/Action
  - Simple but powerful model for handling events on UI widgets
  - UI widgets send their target an action, with themselves as the single argument
  - A nil target implies that the action goes to the first responder
    - `cut:`, `copy:`, `paste:`, `close:`, `save:`, ...

## User Interface

- Consistent with the platform
- Created via Interface Builder, and stored in nib files as archived objects
- The nib file also contains target/action connections and other relationships
- Can have multiple nib files
- As with all resources, nib files can be customized for different platforms:
  - `MyApp.nib`
  - `MyApp-macintosh.nib`
  - `MyApp-windows.nib`

## User Interface Elements

- Simple widgets
  - `NSControl`, `NSButton`, `NSSlider`, `NSTextField`, `NSColorWell`, `NSImageView`, ...
- Complex widgets
  - `NSMatrix`, `NSMenu`, `NSComboBox`
  - `NSTableView`, `NSBrowser`, `NSOutlineView`
  - These display and edit complex data structures
  - They store no data; they talk to a `dataSource` to get the data lazily
- `NSTableView`
  - Tables of data
- `NSBrowser`
  - Hierarchical data, shown in columns
- `NSOutlineView` (New in DR)
  - Hierarchical data, shown hierarchically
- `NSTextView`
  - Front-end to the text system
  - Powerful, extensible, international
- `NSTextStorage`
  - Back-end
- `NSLayoutManager`
- `NSTextContainer`

(These slides show a screenshot of a text view with mixed English and Japanese text.)

- View groupers
  - `NSScrollView`
  - `NSSplitView`
  - `NSBox`
  - `NSTabView` (New in DR)
- Misc
  - `NSRulerView`
  - `NSProgressIndicator` (New in DR)

## Standard Panels

- Panels
  - Open/Save
  - Color
  - Font
  - Print, PageLayout
  - Fax
  - Spelling
- Accessory views allow extending the standard panels

## Data Type Abstractions

- `NSImage`, `NSImageRep`
  - EPS, TIFF, BMP, PICT, JPG, GIF
- `NSString`, `NSAttributedString`
  - Plain text in Unicode and other encodings, RTF, HTML
- `NSFont`
  - Type 1, TrueType
- `NSColor`
  - Various color spaces, patterns, ColorSync

## System Services

- `NSApplication`
- `NSWorkspace`
  - Interact with the Workspace
  - Obtain information about applications, document types, icons
- `NSFileWrapper`
  - Deal with documents stored as folders
- `NSPasteboard`
- Drag and Drop
- `NSSpellChecker`, `NSSpellServer`
- `NSInputManager`, `NSInputServer`
- Formatting and Validation
- Keyboard Navigation
- `NSKeyBindingManager` (New in DR)
  - Map keyboard sequences to actions
- Help
  - ToolTips
  - Context Help
  - Comprehensive Help

## Interapplication Services

- Allows extending the system via operations on data
  - Operations for installed services appear in the menus of applications
  - Slide shows a Services menu: AreaCode, Capitalize String, Chartsmith, Define in Webster, Grab, Graphity, HeaderViewer, Librarian, Mail, MailViewer (Mail Text, Mail To), Merge, OmniWeb, Open File

## Filter Services

- Convert files to formats recognized by the system
  - `NSPasteboard` `pasteboardByFilteringFile:` or `pasteboardByFilteringData:ofType:`
  - `NSImage` `initWithContentsOfFile:`, `imageFileTypes`
  - Soon on `NSAttributedString`

## Internationalization

- Unicode everywhere
- International text object
- Easily localizable

## What's There in 4.2

- Almost everything discussed so far
- Tools
  - Interface Builder, Project Builder
  - FileMerge, Yap, Terminal
  - Performance Tools
- Examples
  - `/NextDeveloper/Examples/AppKit`
- Documentation
  - Class reference and release notes (accessible through PB)

## Right Around the Corner...

- Macintosh UI
- Undo
- New user interface classes
- API additions to existing classes
- Internet data types (HTML, JPG, GIF)

## And Beyond...

- Java APIs
- Java Beans and (on Windows) ActiveX integration
- Scriptability
- More sophisticated text support
- More multi-thread safety
- Advanced UI

## Related Talks

Talks you hopefully went to:

- 209 Rhapsody Text System and Localization
- 212 Imaging Under Rhapsody

And talks you should go to:

- 208 Yellow Box Overview, Today 3:10, Room B
- 216 Developing with IB & PB, Tomorrow 10:50, Hall 1
- 405 Building Java-based Applications, Tomorrow 3:10, Room A2
- 207 Intro to Foundation Framework, Tomorrow 3:10, Room B
- 219 OpenStep: A View from the Trenches, Tomorrow 3:10, Hall 1
