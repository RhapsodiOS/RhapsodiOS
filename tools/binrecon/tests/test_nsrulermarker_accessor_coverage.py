from pathlib import Path

from selector_check import source_methods


def test_ruler_marker_attribute_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSRulerMarker ruler]",
        "-[NSRulerMarker initWithRulerView:markerLocation:image:imageOrigin:]",
        "-[NSRulerMarker copyWithZone:]",
        "-[NSRulerMarker dealloc]",
        "-[NSRulerMarker markerLocation]",
        "-[NSRulerMarker setMarkerLocation:]",
        "-[NSRulerMarker image]",
        "-[NSRulerMarker setImage:]",
        "-[NSRulerMarker imageOrigin]",
        "-[NSRulerMarker setImageOrigin:]",
        "-[NSRulerMarker isMovable]",
        "-[NSRulerMarker setMovable:]",
        "-[NSRulerMarker isRemovable]",
        "-[NSRulerMarker setRemovable:]",
        "-[NSRulerMarker isDragging]",
        "-[NSRulerMarker representedObject]",
        "-[NSRulerMarker setRepresentedObject:]",
        "-[NSRulerMarker thicknessRequiredInRuler]",
        "-[NSRulerMarker _originPointInRuler]",
        "-[NSRulerMarker _compositePointInRuler]",
        "-[NSRulerMarker imageRectInRuler]",
    }
    assert expected <= methods

    source = (appkit / "NSRulerMarker.m").read_text()
    assert "return _ruler;" in source
    assert "_ruler = ruler;" in source
    assert "_location = markerLocation;" in source
    assert "_image = [image retain];" in source
    assert "_rFlags.movable = YES;" in source
    assert "[_image release];" in source
    assert "[_representedObject release];" in source
    assert "[super dealloc];" in source
    assert "NSCopyObject(self, 0, zone)" in source
    assert "copy->_image = [_image retain];" in source
    assert "copy->_representedObject = [_representedObject copyWithZone:zone];" in source
    assert "return _location;" in source
    assert "_location = markerLocation;" in source
    assert "return _image;" in source
    assert "_image = [image retain];" in source
    assert "return _imageOrigin;" in source
    assert "_imageOrigin = imageOrigin;" in source
    assert "return _rFlags.movable;" in source
    assert "_rFlags.movable = movable;" in source
    assert "return _rFlags.removable;" in source
    assert "_rFlags.removable = removable;" in source
    assert "return _rFlags.dragging;" in source
    assert "return _representedObject;" in source
    assert "_representedObject = [representedObject copy];" in source
    assert "return [_image size].height - _imageOrigin.y;" in source
    assert "[[_ruler clientView] convertPoint:clientPoint toView:_ruler]" in source
    assert "[_ruler baselineLocation]" in source
    assert "[_image isFlipped] == [_ruler isFlipped]" in source
    assert "NSMakeRect(origin.x, origin.y, imageSize.width, imageSize.height)" in source
