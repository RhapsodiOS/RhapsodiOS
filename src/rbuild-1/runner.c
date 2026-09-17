#include "runner.h"
#include "architecture.h"
#include "apk.h"
#include "builder.h"
#include "exec.h"
#include "kernel.h"
#include "manifest.h"
#include "package.h"
#include "strutil.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef RBUILD_RUNNER_TESTING
static void (*runner_before_replay_test_hook)(void) = 0;
void runner_test_set_before_replay_hook(void (*hook)(void)) {
    runner_before_replay_test_hook = hook;
}
static void run_before_replay_test_hook(void) {
    if (runner_before_replay_test_hook != 0)
        runner_before_replay_test_hook();
}
#else
static void run_before_replay_test_hook(void) {
}
#endif

static int safe_component(const char *value) {
    const unsigned char *p = (const unsigned char *)value;
    if (value == 0 || value[0] == '\0' || strcmp(value, ".") == 0 ||
        strcmp(value, "..") == 0) return 0;
    for (; *p != '\0'; p++)
        if (!( (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
               (*p >= '0' && *p <= '9') || *p == '.' || *p == '_' ||
               *p == '+' || *p == '-')) return 0;
    return 1;
}

static int source_text_safe(const char *value) {
    const unsigned char *p = (const unsigned char *)value;
    if (value == 0 || value[0] == '\0') return 0;
    for (; *p != '\0'; p++)
        if (*p < 32 || *p == 127 || *p == '\\') return 0;
    return 1;
}

static int unsafe_host_path(const char *path) {
    static const char *protected_trees[] = {
        "/System", "/usr", "/lib", "/bin", "/sbin", "/etc",
        "/Library", "/private/etc", 0
    };
    static const char *container_roots[] = {
        "/var", "/private/var", "/Users", "/Developer", 0
    };
    int i;
    for (i = 0; protected_trees[i] != 0; i++) {
        size_t n = strlen(protected_trees[i]);
        if (strncmp(path, protected_trees[i], n) == 0 &&
            (path[n] == '\0' || path[n] == '/')) return 1;
    }
    for (i = 0; container_roots[i] != 0; i++)
        if (strcmp(path, container_roots[i]) == 0) return 1;
    return 0;
}

static char *normalize_boundary(const char *path) {
    strlist parts;
    sbuf result;
    const char *p;
    char *out;
    size_t i;
    struct stat st;
    char probe[4096];
    char resolved[4096];
    char *slash;
    const char *suffix;
    char *resolved_full;

    if (path == 0 || path[0] != '/') return 0;
    strlist_init(&parts);
    p = path;
    while (*p != '\0') {
        const char *start;
        size_t length;
        while (*p == '/') p++;
        if (*p == '\0') break;
        start = p;
        while (*p != '\0' && *p != '/') p++;
        length = (size_t)(p - start);
        if (length == 1 && start[0] == '.') continue;
        if (length == 2 && start[0] == '.' && start[1] == '.') {
            if (parts.count != 0) {
                free(parts.items[--parts.count]);
            }
            continue;
        }
        {
            char *part = (char *)xmalloc(length + 1);
            memcpy(part, start, length); part[length] = '\0';
            strlist_push(&parts, part); free(part);
        }
    }
    sbuf_init(&result); sbuf_putc(&result, '/');
    for (i = 0; i < parts.count; i++) {
        if (i != 0) sbuf_putc(&result, '/');
        sbuf_puts(&result, parts.items[i]);
    }
    out = sbuf_steal(&result); sbuf_free(&result); strlist_free(&parts);
    if (strcmp(out, "/") == 0 || strcmp(out, "/tmp") == 0 ||
        strcmp(out, "/private/tmp") == 0 || strcmp(out, "/build") == 0 ||
        unsafe_host_path(out)) {
        free(out); return 0;
    }
    if (strlen(out) >= sizeof(probe)) { free(out); return 0; }
    if (lstat(out, &st) == 0 && S_ISLNK(st.st_mode)) {
        free(out); return 0;
    }
    strcpy(probe, out);
    while (lstat(probe, &st) != 0) {
        if (errno != ENOENT) { free(out); return 0; }
        slash = strrchr(probe, '/');
        if (slash == probe) { probe[1] = '\0'; break; }
        if (slash == 0) { free(out); return 0; }
        *slash = '\0';
    }
    if (realpath(probe, resolved) == 0) { free(out); return 0; }
    if (strcmp(resolved, "/") == 0 && strcmp(probe, "/") != 0) {
        free(out); return 0;
    }
    suffix = out + strlen(probe);
    resolved_full = str_cats(resolved,
                             strcmp(resolved, "/") == 0 && *suffix == '/' ?
                             suffix + 1 : suffix, (char *)0);
    if (strcmp(resolved_full, "/") == 0 || unsafe_host_path(resolved_full)) {
        free(resolved_full); free(out); return 0;
    }
    free(resolved_full);
    return out;
}

static char *normalize_output(const char *path) {
    char cwd[4096];
    char *absolute;
    char *normalized;
    struct stat st;
    if (path == 0 || path[0] == '\0') return 0;
    if (path[0] == '/') {
        normalized = normalize_boundary(path);
    } else {
        if (getcwd(cwd, sizeof(cwd)) == 0) return 0;
        absolute = str_cats(cwd, "/", path, (char *)0);
        normalized = normalize_boundary(absolute);
        free(absolute);
    }
    if (normalized != 0 && lstat(normalized, &st) == 0 &&
        !S_ISDIR(st.st_mode)) {
        free(normalized);
        return 0;
    }
    return normalized;
}

static int mkdir_one(const char *path) {
    struct stat st;
    if (mkdir(path, 0777) == 0) return 0;
    if (errno == EEXIST && stat(path, &st) == 0 && S_ISDIR(st.st_mode))
        return 0;
    return 1;
}

static int mkdir_path(const char *path) {
    char *copy;
    char *p;
    int rc = 0;
    if (path == 0 || path[0] != '/') return 1;
    copy = xstrdup(path);
    for (p = copy + 1; *p != '\0'; p++) {
        if (*p != '/') continue;
        *p = '\0';
        if (mkdir_one(copy) != 0) { rc = 1; break; }
        *p = '/';
    }
    if (rc == 0 && mkdir_one(copy) != 0) rc = 1;
    free(copy);
    return rc;
}

static unsigned long fnv_bytes(unsigned long hash, const void *data,
                               size_t count) {
    const unsigned char *p = (const unsigned char *)data;
    size_t i;
    for (i = 0; i < count; i++) {
        hash ^= (unsigned long)p[i];
        hash *= 16777619UL;
        hash &= 0xffffffffUL;
    }
    return hash;
}

static int fingerprint_file(const char *path, unsigned long *out) {
    FILE *f;
    unsigned long hash = 2166136261UL;
    char buf[4096];
    size_t n;
    f = fopen(path, "rb");
    if (f == 0) return 1;
    while ((n = fread(buf, 1, sizeof(buf), f)) != 0)
        hash = fnv_bytes(hash, buf, n);
    if (ferror(f)) {
        fclose(f);
        return 1;
    }
    if (fclose(f) != 0) return 1;
    *out = hash;
    return 0;
}

static unsigned long entry_fingerprint(const ManifestEntry *entry,
                                       const char *target,
                                       const char *architecture) {
    unsigned long hash = 2166136261UL;
    static const char separator = '\0';
    hash = fnv_bytes(hash, entry->type, strlen(entry->type));
    hash = fnv_bytes(hash, &separator, 1);
    hash = fnv_bytes(hash, entry->source, strlen(entry->source));
    hash = fnv_bytes(hash, &separator, 1);
    hash = fnv_bytes(hash, target, strlen(target));
    hash = fnv_bytes(hash, &separator, 1);
    hash = fnv_bytes(hash, RB_ARCH_POLICY_VERSION, strlen(RB_ARCH_POLICY_VERSION));
    hash = fnv_bytes(hash, &separator, 1);
    hash = fnv_bytes(hash, architecture, strlen(architecture));
    return hash;
}

static char *variant_canon(const Package *pkg, const char *suffix) {
    Package variant;
    char *data;
    char *name;
    char *canon;
    package_init(&variant);
    data = package_unparse(pkg);
    package_parse(&variant, data);
    free(data);
    name = str_cats(variant.package, suffix, (char *)0);
    package_set(&variant.package, name);
    free(name);
    canon = package_canon_name(&variant);
    package_free(&variant);
    return canon;
}

static int regular_file(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int artifact_present(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0;
}

static int validate_or_quarantine(const char *path, const Toolchain *tc,
                                  const char *pkgname, const char *pkgver,
                                  const char *architecture, int *exists) {
    unsigned required;
    if (architecture_parse(architecture, &required) != 0) return 1;
    return builder_cache_status(path, tc, pkgname, pkgver, required,
                                 str_has_suffix(pkgname, "-obj"), exists);
}

static const Toolchain *validation_toolchain(const RunnerOptions *opt) {
    static Toolchain fallback;
    static int initialized = 0;
    if (opt->toolchain != 0) return opt->toolchain;
    if (!initialized) {
        toolchain_init(&fallback);
        fallback.tar = xstrdup("tar");
        fallback.gzip = xstrdup("gzip");
        initialized = 1;
    }
    return &fallback;
}

static int parse_hex(const char *text, unsigned long *value) {
    char *end;
    unsigned long result;
    size_t i;
    if (strlen(text) != 8) return 1;
    for (i = 0; i < 8; i++)
        if (!((text[i] >= '0' && text[i] <= '9') ||
              (text[i] >= 'a' && text[i] <= 'f'))) return 1;
    result = strtoul(text, &end, 16);
    if (*end != '\0' || result > 0xffffffffUL) return 1;
    *value = result;
    return 0;
}

typedef struct {
    int exists;
    int legacy; /* Existing record lacks current architecture policy. */
    int header;
    int object;
} StateInfo;

static int check_state(const char *path, const RunnerOptions *opt,
                       unsigned long tool_hash, unsigned long entry_hash,
                       const ManifestEntry *entry, const char *target,
                       const char *package_path, const char *architecture,
                       StateInfo *info) {
    FILE *f;
    char line[4096];
    char *expected_profile;
    char *expected_source;
    char *expected_target;
    char *expected_package;
    unsigned long stored_tool;
    unsigned long stored_entry;
    int line_no = 0, field = 0, format = 1;
    int saw_policy = 0, saw_architecture = 0;
    int policy_current = 0, architecture_current = 0, architecture_covers = 0;
    struct stat state_stat;
    memset(info, 0, sizeof(*info));
    if (lstat(path, &state_stat) == 0 && !S_ISREG(state_stat.st_mode)) {
        fprintf(stderr, "rbuild: unsafe state record %s\n", path);
        return -1;
    }
    f = fopen(path, "r");
    if (f == 0) {
        if (errno == ENOENT) return 0;
        fprintf(stderr, "rbuild: cannot read state record %s\n", path);
        return -1;
    }
    expected_profile = str_cats("profile=", opt->toolchain->profile, "\n",
                                (char *)0);
    expected_source = str_cats("source=", entry->source, "\n", (char *)0);
    expected_target = str_cats("target=", target, "\n", (char *)0);
    expected_package = str_cats("package=", package_path, "\n", (char *)0);
    while (fgets(line, sizeof(line), f) != 0) {
        line_no++;
        if (strchr(line, '\n') == 0 || line_no > 10) goto corrupt;
        if (line_no == 1 && str_has_prefix(line, "format=")) {
            if (strcmp(line, "format=2\n") == 0) format = 2;
            else if (strcmp(line, "format=3\n") == 0) format = 3;
            else goto corrupt;
            continue;
        }
        /* Markers are named, so either may be absent without shifting the
         * mandatory fields. Missing/old marker values mean stale policy. */
        if (format == 3 && str_has_prefix(line, "architecture_policy=")) {
            if (saw_policy) goto corrupt;
            saw_policy = 1;
            policy_current = strcmp(line, "architecture_policy="
                                     RB_ARCH_POLICY_VERSION "\n") == 0;
            continue;
        }
        if (format == 3 && str_has_prefix(line, "effective_architecture=")) {
            if (saw_architecture) goto corrupt;
            saw_architecture = 1;
            line[strlen(line) - 1] = '\0';
            architecture_current = strcmp(line + 23, architecture) == 0;
            if (!architecture_current) {
                unsigned stored_arch = 0, wanted_arch = 0;
                if (architecture_parse(line + 23, &stored_arch) == 0 &&
                    architecture_parse(architecture, &wanted_arch) == 0 &&
                    wanted_arch != 0 && (stored_arch & wanted_arch) == wanted_arch)
                    architecture_covers = 1;
            }
            continue;
        }
        field++;
        if (field > (format == 1 ? 6 : 7)) goto corrupt;
        if (field == 1 && strcmp(line, expected_profile) != 0) goto mismatch;
        if (field == 2) {
            if (strncmp(line, "toolchain_fingerprint=", 22) != 0) goto corrupt;
            line[strlen(line) - 1] = '\0';
            if (parse_hex(line + 22, &stored_tool) != 0) goto corrupt;
            if (stored_tool != tool_hash) goto mismatch;
        }
        if (field == 3) {
            if (strncmp(line, "entry_fingerprint=", 18) != 0) goto corrupt;
            line[strlen(line) - 1] = '\0';
            if (parse_hex(line + 18, &stored_entry) != 0) goto corrupt;
        }
        if (field == 4 && strcmp(line, expected_source) != 0) goto corrupt;
        if (field == 5 && strcmp(line, expected_target) != 0) goto corrupt;
        if (field == 6 && strcmp(line, expected_package) != 0) goto corrupt;
        if (field == 7) {
            if (strcmp(line, "companions=none\n") == 0) {
                info->header = 0; info->object = 0;
            } else if (strcmp(line, "companions=hdr\n") == 0) {
                info->header = 1; info->object = 0;
            } else if (strcmp(line, "companions=obj\n") == 0) {
                info->header = 0; info->object = 1;
            } else if (strcmp(line, "companions=hdr,obj\n") == 0) {
                info->header = 1; info->object = 1;
            } else goto corrupt;
        }
    }
    if (ferror(f) || field != (format == 1 ? 6 : 7)) goto corrupt;
    info->legacy = format != 3 || !policy_current ||
                   (!architecture_current && !architecture_covers);
    /* Old records have an older entry hash. Classify staleness first, but
     * retain the existing mismatch failure for current policy records.
     * A covering architecture (universal vs thin) changes the entry hash
     * without making the cached APK stale. */
    if (!info->legacy && stored_entry != entry_hash && !architecture_covers)
        goto mismatch;
    info->exists = 1;
    fclose(f);
    free(expected_package); free(expected_target); free(expected_source);
    free(expected_profile);
    return 0;
mismatch:
    fclose(f);
    free(expected_package); free(expected_target); free(expected_source);
    free(expected_profile);
    fprintf(stderr, "rbuild: toolchain state mismatch; use -Fresh\n");
    return -1;
corrupt:
    fclose(f);
    free(expected_package); free(expected_target); free(expected_source);
    free(expected_profile);
    fprintf(stderr, "rbuild: corrupt state record %s; use -Fresh\n", path);
    return -1;
}

static int write_state(const char *path, const RunnerOptions *opt,
                       unsigned long tool_hash, unsigned long entry_hash,
                       const ManifestEntry *entry, const char *target,
                       const char *package_path, const char *architecture,
                       int have_header, int have_object) {
    char temporary[4096];
    FILE *f = 0;
    int fd = -1;
    int attempt;
    int rc = 0;
    struct stat state_stat;
    if (strlen(path) + 64 >= sizeof(temporary)) return 1;
    if (lstat(path, &state_stat) == 0 && !S_ISREG(state_stat.st_mode)) return 1;
    for (attempt = 0; attempt < 100; attempt++) {
        sprintf(temporary, "%s.tmp.%ld.%d", path, (long)getpid(), attempt);
        fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0666);
        if (fd >= 0) break;
        if (errno != EEXIST) return 1;
    }
    if (fd < 0) return 1;
    f = fdopen(fd, "w");
    if (f == 0) { close(fd); unlink(temporary); return 1; }
    if (fprintf(f, "format=3\n") < 0 ||
        fprintf(f, "profile=%s\n", opt->toolchain->profile) < 0 ||
        fprintf(f, "toolchain_fingerprint=%08lx\n", tool_hash) < 0 ||
        fprintf(f, "entry_fingerprint=%08lx\n", entry_hash) < 0 ||
        fprintf(f, "source=%s\n", entry->source) < 0 ||
        fprintf(f, "target=%s\n", target) < 0 ||
        fprintf(f, "package=%s\n", package_path) < 0 ||
        fprintf(f, "companions=%s\n",
                have_header ? (have_object ? "hdr,obj" : "hdr") :
                              (have_object ? "obj" : "none")) < 0 ||
        fprintf(f, "architecture_policy=%s\n", RB_ARCH_POLICY_VERSION) < 0 ||
        fprintf(f, "effective_architecture=%s\n", architecture) < 0 ||
        fflush(f) != 0) rc = 1;
    if (rc == 0 && fsync(fd) != 0) rc = 1;
    if (fclose(f) != 0) rc = 1;
    if (rc == 0 && rename(temporary, path) != 0) rc = 1;
    if (rc != 0) unlink(temporary);
    return rc;
}

static int replay(const char *path, const RunnerOptions *opt,
                  const char *pkgname, const char *pkgver,
                  const char *architecture) {
    if (!regular_file(path)) {
        fprintf(stderr, "rbuild: required APK unavailable at replay: %s\n",
                path);
        return 1;
    }
    {
        unsigned required;
        if (architecture_parse(architecture, &required) != 0) return 1;
        return apk_use_arch(path, opt->sysroot, opt->toolchain, pkgname,
                             pkgver, required, str_has_suffix(pkgname, "-obj"), 1);
    }
}

static int run_entry(const ManifestEntry *entry, const char *seeddir,
                     const char *dstdir, const RunnerOptions *opt,
                     unsigned long tool_hash) {
    Package pkg;
    Params params;
    BuildOptions build_opt;
    strlist repository;
    const char *target = entry->targets ? entry->targets : "all";
    int headers_only = strcmp(target, "headers") == 0;
    int all_target = strcmp(target, "all") == 0;
    char *base_canon = 0;
    char *hdr_canon = 0;
    char *obj_canon = 0;
    char *base_path = 0;
    char *hdr_path = 0;
    char *obj_path = 0;
    char *state_path = 0;
    char *log_path = 0;
    unsigned long entry_hash;
    int base_exists = 0, hdr_exists = 0, obj_exists = 0;
    int base_was = 0, hdr_was = 0, obj_was = 0;
    int post_hdr_was = 0, post_obj_was = 0;
    StateInfo state_info;
    int must_build = 0;
    int rc = 1;
    char *version = 0;
    char *hdr_name = 0;
    char *obj_name = 0;
    const Toolchain *validate_tc = validation_toolchain(opt);

    package_init(&pkg); params_init(&params);
    memset(&state_info, 0, sizeof(state_info));
    if (!source_text_safe(entry->source) ||
        !(headers_only || all_target)) {
        fprintf(stderr, "rbuild: invalid manifest source or target\n");
        goto done;
    }
    if (builder_scan(entry->type, entry->source, &pkg, &params) != 0) {
        fprintf(stderr, "rbuild: skipping \"%s\": scan failed\n", entry->source);
        goto done;
    }
    build_options_init(&build_opt);
    build_opt.clean = !opt->bootstrap;
    build_opt.bootstrap = opt->bootstrap;
    build_opt.sysroot = opt->sysroot;
    build_opt.state_dir = opt->state_dir;
    build_opt.toolchain = opt->toolchain;
    build_opt.operation_arch = opt->operation_arch;
    if (builder_resolve_architecture(&pkg, &build_opt) != 0) {
        fprintf(stderr, "rbuild: architecture resolution failed for %s\n", entry->source);
        goto done;
    }
    version = package_canon_version(&pkg);
    hdr_name = str_cats(pkg.package, "-hdrs", (char *)0);
    obj_name = str_cats(pkg.package, "-obj", (char *)0);
    if (!safe_component(pkg.package) || !safe_component(version) ||
        !safe_component(pkg.architecture) || !safe_component(target)) {
        fprintf(stderr, "rbuild: unsafe package identity in %s\n", entry->source);
        goto done;
    }
    base_canon = package_canon_name(&pkg);
    hdr_canon = variant_canon(&pkg, "-hdrs");
    obj_canon = variant_canon(&pkg, "-obj");
    base_path = str_cats(dstdir, "/", base_canon, ".apk", (char *)0);
    hdr_path = str_cats(dstdir, "/", hdr_canon, ".apk", (char *)0);
    obj_path = str_cats(dstdir, "/", obj_canon, ".apk", (char *)0);

    if (opt->state_dir != 0 && !exec_dry_run) {
        char *projects = str_cats(opt->state_dir, "/projects", (char *)0);
        char *logs = str_cats(opt->state_dir, "/logs", (char *)0);
        if (mkdir_path(projects) != 0 || mkdir_path(logs) != 0) {
            fprintf(stderr, "rbuild: cannot create state directories\n");
            free(projects); free(logs); goto done;
        }
        state_path = str_cats(projects, "/", base_canon, "-", target,
                              ".done", (char *)0);
        log_path = str_cats(logs, "/", base_canon, "-", target,
                            ".log", (char *)0);
        free(projects); free(logs);
        if (exec_set_log(log_path) != 0) goto done;
    }

    entry_hash = entry_fingerprint(entry, target, pkg.architecture);
    if (opt->bootstrap && !exec_dry_run &&
        check_state(state_path, opt, tool_hash,
                                     entry_hash, entry, target,
                                     strcmp(target, "headers") == 0 ?
                                     hdr_path : base_path,
                                     pkg.architecture, &state_info) != 0) goto done;

    if (opt->bootstrap) {
        if (headers_only) {
            if (validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                       version, pkg.architecture,
                                       &hdr_exists) != 0) goto done;
            must_build = !hdr_exists;
        } else {
            base_was = artifact_present(base_path);
            if (validate_or_quarantine(base_path, validate_tc, pkg.package,
                                       version, pkg.architecture,
                                       &base_exists) != 0) goto done;
            if (all_target) {
                hdr_was = artifact_present(hdr_path);
                obj_was = artifact_present(obj_path);
                if (validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                           version, pkg.architecture,
                                           &hdr_exists) != 0 ||
                    validate_or_quarantine(obj_path, validate_tc, obj_name,
                                           version, pkg.architecture,
                                           &obj_exists) != 0) goto done;
            }
            must_build = !base_exists;
        }
        if (all_target)
            must_build = !base_exists || (hdr_was && !hdr_exists) ||
                         (obj_was && !obj_exists);
        if (all_target && state_info.exists &&
            ((state_info.header && !hdr_exists) ||
             (state_info.object && !obj_exists))) must_build = 1;
        if (state_info.exists && state_info.legacy) must_build = 1;
        if (base_was && !base_exists) must_build = 1;
    } else {
        if (headers_only) {
            if (validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                       version, pkg.architecture,
                                       &hdr_exists) != 0) goto done;
            must_build = !hdr_exists;
        } else {
            base_was = artifact_present(base_path);
            hdr_was = artifact_present(hdr_path);
            obj_was = artifact_present(obj_path);
            if (validate_or_quarantine(base_path, validate_tc, pkg.package,
                                       version, pkg.architecture,
                                       &base_exists) != 0 ||
                validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                       version, pkg.architecture,
                                       &hdr_exists) != 0 ||
                validate_or_quarantine(obj_path, validate_tc, obj_name,
                                       version, pkg.architecture,
                                       &obj_exists) != 0) goto done;
            must_build = !base_exists || (hdr_was && !hdr_exists) ||
                         (obj_was && !obj_exists);
        }
    }

    strlist_init(&repository);
    strlist_push(&repository, dstdir);
    strlist_push(&repository, seeddir);
    build_opt.force = must_build;
    if (must_build) {
        printf("must build %s.apk using %s %s\n", base_canon,
               entry->type, entry->source);
        fflush(stdout);
        if (builder_build(entry->type, entry->source, &repository, target,
                          dstdir, &build_opt) != 0) {
            fprintf(stderr, "rbuild: build of \"%s\" failed\n", entry->source);
            strlist_free(&repository); goto done;
        }
    } else printf("already have %s\n", headers_only ? hdr_path : base_path);
    strlist_free(&repository);

    if (exec_dry_run) { rc = 0; goto done; }

    if (opt->bootstrap) {
        if (headers_only) {
            if (validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                       version, pkg.architecture,
                                       &hdr_exists) != 0) goto done;
        } else {
            if (validate_or_quarantine(base_path, validate_tc, pkg.package,
                                       version, pkg.architecture,
                                       &base_exists) != 0) goto done;
            if (all_target) {
                post_hdr_was = artifact_present(hdr_path);
                post_obj_was = artifact_present(obj_path);
                if (validate_or_quarantine(hdr_path, validate_tc, hdr_name,
                                           version, pkg.architecture,
                                           &hdr_exists) != 0 ||
                    validate_or_quarantine(obj_path, validate_tc, obj_name,
                                           version, pkg.architecture,
                                           &obj_exists) != 0) goto done;
            }
        }
        if ((headers_only && !hdr_exists) ||
            (!headers_only && !base_exists) ||
            (all_target && ((post_hdr_was && !hdr_exists) ||
                            (post_obj_was && !obj_exists)))) {
            fprintf(stderr, "rbuild: required APK missing after build of %s\n",
                    entry->source);
            goto done;
        }
        run_before_replay_test_hook();
        if (headers_only) {
            if (replay(hdr_path, opt, hdr_name, version,
                       pkg.architecture) != 0) goto done;
        } else {
            if (all_target && hdr_exists &&
                replay(hdr_path, opt, hdr_name, version,
                       pkg.architecture) != 0)
                goto done;
            if (all_target && obj_exists &&
                replay(obj_path, opt, obj_name, version,
                       pkg.architecture) != 0)
                goto done;
            if (replay(base_path, opt, pkg.package, version,
                       pkg.architecture) != 0) goto done;
        }
        if (write_state(state_path, opt, tool_hash, entry_hash, entry, target,
                        headers_only ? hdr_path : base_path, pkg.architecture,
                        all_target && hdr_exists,
                        all_target && obj_exists)
            != 0) {
            fprintf(stderr, "rbuild: cannot write state record %s\n", state_path);
            goto done;
        }
    } else if (headers_only) {
        if (validate_or_quarantine(hdr_path, validate_tc, hdr_name, version,
                                   pkg.architecture, &hdr_exists) != 0 ||
            !hdr_exists) goto done;
    } else {
        post_hdr_was = artifact_present(hdr_path);
        post_obj_was = artifact_present(obj_path);
        if (validate_or_quarantine(base_path, validate_tc, pkg.package,
                                   version, pkg.architecture,
                                   &base_exists) != 0 ||
            validate_or_quarantine(hdr_path, validate_tc, hdr_name, version,
                                   pkg.architecture, &hdr_exists) != 0 ||
            validate_or_quarantine(obj_path, validate_tc, obj_name, version,
                                   pkg.architecture, &obj_exists) != 0 ||
            !base_exists || (post_hdr_was && !hdr_exists) ||
            (post_obj_was && !obj_exists)) goto done;
    }
    rc = 0;
