#include "kernel.h"
#include "test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char scratch[160];

static void write_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs(text, f);
        fclose(f);
    }
}

static void write_rel(const char *rel, const char *text) {
    char *path = path_join(scratch, rel);
    write_file(path, text);
    free(path);
}

static int setup_tree(void) {
    char command[1024];

    sprintf(scratch, "/tmp/rbuild-kernel-%ld", (long)getpid());
    sprintf(command,
            "rm -rf %s && mkdir -p "
            "%s/drivers-ppc/bus/drvPExpert/dpkg "
            "%s/drivers-ppc/bus/drvPPCOHare/dpkg "
            "%s/drivers-ppc/storage/drvSwimFloppy "
            "%s/drivers-ppc/network/Intel82557/dpkg "
            "%s/drivers-ppc/sound/notADriver/dpkg "
            "%s/drivers-i386/bus/drvEISABus/dpkg "
            "%s/drvBPF/dpkg "
            "%s/drvSCSIServer/dpkg "
            "%s/drvSCSITape/dpkg "
            "%s/drvPortServer",
            scratch, scratch, scratch, scratch, scratch, scratch,
            scratch, scratch, scratch, scratch, scratch);
    if (system(command) != 0) return -1;
    write_rel("drivers-ppc/bus/drvPExpert/dpkg/control", "Package: PExpert\n");
    write_rel("drivers-ppc/bus/drvPPCOHare/dpkg/control", "Package: PPCOHare\n");
    write_rel("drivers-ppc/storage/drvSwimFloppy/Makefile", "all:\n");
    write_rel("drivers-ppc/network/Intel82557/dpkg/control",
              "Package: Intel82557\n");
    write_rel("drivers-ppc/sound/notADriver/dpkg/control",
              "Package: notADriver\n");
    write_rel("drivers-i386/bus/drvEISABus/dpkg/control", "Package: EISABus\n");
    write_rel("drvBPF/dpkg/control", "Package: BPF\n");
    write_rel("drvSCSIServer/dpkg/control", "Package: SCSIServer\n");
    write_rel("drvSCSITape/dpkg/control", "Package: SCSITape\n");
    write_rel("drvPortServer/Makefile", "all:\n");
    return 0;
}

static void cleanup_tree(void) {
    char command[192];
    sprintf(command, "rm -rf %s", scratch);
    system(command);
}

TEST(test_kernel_arch_safe) {
    CHECK_INT(kernel_arch_safe("ppc"), 1);
    CHECK_INT(kernel_arch_safe("i386"), 1);
    CHECK_INT(kernel_arch_safe("mips_safe"), 1);
    CHECK_INT(kernel_arch_safe(""), 0);
    CHECK_INT(kernel_arch_safe(0), 0);
    CHECK_INT(kernel_arch_safe("ppc other"), 0);
    CHECK_INT(kernel_arch_safe("ppc-le"), 0);
    CHECK_INT(kernel_arch_safe("9ppc"), 0);
}

TEST(test_kernel_core_packages) {
    strlist packages;
    strlist_init(&packages);
    CHECK_INT(kernel_core_packages("ppc", &packages), 0);
    CHECK_INT(packages.count, 5);
    CHECK_STR(packages.items[0], "driverkit-3");
    CHECK_STR(packages.items[1], "driverTools-1");
    CHECK_STR(packages.items[2], "kernload-1");
    CHECK_STR(packages.items[3], "drivers-ppc/bus/drvPExpert");
    CHECK_STR(packages.items[4], "kernel-7");
    strlist_free(&packages);

    strlist_init(&packages);
    CHECK_INT(kernel_core_packages("i386", &packages), 0);
    CHECK_STR(packages.items[3], "drivers-i386/bus/drvPExpert");
    strlist_free(&packages);

    strlist_init(&packages);
    CHECK_INT(kernel_core_packages("ppc other", &packages), -1);
    CHECK_INT(packages.count, 0);
    strlist_free(&packages);
}

