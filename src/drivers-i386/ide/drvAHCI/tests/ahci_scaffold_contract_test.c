#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SOURCE_ROOT_SIZE 512
#define PATH_BUFFER_SIZE 1024

typedef int (*Validator)(const char *text);

static int failures;
static char source_root[SOURCE_ROOT_SIZE] = "..";

static int bounded_join(char *out, size_t out_size, const char *left,
                        const char *right)
{
    size_t left_length;
    size_t right_length;

    left_length = strlen(left);
    right_length = strlen(right);
    if (left_length > out_size || right_length > out_size ||
        left_length + 1U + right_length + 1U > out_size)
        return 0;
    memcpy(out, left, left_length);
    out[left_length] = '/';
    memcpy(out + left_length + 1U, right, right_length + 1U);
    return 1;
}

static int set_repository_root(const char *root)
{
    static const char project_path[] =
        "src/drivers-i386/ide/drvAHCI";
    char joined[SOURCE_ROOT_SIZE];

    if (!bounded_join(joined, sizeof(joined), root, project_path))
        return 0;
    memcpy(source_root, joined, strlen(joined) + 1U);
    return 1;
}

static int replace_once(char *out, size_t out_size, const char *input,
                        const char *old_text, const char *new_text)
{
    const char *match;
    size_t prefix_length;
    size_t old_length;
    size_t new_length;
    size_t suffix_length;

    match = strstr(input, old_text);
    if (match == NULL)
        return 0;
    prefix_length = (size_t)(match - input);
    old_length = strlen(old_text);
    new_length = strlen(new_text);
    suffix_length = strlen(match + old_length);
    if (prefix_length + new_length + suffix_length + 1U > out_size)
        return 0;
    memcpy(out, input, prefix_length);
    memcpy(out + prefix_length, new_text, new_length);
    memcpy(out + prefix_length + new_length, match + old_length,
           suffix_length + 1U);
    return 1;
}

