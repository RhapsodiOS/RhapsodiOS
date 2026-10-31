#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "../TerminalScreen.h"

int main(void)
{
    uint8_t wrappedRows[8] = { 0 };
    uint32_t firstRow;
    uint32_t lastRow;

    /* Walking back follows the preceding row's wrap flag, as PPC does. */
    wrappedRows[4] = 1;
    assert(terminalClearScrollbackRange(wrappedRows, 1, 8, 4, 1,
                                        &firstRow, &lastRow));
    assert(firstRow == 4);
    assert(lastRow == 5);

    /* The clicked row's flag extends forward, not backward. */
    wrappedRows[4] = 0;
    wrappedRows[5] = 1;
    wrappedRows[6] = 1;
    assert(terminalClearScrollbackRange(wrappedRows, 1, 8, 4, 1,
                                        &firstRow, &lastRow));
    assert(firstRow == 5);
    assert(lastRow == 7);

    /* A wrapped row above the visible screen does not extend the range. */
    wrappedRows[5] = 0;
    wrappedRows[4] = 1;
    wrappedRows[3] = 1;
    assert(terminalClearScrollbackRange(wrappedRows, 1, 8, 4, 1,
                                        &firstRow, &lastRow));
    assert(firstRow == 4);
    assert(lastRow == 5);

    puts("scrollback: ok");
    return 0;
}
