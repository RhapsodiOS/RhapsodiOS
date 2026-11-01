from pathlib import Path

from selector_check import source_methods


def test_image_rep_registration_and_class_lookups_follow_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSImageRep registerImageRepClass:]",
        "+[NSImageRep unregisterImageRepClass:]",
        "+[NSImageRep registeredImageRepClasses]",
        "+[NSImageRep imageRepClassForFileType:]",
        "+[NSImageRep imageRepClassForPasteboardType:]",
        "+[NSImageRep imageRepClassForData:]",
        "+[NSImageRep canInitWithData:]",
    }
    assert selectors <= methods

    source = (appkit / "NSImageRep.m").read_text()
    assert "static NSMutableArray *imageHandlers;" in source
    assert "initWithCapacity:3" in source
    assert "NSImageRepRegistryDidChangeNotification" in source
    assert "_NSAppKitGlobalLock" in source
    assert "_NSAppKitLock(" in source
    assert "_NSAppKitUnlock(" in source
    assert "imageRepForType(type, @selector(imageUnfilteredFileTypes)," in source
    assert "imageRepForType(type, @selector(imageUnfilteredPasteboardTypes)," in source
    assert "performSelector:selector" in source
    assert "[types containsObject:type]" in source
    assert "canInitWithData:data" in source


def test_image_rep_type_lists_are_derived_cached_and_url_wrappers_are_file_only():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSImageRep imageUnfilteredFileTypes]",
        "+[NSImageRep imageUnfilteredPasteboardTypes]",
        "+[NSImageRep imageFileTypes]",
        "+[NSImageRep imagePasteboardTypes]",
        "+[NSImageRep imageRepsWithContentsOfURL:]",
        "+[NSImageRep imageRepWithContentsOfURL:]",
    }
    assert selectors <= methods

    source = (appkit / "NSImageRep.m").read_text()
    assert "static NSMutableDictionary *imageFileTypesTable;" in source
    assert "static NSMutableDictionary *imagePasteboardTypesTable;" in source
    assert "NSGetFileTypes([self imagePasteboardTypes])" in source
    assert "NSCreateFilenamePboardType(fileType)" in source
    assert "[NSPasteboard typesFilterableTo:type]" in source
    assert "[mutableTypes addObjectsFromArray:" in source
    assert "[url isFileURL]" in source
    assert "[url path]" in source
    assert "imageRepsWithContentsOfFile:" in source
    assert "imageRepWithContentsOfFile:" in source


def test_image_rep_file_loading_uses_registered_handler_and_filter_fallback():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSImageRep imageRepsWithContentsOfFile:]" in methods
    assert "+[NSImageRep imageRepWithContentsOfFile:]" in methods

    source = (appkit / "NSImageRep.m").read_text()
    assert "newDataOnImageFromFile(filename, classForImage)" in source
    assert "[filename pathExtension]" in source
    assert "[NSPasteboard pasteboardByFilteringFile:filename]" in source
    assert "[imageClass imagePasteboardTypes]" in source
    assert "[imageClass imageUnfilteredPasteboardTypes]" in source
    assert "imageRepClassForFileType:fileType" in source
    assert "@selector(imageRepsWithData:)" in source
    assert "@selector(imageRepWithData:)" in source
    assert "[data release]" in source


def test_image_rep_pasteboard_detection_and_loaders_follow_filter_order():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSImageRep canInitWithPasteboard:]",
        "+[NSImageRep imageRepWithPasteboard:]",
        "+[NSImageRep imageRepsWithPasteboard:]",
    }
    assert selectors <= methods

    source = (appkit / "NSImageRep.m").read_text()
    assert "firstObjectCommonWithArray:[imageClass imageUnfilteredPasteboardTypes]" in source
    assert "pasteboardByFilteringTypesInPasteboard:pasteboard" in source
    assert "propertyListForType:NSFilenamesPboardType" in source
    assert "[imageClass imageFileTypes]" in source
    assert "NSGetFileType(selectedType)" in source
    assert "initImageFromPasteboard(self, pasteboard, YES)" in source
    assert "initImageFromPasteboard(self, pasteboard, NO)" in source
