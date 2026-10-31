# 405 Java Rhapsody Apps

## Building Java-based Applications for Rhapsody

- Scott Forstall
- Manager, Java Application Technologies

## Take Home Points

- Apple is fully embracing Java
- Apple will provide the best platform to build and run Java apps
- Apple will provide all standard Java libraries
- Apple will open up the Yellow Frameworks to Java
- Apple will integrate the Yellow platform with the standard Java platform

## Java, Java, Java

Java is really three things:

- Language
- Virtual Machine (VM)
- Libraries

## Java the Language

- Full-featured and powerful
- Object oriented
- Garbage collected
- Dynamically dispatched
- Apple will provide a compiler for the language, but any standard Java compiler will work

## Java the Virtual Machine (VM)

Turns every machine into a Java machine.

- Java compiles into architecture-independent bytecodes
- The Java VM interprets bytecodes
- Java bytecodes run wherever VM runs
- VM provides security
- VM optionally compiles (JITs) code
- Apple will provide an optimized Virtual Machine

## Java the Libraries

- Foundation
  - String
  - Number
  - Dictionary
- UI: Abstract Windowing Toolkit (AWT)
  - Button
  - Window
  - Image
- Apple will provide all standard libraries

## How Will Apple Provide AWT?

Through Yellow Frameworks...

## Yellow Frameworks

Full-featured object-oriented frameworks for building apps

- Widgets: windows, buttons, text
- Events, fonts, graphics
- Drag and drop
- International text
- Printing support
- ColorSync
- QuickTime

The basis of Rhapsody and AWT.

## AWT on Rhapsody

- AWT is layered on the Yellow Frameworks (events, windows, graphics)
- AWT components such as Button use peers implemented in Objective-C on top of the Yellow Frameworks
- *Diagram (built up over several slides): AWT sits at the right above the Yellow Frameworks, with ObjC bracketing the Yellow Frameworks base at the left and "Events, Windows, Graphics" labelled on the Yellow Frameworks. Then AWT's Window and Button each connect down to a Window peer and Button peer in the Yellow Frameworks.*

## The Yellow Platform

All of Java plus all of Yellow

- *Diagram: the Yellow Frameworks base with an ObjC bracket at the left, a Java box above it beside an AWT box on the right, and IFC, AFC and JavaBeans stacked above AWT.*

## Why Settle for 7-Eleven?

- Yellow Frameworks add the functionality required by a full-featured desktop application
  - Drag and drop
  - Printing
  - Font support
  - ColorSync
  - International text
  - Scripting
  - QuickTime

## Let's Grow 7-Eleven into Safeway

- Apple is actively working with JavaSoft to improve AWT in the form of JFC

## The Yellow Platform in Java

Integration between Java and Objective-C opens up the platform.

- Access all Yellow Frameworks from Java
- Any program written to the Yellow Frameworks in Objective-C can now be written in Java
- Developer can write in Java, Objective-C, or a combination of both

## Is This Magic?

Java and Objective-C similarities enable integration:

- Similar object models
- Dynamically dispatched
- Comprehensive runtime information
- Single inheritance for classes
- Multiple inheritance for interfaces

## A Bridge to the 21st Century

- Bi-directional Java/Objective-C bridge
  - Message Objective-C from Java
  - Message Java from Objective-C
  - Subclass Objective-C classes in Java
- Tools available to help create cross-language bindings
- Provide new Java APIs in Objective-C through Modern Objective-C syntax

## Is It a Toll Bridge?

*Usage patterns determine performance*

- Some performance cost for crossing bridge
- Execution that remains on one side performs at native speed
- Apple researching many ways to improve performance

## Cross-Platform with Single Executable

- Yellow Frameworks are cross-platform
  - Rhapsody
  - Mac OS
  - Windows 95
  - Windows NT
- Java is cross-platform
- Yellow Box apps written in Java are cross-platform without recompilation

## Cross-Platform Yellow Box

- *Diagram: a Rhapsody, Mac OS, Win95, WinNT bar at the bottom, with the Yellow Frameworks above it. ObjC brackets the frameworks' left; a Java box, topped by JavaBeans, sits in the middle. AWT is on the right, topped by IFC and AFC and then JavaBeans.*

## Can't We All Just Get Along?

*Java, Yellow Frameworks and AWT can!*

- Apple will tightly integrate AWT, Beans, and Yellow Frameworks
- JavaBeans will live as first-class citizens in Yellow apps
- Developer tools will support Java
  - Java editing and debugging
  - Interface Builder support for JavaBeans

## Demo

What? You Don't Believe Me?

## How It Works

- *Diagram: three columns, Objective-C, Bridge and Java, with a temperature converter example:*
  1. Objective-C: user enters Fahrenheit
  2. Across the bridge: `convert()` is called in Java
  3. Java gets Fahrenheit; the bridge returns the user input from Objective-C
  4. Java computes Celsius and sets Celsius
  5. Objective-C displays Celsius

## Thank You and Good Night

More Take Home Points:

- Apple will provide complete JDK
- Access Yellow Frameworks through Objective-C or Java
- Choose
  - JDK platform
  - Yellow Frameworks
  - Integrate best technologies of each to produce best applications
