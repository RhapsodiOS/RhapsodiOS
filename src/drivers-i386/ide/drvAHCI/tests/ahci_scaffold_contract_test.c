#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
static char source_root[512] = "..";

static char *read_file(const char *path)
{
    FILE *file;
    long length;
    char *text;
    char full_path[1024];

    sprintf(full_path, "%s/%s", source_root, path);
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

static void require_text(const char *path, const char *needle)
{
    char *text;

    text = read_file(path);
    if (text == NULL || strstr(text, needle) == NULL) {
        fprintf(stderr, "missing %s in %s\n", needle, path);
        ++failures;
    }
    free(text);
}

static void reject_text(const char *path, const char *needle)
{
    char *text;

    text = read_file(path);
    if (text == NULL || strstr(text, needle) != NULL) {
        fprintf(stderr, "unexpected %s in %s\n", needle, path);
        ++failures;
    }
    free(text);
}

static void test_bundle_contract(void)
{
    require_text("Makefile", "NAME = AHCI");
    require_text("Makefile.preamble", "INCLUDED_ARCHS = i386");
    require_text("PB.project", "PROJECTNAME = AHCI");
    require_text("AHCI.drvproj/Makefile", "NAME = AHCI");
    require_text("AHCI.drvproj/Makefile.preamble", "INCLUDED_ARCHS = i386");
    require_text("AHCI.drvproj/PB.project", "PROJECTNAME = AHCI");
    require_text("AHCI.drvproj/PB.project", "AHCI.lksproj");
    require_text("AHCI.drvproj/PB.project", "PostLoad.tproj");
    require_text("AHCI.drvproj/Default.table", "\"Class Names\" = \"AHCIController\"");
    require_text("AHCI.drvproj/Default.table", "\"Auto Detect IDs\" = \"0x29228086\"");
    require_text("AHCI.drvproj/DriverInfo", "DRIVER_NAME=\"AHCI\"");
    require_text("AHCI.drvproj/English.lproj/Localizable.strings", "\"AHCI\"");
    require_text("AHCI.drvproj/AHCI.lksproj/Makefile", "NAME = AHCI");
    require_text("AHCI.drvproj/AHCI.lksproj/Makefile.preamble", "INCLUDED_ARCHS = i386");
    require_text("AHCI.drvproj/AHCI.lksproj/Makefile", "CFILES = AHCICommand.c AHCIState.c");
    require_text("AHCI.drvproj/AHCI.lksproj/Makefile", "CLASSES = AHCIController.m");
    require_text("AHCI.drvproj/AHCI.lksproj/PB.project", "AHCIController.m");
    require_text("AHCI.drvproj/AHCI.lksproj/PB.project", "AHCICommand.c");
    require_text("AHCI.drvproj/AHCI.lksproj/PB.project", "AHCIState.c");
    require_text("AHCI.drvproj/AHCI.lksproj/Load_Commands.sect", "WIRE");
    reject_text("AHCI.drvproj/Default.table", "IdeController");
    reject_text("AHCI.drvproj/Default.table", "AtapiController");
    reject_text("AHCI.drvproj/Default.table", "IdeDisk");
    reject_text("AHCI.drvproj/Default.table", "EIDE");
    require_text("AHCI.drvproj/PostLoad.tproj/Makefile", "NAME = PostLoad");
    require_text("AHCI.drvproj/PostLoad.tproj/Makefile.preamble", "INCLUDED_ARCHS = i386");
    require_text("AHCI.drvproj/PostLoad.tproj/PB.project", "PROJECTNAME = PostLoad");
    require_text("AHCI.drvproj/PostLoad.tproj/PB.project", "PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make;");
    require_text("AHCI.drvproj/PostLoad.tproj/PB.project", "WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make;");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "N_AHCI_DEVICES");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "32");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "N_AHCI_PARTITIONS");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "8");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "AHCI_BLOCK_MAJOR 3");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "AHCI_CHARACTER_MAJOR 15");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "makeNode(\"hd\"");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "makeNode(\"rhd\"");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "lstat(path, &status)");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "unlink(path)");
    require_text("AHCI.drvproj/PostLoad.tproj/PostLoad.m", "mknod(path, mode, device)");
}

static void test_controller_contract(void)
{
    const char *path;

    path = "AHCI.drvproj/AHCI.lksproj/AHCIController.m";
    require_text(path, "@implementation AHCIController");
    require_text(path, "+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription");
    require_text(path, "getPCIConfigData");
    require_text(path, "0x29228086");
    require_text(path, "0x010601");
    require_text(path, "IOPCIDirectDevice");
    reject_text(path, "IdeController");
    reject_text(path, "AtapiController");
    reject_text(path, "IdeDisk");
}

int main(int argc, char **argv)
{
    if (argc > 1) {
        sprintf(source_root, "%s/src/drivers-i386/ide/drvAHCI", argv[1]);
    }
    test_bundle_contract();
    test_controller_contract();
    if (failures != 0) {
        fprintf(stderr, "ahci_scaffold_contract_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    printf("ahci_scaffold_contract_test: all tests passed\n");
    return EXIT_SUCCESS;
}
