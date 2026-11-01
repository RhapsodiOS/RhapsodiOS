from pathlib import Path

from selector_check import source_methods


def test_bitmap_image_rep_state_and_metadata_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSBitmapImageRep initialize]",
        "+[NSBitmapImageRep imageUnfilteredFileTypes]",
        "+[NSBitmapImageRep imageUnfilteredPasteboardTypes]",
        "+[NSBitmapImageRep canInitWithData:]",
        "-[NSBitmapImageRep isPlanar]",
        "-[NSBitmapImageRep samplesPerPixel]",
        "-[NSBitmapImageRep bitsPerPixel]",
        "-[NSBitmapImageRep bytesPerRow]",
        "-[NSBitmapImageRep bytesPerPlane]",
        "-[NSBitmapImageRep numberOfPlanes]",
        "-[NSBitmapImageRep getBitmapDataPlanes:]",
        "-[NSBitmapImageRep bitmapData]",
        "-[NSBitmapImageRep setCompression:factor:]",
        "-[NSBitmapImageRep getCompression:factor:]",
        "-[NSBitmapImageRep valueForProperty:]",
        "-[NSBitmapImageRep setProperty:withValue:]",
        "-[NSBitmapImageRep canBeCompressedUsing:]",
        "-[NSBitmapImageRep prepareGState]",
        "-[NSBitmapImageRep _canDrawOutsideOfItsBounds]",
        "-[NSBitmapImageRep _freeImage]",
        "-[NSBitmapImageRep dealloc]",
    }
    assert selectors <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "[self setVersion:17]" in source
    assert "_moreRepFlags.isPlanar" in source
    assert "_moreRepFlags.bitsPerPixel" in source
    assert "_moreRepFlags.numColors" in source
    assert "[self hasAlpha]" in source
    assert "_bytesPerRow * [self pixelsHigh]" in source
    assert "_properties = [[NSMutableDictionary alloc] initWithCapacity:1]" in source
    assert "_moreRepFlags.compression = compression" in source
    assert "_moreRepFlags.compressionFactor = (int)factor" in source
    assert '@"tiff", @"TIFF", @"TIF"' in source
    assert "NSTIFFPboardType" in source
    assert "freeVm(planeData[i], bytesPerPlane)" in source
    assert "NSZoneFree(NSZoneFromPointer(_data), _data)" in source
    assert "[_tiffData release]" in source
    assert "compression == NSTIFFCompressionCCITTFAX3" in source
    assert "compression == NSTIFFCompressionJPEG" in source
    assert "bytes[0] == 'I' || bytes[0] == 'M'" in source
    assert "bytes[0] == 'G'" in source
    assert "bytes[0] == 137" in source
    assert "bytes[9] == 'F'" in source
    assert "return NO;" in source


def test_bitmap_image_rep_returns_reference_tiff_compression_types():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSBitmapImageRep getTIFFCompressionTypes:count:]" in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "bitmapTIFFCompressionTypes[]" in source
    expected = [
        "NSTIFFCompressionNone",
        "NSTIFFCompressionLZW",
        "NSTIFFCompressionJPEG",
        "NSTIFFCompressionPackBits",
        "NSTIFFCompressionCCITTFAX3",
        "NSTIFFCompressionCCITTFAX4",
    ]
    positions = [source.index(value, source.index("bitmapTIFFCompressionTypes[]")) for value in expected]
    assert positions == sorted(positions)
    assert "*numTypes = 6" in source


def test_private_image_reader_base_owns_lazy_plane_loading():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSImageReader initWithData:]",
        "-[NSImageReader loadImageHeader]",
        "-[NSImageReader loadImage:]",
        "-[NSImageReader bitmapDataPlanes]",
        "-[NSImageReader numberOfPlanes]",
        "-[NSImageReader bytesPerPlane]",
        "-[NSImageReader dealloc]",
    }
    assert selectors <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "loadError = ![self loadImage:planes]" in source
    assert "NSZoneMalloc([self zone], bytesPerPlane)" in source
    assert "[self loadImage:planes]" in source
    assert "data = nil" in source
    assert source.count("NS_DURING") >= 2


def test_bitmap_image_rep_validates_and_owns_bitmap_planes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert (
        "-[NSBitmapImageRep initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:"
        "samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:]"
    ) in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "validateBitmapParams(width, height, bps, spp, pixelBits" in source
    assert "planes[0] != NULL" in source
    assert "NSZoneCalloc([self zone], 5, sizeof(unsigned char *))" in source
    assert "_moreRepFlags.memory = 1" in source


