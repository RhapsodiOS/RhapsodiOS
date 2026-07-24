#include "pkginfo.h"
#include "strutil.h"
#include "exec.h"
#include <stdio.h>
#include <stdlib.h>

static void emit(FILE *f, const char *key, const char *value) {
    if (value) fprintf(f, "%s = %s\n", key, value);
}

int pkginfo_write(const Package *p, const char *path) {
    FILE *f = fopen(path, "w");
    char *ver;
    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s for writing\n", path);
        return 1;
    }
    ver = package_canon_version(p);
    emit(f, "pkgname", p->package);
    emit(f, "pkgver", ver);
    emit(f, "arch", p->architecture);
    emit(f, "pkgdesc", p->description);
    emit(f, "maintainer", p->maintainer);
    emit(f, "origin", p->source);
    emit(f, "provides", p->provides);
    emit(f, "replaces", p->replaces);
    if (p->has_build_depends) {
        sbuf s;
        char *joined;
        size_t i;
        sbuf_init(&s);
        for (i = 0; i < p->build_depends.count; i++) {
            if (i) sbuf_putc(&s, ' ');
            sbuf_puts(&s, p->build_depends.items[i]);
        }
        joined = sbuf_steal(&s);
        emit(f, "builddepends", joined);
        free(joined);
        sbuf_free(&s);
    }
    free(ver);
    fclose(f);
    return 0;
}

int pkginfo_build_apk(const char *root_dir, const char *out_apk) {
    /* tar -C <root_dir> -cf - . | gzip -9 > <out_apk> */
    char *cmd = str_cats("tar -C '", root_dir, "' -cf - . | gzip -9 > '",
                         out_apk, "'", (char *)0);
    char *argv[4];
    int rc;
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
    rc = exec_run_checked(argv);
    free(cmd);
    return rc;
}
