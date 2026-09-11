#include "builder.h"
#include "manifest.h"
#include "exec.h"
#include "kernel.h"
#include "strutil.h"
#include "package.h"
#include "runner.h"
#include "toolchain.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static const char *USAGE =
    "usage:\n"
    "  rbuild buildpackage [--state DIR] [--arch ARCH] [--dir]"
    " [--target {all|headers|objs|local}]"
    " <source> <repository> <dstdir>\n"
    "  rbuild buildall [--state DIR] <srclist> <repository> <dstdir>\n"
    "  rbuild bootstrap --sysroot ROOT --toolchain FILE --state DIR"
    " <srclist> <repository> <dstdir>\n"
    "  rbuild kernel [--state DIR] --arch ARCH"
    " <srcdir> <repository> <dstdir>\n"
    "  rbuild kerneldrivers [--state DIR] --arch ARCH"
    " <srcdir> <repository> <dstdir>\n"
    "  rbuild missing   <srclist> <dstdir>\n"
    "  (global: -n/--dry-run)\n";

static void usage(void) { fputs(USAGE, stderr); }

static int cmd_buildpackage(int argc, char **argv) {
    const char *type = "dir";
    const char *target = "all";
    const char *source, *seeddir, *dstdir;
    const char *state_dir = 0;
    const char *arch = 0;
    int i = 0;
    int rc;

    while (i < argc && strncmp(argv[i], "--", 2) == 0) {
        const char *name = argv[i++];
        if (strcmp(name, "--dir") == 0) {
            type = "dir";
            continue;
        }
        if (strcmp(name, "--cvs") == 0) {
            fprintf(stderr, "rbuild: cvs support has been removed; "
                            "build from a --dir source\n");
            return 1;
        }
        if (i >= argc) { usage(); return 1; }
        if (strcmp(name, "--state") == 0) {
            state_dir = argv[i++];
            if (state_dir[0] != '/') {
                fprintf(stderr, "rbuild: state directory must be absolute\n");
                return 1;
            }
        } else if (strcmp(name, "--target") == 0) {
            target = argv[i++];
        } else if (strcmp(name, "--arch") == 0) {
            arch = argv[i++];
        } else {
            usage();
            return 1;
        }
    }

    if (argc - i != 3) { usage(); return 1; }
    if (arch != 0 && !kernel_arch_safe(arch)) {
        fprintf(stderr, "rbuild: unsafe architecture \"%s\"\n", arch);
        return 1;
    }
    source = argv[i]; seeddir = argv[i + 1]; dstdir = argv[i + 2];

    rc = runner_buildpackage(type, source, seeddir, target, dstdir,
                             state_dir, arch);
    return rc;
}

static int cmd_buildall(int argc, char **argv) {
    RunnerOptions opt;
    const char *state = 0;
    int i = 0;
    if (i < argc && strcmp(argv[i], "--state") == 0) {
        if (++i >= argc) { usage(); return 1; }
        state = argv[i++];
        if (state[0] != '/') {
            fprintf(stderr, "rbuild: state directory must be absolute\n");
            return 1;
        }
    }
    if (argc - i != 3) { usage(); return 1; }
    memset(&opt, 0, sizeof(opt));
    opt.state_dir = state;
    return runner_manifest(argv[i], argv[i + 1], argv[i + 2], &opt);
}

static int cmd_bootstrap(int argc, char **argv) {
    const char *sysroot = 0;
    const char *profile = 0;
    const char *state = 0;
    Toolchain tc;
    RunnerOptions opt;
    int i = 0;
    int rc;
    while (i < argc && strncmp(argv[i], "--", 2) == 0) {
        const char *name = argv[i++];
        const char *value;
        if (i >= argc) { usage(); return 1; }
        value = argv[i++];
        if (strcmp(name, "--sysroot") == 0) sysroot = value;
        else if (strcmp(name, "--toolchain") == 0) profile = value;
        else if (strcmp(name, "--state") == 0) state = value;
        else { usage(); return 1; }
    }
    if (argc - i != 3 || sysroot == 0 || profile == 0 || state == 0) {
        usage(); return 1;
    }
    if (sysroot[0] != '/' || state[0] != '/') {
        fprintf(stderr, "rbuild: sysroot and state directory must be absolute\n");
        return 1;
    }
    toolchain_init(&tc);
    if (toolchain_load(&tc, profile) != 0 || toolchain_validate(&tc) != 0) {
        toolchain_free(&tc); return 1;
    }
    memset(&opt, 0, sizeof(opt));
    opt.bootstrap = 1;
    opt.sysroot = sysroot;
    opt.state_dir = state;
    opt.toolchain = &tc;
    opt.toolchain_file = profile;
    rc = runner_manifest(argv[i], argv[i + 1], argv[i + 2], &opt);
    toolchain_free(&tc);
    return rc;
}