def test_bitmap_image_rep_initializes_from_private_reader():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSBitmapImageRep _initWithImageReader:]" in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "[reader pixelsWide]" in source
    assert "[reader colorSpaceName]" in source
    assert "[self getBitmapDataPlanes:planes]" in source
    assert "[reader loadImage:planes]" in source


def test_bmp_reader_parses_headers_and_converts_supported_pixel_depths():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSBMPImageReader initWithData:DIBFormat:]",
        "-[NSBMPImageReader getByte]",
        "-[NSBMPImageReader getLEWord]",
        "-[NSBMPImageReader getLELong]",
        "-[NSBMPImageReader loadBitmapFileHeader]",
        "-[NSBMPImageReader loadBitmapInfoHeader]",
        "-[NSBMPImageReader loadImageHeader]",
        "-[NSBMPImageReader loadImage:]",
        "-[NSBMPImageReader numberOfPaletteEntries]",
        "-[NSBMPImageReader numberOfSamplesPerPaletteEntry]",
        "-[NSBMPImageReader palette]",
        "-[NSBMPImageReader dealloc]",
    }
    assert selectors <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "NSBadBitmapParametersException" in source
    assert "actualBitsPerPixel == 4" in source
    assert "actualBitsPerPixel == 8" in source
    assert "actualBitsPerPixel == 16" in source
    assert "actualBitsPerPixel == 24" in source
    assert "actualBitsPerPixel == 32" in source
    assert "@implementation NSBMPImageReader" in source
    assert "[super dealloc]" in source


def test_bitmap_image_rep_dispatches_bmp_data_through_reader():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSBitmapImageRep imageRepsWithData:]",
        "+[NSBitmapImageRep imageRepWithData:]",
        "+[NSBitmapImageRep _imagesWithData:zone:]",
    }
    assert selectors <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "DetermineImageDataFormat(data)" in source
    assert "format == 2" in source
    assert "format == 3" in source
    assert "initWithData:data DIBFormat:NO" in source
    assert "_initWithDIB:data" in source
    assert "_initWithImageReader:reader" in source


def test_bitmap_image_rep_has_gif_reader_and_dispatch_path():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSGIFImageReader loadImageHeader]",
        "-[NSGIFImageReader loadImage:]",
        "-[NSGIFImageReader colorTable]",
        "-[NSGIFImageReader setImageNumber:]",
    } <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "@implementation NSGIFImageReader" in source
    assert "format == 5" in source
    assert "gifReadFrame" in source
    assert "gifFrameCount" in source
    assert "for (frameNumber = 0; frameNumber < frameCount; ++frameNumber)" in source


def test_bitmap_image_rep_initializes_dib_data_through_reader():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSBitmapImageRep _initWithDIB:]" in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "initWithData:dibData DIBFormat:YES" in source
    assert "[self _initWithImageReader:reader]" in source


def test_bitmap_image_rep_decodes_png_through_reader():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSPNGImageReader loadImageHeader]",
        "-[NSPNGImageReader loadImage:]",
    } <= methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "@implementation NSPNGImageReader" in source
    assert "format == 6" in source
    assert "inflatePNGImage" in source
    assert "uncompress(raw" in source
    assert "passCount = info.interlace ? 7 : 1" in source
    assert "pngCorrectSample" in source
    assert "fileGamma * 2.222" in source
    assert "LIBS = -lz -lm" in (appkit / "Makefile.preamble").read_text()


def test_bitmap_image_rep_init_with_data_returns_first_decoded_rep():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSBitmapImageRep initWithData:]" in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    assert "_imagesWithData:copy zone:zone" in source
    assert "[images count] == 0" in source
    assert "[[images objectAtIndex:0] retain]" in source


def test_bitmap_image_rep_localizes_tiff_compression_names():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSBitmapImageRep localizedNameForTIFFCompressionType:]" in methods

    source = (appkit / "NSBitmapImageRep.m").read_text()
    for label in (
        "Lempel-Ziv & Welch",
        "CCITT Group 3",
        "CCITT Group 4",
        "Obsolete NeXT 2bit",
        "Obsolete JPEG",
    ):
        assert label in source
    assert 'table:@"TIFFCompression"' in source