static char *read_file(const char *path)
{
    FILE *file;
    long length;
    char *text;
    char full_path[PATH_BUFFER_SIZE];

    if (!bounded_join(full_path, sizeof(full_path), source_root, path))
        return NULL;
    file = fopen(full_path, "rb");
    if (file == NULL)
        return NULL;
    if (fseek(file, 0, SEEK_END) != 0 ||
        (length = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    text = (char *)malloc((size_t)length + 1U);
    if (text == NULL) {
        fclose(file);
        return NULL;
    }
    if (fread(text, 1, (size_t)length, file) != (size_t)length) {
        free(text);
        fclose(file);
        return NULL;
    }
    text[length] = '\0';
    fclose(file);
    return text;
}

static char *without_comments(const char *text, int hash_comments)
{
    size_t index;
    size_t output;
    size_t length;
    int block_comment;
    int line_comment;
    int line_start;
    int quoted;
    char quote;
    char *clean;

    length = strlen(text);
    clean = (char *)malloc(length + 1U);
    if (clean == NULL)
        return NULL;
    output = 0;
    block_comment = 0;
    line_comment = 0;
    line_start = 1;
    quoted = 0;
    quote = '\0';
    for (index = 0; index < length; ++index) {
        char current;
        char next;

        current = text[index];
        next = index + 1U < length ? text[index + 1U] : '\0';
        if (block_comment) {
            if (current == '*' && next == '/') {
                block_comment = 0;
                ++index;
            } else if (current == '\n') {
                clean[output++] = current;
                line_start = 1;
            }
            continue;
        }
        if (line_comment) {
            if (current == '\n') {
                line_comment = 0;
                clean[output++] = current;
                line_start = 1;
            }
            continue;
        }
        if (!quoted && current == '/' && next == '*') {
            block_comment = 1;
            ++index;
            continue;
        }
        if (!quoted && current == '/' && next == '/') {
            line_comment = 1;
            ++index;
            continue;
        }
        if (!quoted && hash_comments && line_start && current == '#') {
            line_comment = 1;
            continue;
        }
        clean[output++] = current;
        if (quoted && current == '\\' && next != '\0') {
            clean[output++] = next;
            ++index;
            continue;
        }
        if (current == '\'' || current == '"') {
            if (!quoted) {
                quoted = 1;
                quote = current;
            } else if (quote == current) {
                quoted = 0;
            }
        }
        if (current == '\n')
            line_start = 1;
        else if (!isspace((unsigned char)current))
            line_start = 0;
    }
    clean[output] = '\0';
    return clean;
}

static char *without_whitespace(const char *text)
{
    size_t input;
    size_t output;
    size_t length;
    char *normalized;

    length = strlen(text);
    normalized = (char *)malloc(length + 1U);
    if (normalized == NULL)
        return NULL;
    output = 0;
    for (input = 0; input < length; ++input) {
        if (!isspace((unsigned char)text[input]))
            normalized[output++] = text[input];
    }
    normalized[output] = '\0';
    return normalized;
}

static int has_exact_line(const char *text, const char *expected,
                          int hash_comments)
{
    char *clean;
    char *cursor;
    int found;

    clean = without_comments(text, hash_comments);
    if (clean == NULL)
        return 0;
    cursor = clean;
    found = 0;
    while (*cursor != '\0') {
        char *begin;
        char *end;
        char saved;

        begin = cursor;
        while (*begin == ' ' || *begin == '\t' || *begin == '\r')
            ++begin;
        end = strchr(begin, '\n');
        if (end == NULL)
            end = begin + strlen(begin);
        while (end > begin &&
               (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r'))
            --end;
        saved = *end;
        *end = '\0';
        if (strcmp(begin, expected) == 0)
            found = 1;
        *end = saved;
        if (found || saved == '\0')
            break;
        cursor = end + 1;
    }
    free(clean);
    return found;
}

static int has_scoped_expression(const char *text, const char *scope_begin,
                                 const char *scope_end,
                                 const char *expression)
{
    char *clean;
    char *begin;
    char *end;
    char *scope;
    char *normalized_scope;
    char *normalized_expression;
    size_t scope_length;
    int found;

    clean = without_comments(text, 0);
    if (clean == NULL)
        return 0;
    begin = strstr(clean, scope_begin);
    end = begin == NULL ? NULL : strstr(begin + strlen(scope_begin), scope_end);
    if (begin == NULL || end == NULL) {
        free(clean);
        return 0;
    }
    scope_length = (size_t)(end - begin);
    scope = (char *)malloc(scope_length + 1U);
    if (scope == NULL) {
        free(clean);
        return 0;
    }
    memcpy(scope, begin, scope_length);
    scope[scope_length] = '\0';
    normalized_scope = without_whitespace(scope);
    normalized_expression = without_whitespace(expression);
    found = normalized_scope != NULL && normalized_expression != NULL &&
            strstr(normalized_scope, normalized_expression) != NULL;
    free(normalized_expression);
    free(normalized_scope);
    free(scope);
    free(clean);
    return found;
}

static int has_identifier(const char *text, const char *identifier)
{
    char *clean;
    char *match;
    size_t length;
    int found;

    clean = without_comments(text, 0);
    if (clean == NULL)
        return 0;
    length = strlen(identifier);
    found = 0;
    match = clean;
    while ((match = strstr(match, identifier)) != NULL) {
        int before_ok;
        int after_ok;

        before_ok = match == clean ||
            (!isalnum((unsigned char)match[-1]) && match[-1] != '_');
        after_ok = !isalnum((unsigned char)match[length]) &&
                   match[length] != '_';
        if (before_ok && after_ok) {
            found = 1;
            break;
        }
        match += length;
    }
    free(clean);
    return found;
}

static int valid_default_table(const char *text)
{
    return has_exact_line(text, "\"Class Names\" = \"AHCIController\";", 1) &&
           has_exact_line(text, "\"Auto Detect IDs\" = \"0x29228086\";", 1) &&
           has_exact_line(text, "\"Boot Driver\";", 1);
}

static int valid_controller_header(const char *text)
{
    return has_exact_line(text, "@interface AHCIController : IODirectDevice", 0) &&
           has_exact_line(text, "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;", 0) &&
           has_exact_line(text, "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;", 0) &&
           has_exact_line(text, "- (void)interruptOccurred;", 0);
}

static int valid_controller_source(const char *text)
{
    static const char probe[] =
        "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription";
    static const char initializer[] =
        "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription";

    return has_exact_line(text, "#import <driverkit/i386/IOPCIDirectDevice.h>", 0) &&
           has_exact_line(text, "#define AHCI_ICH9_PCI_ID 0x29228086", 0) &&
           has_exact_line(text, "#define AHCI_PCI_CLASS_CODE 0x010601", 0) &&
           has_exact_line(text, "@implementation AHCIController", 0) &&
           has_scoped_expression(text, probe, initializer,
               "AHCIController *controller;") &&
           has_scoped_expression(text, probe, initializer,
               "controller = [[self alloc] initFromDeviceDescription:deviceDescription];") &&
           has_scoped_expression(text, probe, initializer,
               "if (controller == nil) return NO;") &&
           has_scoped_expression(text, probe, initializer,
               "[controller free]; return NO;") &&
           !has_scoped_expression(text, probe, initializer, "return YES;") &&
           has_scoped_expression(text, initializer, "@end",
               "[self getPCIConfigData:&pciID atRegister:0x00] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "@end",
               "pciID != AHCI_ICH9_PCI_ID") &&
           has_scoped_expression(text, initializer, "@end",
               "[self getPCIConfigData:&classRevision atRegister:0x08] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "@end",
               "((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE") &&
           has_scoped_expression(text, initializer, "@end",
               "IOLog(\"%s: Intel AHCI 8086:2922 class 01:06:01 matched; attachment deferred\\n\", [self name]);") &&
           has_scoped_expression(text, initializer, "@end", "return self;") &&
           !has_identifier(text, "IdeController") &&
           !has_identifier(text, "AtapiController") &&
           !has_identifier(text, "IdeDisk");
}

static int valid_postload(const char *text)
{
    return has_exact_line(text, "#define N_AHCI_PARTITIONS 8", 0) &&
           has_exact_line(text, "#define N_AHCI_DEVICES 32", 0) &&
           has_exact_line(text, "#define AHCI_BLOCK_MAJOR 3", 0) &&
           has_exact_line(text, "#define AHCI_CHARACTER_MAJOR 15", 0) &&
           has_scoped_expression(text, "int main(", "static int makeNode",
               "for (unit = 0; unit < N_AHCI_DEVICES; ++unit)") &&
           has_scoped_expression(text, "int main(", "static int makeNode",
               "for (partition = 0; partition < N_AHCI_PARTITIONS; ++partition)") &&
           has_scoped_expression(text, "int main(", "static int makeNode",
               "makeNode(\"hd\", unit, AHCI_BLOCK_MAJOR, partition, DEV_MOD_BLOCK)") &&
           has_scoped_expression(text, "int main(", "static int makeNode",
               "makeNode(\"rhd\", unit, AHCI_CHARACTER_MAJOR, partition, DEV_MOD_CHAR)") &&
           has_scoped_expression(text, "static int makeNode", "return 0;\n}",
               "minor = unit * N_AHCI_PARTITIONS + partition;") &&
           has_scoped_expression(text, "static int makeNode", "return 0;\n}",
               "device = (major << 8) | minor;") &&
           has_scoped_expression(text, "static int makeNode", "return 0;\n}",
               "if (mknod(path, mode, device))");
}

static void require_line_file(const char *path, const char *line,
                              int hash_comments)
{
    char *text;

    text = read_file(path);
    if (text == NULL || !has_exact_line(text, line, hash_comments)) {
        fprintf(stderr, "missing exact line %s in %s\n", line, path);
        ++failures;
    }
    free(text);
}

static void require_valid_file(const char *path, Validator validator)
{
    char *text;

    text = read_file(path);
    if (text == NULL || !validator(text)) {
        fprintf(stderr, "invalid contract in %s\n", path);
        ++failures;
    }
    free(text);
}

static void require_absent_identifier(const char *path,
                                      const char *identifier)
{
    char *text;

    text = read_file(path);
    if (text == NULL || has_identifier(text, identifier)) {
        fprintf(stderr, "unexpected identifier %s in %s\n", identifier, path);
        ++failures;
    }
    free(text);
}

static void expect_invalid(const char *name, Validator validator,
                           const char *text)
{
    if (validator(text)) {
        fprintf(stderr, "mutation accepted: %s\n", name);
        ++failures;
    }
}

static void test_validator_mutations(void)
{
    static const char default_ok[] =
        "\"Class Names\" = \"AHCIController\";\n"
        "\"Auto Detect IDs\" = \"0x29228086\";\n"
        "\"Boot Driver\";\n";
    static const char default_no_boot[] =
        "\"Class Names\" = \"AHCIController\";\n"
        "\"Auto Detect IDs\" = \"0x29228086\";\n";
    static const char default_commented_boot[] =
        "\"Class Names\" = \"AHCIController\";\n"
        "\"Auto Detect IDs\" = \"0x29228086\";\n"
        "/* \"Boot Driver\"; */\n";
    static const char header_ok[] =
        "@interface AHCIController : IODirectDevice\n"
        "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;\n"
        "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;\n"
        "- (void)interruptOccurred;\n";
    static const char header_no_interrupt[] =
        "@interface AHCIController : IODirectDevice\n"
        "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;\n"
        "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;\n";
    char postload_ok[2048];
    char postload_31_devices[2048];
    char postload_7_partitions[2048];
    char controller_ok[4096];
    char mutation[4096];
    char long_root[600];

    strcpy(postload_ok,
        "#define N_AHCI_PARTITIONS 8\n#define N_AHCI_DEVICES 32\n"
        "#define AHCI_BLOCK_MAJOR 3\n#define AHCI_CHARACTER_MAJOR 15\n");
    strcat(postload_ok,
        "int main(int argc, char **argv) {\n"
        "for (unit = 0; unit < N_AHCI_DEVICES; ++unit)\n"
        "for (partition = 0; partition < N_AHCI_PARTITIONS; ++partition)\n");
    strcat(postload_ok,
        "makeNode(\"hd\", unit, AHCI_BLOCK_MAJOR, partition, DEV_MOD_BLOCK);\n"
        "makeNode(\"rhd\", unit, AHCI_CHARACTER_MAJOR, partition, DEV_MOD_CHAR);\n"
        "}\nstatic int makeNode(char *name) {\n");
    strcat(postload_ok,
        "minor = unit * N_AHCI_PARTITIONS + partition;\n"
        "device = (major << 8) | minor;\n"
        "if (mknod(path, mode, device)) return -1;\nreturn 0;\n}\n");

    strcpy(controller_ok,
        "#import <driverkit/i386/IOPCIDirectDevice.h>\n"
        "#define AHCI_ICH9_PCI_ID 0x29228086\n"
        "#define AHCI_PCI_CLASS_CODE 0x010601\n"
        "@implementation AHCIController\n");
    strcat(controller_ok,
        "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription {\n"
        "AHCIController *controller;\n"
        "controller = [[self alloc] initFromDeviceDescription:deviceDescription];\n"
        "if (controller == nil) return NO;\n[controller free];\nreturn NO;\n}\n");
    strcat(controller_ok,
        "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription {\n"
        "if ([self getPCIConfigData:&pciID atRegister:0x00] != IO_R_SUCCESS ||\n"
        "pciID != AHCI_ICH9_PCI_ID ||\n");
    strcat(controller_ok,
        "[self getPCIConfigData:&classRevision atRegister:0x08] != IO_R_SUCCESS ||\n"
        "((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE) return nil;\n");
    strcat(controller_ok,
        "IOLog(\"%s: Intel AHCI 8086:2922 class 01:06:01 matched; attachment deferred\\n\", [self name]);\n"
        "return self;\n}\n@end\n");

    if (!valid_default_table(default_ok) ||
        !valid_controller_header(header_ok) ||
        !valid_postload(postload_ok) ||
        !valid_controller_source(controller_ok)) {
        fprintf(stderr, "valid mutation fixture rejected\n");
        ++failures;
    }
    expect_invalid("Boot Driver removed", valid_default_table,
                   default_no_boot);
    expect_invalid("Boot Driver commented", valid_default_table,
                   default_commented_boot);
    expect_invalid("interrupt declaration removed", valid_controller_header,
                   header_no_interrupt);
    if (!replace_once(postload_31_devices, sizeof(postload_31_devices),
                      postload_ok, "#define N_AHCI_DEVICES 32",
                      "#define N_AHCI_DEVICES 31")) {
        fprintf(stderr, "device-count mutation replacement failed\n");
        ++failures;
    } else {
        expect_invalid("31 devices", valid_postload, postload_31_devices);
    }
    if (!replace_once(postload_7_partitions, sizeof(postload_7_partitions),
                      postload_ok, "#define N_AHCI_PARTITIONS 8",
                      "#define N_AHCI_PARTITIONS 7")) {
        fprintf(stderr, "partition-count mutation replacement failed\n");
        ++failures;
    } else {
        expect_invalid("7 partitions", valid_postload,
                       postload_7_partitions);
    }

    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "0x010601", "0x010600"))
        ++failures;
    expect_invalid("wrong PCI class tuple", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      ">> 8", ">> 7"))
        ++failures;
    expect_invalid("wrong PCI class extraction", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "return NO;\n}\n- init",
                      "return YES;\n}\n- init"))
        ++failures;
    expect_invalid("probe returns YES", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "[controller free];", "/* controller free */"))
        ++failures;
    expect_invalid("probe omits free", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), postload_ok,
                      "mknod(path, mode, device)",
                      "mknod(path, mode, minor)"))
        ++failures;
    expect_invalid("wrong mknod device relation", valid_postload, mutation);

    memset(long_root, 'x', sizeof(long_root) - 1U);
    long_root[sizeof(long_root) - 1U] = '\0';
    if (set_repository_root(long_root)) {
        fprintf(stderr, "overlong source root accepted\n");
        ++failures;
    }
}

