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

    if (failures != 0)
        return 1;
    printf("interrupt depth tests passed\n");
    return 0;
}
