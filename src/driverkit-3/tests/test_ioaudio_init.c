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

static const char *
method_body(const char *src, const char *signature)
{
    const char *method;

    method = strstr(src, signature);
    if (method == 0)
        return 0;
    return strchr(method, '{');
}

static const char *
matching_brace(const char *body)
{
    const char *p;
    int depth;

    if (body == 0 || *body != '{')
        return 0;
    depth = 0;
    for (p = body; *p != 0; p++) {
        if (*p == '{')
            depth++;
        else if (*p == '}') {
            depth--;
            if (depth == 0)
                return p;
        }
    }
    return 0;
}

static int
contains_in_span(const char *start, const char *end, const char *text)
{
    size_t text_len;
    size_t span_len;
    const char *p;

    if (start == 0 || end == 0 || start >= end)
        return 0;
    text_len = strlen(text);
    span_len = (size_t)(end - start);
    if (text_len > span_len)
        return 0;
    for (p = start; p + text_len <= end; p++) {
        if (strncmp(p, text, text_len) == 0)
            return 1;
    }
    return 0;
}

static int
set_parameter_sets_right_input_gain(const char *src)
{
    const char *body;
    const char *end;
    const char *case_right;
    const char *case_end;
    const char *next_case;

    body = method_body(src, "- (BOOL) _setParameter:");
    end = matching_brace(body);
    if (body == 0 || end == 0)
        return 0;

    case_right = 0;
    for (next_case = body; next_case < end; next_case++) {
        if (strncmp(next_case, "case NX_SoundDeviceInputGainRight:", 34) == 0) {
            case_right = next_case;
            break;
        }
    }
    if (case_right == 0)
        return 0;

    next_case = case_right + 34;
    case_end = end;
    while (next_case < end) {
        if (strncmp(next_case, "case ", 5) == 0) {
            case_end = next_case;
            break;
        }
        if (strncmp(next_case, "default:", 8) == 0) {
            case_end = next_case;
            break;
        }
        next_case++;
    }
    return contains_in_span(case_right, case_end,
        "[self _setInputGainRight:(unsigned int)value]");
}

static int
init_runs_after_command_thread(const char *src)
{
    const char *body;
    const char *end;
    const char *settings;
    const char *command;
    const char *thread;

    body = method_body(src, "- initFromDeviceDescription:_description");
    end = matching_brace(body);
    if (body == 0 || end == 0)
        return 0;

    settings = 0;
    command = 0;
    thread = 0;
    {
        const char *p;
        for (p = body; p < end; p++) {
            if (settings == 0 &&
                strncmp(p, "[self _initAudioHardwareSettings]", 33) == 0)
                settings = p;
            if (command == 0 &&
                strncmp(p, "_audioCommand = [[AudioCommand alloc]", 37) == 0)
                command = p;
            if (thread == 0 &&
                strncmp(p, "IOForkThread((IOThreadFunc)ioThread", 35) == 0)
                thread = p;
        }
    }
    return settings != 0 && command != 0 && thread != 0 &&
        settings > command && settings > thread;
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
    CHECK(set_parameter_sets_right_input_gain(src));
    CHECK(init_runs_after_command_thread(src));

    free(src);
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