TEST(test_kernel_scan_drivers) {
    strlist packages;
    CHECK_INT(setup_tree(), 0);

    strlist_init(&packages);
    CHECK_INT(kernel_scan_drivers(scratch, "ppc", &packages), 0);
    CHECK_INT(packages.count, 5);
    CHECK_STR(packages.items[0], "drvBPF");
    CHECK_STR(packages.items[1], "drvSCSIServer");
    CHECK_STR(packages.items[2], "drvSCSITape");
    CHECK_STR(packages.items[3], "drivers-ppc/bus/drvPPCOHare");
    CHECK_STR(packages.items[4], "drivers-ppc/network/Intel82557");
    strlist_free(&packages);

    strlist_init(&packages);
    CHECK_INT(kernel_scan_drivers(scratch, "i386", &packages), 0);
    CHECK_INT(packages.count, 4);
    CHECK_STR(packages.items[0], "drvBPF");
    CHECK_STR(packages.items[1], "drvSCSIServer");
    CHECK_STR(packages.items[2], "drvSCSITape");
    CHECK_STR(packages.items[3], "drivers-i386/bus/drvEISABus");
    strlist_free(&packages);

    strlist_init(&packages);
    CHECK_INT(kernel_scan_drivers(scratch, "ppc other", &packages), -1);
    CHECK_INT(packages.count, 0);
    strlist_free(&packages);

    strlist_init(&packages);
    CHECK_INT(kernel_scan_drivers("/no/such/rbuild-kernel-src", "ppc",
                                  &packages), -1);
    strlist_free(&packages);

    cleanup_tree();
}

TEST(test_kernel_load_blacklist) {
    char path[192];
    strlist skip;
    FILE *f;

    sprintf(path, "/tmp/rbuild-kbl-%ld.json", (long)getpid());
    f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("{\n  \"skip\": [\n"
              "    \"drivers-ppc/network/Intel82557\",\n"
              "    \"drvBPF\"\n"
              "  ]\n}\n", f);
        fclose(f);
    }
    strlist_init(&skip);
    CHECK_INT(kernel_load_blacklist(path, &skip), 0);
    CHECK_INT(skip.count, 2);
    CHECK_STR(skip.items[0], "drivers-ppc/network/Intel82557");
    CHECK_STR(skip.items[1], "drvBPF");
    CHECK_INT(kernel_driver_blacklisted(&skip, "drvBPF"), 1);
    CHECK_INT(kernel_driver_blacklisted(&skip,
                                       "drivers-ppc/network/Intel82557"), 1);
    CHECK_INT(kernel_driver_blacklisted(&skip,
                                       "drivers-ppc/bus/drvPPCOHare"), 0);
    CHECK_INT(kernel_driver_blacklisted(0, "drvBPF"), 0);
    strlist_free(&skip);
    remove(path);

    strlist_init(&skip);
    CHECK_INT(kernel_load_blacklist("/no/such/rbuild-kbl.json", &skip), -1);
    CHECK_INT(skip.count, 0);
    strlist_free(&skip);

    f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("{\"skip\":[]}\n", f);
        fclose(f);
    }
    strlist_init(&skip);
    CHECK_INT(kernel_load_blacklist(path, &skip), 0);
    CHECK_INT(skip.count, 0);
    strlist_free(&skip);
    remove(path);

    f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("{\"nope\":[]}\n", f);
        fclose(f);
    }
    strlist_init(&skip);
    CHECK_INT(kernel_load_blacklist(path, &skip), -1);
    strlist_free(&skip);
    remove(path);

    f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("{\"skip\":[\"../etc/passwd\"]}\n", f);
        fclose(f);
    }
    strlist_init(&skip);
    CHECK_INT(kernel_load_blacklist(path, &skip), -1);
    strlist_free(&skip);
    remove(path);
}

TEST(test_kernel_blacklist_filters_scan) {
    strlist found;
    strlist skip;
    strlist keep;
    size_t i;

    CHECK_INT(setup_tree(), 0);
    strlist_init(&found);
    CHECK_INT(kernel_scan_drivers(scratch, "ppc", &found), 0);
    strlist_init(&skip);
    strlist_push(&skip, "drivers-ppc/network/Intel82557");
    strlist_push(&skip, "drvBPF");
    strlist_init(&keep);
    for (i = 0; i < found.count; i++) {
        if (!kernel_driver_blacklisted(&skip, found.items[i]))
            strlist_push(&keep, found.items[i]);
    }
    CHECK_INT(keep.count, 3);
    CHECK_STR(keep.items[0], "drvSCSIServer");
    CHECK_STR(keep.items[1], "drvSCSITape");
    CHECK_STR(keep.items[2], "drivers-ppc/bus/drvPPCOHare");
    strlist_free(&found);
    strlist_free(&skip);
    strlist_free(&keep);
    cleanup_tree();
}

static void run_all(void) {
    RUN(test_kernel_arch_safe);
    RUN(test_kernel_core_packages);
    RUN(test_kernel_scan_drivers);
    RUN(test_kernel_load_blacklist);
    RUN(test_kernel_blacklist_filters_scan);
}

TEST_MAIN()
