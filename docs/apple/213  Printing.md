# 213  Printing

## Printing Under Rhapsody

Paul Danbold, Yellow Print Team

Kurt Werle, Yellow Print Team

## What We'll Cover

- Printing on OpenStep today
  - AppKit
  - PrintKit
  - Spooling and print queues
- Printing on Rhapsody
  - What's going to change
  - What to expect for Premier and Unified

## Printing with the AppKit

AppKit classes: `NSPageLayout`, `NSPrintPanel`, `NSPrintInfo`, `NSPrintOperation`, `NSView`, `NSPrinter`.

## NSPageLayout

- Overhaul UI
- Format for... printer type
- PPD-based paper list
- Custom page sizes
- Show margins in thumbnail

## NSPrintPanel

- Overhaul UI
- List preferred printers
- More n-up options and borders
- PPD-based feature constraints
- Save as PDF, TIFF, JPEG, GIF, PNG

## NSPrintInfo

- printer
- name (letter, legal, A4, ...)
- size (height, width)
- orientation (portrait, ...)
- margins (left, right, ...)
- center (horizontal, vertical)
- scale
- n-up
- first, last page to print
- copies
- collate
- paper feed (input slot)
- disposition (print, fax, disk)
- ...

## NSPrintOperation

Generates a PostScript document with DSC comments, for example:

```
%!PS-Adobe-2.0
%%Title: (Rhapsody Demo)
%%Creator: (DemoApp: ...)
%%CreationDate: (2:15 PM ...)
%%For: (Paul Danbold)
%%Routing: (mailto:\ ...)
%%Pages: 1
%%DocumentFonts: Helvetica
%%DocumentNeededFonts: Helvetica ...
%%DocumentSuppliedFonts:
%%DocumentData: Clean7Bit
%%PageOrder: Ascend
%%Orientation: Portrait
...
```

## NSView

`NSView` generates the page content as PostScript, for example:

```
...
gsave
0 0 492 420 rectclip
1 nxsetgray
0 0 492 420 rectfill
/Helvetica findfont 12 selectfont ...
90
exch
defineuserobject
90 execuserobject setfont
0 nxsetgray
6 48 moveto (rhapsody) show
...
showpage
```

Planned changes:

- Optimize generated PostScript
- Update DSC comments
- Protect feature invocation code
- Support PS Level 3
- Support ColorSync

## NSPrinter

Parses the printer's PPD file, for example:

```
*PPD-Adobe: "4.3"
*% Adobe Systems Post ...
*% Copyright 1987-1996 ...
*% Apple Computer Inc
*% All Rights Reserved.
*% Permission is granted ...
*% End of Copyright statement
*FormatVersion: "4.3"
*FileVersion: "1.1"
*LanguageEncoding: ISOLatin1
*LanguageVersion: English
*PCFileName: "APLWMGS1.PPD"
*Manufacturer: "Apple"
*Product: "(LaserWriter)"
...
```

Planned changes:

- Save parsed PPD data
- Upgrade to PPD spec version 4.3
- Error handling for bad PPDs

## Demo

Kurt Werle, Yellow Print Team

## Spooling the Print Job

The slides show the paths a job takes:

- Printing to a direct connect printer
- Printing to a remote spooler
- Printing to a remote printer

A diagram of computers, printers and a network shows three paths: printing to a direct connect printer, printing to a remote spooler, and printing to a remote printer.

Four further diagrams show the flow through `AppKit`, `npd`, `lpr`, `lpd`, a spool directory and the PrintKit:

- Standard local spooling path (runs `prserver`): AppKit to `npd`, then `lpr`, then `lpd`, then PrintKit, which returns to `npd`. The spool directory sits between `npd` and `lpd`.
- Shortcut local spooling path (runs `prserver`): AppKit to `npd`, which talks to PrintKit directly in both directions; `lpr` and `lpd` are greyed out.
- Remote spooling path (runs `prserver`): AppKit to `npd`, `lpr`, `lpd`, then to an `lpd` on the remote machine, then the remote PrintKit and the remote `npd`, which returns to the original `npd`.
- Remote (final form) printing (runs `psprepare`): AppKit to `npd`, then PrintKit, then `lpr`, then `lpd`, with the spool directory between `npd` and `lpd`.

Planned changes:

- PAP server for Blue Box
- NBP support for Yellow Box
- Single-pass PS printing
- Queue management (drag and drop between queues, hold job in queue, reorder jobs, ...)

## NetInfo

A diagram of computers and printers on a network is shown beside the Print panel, with arrows from each printer in the diagram to its entry in the panel's printer list.

## NetInfo Printer Properties

- `sd`: name of the spool directory
- `lf`: name of error log file
- `lp`: device name to open for output
- `rm`: machine name for remote printer
- `sf`: name of output device
- `mx`: maximum file size
- ...
- `ty`: printer type (PPD)
- `name`: local printer name
- `sharedAs`: name of the exported printer
- `sharedTo`: domain in which printer is exported
- `note`: comment field (location)
- ...

## NetInfo (cont.)

- `DriverClass`: name of PrintKit driver
- ...
- `CommClass`: name of PrintKit comms subclass
- `CommType`: serial, parallel, TCPIP
- ...
- `CoverSheet`: print a cover sheet!
- ...

## PrintManager

The slides show PrintManager's printer list, and its Create New Printer panel (local name, remote name, host, communications type such as HP JetDirect, PPD selection, IP address). The panel slide is annotated with the PPD line `*NextDriver: "NXStyleWriter"`.

Planned changes:

- Rewrite it!
- Add AppleTalk support
- Auto bind PPDs
- Logical search for PPDs
- Extensible comms interface

## The PrintKit

`prserver` is responsible for:

- PostScript comment parsing
- Text to PostScript conversion
- PostScript rendering
- Printer communications
- Alerts for printing errors

## PrintKit Bundles

Include some or all of the following:

- Driver object
  - Class hierarchy: `NXFilter` has subclasses `NXPSFile`, `NXPSToFrames` and `NXPrintDriver`; `NXPrintDriver` has subclasses `NXRIPDriver` and `NXPSDriver`; `NXRIPDriver` has subclasses `NXColorBJ` and `NXNLPDriver`
- Communications object
  - Class hierarchy: `NXPrintComm` has subclasses `NXCBJSCSIComm`, `NXPSComm` and `NXSerialComm`; `NXPSComm` has subclasses `NXJetDirectComm`, `NXParallelComm` and `NXSerialPSComm`; `NXParallelPSComm` is a subclass of `NXParallelComm`
- PostScript initialization code
- NetInfo template
- PPD file

## PrintKit Planned Changes

- Download binary fonts
- Subset large fonts
- Better reporting of queue status
- NIB files for PPD features
- Handle >2-way feature constraints

## Fax

- Well integrated into the printing system
- Shares AppKit, spooling and PrintKit capabilities
- Fax driver, loaded by `prserver`, provides fax modem support

Planned changes:

- Support more fax modems
- Improve phone book support
- Enable faxing from the Blue Box

## Summary

A star chart rates printing from Poor to Excellent, first for OpenStep today, then for Rhapsody tomorrow.

OpenStep today:

- PostScript: 5 stars
- Raster: 3 stars
- Vector: half a star
- Fax: 3 stars

Rhapsody tomorrow keeps the same gold stars and adds extra stars, drawn as unfinished placeholder graphics: PostScript gains a partial sixth star, Raster gains two more (5 total), and Fax gains two more (5 total). Vector is unchanged at half a star.

## Contact Us

- rhapsody-dev-feedback@apple.com
- devsupport@apple.com
- http://www.devworld.apple.com/