static void test_bundle_contract(void)
{
    require_line_file("Makefile", "NAME = AHCI", 1);
    require_line_file("Makefile.preamble", "INCLUDED_ARCHS = i386", 1);
    require_line_file("PB.project", "PROJECTNAME = AHCI;", 0);
    require_line_file("AHCI.drvproj/Makefile", "NAME = AHCI", 1);
    require_line_file("AHCI.drvproj/Makefile.preamble",
                      "INCLUDED_ARCHS = i386", 1);
    require_line_file("AHCI.drvproj/PB.project", "PROJECTNAME = AHCI;", 0);
    require_line_file("AHCI.drvproj/PB.project",
                      "SUBPROJECTS = (AHCI.lksproj, PostLoad.tproj);", 0);
    require_valid_file("AHCI.drvproj/Default.table", valid_default_table);
    require_line_file("AHCI.drvproj/DriverInfo", "DRIVER_NAME=\"AHCI\"", 1);
    require_line_file("AHCI.drvproj/English.lproj/Localizable.strings",
                      "\"AHCI\" = \"AHCI Controller\";", 1);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Makefile", "NAME = AHCI", 1);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Makefile.preamble",
                      "INCLUDED_ARCHS = i386", 1);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Makefile",
                      "CFILES = AHCICommand.c AHCIState.c", 1);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Makefile",
                      "CLASSES = AHCIController.m", 1);
    require_line_file("AHCI.drvproj/AHCI.lksproj/PB.project",
                      "C_FILES = (AHCICommand.c, AHCIState.c);", 0);
    require_line_file("AHCI.drvproj/AHCI.lksproj/PB.project",
                      "CLASSES = (AHCIController.m);", 0);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Load_Commands.sect",
                      "WIRE", 1);
    require_absent_identifier("AHCI.drvproj/Default.table", "IdeController");
    require_absent_identifier("AHCI.drvproj/Default.table", "AtapiController");
    require_absent_identifier("AHCI.drvproj/Default.table", "IdeDisk");
    require_line_file("AHCI.drvproj/PostLoad.tproj/Makefile",
                      "NAME = PostLoad", 1);
    require_line_file("AHCI.drvproj/PostLoad.tproj/Makefile.preamble",
                      "INCLUDED_ARCHS = i386", 1);
    require_line_file("AHCI.drvproj/PostLoad.tproj/PB.project",
                      "PROJECTNAME = PostLoad;", 0);
    require_line_file("AHCI.drvproj/PostLoad.tproj/PB.project",
                      "PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make;", 0);
    require_line_file("AHCI.drvproj/PostLoad.tproj/PB.project",
                      "WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make;", 0);
    require_valid_file("AHCI.drvproj/PostLoad.tproj/PostLoad.m",
                       valid_postload);
}

static void test_controller_contract(void)
{
    require_valid_file("AHCI.drvproj/AHCI.lksproj/AHCIController.h",
                       valid_controller_header);
    require_valid_file("AHCI.drvproj/AHCI.lksproj/AHCIController.m",
                       valid_controller_source);
}

int main(int argc, char **argv)
{
    test_validator_mutations();
    if (argc > 1 && !set_repository_root(argv[1])) {
        fprintf(stderr, "source root is too long\n");
        return EXIT_FAILURE;
    }
    test_bundle_contract();
    test_controller_contract();
    if (failures != 0) {
        fprintf(stderr, "ahci_scaffold_contract_test: %d failure(s)\n",
                failures);
        return EXIT_FAILURE;
    }
    printf("ahci_scaffold_contract_test: all tests passed\n");
    return EXIT_SUCCESS;
}