done:
    exec_clear_log();
    free(log_path); free(state_path);
    free(obj_path); free(hdr_path); free(base_path);
    free(obj_canon); free(hdr_canon); free(base_canon);
    free(obj_name); free(hdr_name); free(version);
    package_free(&pkg); params_free(&params);
    return rc;
}

int runner_manifest(const char *srclist, const char *seeddir,
                    const char *dstdir, const RunnerOptions *opt) {
    Manifest manifest;
    RunnerOptions safe_opt;
    const RunnerOptions *run_opt;
    char *safe_sysroot = 0;
    char *safe_state = 0;
    char *safe_dstdir = 0;
    size_t i;
    int failures = 0;
    unsigned long tool_hash = 0;

    if (opt == 0) return 1;
    safe_opt = *opt;
    safe_dstdir = normalize_output(dstdir);
    if (safe_dstdir == 0) {
        fprintf(stderr, "rbuild: unsafe output repository\n");
        return 1;
    }
    if (opt->state_dir != 0) {
        safe_state = normalize_boundary(opt->state_dir);
        if (safe_state == 0) {
            fprintf(stderr, "rbuild: unsafe state directory\n");
            free(safe_dstdir);
            return 1;
        }
        safe_opt.state_dir = safe_state;
    }
    if (opt->bootstrap) {
        safe_sysroot = normalize_boundary(opt->sysroot);
        if (safe_sysroot == 0 || safe_state == 0) {
            fprintf(stderr, "rbuild: unsafe bootstrap sysroot or state directory\n");
            free(safe_sysroot); free(safe_state); free(safe_dstdir);
            return 1;
        }
        safe_opt.sysroot = safe_sysroot;
    }
    run_opt = &safe_opt;
    if (opt->bootstrap &&
        (opt->toolchain == 0 || opt->toolchain_file == 0 ||
         opt->sysroot == 0 || opt->state_dir == 0 ||
         fingerprint_file(opt->toolchain_file, &tool_hash) != 0)) {
        fprintf(stderr, "rbuild: cannot fingerprint toolchain profile\n");
        free(safe_sysroot); free(safe_state); free(safe_dstdir);
        return 1;
    }
    manifest_init(&manifest);
    if (manifest_read(&manifest, srclist) != 0) {
        manifest_free(&manifest);
        free(safe_sysroot); free(safe_state); free(safe_dstdir);
        return 1;
    }
    for (i = 0; i < manifest.count; i++) {
        if (run_entry(&manifest.items[i], seeddir, safe_dstdir, run_opt,
                      tool_hash) != 0) {
            failures = 1;
            if (opt->bootstrap) break;
        }
    }
    manifest_free(&manifest);
    free(safe_sysroot); free(safe_state); free(safe_dstdir);
    return failures;
}

