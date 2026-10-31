# 206 Intro to OOP

## Object Oriented Programming and Languages

- Jordan Dea-Mattson, Senior Evangelist, Rhapsody Evangelism
- Steve Naroff, Senior Technologist, Rhapsody Development Tools

## Session Topics

- Object Oriented Concepts
- Language Requirements
- Language Support
- Closing Thoughts

## Object Oriented Concepts

- Object, surrounded by four concepts: Encapsulation, Modularity, Polymorphism, Hierarchy
- Abstraction encompasses all of them

## Language Requirements

Religion (circa '87)

- Dynamic Object Model
  - Serve application frameworks and tools
- Easy to Learn
  - "Less is more" principle
- Small footprint
  - Code and meta-data must be shared
- Smooth integration with ANSI-C/C++
  - Embrace legacy code

## Dynamic Object Model

Distinctive features

- Introspection
  - All objects are self-describing
- Release-to-release binary compatibility
  - No need to relink client applications
- Message forwarding
  - Integration with other object models
- C-based API/ABI fully specified
  - CodeWarrior modules link painlessly!

## Language Support

- Objective-C
- Objective-C++
- Java
- Dylan?
- Object Pascal?

## Objective-C Type Declarations

Classes: implementation reuse

```objc
@interface NSBrowser : NSControl
{
    <instance variables>
}
<methods>
@end
```

Protocols: design reuse

```objc
@protocol NSDraggingInfo
<methods>
@end
```

## Objective-C Object Declarations


```objc
// untyped
id anyObject;

// typed by class
NSBrowser *myBrowser;

// typed by protocol
id <NSDraggingInfo> aDrag;
```

## Objective-C Method Declarations

Classic syntax

```objc
// instance methods
- (void)setTitle:(NSString *)title ofColumn:(int)column;
- (void)setDelegate:anObject;
- (void)setAction:(SEL)action;

// class methods
+ (Class)cellClass;
+ (void)setCellClass:(Class)creator;
```

Modern syntax

```objc
// instance methods
void setTitleOfColumn(NSString *title, int column);
void setDelegate(id anObject);
void setAction(SEL name);

// class methods
static Class cellClass();
static void setCellClass(Class creator);
```

## Objective-C Method Categories

Binary extensions

```objc
@interface NSString(NSStringDrawing)
NSSize size()
void drawAtPoint(NSPoint p);
void drawInRect(NSRect r);
@end
```

## Objective-C Message Expressions

```objc
// classic
[myBrowser setDelegate:obj];

// modern
myBrowser->setDelegate(obj);
myBrowser.setDelegate(obj);
```

## Objective-C++

What role does it play in the Yellow Box?

- C++ access to Yellow Box APIs
  - Header files are "C++ aware"
- Embrace the next generation(s) of C
  - Legacy code
- Objective-C able to access "C++ goodies"
  - Declarations as statements
  - Exceptions
  - Etc.

## Objective-C++: Peaceful Coexistence

- Both languages retain...
  - Native semantics
  - Native time/space characteristics

## Objective-C++: CodeWarrior

Does CodeWarrior support it?

- YES!

## Objective-C++ Example

Reuse via aggregation

```objc
@interface CalculatorInterface : NSObject
{
    id display;
    CalculatorEngine *engine;
}

id init();
id equalsKey(id sender);
id operationsKey(id sender);
@end
```

```objc
id init() // display is set automatically
{
    engine = new CalculatorEngine;
    return self;
}

id operationKeys(id sender)
{
    res = engine->computeResult(sender);
    display->setDoubleValue(res);
    return self;
}
```

## Java Integration

Design points

- Exploit similarities with Objective-C
- Work with standard Java language tools
  - No special language/compiler magic
- Leverage "best of breed" JVM technology
  - Sun, Microsoft, Apple, Metrowerks, etc.
- Allow hybrid interaction
  - Aggregation and subclassing

Full client access to Yellow Box APIs

```java
public class Browser extends Control
{
    public Browser(Rect frameRect);
    public native void setDelegate(Object o);
    public native void setAction(Selector s);
    public native boolean setPath(String p);
    public native Array selectedCells();
}
```

Diagram (built up over several slides):

- Objective-C: Dynamic Runtime
- Java: Virtual Machine, with Native Stubs inside it
- Bridge between the two; one arrow goes from the Native Stubs across the Bridge to the Dynamic Runtime, and another from the Dynamic Runtime across the Bridge to the Virtual Machine

## Java Mappings

Diagram (built up over several slides), Objective-C type to Java type:

- `short` to `short`
- `int` to `int`
- `long` to `int`
- `unsigned` to `int`
- `BOOL` to `boolean`
- `char` to `byte`
- `float` to `float`
- `double` to `double`

Object types:

- `id` to `java.lang.Object`
- `SEL` to `apple.core.Selector`
- `NSString *` to `java.lang.String`
- `NSNumber *` to `java.lang.Number`
- `<class> *` to `<class>`

## Java Integration: How Does It Work?

- Types that don't map automatically
  - Non-object pointer usage
  - Structures, unions, and enums
  - Typedefs
- Java enabled Objective-C objects
  - Descendents of `apple.core.id`
  - Subclassing "just works"

## Java to ObjC Bridge Specification

`.jobs` file:

```
type
  BOOL = boolean
  NSRect = apple.core.Rect using
           NSConvertRectToJava
           NSConvertRectFromJava
selector
  -isEqual: = equals
  -hash = hashCode
  -copyWithZone: = clone
```

Diagram (built up over several slides): the `.jobs` file is processed by `bridget`, which generates Java client classes and Native stub functions.

## Closing Thoughts

Language choices

- Dynamic
  - Over static
- Diversity
  - Over purity
- Performance
  - Over purity
- Pragmatic solutions

## Q&A
