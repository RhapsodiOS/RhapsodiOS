/*
 * Host check that -[IOAudio _initAudioHardwareSettings] defaults both
 * channels. OPENSTEP/Darwin called Right twice and Left twice.
 */

#define _CRT_SECURE_NO_WARNINGS 1

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", \
            __FILE__, __LINE__, #expression); \
        ++failures; \
    } \
} while (0)

static char *
read_file(const char *path)
{
    FILE *file;
    long size;
    char *buf;
    size_t n;

    file = fopen(path, "rb");
    if (file == 0)
        return 0;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    size = ftell(file);
    if (size < 0) {
        fclose(file);
        return 0;
    }
    rewind(file);
    buf = (char *)malloc((size_t)size + 1U);
    if (buf == 0) {
        fclose(file);
        return 0;
    }
    n = fread(buf, 1, (size_t)size, file);
    fclose(file);
    buf[n] = 0;
    return buf;
}

static int
extract_init_setters(const char *src, char names[][64], int max)
{
    const char *method;
    const char *body;
    const char *p;
    int depth;
    int count;

    method = strstr(src, "- (void) _initAudioHardwareSettings");
    if (method == 0)
        return -1;
    body = strchr(method, '{');
    if (body == 0)
        return -1;

    count = 0;
    depth = 0;
    for (p = body; *p != 0; p++) {
        if (*p == '{') {
            depth++;
            continue;
        }
        if (*p == '}') {
            depth--;
            if (depth == 0)
                break;
            continue;
        }
        if (strncmp(p, "[self _set", 10) == 0) {
            const char *name;
            size_t len;

            name = p + 6; /* skip "[self " */
            len = 0;
            while (name[len] != 0 && name[len] != ':' && name[len] != ']')
                len++;
            if (count >= max || len == 0 || len >= 63)
                return -1;
            memcpy(names[count], name, len);
            names[count][len] = 0;
            count++;
        }
    }
    return count;
}

int
main(void)
{
    char *src;
    char names[8][64];
    int count;
    const char *path = "../libDriver/Kernel/IOAudio.m";

    src = read_file(path);
    if (src == 0) {
        fprintf(stderr, "cannot read %s\n", path);
        return 1;
    }

    count = extract_init_setters(src, names, 8);
    CHECK(count == 4);
    if (count == 4) {
        CHECK(strcmp(names[0], "_setInputGainLeft") == 0);
        CHECK(strcmp(names[1], "_setInputGainRight") == 0);
        CHECK(strcmp(names[2], "_setOutputAttenuationLeft") == 0);
        CHECK(strcmp(names[3], "_setOutputAttenuationRight") == 0);
    }

    free(src);
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