static int buildpackage_for_arch(const char *type, const char *source,
                        const char *seeddir, const char *target,
                        const char *dstdir, const char *state_dir,
                        unsigned operation_arch, const char *arch) {
    strlist repository;
    BuildOptions opt;
    Package pkg;
    Params params;
    char *canon = 0;
    char *logs = 0;
    char *log_path = 0;
    char *safe_state = 0;
    char *safe_dstdir = 0;
    char *version = 0;
    int rc = 1;

    /* Standalone buildpackage historically passed its target through to the
       builder (including objs, local, and binary).  Keep that compatibility;
       only manifest/bootstrap targets use the stricter all/headers policy. */
    if (!source_text_safe(source) || !safe_component(target)) {
        fprintf(stderr, "rbuild: invalid buildpackage source or target\n");
        goto done;
    }
    safe_dstdir = normalize_output(dstdir);
    if (safe_dstdir == 0) {
        fprintf(stderr, "rbuild: unsafe output repository\n");
        goto done;
    }
    if (state_dir != 0) {
        safe_state = normalize_boundary(state_dir);
        if (safe_state == 0) {
            fprintf(stderr, "rbuild: unsafe state directory\n");
            goto done;
        }
    }
    package_init(&pkg); params_init(&params);
    if (builder_scan(type, source, &pkg, &params) != 0) goto done_scanned;
    build_options_init(&opt);
    opt.operation_arch = operation_arch;
    if (builder_resolve_architecture(&pkg, &opt) != 0) {
        fprintf(stderr, "rbuild: architecture resolution failed for %s\n", source);
        goto done_scanned;
    }
    version = package_canon_version(&pkg);
    if (!safe_component(pkg.package) || !safe_component(version) ||
        !safe_component(pkg.architecture)) {
        fprintf(stderr, "rbuild: unsafe package identity in %s\n", source);
        goto done_scanned;
    }
    if (safe_state != 0 && !exec_dry_run) {
        canon = package_canon_name(&pkg);
        logs = str_cats(safe_state, "/logs", (char *)0);
        log_path = str_cats(logs, "/", canon, "-", target, ".log",
                            (char *)0);
        if (mkdir_path(logs) != 0 || exec_set_log(log_path) != 0)
            goto done_scanned;
    }
    strlist_init(&repository);
    strlist_push(&repository, safe_dstdir);
    strlist_push(&repository, seeddir);
    opt.state_dir = safe_state;
    opt.clean = 1;
    if (arch != 0) {
        if (!kernel_arch_safe(arch)) {
            fprintf(stderr, "rbuild: unsafe architecture \"%s\"\n", arch);
            goto done_scanned;
        }
        opt.target_arch = arch;
    }
    rc = builder_build(type, source, &repository, target, safe_dstdir, &opt);
    strlist_free(&repository);
done_scanned:
    package_free(&pkg); params_free(&params);
done:
    exec_clear_log();
    free(version); free(log_path); free(logs); free(canon);
    free(safe_dstdir); free(safe_state);
    return rc;
}

