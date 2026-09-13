#include "architecture.h"
#include "test.h"
#include <limits.h>

TEST(test_labels) {
    static const char *labels[] = { 0, "universal-apple-rhapsody", "i386",
        "i386-apple-rhapsody", "ppc", "ppc-apple-rhapsody" };
    static const unsigned masks[] = { 3, 3, 1, 1, 2, 2 };
    unsigned i, mask;
    CHECK_INT(RB_ARCH_I386, 1U);
    CHECK_INT(RB_ARCH_PPC, 2U);
    CHECK_INT(RB_ARCH_UNIVERSAL, 3U);
    CHECK_STR(RB_ARCH_POLICY_VERSION, "1");
    for (i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
        mask = 99;
        CHECK_INT(architecture_parse(labels[i], &mask), 0);
        CHECK_INT(mask, masks[i]);
    }
    CHECK_STR(architecture_label(1), "i386-apple-rhapsody");
    CHECK_STR(architecture_label(2), "ppc-apple-rhapsody");
    CHECK_STR(architecture_label(3), "universal-apple-rhapsody");
    CHECK_STR(architecture_archs(1), "i386");
    CHECK_STR(architecture_archs(2), "ppc");
    CHECK_STR(architecture_archs(3), "i386 ppc");
    CHECK_STR(architecture_cflags(1), "-arch i386");
    CHECK_STR(architecture_cflags(2), "-arch ppc");
    CHECK_STR(architecture_cflags(3), "-arch i386 -arch ppc");
}

TEST(test_invalid_labels) {
    static const char *labels[] = { "", "universal", "arm64", "I386",
        "powerpc", "i386 ppc", " i386", "ppc ", "i386-apple-darwin" };
    unsigned i, mask;
    for (i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
        mask = 99;
        CHECK(architecture_parse(labels[i], &mask) != 0);
        CHECK_INT(mask, 99);
    }
}

TEST(test_resolve) {
    unsigned source, operation, effective;
    for (source = 1; source <= 3; source++) {
        for (operation = 0; operation <= 3; operation++) {
            int valid = operation == 0 || (source & operation) == operation;
            effective = 99;
            if (valid) {
                CHECK_INT(architecture_resolve(source, operation, &effective), 0);
                CHECK_INT(effective, operation ? operation : source);
            } else {
                CHECK(architecture_resolve(source, operation, &effective) != 0);
                CHECK_INT(effective, 99);
            }
        }
    }
    {
        unsigned effective = 99;
        CHECK_INT(architecture_resolve(RB_ARCH_UNIVERSAL, RB_ARCH_UNIVERSAL,
                                       &effective), 0);
        CHECK_INT(effective, RB_ARCH_UNIVERSAL);
        effective = 99;
        CHECK(architecture_resolve(RB_ARCH_I386, RB_ARCH_UNIVERSAL,
                                   &effective) != 0);
        CHECK_INT(effective, 99);
        effective = 99;
        CHECK(architecture_resolve(RB_ARCH_PPC, RB_ARCH_UNIVERSAL,
                                   &effective) != 0);
        CHECK_INT(effective, 99);
    }
}

TEST(test_invalid_masks) {
    static const unsigned masks[] = { 0, 4, 5, 6, 7, UINT_MAX };
    unsigned i, effective;
    for (i = 0; i < sizeof(masks) / sizeof(masks[0]); i++) {
        effective = 99;
        CHECK(architecture_label(masks[i]) == 0);
        CHECK(architecture_archs(masks[i]) == 0);
        CHECK(architecture_cflags(masks[i]) == 0);
        CHECK(architecture_resolve(masks[i], 0, &effective) != 0);
        CHECK_INT(effective, 99);
        if (masks[i] != 0) {
            CHECK(architecture_resolve(3, masks[i], &effective) != 0);
            CHECK_INT(effective, 99);
        }
    }
}

static void run_all(void) {
    RUN(test_labels);
    RUN(test_invalid_labels);
    RUN(test_resolve);
    RUN(test_invalid_masks);
}

TEST_MAIN()
