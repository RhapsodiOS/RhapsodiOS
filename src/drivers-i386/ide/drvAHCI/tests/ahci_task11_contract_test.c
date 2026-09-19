#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static char *read_file(const char *path)
{
    FILE *file;
    long length;
    char *text;

    file = fopen(path, "rb");
    if (file == NULL)
        return NULL;
    fseek(file, 0, SEEK_END);
    length = ftell(file);
    fseek(file, 0, SEEK_SET);
    text = (char *)malloc((size_t)length + 1U);
    if (text == NULL || fread(text, 1, (size_t)length, file) !=
        (size_t)length) {
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
        fprintf(stderr, "%s: missing %s\n", path, needle);
        ++failures;
    }
    free(text);
}

static void require_absent(const char *path, const char *needle)
{
    char *text;

    text = read_file(path);
    if (text == NULL || strstr(text, needle) != NULL) {
        fprintf(stderr, "%s: unexpected %s\n", path, needle);
        ++failures;
    }
    free(text);
}

static void require_order(const char *path, const char *first,
                          const char *second)
{
    char *text;
    char *a;
    char *b;

    text = read_file(path);
    a = text == NULL ? NULL : strstr(text, first);
    b = a == NULL ? NULL : strstr(a + strlen(first), second);
    if (b == NULL) {
        fprintf(stderr, "%s: missing order %s -> %s\n", path, first,
                second);
        ++failures;
    }
    free(text);
}

static void require_scoped_order(const char *path, const char *scopeStart,
                                 const char *scopeEnd, const char *first,
                                 const char *second)
{
    char *text;
    char *scope;
    char *end;
    char *a;
    char *b;

    text = read_file(path);
    scope = text == NULL ? NULL : strstr(text, scopeStart);
    end = scope == NULL ? NULL :
          strstr(scope + strlen(scopeStart), scopeEnd);
    a = scope == NULL ? NULL : strstr(scope, first);
    b = a == NULL ? NULL : strstr(a + strlen(first), second);
    if (scope == NULL || end == NULL || a == NULL || b == NULL ||
        a >= end || b >= end) {
        fprintf(stderr, "%s: missing scoped order %s: %s -> %s\n",
                path, scopeStart, first, second);
        ++failures;
    }
    free(text);
}

