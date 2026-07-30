#define _CRT_SECURE_NO_WARNINGS

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                        \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static char *read_source(const char *path)
{
    FILE *file;
    char *text;
    long length;
    size_t count;

    file = fopen(path, "rb");
    if (file == NULL)
        return NULL;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    text = (char *)malloc((size_t)length + 1);
    if (text == NULL) {
        fclose(file);
        return NULL;
    }
    count = fread(text, 1, (size_t)length, file);
    fclose(file);
    if (count != (size_t)length) {
        free(text);
        return NULL;
    }
    text[length] = '\0';
    return text;
}

static unsigned int count_occurrences(const char *text, const char *needle)
{
    unsigned int count;
    size_t length;

    count = 0;
    length = strlen(needle);
    while ((text = strstr(text, needle)) != NULL) {
        ++count;
        text += length;
    }
    return count;
}

static void test_private_namespace_is_removed(const char *kernelHeader,
                                              const char *kernelSource,
                                              const char *diskSource,
                                              const char *internalHeader)
{
    CHECK(strstr(kernelHeader, "IdeDiskTransportIoctl") != NULL);
    CHECK(strstr(kernelHeader, "ideopen") == NULL);
    CHECK(strstr(kernelHeader, "ideclose") == NULL);
    CHECK(strstr(kernelHeader, "idestrategy") == NULL);
    CHECK(strstr(kernelHeader, "ideioctl") == NULL);

    CHECK(strstr(kernelSource, "IdeIdMap") == NULL);
    CHECK(strstr(kernelSource, "ide_dev[") == NULL);
    CHECK(strstr(kernelSource, "ide_init_idmap") == NULL);
    CHECK(strstr(kernelSource, "ide_idmap") == NULL);
    CHECK(strstr(kernelSource, "ide_block_major") == NULL);
    CHECK(strstr(kernelSource, "ide_raw_major") == NULL);
    CHECK(strstr(kernelSource, "ideopen(") == NULL);
    CHECK(strstr(kernelSource, "ideclose(") == NULL);
    CHECK(strstr(kernelSource, "idestrategy(") == NULL);

    CHECK(strstr(diskSource, "static int diskUnit") == NULL);
    CHECK(strstr(diskSource, "switchTableInited") == NULL);
    CHECK(strstr(diskSource, "+ (BOOL)hd_devsw_init") == NULL);
    CHECK(strstr(diskSource, "addToCdevswFromDescription") == NULL);
    CHECK(strstr(diskSource, "addToBdevswFromDescription") == NULL);

    CHECK(strstr(internalHeader, "NUM_IDE_DEV") == NULL);
    CHECK(strstr(internalHeader, "Ide_dev_t") == NULL);
    CHECK(strstr(internalHeader, "ide_init_idmap") == NULL);
    CHECK(strstr(internalHeader, "ide_idmap") == NULL);
}

static void test_shared_registration_and_unwind(const char *diskSource)
{
    const char *devsw;
    const char *registration;
    const char *initialization;

    devsw = strstr(diskSource,
                   "ata_hd_devsw_init(self, deviceDescription)");
    registration = strstr(diskSource,
                          "ata_hd_register(diskId, "
                          "IdeDiskTransportIoctl, &idMap)");
    initialization = strstr(diskSource,
                            "ideDiskInit:(unsigned int)globalUnit "
                            "target:unit");
    CHECK(devsw != NULL);
    CHECK(registration != NULL);
    CHECK(initialization != NULL);
    if (devsw != NULL && registration != NULL)
        CHECK(devsw < registration);
    if (registration != NULL && initialization != NULL)
        CHECK(registration < initialization);

    CHECK(strstr(diskSource, "[diskId setDevAndIdInfo:idMap]") != NULL);
    CHECK(strstr(diskSource, "[diskId registerDevice] == nil") != NULL);
    CHECK(count_occurrences(diskSource, "ata_hd_unregister(globalUnit)") >= 2);
}

