from pathlib import Path

from selector_check import source_methods


def test_nib_connector_implements_connection_state_and_coding_methods():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSNibConnector initialize]",
        "-[NSNibConnector init]",
        "-[NSNibConnector source]",
        "-[NSNibConnector setSource:]",
        "-[NSNibConnector destination]",
        "-[NSNibConnector setDestination:]",
        "-[NSNibConnector label]",
        "-[NSNibConnector setLabel:]",
        "-[NSNibConnector initWithCoder:]",
        "-[NSNibConnector encodeWithCoder:]",
        "-[NSNibConnector replaceObject:withObject:]",
        "-[NSNibConnector establishConnection]",
        "-[NSNibConnector dealloc]",
        "-[NSNibConnector instantiateWithObjectInstantiator:]",
    }
    assert selectors <= methods


def test_nib_connector_copies_labels_and_round_trips_both_archive_formats():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSNibConnector.m").read_text()

    setter = source.rsplit("- (void)setLabel:(NSString *)label", 1)[1].split("\n}", 1)[0]
    assert "[_label isEqual:label]" in setter
    assert "[_label release]" in setter
    assert "[label copyWithZone:[self zone]]" in setter

    decoder = source.rsplit("- (id)initWithCoder:(NSCoder *)coder", 1)[1].split("\n}", 1)[0]
    assert 'versionForClassName:@"NSNibConnector"' in decoder
    assert 'versionForClassName:@"NSNibConnector"] > 16' in decoder
    assert 'decodeValuesOfObjCTypes:"@@@"' in decoder
    assert 'decodeValuesOfObjCTypes:"@@*"' in decoder
    assert "initWithCString:label length:(unsigned)strlen(label) encoding:NSASCIIStringEncoding" in decoder
    assert "[_source retain]" in decoder
    assert "[_destination retain]" in decoder

    encoder = source.rsplit("- (void)encodeWithCoder:(NSCoder *)coder", 1)[1].split("\n}", 1)[0]
    assert 'encodeValuesOfObjCTypes:"@@@"' in encoder
    assert "&_source, &_destination, &_label" in encoder


def test_nib_connector_replaces_source_or_destination_by_identity():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSNibConnector.m").read_text()
    body = source.rsplit("- (void)replaceObject:(id)oldObject withObject:(id)newObject", 1)[1].split("\n}", 1)[0]
    assert "[self source] == oldObject" in body
    assert "[self setSource:newObject]" in body
    assert "[self destination] == oldObject" in body
    assert "[self setDestination:newObject]" in body
