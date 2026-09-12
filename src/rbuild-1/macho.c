#include "macho.h"
#include "architecture.h"
#include <stdio.h>
#include <string.h>
#include <limits.h>

/* On-disk widths from cctools' mach-o/{loader,fat}.h and bsd/include/ar.h.
 * Decode bytes explicitly: the build host need not have Mach headers or
 * the target's byte order/word size. File regions always fit in a long. */
static unsigned long word(const unsigned char *p, int le) {
    if (le)
        return (unsigned long)p[0] | ((unsigned long)p[1] << 8) |
            ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24);
    return (unsigned long)p[3] | ((unsigned long)p[2] << 8) |
        ((unsigned long)p[1] << 16) | ((unsigned long)p[0] << 24);
}
static int read_at(FILE *f, unsigned long off, void *buf, unsigned n) {
    return fseek(f, (long)off, SEEK_SET) != 0 || fread(buf, 1, n, f) != n;
}
static unsigned cpu_mask(unsigned long cpu) {
    if (cpu == 7) return RB_ARCH_I386;
    if (cpu == 18) return RB_ARCH_PPC;
    return 0;
}
static int decimal(const unsigned char *p, unsigned n, unsigned long *value) {
    unsigned i = 0;
    unsigned long v = 0;
    while (i < n && p[i] >= '0' && p[i] <= '9') {
        if (v > (ULONG_MAX - (p[i] - '0')) / 10) return 1;
        v = v * 10 + p[i++] - '0';
    }
    if (!i) return 1;
    while (i < n && p[i] == ' ') i++;
    if (i != n) return 1;
    *value = v;
    return 0;
}
static int symbol_name(const char *name) {
    return !strcmp(name, "__.SYMDEF") ||
        !strcmp(name, "__.SYMDEF SORTED") ||
        !strcmp(name, "/") || !strcmp(name, "/SYM64/");
}
/* Names may be arbitrarily long; only a short exact symbol name matters.
 * BSD names can have trailing NUL padding. GNU names end with slash-newline. */
static int stored_name(FILE *f, unsigned long off, unsigned long size,
                       int gnu, char name[32]) {
    unsigned char c;
    unsigned long i;
    unsigned n = 0;
    int padding = 0, long_name = 0;
    for (i = 0; i < size; i++) {
        if (read_at(f, off+i, &c, 1)) return 1;
        if (gnu && c == '\n') {
            if (n && name[n-1] == '/') n--;
            name[long_name ? 0 : n] = 0;
            return 0;
        }
        if (!gnu && !c) { padding = 1; continue; }
        if (padding || !c) return 1;
        if (n < 31) name[n++] = (char)c;
        else long_name = 1;
    }
    if (gnu) return 1;
    name[long_name ? 0 : n] = 0;
    return 0;
}
static int inspect(FILE *, unsigned long, unsigned long, unsigned, unsigned *);

