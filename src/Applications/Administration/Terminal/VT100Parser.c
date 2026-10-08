#include "VT100Parser.h"

void vt100ParserInit(VT100Parser *parser, TerminalChunk *arguments)
{
    if (!parser)
        return;
    parser->arguments = arguments;
    parser->privateMode = 0;
    parser->collectingCSI = 0;
    parser->command = 0;
}

VT100ArgsResult vt100ParserBeginCSI(VT100Parser *parser,
                                    unsigned char firstByte)
{
    if (!parser)
        return VT100_ARGS_CONTINUE;
    vt100ArgsReset(parser->arguments);
    parser->privateMode = (unsigned char)(firstByte == '?');
    parser->collectingCSI = 1;
    parser->command = 0;
    if (parser->privateMode)
        return VT100_ARGS_CONTINUE;
    return vt100ParserConsumeCSI(parser, firstByte);
}

VT100ArgsResult vt100ParserConsumeCSI(VT100Parser *parser,
                                      unsigned char byte)
{
    VT100ArgsResult result;

    if (!parser || !parser->collectingCSI)
        return VT100_ARGS_CONTINUE;
    result = vt100ArgsConsume(&parser->arguments, byte, parser->privateMode);
    if (result != VT100_ARGS_CONTINUE) {
        parser->command = byte;
        parser->collectingCSI = 0;
    }
    return result;
}
