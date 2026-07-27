from selector_check import source_methods


def _write(tmp_path, text):
    (tmp_path / "Sample.m").write_text(text)
    return {entry[0] for entry in source_methods(tmp_path)}


def test_comment_between_argument_and_keyword_is_not_read_as_the_keyword(tmp_path):
    """A `/* */` comment inside a wrapped selector must not become a keyword.

    The reference sources comment their arguments inline, so the comment sits
    between an argument name and the next keyword. Stripping parentheses alone
    leaves it in place, and the segment walk then reads `/*` as the keyword.
    """
    names = _write(tmp_path, """\
@implementation SCSITape
- (stInitReturn_t) initSCSITape:(int)iunit \t/* IODevice unit # */
    target:\t\t(u_char) stTarget
    lun:\t\t(u_char) stLun
    controller:\t\tcontrollerId
    majorDeviceNumber:\t(int) major
{
}
@end
""")

    assert names == {
        "-[SCSITape initSCSITape:target:lun:controller:majorDeviceNumber:]"
    }


def test_comment_before_a_trailing_keyword_is_not_read_as_the_keyword(tmp_path):
    names = _write(tmp_path, """\
@implementation SCSITape
- (sc_status_t) executeRequest: (IOSCSIRequest *)scsiReq
    buffer:(void *) buffer /* data destination */
    client:(vm_task_t) client
    senseBuf:(esense_reply_t *) senseBuf
{
}
@end
""")

    assert names == {"-[SCSITape executeRequest:buffer:client:senseBuf:]"}


def test_empty_keywords_are_preserved(tmp_path):
    names = _write(tmp_path, """\
@implementation Widget
- (id)initFromDeviceDescription:(id)d :(int)a :(int)b :(int)c
{
}
@end
""")

    assert names == {"-[Widget initFromDeviceDescription::::]"}


def test_selector_without_arguments(tmp_path):
    names = _write(tmp_path, """\
@implementation Widget
+ (BOOL)probe:(id)desc
{
}
- (void)free
{
}
@end
""")

    assert names == {"+[Widget probe:]", "-[Widget free]"}


def test_category_scopes_the_class_name(tmp_path):
    names = _write(tmp_path, """\
@implementation SCSITape ( private )
- (void)reserveAllLuns
{
}
@end
""")

    assert names == {"-[SCSITape(private) reserveAllLuns]"}


def test_nested_parentheses_in_an_argument_type(tmp_path):
    """Function-pointer arguments nest parentheses; the inner pair is not a type."""
    names = _write(tmp_path, """\
@implementation Widget
- (void)setCallback:(void (*)(int))handler context:(void *)context
{
}
@end
""")

    assert names == {"-[Widget setCallback:context:]"}


def test_semicolon_then_brace_method_definition_is_recorded(tmp_path):
    """NeXT-era GCC allows a ';' between a method signature and its body.

    AppleCuda's StartCudaTransmission: in cuda.m is written this way. This
    scanner mirrors source_map.py's `source_sites`, which had -- and no
    longer has -- the identical defect: it read the trailing ';' as ending a
    forward declaration and never yielded the definition that follows.
    """
    names = _write(tmp_path, """\
@implementation AppleCuda
- (void)StartCudaTransmission:(CudaRequest *)plugInMessage;
{
    return;
}
@end
""")

    assert names == {"-[AppleCuda StartCudaTransmission:]"}


def test_method_declaration_ending_in_semicolon_is_not_read_as_a_definition(tmp_path):
    """A `- foo;` declaration inside an @implementation has no body.

    Without a semicolon guard, the scan for the body brace runs past the
    declaration and swallows the next real method's signature along with it,
    producing one bogus merged entry and losing the real method entirely.
    source_map.py already guards against this with its `found_semicolon`
    check; selector_check.py must do the same.
    """
    names = _write(tmp_path, """\
@implementation Foo
- (BOOL)declOnly:(int)x;
- (void)realMethod:(int)y
{
}
@end
""")

    assert names == {"-[Foo realMethod:]"}


def test_declaration_does_not_reach_a_later_c_function_brace(tmp_path):
    """Only the *next* non-blank line may turn a ';' into a definition.

    A forward declaration followed by a non-boundary construct that later
    opens a brace -- here a C helper -- must not be read as a definition.
    Scanning on until any brace invents "-[Foo declaredOnly:]".
    """
    names = _write(tmp_path, """\
@implementation Foo
- (void)declaredOnly:(int)x;

static int helper(int a) {
    return a;
}

- (void)realMethod:(int)y
{
}
@end
""")

    assert names == {"-[Foo realMethod:]"}


def test_c_continuation_line_starting_with_a_sign_is_not_a_signature(tmp_path):
    """A wrapped arithmetic term at column zero looks like a signature.

    BMacEnetPrivate.m wraps sums that way. The trailing ';' is what stops
    the body search; without it "+ 2 * sizeof(IODBDMADescriptor) );" scans
    on to the next brace and yields "+[Foo 2]".
    """
    names = _write(tmp_path, """\
@implementation Foo
- (void)compute
{
    dbdmaSize = round_page( RX_RING_LENGTH * sizeof(enet_dma_cmd_t)
+ 2 * sizeof(IODBDMADescriptor) );
    /*
     * Allocate required memory
     */
    if ( !dmaCommands )
    {
        badFrameCount = ReadBigMacRegister(ioBaseEnet, kFECNT)
+ ReadBigMacRegister(ioBaseEnet, kAECNT)
+ ReadBigMacRegister(ioBaseEnet, kLECNT);
    }
}
- (void)realMethod:(int)y
{
}
@end
""")

    assert names == {"-[Foo compute]", "-[Foo realMethod:]"}