int runner_buildpackage(const char *type, const char *source,
                        const char *seeddir, const char *target,
                        const char *dstdir, const char *state_dir,
                        const char *arch) {
    unsigned operation_arch = 0;
    if (arch != 0) {
        if (architecture_parse(arch, &operation_arch) != 0 ||
            (operation_arch != RB_ARCH_I386 &&
             operation_arch != RB_ARCH_PPC)) {
            fprintf(stderr,
                    "rbuild: unsupported or unsafe architecture \"%s\"\n",
                    arch);
            return 1;
        }
    }
    return buildpackage_for_arch(type, source, seeddir, target, dstdir,
                                 state_dir, operation_arch, arch);
}

int runner_kernel(const char *srcdir, const char *seeddir, const char *dstdir,
                  const char *arch, const char *state_dir) {
    strlist packages;
    size_t i;
    int rc = 1;
    char *path;
    unsigned operation_arch;

    if (!kernel_arch_safe(arch) ||
        architecture_parse(arch, &operation_arch) != 0 ||
        (operation_arch != RB_ARCH_I386 && operation_arch != RB_ARCH_PPC)) {
        fprintf(stderr, "rbuild: unsupported or unsafe architecture \"%s\"\n",
                arch ? arch : "");
        return 1;
    }
    strlist_init(&packages);
    if (kernel_core_packages(arch, &packages) != 0) goto done;
    for (i = 0; i < packages.count; i++) {
        struct stat st;
        path = path_join(srcdir, packages.items[i]);
        if (stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) {
            printf("rbuild: skip missing kernel source %s\n", packages.items[i]);
            fflush(stdout);
            free(path);
            continue;
        }
        if (buildpackage_for_arch("dir", path, seeddir, "all", dstdir,
                                  state_dir, operation_arch, arch) != 0) {
            fprintf(stderr, "rbuild: kernel failed: %s\n", packages.items[i]);
            free(path);
            goto done;
        }
        printf("rbuild: ok %s\n", packages.items[i]);
        free(path);
    }
    printf("rbuild: kernel complete\n");
    rc = 0;
done:
    strlist_free(&packages);
    return rc;
}

