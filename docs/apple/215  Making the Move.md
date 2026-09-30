# 215  Making the Move

## Making the Move to Rhapsody

Jordan Dea-Mattson, Randy Nelson

## Making the Move to Rhapsody

A diagram shows the paths from Mac OS to Rhapsody: Mac OS leads to Allegro Tempo, which leads to the Blue Box; Mac OS also leads to Rhapsody along the path labeled Latitude; and Yellow leads to Yellow for Mac OS.

## Very Simple Text: MRD

The Market Requirements Document for the Very Simple Text application indicates it must:

- Break the 32K text limit
- Provide advanced typography support
  - Kerning, ligatures, variable baselines, drag and drop color
  - Graphic rulers; left, right, center and decimal tabs
  - Cut and paste font and paragraph attributes

## Very Simple Text: Nice-to-Haves

If possible, the application should also:

- Support multi-platform drag and drop graphics
- Support spell checking, using a shared, system-wide dictionary; support custom system and user dictionaries
- Provide integration with other applications; text and graphics should be available for use by other applications, like mail

## Getting Started

- Start up Project Builder
  - `/NextDeveloper/Apps/Project Builder`
- Create a new project, of the type Application
  - Save the project as "VerySimpleText"
- Click the Build button on the Project window: it brings up the Build panel
  - Click the Build panel's Build button

## First Test

- Click the Run button on the Project window: it brings up the Run panel
  - Click the Run panel's Run button
- We have a complete working Rhapsody application that does nothing, but does so gracefully

## Building the Interface

- Locate the interface file, found under Interfaces in the Project window
  - Double-click `VerySimpleText.nib`
- This launches Interface Builder
  - `/NextDeveloper/Apps/Interface Builder`
  - Interface Builder creates nib files: archives of initialized, connected objects that make up a user interface

## The About Box

- Locate the Palette panel
  - Select the Windows palette
- Drag a panel object into the workspace
  - This will be our About Box
- To change an object in Interface Builder, you can use direct manipulation
  - Click Interface Builder's resize control in the upper left corner of the panel's title bar
  - Resize the panel to an appropriate size and position

## Setting up the About Box

- You can also use an Inspector to change an object in Interface Builder
  - From Interface Builder's Tools menu, choose Inspector...
- The Inspector panel lets you change the currently selected object
  - In the Inspector's Attributes mode, change the Title attribute to "About Very Simple Text"

## Adding Text to the About Box

- Now, let's add some text to the About Box
  - Select the Views palette in the Palette panel
  - Drag a text object (it says "Title") from the Views palette into the panel
  - Resize it until you like its size and position
  - Double-click the text object and enter "Very Simple Text"
- Next, select the text object and copy it, then paste a copy back into the window
  - Change this text object to identify yourself as the author of the application

## Adding an Image to the About Box

- Now, let's get an image to add to the About Box
  - First, go to the file system by double-clicking the NeXT icon and locate an image
  - Drag an image from the file viewer into the Project window in Interface Builder
- Notice the integration between the file system, Interface Builder and Project Builder
  - Confirm that you want to add the image to the project
  - Double-click Interface Builder's icon to once again make it the current application
- Now, let's add the image to the About Box
  - Select the Data Views palette in the Palette panel
  - Drag an Image View into the panel
- Locate the Project window: it will be in its Images mode
  - Drag the image you just added onto the Image View in the panel

## Changing the Menu Item Text

- Next, let's change the text of the Info menu's Info Panel... menu item
  - Click on the main menu's Info menu, which will reveal its submenu
  - Select the "Info Panel..." text and replace it with "About Very Simple Text..."

## Connecting the Menu Item to the About Box

- Next, we'll connect a menu item to the About Box, so that when the user clicks the menu item, the About Box will be shown
  - Hold down the Control key and drag from the About Very Simple Text... menu item to the title bar of the About Box
- The Inspector changes to its Connections mode
  - Select `makeKeyAndOrderFront:` from the Actions that are listed
  - Click Connect in the Inspector to confirm that the menu should send the panel the `makeKeyAndOrderFront:` message

## Testing the About Box

- Let's test what we've done so far
  - Close the panel
  - Choose Test Interface from Interface Builder's Document menu
  - Click the About Very Simple Text... menu item, found in the Info menu
  - When you are done testing, choose Quit from the main menu
- In Interface Builder, save your work by choosing Save from the Document menu

## Building the Text Window

- Inspect the window
  - In its Size inspector, set minimum size to Current
- Go to the Data Views palette
  - Add a Scroll View containing a Text View
  - Resize the Scroll View to fill the window
- Inspect the Scroll View in Size mode
  - Set the Scroll View containing the Text View to resize when the window resizes
- Inspect the Scroll View in Attributes mode
  - Set Graphics Allowed

## Building the Main Menu

- Change the main menu's title
  - Select the main menu in the Project window
  - In the Attributes inspector, change its title to "VerySimpleText"

## Adding the Built-in Menus

- Set the Palette panel to the Menus palette
- Drag in the Document menu after Info
- Remove the Edit menu
  - Select it and press Delete
  - Drag in a new Edit menu after Document
- Drag in the Format menu after Edit

## Adding Custom Menu Items

- Drag in a generic menu item after Windows
  - Change its title to "Print..."
  - Add "p" as key equivalent

## Creating the Document Class