static int cmd_missing(int argc, char **argv) {
    const char *srclist, *dstdir;
    Manifest m;
    size_t i;
    int rc = 0;

    if (argc != 2) { usage(); return 1; }
    srclist = argv[0]; dstdir = argv[1];

    manifest_init(&m);
    if (manifest_read(&m, srclist) != 0) { manifest_free(&m); return 1; }

    for (i = 0; i < m.count; i++) {
        const char *type = m.items[i].type;
        const char *source = m.items[i].source;
        const char *target = m.items[i].targets ? m.items[i].targets : "all";
        Package pkg; Params params; char *found;

        if (strcmp(target, "all") != 0 && strcmp(target, "headers") != 0) {
            fprintf(stderr,
                "rbuild: unsupported manifest target \"%s\" for missing\n",
                target);
            rc = 1;
            continue;
        }

        package_init(&pkg); params_init(&params);
        if (builder_scan(type, source, &pkg, &params) != 0) {
            fprintf(stderr, "rbuild: skipping \"%s\": scan failed\n", source);
            package_free(&pkg); params_free(&params);
            continue;
        }
        if (strcmp(target, "headers") == 0) {
            char *header_package = str_cats(pkg.package, "-hdrs", (char *)0);
            package_set(&pkg.package, header_package);
            free(header_package);
        }
        found = builder_exists(&pkg, "any", dstdir);
        if (!found) {
            char *canon = package_canon_name(&pkg);
            printf("must build %s.apk using %s %s\n", canon, type, source);
            free(canon);
        } else {
            free(found);
        }
        package_free(&pkg); params_free(&params);
    }

    manifest_free(&m);
    return rc;
}

static int cmd_kernel(int argc, char **argv, int drivers) {
    const char *state = 0;
    const char *arch = 0;
    int i = 0;

    while (i < argc && strncmp(argv[i], "--", 2) == 0) {
        const char *name = argv[i++];
        const char *value;
        if (i >= argc) { usage(); return 1; }
        value = argv[i++];
        if (strcmp(name, "--state") == 0) state = value;
        else if (strcmp(name, "--arch") == 0) arch = value;
        else { usage(); return 1; }
    }
    if (argc - i != 3 || arch == 0) { usage(); return 1; }
    if (state != 0 && state[0] != '/') {
        fprintf(stderr, "rbuild: state directory must be absolute\n");
        return 1;
    }
    if (!kernel_arch_safe(arch)) {
        fprintf(stderr, "rbuild: unsafe architecture \"%s\"\n", arch);
        return 1;
    }
    if (drivers)
        return runner_kerneldrivers(argv[i], argv[i + 1], argv[i + 2],
                                    arch, state);
    return runner_kernel(argv[i], argv[i + 1], argv[i + 2], arch, state);
}

int main(int argc, char **argv) {
    int i = 1;
    const char *sub;

    /* Global flags before the subcommand. */
    while (i < argc && (strcmp(argv[i], "-n") == 0 ||
                        strcmp(argv[i], "--dry-run") == 0)) {
        exec_dry_run = 1;
        i++;
    }

    if (i >= argc) { usage(); return 1; }
    sub = argv[i]; i++;

    /* Allow -n between subcommand and its args too. */
    while (i < argc && (strcmp(argv[i], "-n") == 0 ||
                        strcmp(argv[i], "--dry-run") == 0)) {
        exec_dry_run = 1;
        i++;
    }

    if (strcmp(sub, "buildpackage") == 0)
        return cmd_buildpackage(argc - i, argv + i);
    if (strcmp(sub, "buildall") == 0)
        return cmd_buildall(argc - i, argv + i);
    if (strcmp(sub, "bootstrap") == 0)
        return cmd_bootstrap(argc - i, argv + i);
    if (strcmp(sub, "kernel") == 0)
        return cmd_kernel(argc - i, argv + i, 0);
    if (strcmp(sub, "kerneldrivers") == 0)
        return cmd_kernel(argc - i, argv + i, 1);
    if (strcmp(sub, "missing") == 0)
        return cmd_missing(argc - i, argv + i);

    fprintf(stderr, "rbuild: unknown subcommand \"%s\"\n", sub);
    usage();
    return 1;
}