int runner_kerneldrivers(const char *srcdir, const char *seeddir,
                         const char *dstdir, const char *arch,
                         const char *state_dir) {
    strlist packages;
    strlist failed;
    strlist found;
    strlist skip;
    strlist skipped;
    size_t i;
    int rc = 1;
    int passes = 0;
    char *path;
    char *list_path;
    unsigned operation_arch;

    if (!kernel_arch_safe(arch) ||
        architecture_parse(arch, &operation_arch) != 0 ||
        (operation_arch != RB_ARCH_I386 && operation_arch != RB_ARCH_PPC)) {
        fprintf(stderr, "rbuild: unsupported or unsafe architecture \"%s\"\n",
                arch ? arch : "");
        return 1;
    }
    strlist_init(&packages);
    strlist_init(&failed);
    strlist_init(&found);
    strlist_init(&skip);
    strlist_init(&skipped);
    list_path = path_join(srcdir, KERNEL_DRIVERS_BLACKLIST_REL);
    if (kernel_load_blacklist(list_path, &skip) != 0) {
        fprintf(stderr,
                "rbuild: unable to read kernel driver blacklist %s\n",
                list_path);
        free(list_path);
        goto done;
    }
    free(list_path);
    if (kernel_scan_drivers(srcdir, arch, &found) != 0) {
        fprintf(stderr,
                "rbuild: unable to scan drivers for architecture \"%s\"\n",
                arch);
        goto done;
    }
    for (i = 0; i < found.count; i++) {
        if (kernel_driver_blacklisted(&skip, found.items[i])) {
            printf("rbuild: skip %s\n", found.items[i]);
            strlist_push(&skipped, found.items[i]);
        } else {
            strlist_push(&packages, found.items[i]);
        }
    }
    for (i = 0; i < packages.count; i++) {
        path = path_join(srcdir, packages.items[i]);
        if (buildpackage_for_arch("dir", path, seeddir, "all", dstdir,
                                  state_dir, operation_arch, arch) != 0) {
            fprintf(stderr, "rbuild: FAIL %s\n", packages.items[i]);
            strlist_push(&failed, packages.items[i]);
        } else {
            printf("rbuild: ok %s\n", packages.items[i]);
            passes++;
        }
        free(path);
    }
    printf("======== kerneldrivers summary ========\n");
    printf("drivers skipped: %d\n", (int)skipped.count);
    printf("drivers ok: %d\n", passes);
    printf("drivers fail: %d\n", (int)failed.count);
    for (i = 0; i < failed.count; i++)
        printf("  FAIL %s\n", failed.items[i]);
    if (failed.count != 0) {
        fprintf(stderr,
                "rbuild: kerneldrivers finished with %d driver failure(s)\n",
                (int)failed.count);
        goto done;
    }
    printf("rbuild: kerneldrivers complete\n");
    rc = 0;
done:
    strlist_free(&packages);
    strlist_free(&failed);
    strlist_free(&found);
    strlist_free(&skip);
    strlist_free(&skipped);
    return rc;
}
