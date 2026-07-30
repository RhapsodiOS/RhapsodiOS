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

static int has_scoped_ordered_pair(const char *text, const char *scope_begin,
                                   const char *scope_end,
                                   const char *first_expression,
                                   const char *second_expression)
{
    char *clean;
    char *begin;
    char *end;
    char *scope;
    char *normalized_scope;
    char *normalized_first;
    char *normalized_second;
    char *first_match;
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
    normalized_first = without_whitespace(first_expression);
    normalized_second = without_whitespace(second_expression);
    found = 0;
    if (normalized_scope != NULL && normalized_first != NULL &&
        normalized_second != NULL) {
        first_match = strstr(normalized_scope, normalized_first);
        found = first_match != NULL &&
            strstr(first_match + strlen(normalized_first),
                   normalized_second) != NULL;
    }
    free(normalized_second);
    free(normalized_first);
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
           has_exact_line(text, "#import \"AHCIHBA.h\"", 0) &&
           has_exact_line(text, "#import \"AHCIPCI.h\"", 0) &&
           has_exact_line(text, "#import \"AHCIShared.h\"", 0) &&
           has_exact_line(text, "@implementation AHCIController", 0) &&
           has_scoped_expression(text, "static int AHCIMMIOOffsetValid",
               "static AHCIU32 AHCIMMIORead",
               "mmio == 0 || mmio->base == 0 || mmio->length < sizeof(AHCIU32) || (offset & 3U) != 0 || offset > mmio->length - sizeof(AHCIU32)") &&
           has_scoped_expression(text, probe, initializer,
               "AHCIController *controller;") &&
           has_scoped_expression(text, probe, initializer,
               "controller = [[self alloc] initFromDeviceDescription:deviceDescription];") &&
           has_scoped_expression(text, probe, initializer,
               "if (controller == nil) return NO;") &&
           has_scoped_expression(text, probe, initializer,
               "if ([controller registerDevice] == nil) { [controller free]; return NO; }") &&
           has_scoped_expression(text, probe, initializer, "return YES;") &&
           has_scoped_expression(text, initializer, "- free",
               "pciDeviceDescription = deviceDescription;") &&
           has_scoped_expression(text, initializer, "- free",
               "[IODirectDevice getPCIConfigData:&pciID atRegister:AHCI_PCI_ID_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "pciID != AHCI_ICH9_PCI_ID") &&
           has_scoped_expression(text, initializer, "- free",
               "[IODirectDevice getPCIConfigData:&classRevision atRegister:AHCI_PCI_CLASS_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE") &&
           has_scoped_expression(text, initializer, "- free",
               "[IODirectDevice getPCIConfigData:&bar5 atRegister:AHCI_PCI_BAR5_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "AHCIPCIValidateBAR5((AHCIU32)bar5, AHCI_ABAR_LENGTH, &abarPhysical) != AHCI_PCI_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "originalPCIConfig = (AHCIU32)command;") &&
           has_scoped_expression(text, initializer, "- free",
               "AHCIPCIPlanCommand(originalPCIConfig, &enabledCommand, &pciCommandRestore, &commandChanged) != AHCI_PCI_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "if (pciCommandChanged) { pciCommandWriteAttempted = YES; if ([IODirectDevice setPCIConfigData:enabledCommand atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS) { [self free]; return nil; } }") &&
           has_scoped_expression(text, initializer, "- free",
               "if ([IODirectDevice getPCIConfigData:&commandReadback atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS || AHCIPCIValidateCommandReadback((AHCIU32)commandReadback) != AHCI_PCI_SUCCESS) { [self free]; return nil; }") &&
           has_scoped_expression(text, initializer, "- free",
               "memoryRange.start = abarPhysical;") &&
           has_scoped_expression(text, initializer, "- free",
               "memoryRange.size = AHCI_ABAR_LENGTH;") &&
           has_scoped_expression(text, initializer, "- free",
               "[deviceDescription setMemoryRangeList:&memoryRange num:1] != IO_R_SUCCESS") &&
           has_scoped_expression(text, initializer, "- free",
               "[super initFromDeviceDescription:deviceDescription] == nil") &&
           has_scoped_expression(text, initializer, "- free",
               "mapResult = [self mapMemoryRange:0 to:&abarAddress findSpace:YES cache:IO_CacheOff]; if (mapResult != IO_R_SUCCESS) { [self free]; return nil; } abarMapped = YES; if (abarAddress == 0 || (abarAddress & 3U) != 0) { [self free]; return nil; }") &&
           has_scoped_expression(text, initializer, "- free",
               "if (AHCIHBAInitialize(&ops, &hbaInfo) != AHCI_HBA_SUCCESS) { [self free]; return nil; }") &&
           has_scoped_expression(text, initializer, "- free",
               "mmio.base = (volatile unsigned char *)abarAddress; mmio.length = AHCI_ABAR_LENGTH; ops.context = &mmio; ops.read = AHCIMMIORead; ops.write = AHCIMMIOWrite; ops.delay = AHCIDelayMilliseconds; ops.barrier = AHCIMMIOBarrier;") &&
           has_scoped_expression(text, initializer, "- free",
               "IOLog(\"%s: Intel AHCI 8086:2922 class 01:06:01 version %x CAP %08x CAP2 %08x PI %08x attached\\n\", [self name], hbaInfo.version, hbaInfo.capabilities, hbaInfo.capabilities2, hbaInfo.portsImplemented);") &&
           has_scoped_expression(text, initializer, "- free", "return self;") &&
           has_scoped_expression(text, "- free", "@end",
               "[self unmapMemoryRange:0 from:abarAddress]") &&
           has_scoped_expression(text, "- free", "@end",
               "if (pciCommandWriteAttempted && pciCommandChanged)") &&
           has_scoped_expression(text, "- free", "@end",
               "[IODirectDevice setPCIConfigData:pciCommandRestore atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:pciDeviceDescription]") &&
           has_scoped_ordered_pair(text, "- free", "@end",
               "[self unmapMemoryRange:0 from:abarAddress]",
               "[IODirectDevice setPCIConfigData:pciCommandRestore atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:pciDeviceDescription]") &&
           has_scoped_ordered_pair(text, "- free", "@end",
               "[IODirectDevice setPCIConfigData:pciCommandRestore atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:pciDeviceDescription]",
               "return [super free];") &&
           !has_identifier(text, "IdeController") &&
           !has_identifier(text, "AtapiController") &&
           !has_identifier(text, "IdeDisk") &&
           !has_identifier(text, "AHCIPort") &&
           !has_identifier(text, "IOMalloc") &&
           !has_identifier(text, "IOMallocLow");
}

static int valid_link_makefile(const char *text)
{
    return has_exact_line(text,
        "CFILES = AHCICommand.c AHCIState.c AHCIHBA.c AHCIPCI.c", 1) &&
        has_exact_line(text, "CLASSES = AHCIController.m", 1) &&
        has_exact_line(text,
        "HFILES = AHCIController.h AHCIRegs.h AHCICommand.h AHCIState.h AHCIHBA.h AHCIPCI.h AHCIShared.h",
        1) &&
        !has_identifier(text, "AHCIPort");
}

static int valid_link_project(const char *text)
{
    return has_exact_line(text,
        "C_FILES = (AHCICommand.c, AHCIState.c, AHCIHBA.c, AHCIPCI.c);", 0) &&
        has_exact_line(text, "CLASSES = (AHCIController.m);", 0) &&
        has_exact_line(text,
        "H_FILES = (AHCIController.h, AHCIRegs.h, AHCICommand.h, AHCIState.h, AHCIHBA.h, AHCIPCI.h, AHCIShared.h);",
        0) &&
        !has_identifier(text, "AHCIPort");
}

static int valid_hba_source(const char *text)
{
    return has_exact_line(text, "#include \"AHCIHBA.h\"", 0) &&
           has_scoped_ordered_pair(text, "static void ahci_write",
               "static AHCIHBAResult ahci_bios_handoff",
               "ops->write(ops->context, offset, value);",
               "ops->barrier(ops->context);") &&
           has_scoped_expression(text, "AHCIHBAResult AHCIHBAInitialize",
               "}", "info->capabilities = ops->read(ops->context, AHCI_REG_CAP);") &&
           has_scoped_expression(text, "static void ahci_disable_interrupts",
               "AHCIHBAResult AHCIHBAInitialize",
               "(ghc | AHCI_GHC_AE) & ~(AHCI_GHC_IE | AHCI_GHC_HR)") &&
           has_scoped_expression(text, "static void ahci_disable_interrupts",
               "AHCIHBAResult AHCIHBAInitialize",
               "ahci_write(ops, AHCI_REG_IS, 0xffffffffU);") &&
           has_scoped_expression(text, "result = ahci_bios_handoff",
               "ghc = ops->read(ops->context, AHCI_REG_GHC);",
               "if (result != AHCI_HBA_SUCCESS) { return result; }") &&
           has_identifier(text, "AHCI_BOHC_BB_OBSERVE_MS") &&
           has_identifier(text, "AHCI_BOHC_HANDOFF_TIMEOUT_MS") &&
           has_identifier(text, "AHCI_HBA_RESET_TIMEOUT_MS") &&
           !has_identifier(text, "AHCIPort") &&
           !has_identifier(text, "IOMalloc") &&
           !has_identifier(text, "IOMallocLow");
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
    char controller_ok[16384];
    char mutation[16384];
    char link_makefile_ok[512];
    char hba_source_ok[2048];
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
        "#import \"AHCIHBA.h\"\n#import \"AHCIPCI.h\"\n"
        "#import \"AHCIShared.h\"\n"
        "static int AHCIMMIOOffsetValid(AHCIMMIOContext *mmio, AHCIU32 offset) {\n"
        "return !(mmio == 0 || mmio->base == 0 || mmio->length < sizeof(AHCIU32) || (offset & 3U) != 0 || offset > mmio->length - sizeof(AHCIU32));\n}\n"
        "static AHCIU32 AHCIMMIORead(void *context, AHCIU32 offset) { return 0; }\n"
        "@implementation AHCIController\n");
    strcat(controller_ok,
        "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription {\n"
        "AHCIController *controller;\n"
        "controller = [[self alloc] initFromDeviceDescription:deviceDescription];\n"
        "if (controller == nil) return NO;\n"
        "if ([controller registerDevice] == nil) { [controller free]; return NO; }\n"
        "return YES;\n}\n");
    strcat(controller_ok,
        "- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription {\n"
        "pciDeviceDescription = deviceDescription;\n"
        "if ([IODirectDevice getPCIConfigData:&pciID atRegister:AHCI_PCI_ID_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||\n"
        "pciID != AHCI_ICH9_PCI_ID ||\n");
    strcat(controller_ok,
        "[IODirectDevice getPCIConfigData:&classRevision atRegister:AHCI_PCI_CLASS_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||\n"
        "((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE) return nil;\n");
    strcat(controller_ok,
        "if ([IODirectDevice getPCIConfigData:&bar5 atRegister:AHCI_PCI_BAR5_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||\n"
        "AHCIPCIValidateBAR5((AHCIU32)bar5, AHCI_ABAR_LENGTH, &abarPhysical) != AHCI_PCI_SUCCESS) return nil;\n");
    strcat(controller_ok,
        "originalPCIConfig = (AHCIU32)command;\n"
        "if (AHCIPCIPlanCommand(originalPCIConfig, &enabledCommand, &pciCommandRestore, &commandChanged) != AHCI_PCI_SUCCESS) return nil;\n"
        "if (pciCommandChanged) { pciCommandWriteAttempted = YES;\n"
        "if ([IODirectDevice setPCIConfigData:enabledCommand atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS) { [self free]; return nil; } }\n");
    strcat(controller_ok,
        "if ([IODirectDevice getPCIConfigData:&commandReadback atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||\n"
        "AHCIPCIValidateCommandReadback((AHCIU32)commandReadback) != AHCI_PCI_SUCCESS) { [self free]; return nil; }\n");
    strcat(controller_ok,
        "memoryRange.start = abarPhysical;\nmemoryRange.size = AHCI_ABAR_LENGTH;\n"
        "if ([deviceDescription setMemoryRangeList:&memoryRange num:1] != IO_R_SUCCESS) return nil;\n"
        "if ([super initFromDeviceDescription:deviceDescription] == nil) return nil;\n");
    strcat(controller_ok,
        "mapResult = [self mapMemoryRange:0 to:&abarAddress findSpace:YES cache:IO_CacheOff];\n"
        "if (mapResult != IO_R_SUCCESS) { [self free]; return nil; }\n"
        "abarMapped = YES;\n"
        "if (abarAddress == 0 || (abarAddress & 3U) != 0) { [self free]; return nil; }\n");
    strcat(controller_ok,
        "mmio.base = (volatile unsigned char *)abarAddress; mmio.length = AHCI_ABAR_LENGTH;\n"
        "ops.context = &mmio; ops.read = AHCIMMIORead; ops.write = AHCIMMIOWrite;\n"
        "ops.delay = AHCIDelayMilliseconds; ops.barrier = AHCIMMIOBarrier;\n"
        "if (AHCIHBAInitialize(&ops, &hbaInfo) != AHCI_HBA_SUCCESS) { [self free]; return nil; }\n");
    strcat(controller_ok,
        "IOLog(\"%s: Intel AHCI 8086:2922 class 01:06:01 version %x CAP %08x CAP2 %08x PI %08x attached\\n\", [self name], hbaInfo.version, hbaInfo.capabilities, hbaInfo.capabilities2, hbaInfo.portsImplemented);\n"
        "return self;\n}\n- free { if (abarMapped) { [self unmapMemoryRange:0 from:abarAddress]; }\n"
        "if (pciCommandWriteAttempted && pciCommandChanged) {\n"
        "[IODirectDevice setPCIConfigData:pciCommandRestore atRegister:AHCI_PCI_COMMAND_REGISTER withDeviceDescription:pciDeviceDescription]; }\n"
        "return [super free]; }\n@end\n");

    strcpy(link_makefile_ok,
        "CFILES = AHCICommand.c AHCIState.c AHCIHBA.c AHCIPCI.c\n"
        "CLASSES = AHCIController.m\n"
        "HFILES = AHCIController.h AHCIRegs.h AHCICommand.h AHCIState.h AHCIHBA.h AHCIPCI.h AHCIShared.h\n");
    strcpy(hba_source_ok,
        "#include \"AHCIHBA.h\"\n"
        "static void ahci_write(const AHCIHBAOps *ops, AHCIU32 offset, AHCIU32 value) {\n"
        "ops->write(ops->context, offset, value);\n"
        "ops->barrier(ops->context);\n}\n"
        "static AHCIHBAResult ahci_bios_handoff(const AHCIHBAOps *ops, AHCIU32 cap2) { return AHCI_HBA_SUCCESS; }\n"
        "static void ahci_disable_interrupts(const AHCIHBAOps *ops) {\n"
        "ahci_write(ops, AHCI_REG_GHC, (ghc | AHCI_GHC_AE) & ~(AHCI_GHC_IE | AHCI_GHC_HR));\n"
        "ahci_write(ops, AHCI_REG_IS, 0xffffffffU);\n}\n");
    strcat(hba_source_ok,
        "AHCIHBAResult AHCIHBAInitialize(const AHCIHBAOps *ops, AHCIHBAInfo *info) {\n"
        "info->capabilities = ops->read(ops->context, AHCI_REG_CAP);\n"
        "AHCI_BOHC_BB_OBSERVE_MS; AHCI_BOHC_HANDOFF_TIMEOUT_MS;\n"
        "result = ahci_bios_handoff(ops, info->capabilities2);\n"
        "if (result != AHCI_HBA_SUCCESS) { return result; }\n"
        "ghc = ops->read(ops->context, AHCI_REG_GHC);\n"
        "AHCI_HBA_RESET_TIMEOUT_MS;\n}\n");

    if (!valid_default_table(default_ok) ||
        !valid_controller_header(header_ok) ||
        !valid_postload(postload_ok) ||
        !valid_controller_source(controller_ok) ||
        !valid_link_makefile(link_makefile_ok) ||
        !valid_hba_source(hba_source_ok)) {
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
                      "AHCI_PCI_CLASS_CODE", "0x010600"))
        ++failures;
    expect_invalid("wrong PCI class tuple", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      ">> 8", ">> 7"))
        ++failures;
    expect_invalid("wrong PCI class extraction", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "return YES;\n}\n- init",
                      "return NO;\n}\n- init"))
        ++failures;
    expect_invalid("probe omits successful claim", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "[controller registerDevice]", "controller"))
        ++failures;
    expect_invalid("probe omits registration", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "AHCI_PCI_BAR5_REGISTER", "AHCI_PCI_CLASS_REGISTER"))
        ++failures;
    expect_invalid("BAR5 read removed", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "AHCIPCIValidateBAR5((AHCIU32)bar5, AHCI_ABAR_LENGTH, &abarPhysical)",
                      "AHCI_PCI_SUCCESS"))
        ++failures;
    expect_invalid("PCI BAR helper removed", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "AHCIPCIPlanCommand(originalPCIConfig, &enabledCommand, &pciCommandRestore, &commandChanged)",
                      "AHCI_PCI_SUCCESS"))
        ++failures;
    expect_invalid("PCI command helper removed", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "AHCIPCIValidateCommandReadback((AHCIU32)commandReadback)",
                      "AHCI_PCI_SUCCESS"))
        ++failures;
    expect_invalid("PCI readback helper removed", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "memoryRange.size = AHCI_ABAR_LENGTH;",
                      "memoryRange.size = 0x1000U;"))
        ++failures;
    expect_invalid("ABAR span shortened", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "cache:IO_CacheOff", "cache:IO_CacheDefault"))
        ++failures;
    expect_invalid("ABAR cache enabled", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "abarMapped = YES;\nif (abarAddress == 0",
                      "if (abarAddress == 0"))
        ++failures;
    expect_invalid("invalid successful map leaks", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "AHCIHBAInitialize(&ops, &hbaInfo)",
                      "AHCI_HBA_SUCCESS"))
        ++failures;
    expect_invalid("production HBA call removed", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "ops.context = &mmio;", "ops.context = abar;"))
        ++failures;
    expect_invalid("unguarded MMIO context wired", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "if (pciCommandWriteAttempted && pciCommandChanged)",
                      "if (0)"))
        ++failures;
    expect_invalid("PCI rollback removed", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "return [super free];", "return self;"))
        ++failures;
    expect_invalid("super free removed", valid_controller_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), controller_ok,
                      "return self;\n}\n- free",
                      "IOMalloc(1); return self;\n}\n- free"))
        ++failures;
    expect_invalid("port allocation introduced", valid_controller_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), link_makefile_ok,
                      "CFILES = AHCICommand.c AHCIState.c AHCIHBA.c",
                      "CFILES = AHCICommand.c AHCIState.c"))
        ++failures;
    expect_invalid("HBA production source removed", valid_link_makefile,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), link_makefile_ok,
                      " AHCIPCI.c", ""))
        ++failures;
    expect_invalid("PCI production source removed", valid_link_makefile,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), hba_source_ok,
                      "~(AHCI_GHC_IE | AHCI_GHC_HR)",
                      "~AHCI_GHC_IE"))
        ++failures;
    expect_invalid("reset cleanup leaves HR asserted", valid_hba_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), hba_source_ok,
                      "ops->barrier(ops->context);", ""))
        ++failures;
    expect_invalid("write barrier removed", valid_hba_source, mutation);
    if (!replace_once(mutation, sizeof(mutation), hba_source_ok,
                      "if (result != AHCI_HBA_SUCCESS) { return result; }",
                      "if (result != AHCI_HBA_SUCCESS) { }"))
        ++failures;
    expect_invalid("BOHC timeout pushback removed", valid_hba_source,
                   mutation);
    if (!replace_once(mutation, sizeof(mutation), hba_source_ok,
                      "AHCI_HBA_RESET_TIMEOUT_MS;",
                      "AHCI_HBA_RESET_TIMEOUT_MS; AHCIPort;"))
        ++failures;
    expect_invalid("port construction introduced", valid_hba_source,
                   mutation);
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
    require_valid_file("AHCI.drvproj/AHCI.lksproj/Makefile",
                       valid_link_makefile);
    require_line_file("AHCI.drvproj/AHCI.lksproj/Makefile",
                      "CLASSES = AHCIController.m", 1);
    require_valid_file("AHCI.drvproj/AHCI.lksproj/PB.project",
                       valid_link_project);
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
    require_valid_file("AHCI.drvproj/AHCI.lksproj/AHCIHBA.c",
                       valid_hba_source);
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
