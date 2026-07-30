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

static int section_contains(const char *start, const char *end,
                            const char *needle)
{
    const char *found;

    if (start == NULL || end == NULL || start >= end)
        return 0;
    found = strstr(start, needle);
    return found != NULL && found < end;
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

static void test_transactional_registration(const char *diskSource,
                                            const char *diskHeader)
{
    const char *probe;
    const char *probeEnd;
    const char *devsw;
    const char *registration;
    const char *initialization;
    const char *publication;
    const char *activation;
    const char *probed;
    const char *bounds;

    probe = strstr(diskSource, "+ (BOOL)probe");
    probeEnd = strstr(probe, "Common read/write methods");
    CHECK(probe != NULL);
    CHECK(probeEnd != NULL);
    if (probe == NULL || probeEnd == NULL)
        return;

    devsw = strstr(probe,
                   "ata_hd_devsw_init(self, deviceDescription)");
    registration = strstr(probe,
                          "ata_hd_register(diskId, "
                          "IdeDiskTransportIoctl, &idMap)");
    initialization = strstr(probe,
                            "ideDiskInit:(unsigned int)globalUnit "
                            "target:unit");
    publication = strstr(probe, "[diskId registerDevice]");
    activation = strstr(probe, "ata_hd_activate_units");
    probed = strstr(probe, "probedControllers[probedControllerCount++]");
    bounds = strstr(probe,
                    "probedControllerCount >= MAX_IDE_CONTROLLERS");
    CHECK(devsw != NULL);
    CHECK(registration != NULL);
    CHECK(initialization != NULL);
    CHECK(publication != NULL);
    CHECK(activation != NULL);
    CHECK(probed != NULL);
    CHECK(bounds != NULL);
    if (publication != NULL && activation != NULL)
        CHECK(publication < activation);
    if (activation != NULL && probed != NULL)
        CHECK(activation < probed);
    if (bounds != NULL && probed != NULL)
        CHECK(bounds < probed);

    CHECK(section_contains(probe, probeEnd,
                           "[diskId setDevAndIdInfo:idMap]"));
    CHECK(section_contains(probe, probeEnd,
                           "IdeDiskRollbackPrepared"));
    CHECK(strstr(diskHeader, "int\t\t\t_hdUnit") != NULL ||
          strstr(diskHeader, "int _hdUnit") != NULL);
}

static void test_target_classification_precedes_reservation(
    const char *diskSource)
{
    const char *probe;
    const char *targetLoop;
    const char *targetLoopEnd;
    const char *atapiGate;
    const char *atapiContinue;
    const char *driveInfo;
    const char *typeGate;
    const char *typeContinue;
    const char *allocation;
    const char *registration;

    probe = strstr(diskSource, "+ (BOOL)probe");
    targetLoop = probe == NULL ? NULL :
        strstr(probe, "for (unit = 0; unit < MAX_IDE_DRIVES; unit++)");
    targetLoopEnd = targetLoop == NULL ? NULL :
        strstr(targetLoop, "if (ata_hd_activate_units");
    CHECK(targetLoop != NULL);
    CHECK(targetLoopEnd != NULL);
    if (targetLoop == NULL || targetLoopEnd == NULL)
        return;

    atapiGate = strstr(targetLoop, "[controllerId isAtapiDevice:unit]");
    driveInfo = strstr(targetLoop, "[controllerId getIdeDriveInfo:unit]");
    typeGate = strstr(targetLoop, "candidateInfo.type == 0");
    allocation = strstr(targetLoop,
                        "[[IdeDisk alloc] initFromDeviceDescription");
    registration = strstr(targetLoop, "ata_hd_register(diskId");
    CHECK(atapiGate != NULL && atapiGate < targetLoopEnd);
    CHECK(driveInfo != NULL && driveInfo < targetLoopEnd);
    CHECK(typeGate != NULL && typeGate < targetLoopEnd);
    CHECK(allocation != NULL && allocation < targetLoopEnd);
    CHECK(registration != NULL && registration < targetLoopEnd);
    if (atapiGate == NULL || driveInfo == NULL || typeGate == NULL ||
        allocation == NULL || registration == NULL)
        return;

    atapiContinue = strstr(atapiGate, "continue;");
    typeContinue = strstr(typeGate, "continue;");
    CHECK(atapiContinue != NULL && atapiContinue < driveInfo);
    CHECK(typeContinue != NULL && typeContinue < allocation);
    CHECK(atapiGate < driveInfo);
    CHECK(driveInfo < typeGate);
    CHECK(typeGate < allocation);
    CHECK(allocation < registration);
}

static void test_safe_teardown(const char *internalSource)
{
    const char *resources;
    const char *resourcesEnd;
    const char *freeMethod;
    const char *freeEnd;
    const char *unregisterCall;
    const char *threadAbort;

    resources = strstr(internalSource, "- initResources");
    resourcesEnd = strstr(resources, "Free up local resources");
    freeMethod = strstr(resourcesEnd, "- free");
    freeEnd = strstr(freeMethod, "Allocate and free IdeBuf");
    CHECK(section_contains(resources, resourcesEnd, "_hdUnit = -1"));
    CHECK(freeMethod != NULL);
    CHECK(freeEnd != NULL);
    if (freeMethod == NULL || freeEnd == NULL)
        return;
    unregisterCall = strstr(freeMethod, "ata_hd_unregister(_hdUnit)");
    threadAbort = strstr(freeMethod, "IDEC_THREAD_ABORT");
    CHECK(unregisterCall != NULL && unregisterCall < freeEnd);
    CHECK(threadAbort != NULL && threadAbort < freeEnd);
    if (unregisterCall != NULL && threadAbort != NULL)
        CHECK(unregisterCall < threadAbort);
    CHECK(section_contains(freeMethod, freeEnd, "return self"));
    CHECK(section_contains(freeMethod, freeEnd, "_hdUnit = -1"));
}

static void test_transport_ioctl_only(const char *kernelSource)
{
    const char *callback;
    const char *callbackEnd;
    const char *validation;
    const char *allocation;
    const char *completion;
    const char *copyoutCall;

    callback = strstr(kernelSource, "IdeDiskTransportIoctl(id disk");
    callbackEnd = strstr(callback, "end of IdeKern.m");
    CHECK(callback != NULL);
    CHECK(callbackEnd != NULL);
    if (callback == NULL || callbackEnd == NULL)
        return;

    CHECK(section_contains(callback, callbackEnd, "case IDEDIOCREQ:"));
    CHECK(section_contains(callback, callbackEnd, "case IDEDIOCINFO:"));
    CHECK(!section_contains(callback, callbackEnd, "case DKIOC"));
    CHECK(section_contains(callback, callbackEnd, "proc == NULL"));
    CHECK(section_contains(callback, callbackEnd,
                           "suser(proc->p_ucred, &proc->p_acflag)"));
    CHECK(!section_contains(callback, callbackEnd, "!suser"));
    CHECK(!section_contains(callback, callbackEnd, "struct ucred cred"));

    validation = strstr(callback, "EIDEIoctlPrepareTransfer");
    allocation = strstr(callback, "IOMalloc(");
    completion = strstr(callback, "EIDEIoctlValidateCompletion");
    copyoutCall = strstr(callback, "copyout(");
    CHECK(validation != NULL);
    CHECK(allocation != NULL);
    CHECK(completion != NULL);
    CHECK(copyoutCall != NULL);
    if (validation != NULL && allocation != NULL)
        CHECK(validation < allocation);
    if (completion != NULL && copyoutCall != NULL)
        CHECK(completion < copyoutCall);
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
    char *diskHeader;
    char *internalHeader;
    char *internalSource;
    char *postloadSource;

    sprintf(path, "%sIdeKernel.h", eide);
    kernelHeader = read_source(path);
    sprintf(path, "%sIdeKernel.m", eide);
    kernelSource = read_source(path);
    sprintf(path, "%sIdeDisk.m", eide);
    diskSource = read_source(path);
    sprintf(path, "%sIdeDisk.h", eide);
    diskHeader = read_source(path);
    sprintf(path, "%sIdeDiskInternal.h", eide);
    internalHeader = read_source(path);
    sprintf(path, "%sIdeDiskInternal.m", eide);
    internalSource = read_source(path);
    postloadSource = read_source(
        "../../drvEIDE/EIDE.drvproj/PostLoad.tproj/PostLoad.m");

    CHECK(kernelHeader != NULL);
    CHECK(kernelSource != NULL);
    CHECK(diskSource != NULL);
    CHECK(diskHeader != NULL);
    CHECK(internalHeader != NULL);
    CHECK(internalSource != NULL);
    CHECK(postloadSource != NULL);
    if (kernelHeader != NULL && kernelSource != NULL && diskSource != NULL &&
        diskHeader != NULL && internalHeader != NULL && internalSource != NULL &&
        postloadSource != NULL) {
        test_private_namespace_is_removed(kernelHeader, kernelSource,
                                          diskSource, internalHeader);
        test_transactional_registration(diskSource, diskHeader);
        test_target_classification_precedes_reservation(diskSource);
        test_safe_teardown(internalSource);
        test_transport_ioctl_only(kernelSource);
        test_global_unit_naming(internalSource);
        test_postload_global_namespace(postloadSource);
    }

    free(kernelHeader);
    free(kernelSource);
    free(diskSource);
    free(diskHeader);
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