static void test_transport_ioctl_only(const char *kernelSource)
{
    const char *callback;

    callback = strstr(kernelSource, "IdeDiskTransportIoctl(id disk");
    CHECK(callback != NULL);
    if (callback == NULL)
        return;

    CHECK(strstr(callback, "case IDEDIOCREQ:") != NULL);
    CHECK(strstr(callback, "case IDEDIOCINFO:") != NULL);
    CHECK(strstr(callback, "case DKIOC") == NULL);
    CHECK(strstr(callback, "return (EINVAL);") != NULL);
    CHECK(strstr(callback, "return (ENOMEM);") != NULL);
}

static void test_global_unit_naming(const char *internalSource)
{
    CHECK(strstr(internalSource,
                 "sprintf(dev_name, \"hd%d\", diskUnit)") != NULL);
    CHECK(strstr(internalSource, "[self setUnit:diskUnit]") != NULL);
    CHECK(strstr(internalSource, "[self setName:dev_name]") != NULL);
}

static void test_postload_global_namespace(const char *postloadSource)
{
    CHECK(strstr(postloadSource, "#define NIDE_DEVICES") != NULL);
    CHECK(strstr(postloadSource, "32") != NULL);
    CHECK(strstr(postloadSource, "#define NIDE_PARTITIONS") != NULL);
    CHECK(strstr(postloadSource, "8") != NULL);
    CHECK(strstr(postloadSource, "iUnit = 0") != NULL);
    CHECK(strstr(postloadSource, "iUnit < NIDE_DEVICES") != NULL);
    CHECK(strstr(postloadSource, "IDE_BLOCK_MAJOR") != NULL);
    CHECK(strstr(postloadSource, "IDE_CHARACTER_MAJOR") != NULL);
    CHECK(strstr(postloadSource, "stat(path") != NULL);
    CHECK(strstr(postloadSource, "st_rdev") != NULL);
    CHECK(strstr(postloadSource, "unlink(path)") != NULL);
    CHECK(strstr(postloadSource, "mknod(path") != NULL);
    CHECK(strstr(postloadSource, "lookUpByDeviceName") == NULL);
}

int main(void)
{
    static const char *eide =
        "../../drvEIDE/EIDE.drvproj/EIDE.lksproj/";
    char path[256];
    char *kernelHeader;
    char *kernelSource;
    char *diskSource;
    char *internalHeader;
    char *internalSource;
    char *postloadSource;

    sprintf(path, "%sIdeKernel.h", eide);
    kernelHeader = read_source(path);
    sprintf(path, "%sIdeKernel.m", eide);
    kernelSource = read_source(path);
    sprintf(path, "%sIdeDisk.m", eide);
    diskSource = read_source(path);
    sprintf(path, "%sIdeDiskInternal.h", eide);
    internalHeader = read_source(path);
    sprintf(path, "%sIdeDiskInternal.m", eide);
    internalSource = read_source(path);
    postloadSource = read_source(
        "../../drvEIDE/EIDE.drvproj/PostLoad.tproj/PostLoad.m");

    CHECK(kernelHeader != NULL);
    CHECK(kernelSource != NULL);
    CHECK(diskSource != NULL);
    CHECK(internalHeader != NULL);
    CHECK(internalSource != NULL);
    CHECK(postloadSource != NULL);
    if (kernelHeader != NULL && kernelSource != NULL && diskSource != NULL &&
        internalHeader != NULL && internalSource != NULL &&
        postloadSource != NULL) {
        test_private_namespace_is_removed(kernelHeader, kernelSource,
                                          diskSource, internalHeader);
        test_shared_registration_and_unwind(diskSource);
        test_transport_ioctl_only(kernelSource);
        test_global_unit_naming(internalSource);
        test_postload_global_namespace(postloadSource);
    }

    free(kernelHeader);
    free(kernelSource);
    free(diskSource);
    free(internalHeader);
    free(internalSource);
    free(postloadSource);

    if (failures != 0) {
        fprintf(stderr, "eide_registry_migration_test: %d failure(s)\n",
                failures);
        return EXIT_FAILURE;
    }

    printf("eide_registry_migration_test: all tests passed\n");
    return EXIT_SUCCESS;
}