static int archive(FILE *f, unsigned long base, unsigned long size,
                   unsigned depth, unsigned *mask) {
    unsigned char h[60], c;
    char name[32];
    unsigned long pos = 8, len, data, end, names = 0, names_size = 0, ext;
    unsigned n, inner, result = 0;
    while (pos < size) {
        if (size-pos < 60 || read_at(f, base+pos, h, 60) ||
            h[58] != '`' || h[59] != '\n' || decimal(h+48, 10, &len))
            return 1;
        data = pos+60;
        if (len > size-data) return 1;
        end = data+len;
        if (len & 1) {
            if (end == size || read_at(f, base+end, &c, 1) || c != '\n')
                return 1;
            end++;
        }
        if (memchr(h, 0, 16)) return 1;
        memcpy(name, h, 16); n = 16;
        while (n && name[n-1] == ' ') n--;
        name[n] = 0;
        if (!strcmp(name, "//")) {
            names = base+data; names_size = len;
            pos = end; continue;
        }
        if (!strncmp(name, "#1/", 3)) {
            if (decimal(h+3, 13, &ext) || !ext || ext > len ||
                stored_name(f, base+data, ext, 0, name)) return 1;
            data += ext; len -= ext;
        } else if (name[0] == '/' && name[1] >= '0' && name[1] <= '9') {
            if (decimal(h+1, 15, &ext) || !names || ext >= names_size)
                return 1;
            if (ext && (read_at(f, names+ext-1, &c, 1) || c != '\n'))
                return 1;
            if (stored_name(f, names+ext, names_size-ext, 1, name)) return 1;
        } else if (n > 1 && name[n-1] == '/' && strcmp(name, "/SYM64/")) {
            name[n-1] = 0;
        }
        if (!symbol_name(name)) {
            if (inspect(f, base+data, len, depth+1, &inner) || !inner ||
                inner == RB_ARCH_UNIVERSAL || (result && result != inner))
                return 1;
            result = inner;
        }
        pos = end;
    }
    *mask = result;
    return 0;
}
static int inspect(FILE *f, unsigned long base, unsigned long size,
                   unsigned depth, unsigned *mask) {
    unsigned char h[28], a[40], cmd[8];
    unsigned long magic, count, bytes, pos, len, off[2], sz[2], cpu[2], i;
    unsigned inner, result;
    int le;
    *mask = 0;
    if (depth > 4) return 1;
    if (size < 4) return 0;
    if (read_at(f, base, h, 4)) return 1;
    magic = word(h, 0);
    if (magic == 0xfeedfacfUL || magic == 0xcffaedfeUL ||
        magic == 0xcafebabfUL || magic == 0xbfbafecaUL) return 1;
    if (magic == 0xfeedfaceUL || magic == 0xcefaedfeUL) {
        le = magic == 0xcefaedfeUL;
        if (size < 28 || read_at(f, base, h, 28)) return 1;
        result = cpu_mask(word(h+4, le));
        count = word(h+16, le); bytes = word(h+20, le);
        if (!result || bytes > size-28 || count > bytes/8) return 1;
        pos = 28;
        for (i = 0; i < count; i++) {
            if (28+bytes-pos < 8 || read_at(f, base+pos, cmd, 8)) return 1;
            len = word(cmd+4, le);
            if (len < 8 || (len & 3) || len > 28+bytes-pos) return 1;
            pos += len;
        }
        if (pos != 28+bytes) return 1;
        *mask = result;
        return 0;
    }
    if (magic == 0xcafebabeUL || magic == 0xbebafecaUL) {
        le = magic == 0xbebafecaUL;
        if (size < 8 || read_at(f, base, h, 8)) return 1;
        count = word(h+4, le);
        /* Only two supported CPUs, with no duplicate CPU slices. */
        if (!count || count > 2 || count > (size-8)/20 ||
            read_at(f, base+8, a, (unsigned)count*20)) return 1;
        result = 0;
        for (i = 0; i < count; i++) {
            cpu[i] = cpu_mask(word(a+i*20, le));
            off[i] = word(a+i*20+8, le); sz[i] = word(a+i*20+12, le);
            if (!cpu[i] || (result & cpu[i]) || !sz[i] ||
                off[i] < 8+count*20 || off[i] > size || sz[i] > size-off[i])
                return 1;
            result |= (unsigned)cpu[i];
        }
        if (count == 2 && off[0] < off[1]+sz[1] && off[1] < off[0]+sz[0])
            return 1;
        for (i = 0; i < count; i++) {
            if (inspect(f, base+off[i], sz[i], depth+1, &inner) || inner != cpu[i])
                return 1;
        }
        *mask = result;
        return 0;
    }
    if (magic == 0x213c6172UL) {
        if (size < 8 || read_at(f, base, h, 8) || memcmp(h, "!<arch>\n", 8))
            return 1;
        return archive(f, base, size, depth, mask);
    }
    return 0;
}
int macho_file_arches(const char *path, unsigned *mask, int *machine_code) {
    FILE *f;
    long size;
    unsigned result;
    int status;
    f = fopen(path, "rb");
    if (!f) return 1;
    if (fseek(f, 0, SEEK_END) || (size = ftell(f)) < 0) {
        fclose(f); return 1;
    }
    status = inspect(f, 0, (unsigned long)size, 0, &result);
    if (fclose(f)) status = 1;
    if (!status) { *mask = result; *machine_code = result != 0; }
    return status;
}
