#include "builder.h"
#include "manifest.h"
#include "exec.h"
#include "strutil.h"
#include "package.h"
#include <stdio.h>
#include <string.h>

static const char *USAGE =
    "usage:\n"
    "  rbuild buildpackage [--dir] [--target {all|headers|objs|local}]"
    " <source> <repository> <dstdir>\n"
    "  rbuild buildall  <srclist> <repository> <dstdir>\n"
    "  rbuild bootstrap <srclist> <repository> <dstdir>\n"
    "  rbuild missing   <srclist> <dstdir>\n"
    "  (global: -n/--dry-run)\n";

static void usage(void) { fputs(USAGE, stderr); }

/* Build the [dstdir, seeddir] repository search list. */
static void make_repo(const char *dstdir, const char *seeddir, strlist *out) {
    strlist_init(out);
    strlist_push(out, dstdir);
    strlist_push(out, seeddir);
}

static int cmd_buildpackage(int argc, char **argv) {
    const char *type = "dir";
    const char *target = "all";
    const char *source, *seeddir, *dstdir;
    strlist repo;
    int i = 0;
    int rc;

    /* optional --dir/--cvs */
    if (i < argc && strcmp(argv[i], "--dir") == 0) { type = "dir"; i++; }
    else if (i < argc && strcmp(argv[i], "--cvs") == 0) {
        fprintf(stderr, "rbuild: cvs support has been removed; "
                        "build from a --dir source\n");
        return 1;
    }

    if (i < argc && strcmp(argv[i], "--target") == 0) {
        i++;
        if (i >= argc) { usage(); return 1; }
        target = argv[i]; i++;
    }

    if (argc - i != 3) { usage(); return 1; }
    source = argv[i]; seeddir = argv[i + 1]; dstdir = argv[i + 2];

    make_repo(dstdir, seeddir, &repo);
    rc = builder_build(type, source, &repo, target, dstdir, 0, 0);
    strlist_free(&repo);
    return rc;
}

static int run_manifest(int argc, char **argv, int native) {
    const char *srclist, *seeddir, *dstdir;
    strlist repo;
    Manifest m;
    size_t i;

    if (argc != 3) { usage(); return 1; }
    srclist = argv[0]; seeddir = argv[1]; dstdir = argv[2];

    make_repo(dstdir, seeddir, &repo);
    manifest_init(&m);
    if (manifest_read(&m, srclist) != 0) {
        manifest_free(&m); strlist_free(&repo); return 1;
    }

    for (i = 0; i < m.count; i++) {
        const char *type = m.items[i].type;
        const char *source = m.items[i].source;
        const char *targets = m.items[i].targets ? m.items[i].targets : "all";
        Package pkg; Params params; char *found;

        package_init(&pkg); params_init(&params);
        if (builder_scan(type, source, &pkg, &params) != 0) {
            fprintf(stderr, "rbuild: skipping \"%s\": scan failed\n", source);
            package_free(&pkg); params_free(&params);
            continue;
        }
        found = builder_exists(&pkg, "any", dstdir);
        if (!found) {
            char *canon = package_canon_name(&pkg);
            printf("must build %s.apk using %s %s\n", canon, type, source);
            fflush(stdout);
            free(canon);
            if (builder_build(type, source, &repo, targets, dstdir,
                              !native, native) != 0)
                fprintf(stderr, "rbuild: build of \"%s\" failed; continuing\n",
                        source);
        } else {
            printf("already have %s\n", found);
            free(found);
        }
        package_free(&pkg); params_free(&params);
    }

    manifest_free(&m);
    strlist_free(&repo);
    return 0;
}

static int cmd_buildall(int argc, char **argv) {
    return run_manifest(argc, argv, 0);
}

static int cmd_bootstrap(int argc, char **argv) {
    return run_manifest(argc, argv, 1);
}

static int cmd_missing(int argc, char **argv) {
    const char *srclist, *dstdir;
    Manifest m;
    size_t i;

    if (argc != 2) { usage(); return 1; }
    srclist = argv[0]; dstdir = argv[1];

    manifest_init(&m);
    if (manifest_read(&m, srclist) != 0) { manifest_free(&m); return 1; }

    for (i = 0; i < m.count; i++) {
        const char *type = m.items[i].type;
        const char *source = m.items[i].source;
        Package pkg; Params params; char *found;

        package_init(&pkg); params_init(&params);
        if (builder_scan(type, source, &pkg, &params) != 0) {
            fprintf(stderr, "rbuild: skipping \"%s\": scan failed\n", source);
            package_free(&pkg); params_free(&params);
            continue;
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
    return 0;
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
    if (strcmp(sub, "missing") == 0)
        return cmd_missing(argc - i, argv + i);

    fprintf(stderr, "rbuild: unknown subcommand \"%s\"\n", sub);
    usage();
    return 1;
}