int main(void)
{
    const char *diskm =
        "../AHCI.drvproj/AHCI.lksproj/AHCIDisk.m";
    const char *internalm =
        "../AHCI.drvproj/AHCI.lksproj/AHCIDiskInternal.m";
    const char *portm =
        "../AHCI.drvproj/AHCI.lksproj/AHCIPort.m";
    const char *controllerm =
        "../AHCI.drvproj/AHCI.lksproj/AHCIController.m";
    const char *eideInternalm =
        "../../drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDiskInternal.m";

    require_text(portm, "identifyBuffer");
    require_order(diskm, "identifyDevice", "ata_hd_register(self, 0,");
    require_order(diskm, "ata_hd_register(self, 0,", "registerDevice");
    require_text(diskm, "ata_hd_activate_units");
    require_text(internalm, "AHCI_ATA_IDENTIFY_DEVICE");
    require_text(internalm, "AHCI_DISK_COMMAND_TIMEOUT_SECONDS");
    require_text(internalm, "AHCI_DISK_FLUSH_TIMEOUT_SECONDS");
    require_text(internalm, "AHCI_ATA_FLUSH_CACHE_EXT");
    require_text(internalm, "completeTransfer:");
    require_text(internalm, "client:request->client");
    require_text(internalm, "_identify.lba48,");
    /* Kernel-loadable drivers must reference the kernel's page_size, not the
     * user-space Mach name vm_page_size.  mach/vm_param.h declares page_size
     * for KERNEL builds and vm_page_size only outside them, so referencing the
     * user-space name leaves an undefined _vm_page_size that sarld cannot
     * resolve against mach_kernel at boot:
     *     rld(): Undefined symbols: _vm_page_size
     * The Floppy boot driver uses page_size; EIDE names vm_page_size in a macro
     * but never expands it, which is why only AHCI failed to link. */
    require_text(internalm, "page_size, &segment");
    require_absent(internalm, "vm_page_size");
    require_absent(portm, "vm_page_size");
    require_text(internalm, "client:IOVmTaskSelf()");
    require_text(internalm, "ata_hd_unregister(_hdUnit)");
    require_text(diskm, "ata_hd_set_flush(_hdUnit,");
    require_text(internalm, "AHCIDiskTransportFlush");
    require_scoped_order(internalm, "- (void)completeRequest:",
                         "- (IOReturn)deviceRwCommon:",
                         "ata_hd_async_claim(registryToken)",
                         "pending = request->pending");
    require_scoped_order(internalm, "- (void)completeRequest:",
                         "- (IOReturn)deviceRwCommon:",
                         "completeTransfer:pending", "freeRequest:request");
    require_scoped_order(internalm, "- (void)completeRequest:",
                         "- (IOReturn)deviceRwCommon:",
                         "freeRequest:request",
                         "ata_hd_async_complete(registryToken)");
    require_scoped_order(eideInternalm, "- (void)ideIoComplete:",
                         "- (void)ideCmdDispatch:",
                         "completeTransfer:pending", "freeIdeBuf:ideBuf");
    require_scoped_order(eideInternalm, "- (void)ideIoComplete:",
                         "- (void)ideCmdDispatch:", "freeIdeBuf:ideBuf",
                         "ata_hd_async_complete(registryToken)");
    require_scoped_order(eideInternalm, "- (void)ideIoComplete:",
                         "- (void)ideCmdDispatch:",
                         "ata_hd_async_claim(registryToken)",
                         "pending = ideBuf->pending");
    require_text(internalm, "portBecameNotReady");
    require_text(portm, "[disk portBecameNotReady]");
    require_text(portm, "notifyDiskOffline");
    require_text(portm, "activeDiskNotifications");
    require_text(portm, "while (activeDiskNotifications != 0)");
    require_text(portm, "diskNotificationsBlocked = YES");
    require_text(portm, "diskUnpublishing");
    require_scoped_order(portm, "matchesKind:(BOOL)sameKind",
                         "- (BOOL)controllerDidReset", "diskUnpublishing",
                         "return AHCI_PORT_COMMAND_ERROR");
    require_scoped_order(portm, "- (BOOL)controllerDidReset",
                         "- (void)controllerResetFailed",
                         "diskUnpublishing", "online =");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt", "diskToFree = disk",
                         "disk = nil");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt", "disk = nil",
                         "[commandLock unlockWith:condition]");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt",
                         "[commandLock unlockWith:condition]",
                         "[diskToFree free]");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt", "disk = diskToFree",
                         "online = NO");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt", "online = NO",
                         "AHCIPortMMIOWrite(mmio,");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt", "online = NO",
                         "++activeDiskNotifications");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt",
                         "[diskToFree portBecameNotReady]",
                         "diskNotificationsBlocked = NO");
    require_scoped_order(portm, "- (BOOL)unpublishDisk",
                         "- (void)handleInterrupt",
                         "[diskToFree portBecameNotReady]",
                         "diskUnpublishing = NO");
    require_order(portm, "if (disk != nil && !diskNotificationsBlocked)",
                  "++activeDiskNotifications");
    require_order(portm, "++activeDiskNotifications",
                  "[commandLock unlockWith:condition]");
    require_order(portm, "[diskToNotify portBecameNotReady]",
                  "--activeDiskNotifications");
    require_order(portm, "asyncAction == AHCI_ASYNC_PORT_OFFLINE",
                  "[commandLock unlockWith:condition]");
    require_order(portm, "[commandLock unlockWith:condition]",
                  "[diskToNotify portBecameNotReady]");
    require_text(diskm, "publication state is uncertain; retaining hd");
    require_text(diskm, "activation failed; retaining hd");
    require_order(diskm, "activation failed; retaining hd",
                  "[self portBecameNotReady]");
    require_order(internalm, "if (_publicationPinned)",
                  "ata_hd_unregister(_hdUnit)");
    require_text(portm, "translation.task = client;");
    require_text(portm, "AHCIPortTranslateAddress, &translation");
    require_text(portm, "- (BOOL)unpublishDisk");
    require_order(controllerm, "unpublishDisk",
                  "ghc & ~AHCI_GHC_IE");
    require_absent(diskm, "addToBdevsw");
    require_absent(diskm, "addToCdevsw");
    require_absent(internalm, "addToBdevsw");
    require_absent(internalm, "addToCdevsw");

    if (failures != 0)
        return 1;
    puts("AHCI Task 11 contract tests passed");
    return 0;
}
