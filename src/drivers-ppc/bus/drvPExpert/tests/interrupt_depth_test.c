#include <stdio.h>

#include "../powermac/interrupt_depth.h"

static int failures;

#define CHECK(expr) do { \
    if (!(expr)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        failures++; \
    } \
} while (0)

int
main(void)
{
    unsigned int depth = 0;
    unsigned int mark;
    const int external = 0x500;
    const int decrementer = 0x900;

    CHECK(!PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthEnter(&depth));
    CHECK(PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthEnter(&depth));
    CHECK(PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthLeave(&depth));
    CHECK(PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthLeave(&depth));
    CHECK(!PEInterruptDepthActive(depth));
    CHECK(!PEInterruptDepthLeave(&depth));
    CHECK(depth == 0);
    depth = ~0u;
    CHECK(!PEInterruptDepthEnter(&depth));
    CHECK(depth == ~0u);

    depth = 0;
    CHECK(!PEInterruptDepthEnterException(&depth, 0x300,
        external, decrementer));
    CHECK(!PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthEnterException(&depth, external,
        external, decrementer));
    CHECK(PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthLeave(&depth));
    CHECK(PEInterruptDepthEnterException(&depth, decrementer,
        external, decrementer));
    CHECK(PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthLeave(&depth));

    mark = PEInterruptDepthMark(depth);
    CHECK(PEInterruptDepthEnterException(&depth, external,
        external, decrementer));
    PEInterruptDepthRecover(&depth, mark);
    CHECK(!PEInterruptDepthActive(depth));
    CHECK(PEInterruptDepthEnter(&depth));
    mark = PEInterruptDepthMark(depth);
    CHECK(PEInterruptDepthEnterException(&depth, decrementer,
        external, decrementer));
    PEInterruptDepthRecover(&depth, mark);
    CHECK(PEInterruptDepthActive(depth));
    CHECK(depth == 1);
    CHECK(PEInterruptDepthLeave(&depth));

    if (failures != 0)
        return 1;
    printf("interrupt depth tests passed\n");
    return 0;
}
