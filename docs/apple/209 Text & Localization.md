# 209 Text & Localization

## Rhapsody Text System and Localization

- Ali Ozer, Yellow Box Application Frameworks
- Andy Daniels, Yellow Box Localization (International, Text and Graphics)

## Rhapsody Text System

Ali Ozer, Yellow Box Application Frameworks

## Text AND Localization?

Really, internationalization.

- Users want to be able to:
  - Create and exchange multilingual documents
  - Use any application in any language on any system
- Developers need to be able to:
  - Write applications that automatically work in any language
  - Localize applications easily and incrementally

## Text System Features

- International
- Powerful

## Text System: International Built-in

- Unicode characters in the backing store
- Character to glyph conversion for display
- Glyph reordering, required for displaying Indic scripts
- Inline input methods, for Asian language input

## Text System: Flexible

Flexible, for a wide range of uses.

- Multiple replaceable classes with public APIs
- Uses of the system:
  - Basic string drawing
  - User interface widgets
  - Simple word processing
  - Specialized text editing
  - High-end publishing

## Text System: Powerful

Powerful, with many out-of-the-box features.

- Multiple fonts, graphics, paragraph styles with ruler support
- Ligatures, kerning, diacritical marks, baseline adjustment
- Spelling checker, text services
- Background layout
- Copy/paste, read/write rich text

## NSString

- Stores an array of Unicode characters
- Provides rich functionality
- Allows conversion to and from other encodings
  - Uses the "default system encoding" to deal with untagged characters

## NSAttributedString

- Stores an `NSString` and arbitrary attributes on each character
- Keeps attributes in `NSDictionary`s (key/value pairs)
- Predefined attributes include: font, color, underline, kerning...
- Implementation and API optimized for runs of the same attributes

*Example: the string "HELLO WORLD" is built up with different attributes on "HELLO" and "WORLD".*

## Main Text Components

- `NSTextStorage`: stores the text as an attributed string
- `NSLayoutManager`: manages glyph generation and layout; stores glyphs and locations
- `NSTextContainer`: defines shapes into which glyphs are laid out
- `NSTextView`: gets and handles events, displays glyphs laid out by the layout manager

## Text System Configurations

- Common configuration: box of text (one text storage, one layout manager, one text container, one text view)
- Multiple containers: columns, pages, etc.
- Non-rectangular containers (custom)
- Multiple layouts: split views of the same text, etc.

## Related Classes

- `NSFont`, `NSFontPanel`, `NSFontManager`
  - Provides font metrics
  - Does character-to-glyph conversion
  - Supports Type 1, TrueType
- `NSInputManager`, `NSInputServer`
  - Manages input methods
- `NSTypesetter`
  - Lays glyphs out in line fragments
- `NSKeyBindingManager`
  - Converts key events to commands

## Event Propagation

Diagram, built up in nine numbered steps around the Text View:

1. Key Event arrives at the Text View
2. Key Event goes from the Text View to the KeyBinding Manager
3. Text input, commands go from the KeyBinding Manager to the Input Manager
4. Text input, commands go from the Input Manager back to the Text View
5. Insert/delete chars, change attributes go from the Text View to the Text Storage
6. Range changed goes from the Text Storage to the Layout Manager
7. Layout glyphs goes between the Layout Manager and the Typesetter
8. Region updated goes from the Layout Manager to the Text View
9. Display region goes from the Text View to the displayed text

## Event Propagation: Background Layout

Same diagram (Text View, Text Storage, Layout Manager, Typesetter), replayed in three passes over steps 6 to 9:

- 6 Range changed (Text Storage to Layout Manager)
- 7 Layout glyphs (Layout Manager and Typesetter), 8 Region updated (Layout Manager to Text View), 9 Display region (Text View to the page)
- Steps 7, 8 and 9 repeat for the remaining text, each pass displaying more lines of the page

## Future Directions

- HTML support
- Track and support popular font formats
- Provide advanced GX typography
- Do bidirectional and vertical scripts out of the box

## Yellow Box Localization

Andy Daniels

International, Text and Graphics

## Localization Support Features

- Multiple languages simultaneously
- Languages individually installable
- Language selection via user preferences
  - Not true dynamic switching
- Cross-platform

## Benefits: Reduced Footprint

Build animation: separate Code plus English, French and Japanese copies of the application, one per language, collapse into a single Code block with English, French and Japanese resources alongside it.

## Benefits: Simple Incremental Localization

- Easy to add and remove localizations
- User-installable
- Facilitates staggered releases

## Benefits: Multiple Switchable Localizations

- Switch via user preference
  - Ordered list of languages
- Different users on the same computer can work in their native language
- Perfect for multi-user installations
  - Multilingual offices, classrooms, language labs, even homes!

## Benefits: SKU Consolidation

- Flexibility
  - Packages based on market groupings
  - Add on as release schedule allows
- Cost
  - Reduced qualification effort
  - Lower cost of goods, lower inventory, simpler distribution, thus...
- Greater profitability!

## Demo

## Under the Covers

## Application Bundle

- Application is directory tree
  - Presented as single object by finder

Diagram: Code, English, French and Japanese blocks.

## Inside the Application Bundle

- Code and other resources
- Locale-specific pieces in `lproj` subdirectories
  - One `lproj` per language

Diagram: `MyApp.app/` contains `MyApp` (code) plus `English.lproj`, `French.lproj` and `Japanese.lproj`, each holding `Info.nib`, `Msg.strings` and `Image.jpg`.

## Typical Files in an lproj

- Nib, a super DITL
  - Window and dialog layout, labels, connections
- Strings file
  - Messages generated by the application
  - Key/value pairs
- Images, help files, html...

## Strings File

- Plain text
- Key/value pairs with comments
  - Keys are strings, not message IDs
- Can be generated from source code
  - `NSLocalizedString(key, comment)`

## Sample Strings File

```
/* Greeting for the user */
"Hello" = "Bonjour";

/* Version string (major.minor) */
"Release %d.%d" = "Version %d.%d"

/* Message indicating file couldn't be found */
"Couldn't open file %@." =
"Impossible d'ouvrir le fichier %@.";

/* Example showing argument reordering */
"%@, couldn't open file %@." =
"Impossible d'ouvrir le fichier %2$@ %1$@.";
```

## Installation

- Use standard Installer
- Package includes localized resources only

Diagram: an installer package adds English, French and then Japanese resources next to the existing Code.

## Aids to Localization

- Auto-generation of strings files
  - `NSLocalizedString(key, comment)` => `genstrings filenames`
- Locked mode in Interface Builder
  - Won't let you break connections
- "Check" mode for applications
  - `NSShowNonLocalizableStrings`
  - `NSShowNonLocalizedStrings`
- AppleGlot support coming

## What's There in OpenStep 4.2?

- Example source code
  - TextEdit, TextSizingExample, and Ruler in `/NextDeveloper/Examples/AppKit`
- Documentation
  - Class references, release notes
  - `/NextLibrary/Documentation/NextDev/TasksAndConcepts/ProgrammingTopics/TextOverview.rtfd`
- French and German Localizations

## For International Types at WWDC...

- Lunch with Apple's International Engineers
  - Thurs., 12:30-1:30, Hall 2, Find balloons!

## Q&A