- Subclass `NSObject`
  - Set the Project window to its Classes mode
  - Select `NSObject`
  - Classes > Subclass
- Rename the subclass
  - Enter "Document" and hit Return
- Add an outlet, to point to the Text View
  - Rename it to "text"
- Add an action, to be sent by the Open... menu item
  - Rename it to `open:`
- Add an action, to be sent by the Save menu item
  - Rename it to `save:`

## Instantiating the Document Class

- Make an instance of the Document class
  - Select the Document class
  - Classes > Instantiate
- The icon for the new Document object appears in the Project window

## Connecting the Document Menu

- Connect the Open... menu item to Document's `open:` action
  - Control-drag from the Open... menu item to the Document object
  - Select `open:`
  - Click Connect
- Connect the Save... menu item to Document's `save:` action
  - Control-drag from the Save... menu item to the Document object
  - Select `save:`
  - Click Connect
- Connect the Print... menu item to the Text View's `print:` action
  - Control-drag from the Print... menu item to the Text View object inside the Scroll View
  - Select `print:`
  - Click Connect

## Connecting the Document Object to the Text View

- Connect the Document object's `text` outlet to the Text View
  - Control-drag from the Document object to the Text View object inside the Scroll View
  - Select `text`
  - Click Connect

## Creating Template Document Class Files

- Make class files from the template provided in the class description
  - Double-click the Document object in the Project window
  - Classes > Create Files
  - Confirm you want them added to the project
- Switch to Project Builder

## Implementing the open: Method

- Declare and instantiate the Open panel
  - `NSOpenPanel *openPanel = [NSOpenPanel openPanel];`
- Run the Open panel for rtfd documents, and test to see if the user cancelled
  - `if ([openPanel runModalForTypes: [NSArray arrayWithObject:@"rtfd"]]) {`
- If the user didn't cancel, have the Text View open the document using the filename the user provided
  - `[text readRTFDFromFile: [openPanel filename]];}`

Document's `open:` method:

```objc
- (void)open:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    if ([openPanel runModalForTypes:
            [NSArray arrayWithObject:@"rtfd"]]) {
        [text readRTFDFromFile: [openPanel filename]];
    }
}
```

## Implementing the save: Method

- Declare and instantiate the Save panel
  - `NSSavePanel *savePanel = [NSSavePanel savePanel];`
- Set the Save panel to save rtfd documents
  - `[savePanel setRequiredFileType:@"rtfd"];`
- Run the Save panel, and test to see if the user cancelled
  - `if ([savePanel runModal]) {`
- If the user didn't cancel, have the Text View write the document using the filename the user provided
  - `[text writeRTFDToFile: [savePanel filename] atomically: YES];`

Document's `save:` method:

```objc
- (void)save:(id)sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    if ([savePanel runModal]) {
        [text writeRTFDToFile: [savePanel filename]
                   atomically: YES];
    }
}
```

## Building the Application

- Bring up the Build panel by clicking the Build button on the Project window
  - Notice that Project Builder prompts for save, and notices unsaved edits in both Project Builder and Interface Builder
  - Click the Build button in the Build panel

## Running the Application

- Bring up the Run panel by clicking the Run button on the Project window
  - Click the Run button in the Run panel

## Testing the Application

- Open a file
  - Document > Open...
  - Open "test.rtfd"
- Change it
  - Enter the text "And again!"
- Save the changes
  - Document > Save...
  - Save as "newTest"

## MRD Check

- Break the 32K text limit
  - Open "bigYAP.rtfd"
- Provide advanced typography support
  - Format > Font > Font Panel...
  - Shift-click the Preview button
  - Select a font to preview
  - Enter text to preview in the text description field

## MRD Check

- Provide advanced typography support
  - Enter "Big Bigger"
  - Select "Big" (just double-click)
  - Change the font size to 50
  - Select "Bigger"
  - Enter 100.25 in the Size text field
  - Select all (triple click)
  - Enter -25 in the Size text field

## MRD Check

- Kerning
  - Enter "WOW"
  - Select "WO"
  - Format > Font > Kern > Tighten
- Ligatures
  - Enter "fight or flight"
  - Select the text
  - Switch the font between Helvetica and Times

## MRD Check

- Variable baselines
  - Enter "bounce"
  - Select "o"
  - Format > Font > Baseline > Raise
  - Select "u"
  - Format > Font > Baseline > Lower

## MRD Check

- Drag and drop color
  - Select text
  - Format > Font > Colors...
  - Drag a color swatch to the selection

## MRD Check

- Graphic rulers; left, right, center and decimal tabs
  - Format > Text > Show Ruler

## MRD Check

- Cut and paste font attributes
  - Select text of the desired font
  - Format > Font > Copy Font
  - Select text of the font to change
  - Format > Font > Paste Font
- Cut and paste paragraph attributes
  - Select text of the desired paragraph style
  - Format > Text > Copy Ruler
  - Select text of the paragraph style to change
  - Format > Text > Paste Ruler

## MRD Check

- Support multi-platform drag and drop graphics
  - TIFF, EPS, BMP
- Support spell checking, using a shared, system-wide dictionary; support custom system and user dictionaries
  - Edit > Spelling...
- Provide integration with other applications; text and graphics should be available for use by other applications, like mail
  - Select the text
  - Services > Mail > Selection

## Q & A
