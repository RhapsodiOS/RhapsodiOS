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
        fprintf(stderr, "%s: missing order %s -> %s\n", path,
                first, second);
        ++failures;
    }
    free(text);
}

int main(void)
{
    const char *header = "../AHCI.drvproj/AHCI.lksproj/AHCIATAPI.h";
    const char *source = "../AHCI.drvproj/AHCI.lksproj/AHCIATAPI.m";
    const char *port = "../AHCI.drvproj/AHCI.lksproj/AHCIPort.m";
    const char *controller =
        "../AHCI.drvproj/AHCI.lksproj/AHCIController.m";
    const char *project = "../AHCI.drvproj/AHCI.lksproj/PB.project";
    const char *makefile = "../AHCI.drvproj/AHCI.lksproj/Makefile";
    const char *logic =
        "../AHCI.drvproj/AHCI.lksproj/AHCIATAPILogic.c";
    const char *logicHeader =
        "../AHCI.drvproj/AHCI.lksproj/AHCIATAPILogic.h";

    require_text(header, "AHCIATAPIController : IOSCSIController");
    require_text(header, "AHCI_ATAPI_IDENTIFY_PACKET_DEVICE");
    require_text(header, "AHCI_ATAPI_IDENTIFY_TIMEOUT_SECONDS 10U");
    require_text(header, "AHCI_ATAPI_PACKET_TIMEOUT_SECONDS");
    require_text(source, "#import <driverkit/kernelDriver.h>");
    require_text(source, "executeSCSI3Request:(IOSCSI3Request *)scsiReq");
    require_text(source, "AHCIATAPIValidateCDBLength");
    require_text(source, "sizeof(scsiReq->cdb)");
    require_text(source, "AHCIATAPIPacketTimeout");
    require_text(source, "AHCIATAPITranslateModeSense6");
    require_text(source, "packetCDBLength = 10;");
    require_text(source, "AHCIATAPIRemapModeSense10");
    require_text(source, "AHCIATAPIEmulateModeSensePage2");
    require_text(source, "writeToClient");
    require_text(source, "resetATAPIDevice:self");
    require_text(source, "AHCIATAPIParseIdentity");
    require_text(source, "AHCIATAPIIdentityMatches");
    require_text(source, "_identity.dmaDirSupported");
    require_text(source, "request->target != 0 || request->lun != 0");
    require_text(source, "AHCIBuildPacketCommand");
    require_text(source, "client:client");
    require_text(source, "AHCI_ATAPI_SECTOR_BYTES");
    require_text(source, "if (request->maxTransfer != 0 && !request->read)");
    require_text(source, "blocks * AHCI_ATAPI_SECTOR_BYTES");
    require_text(source, "C6OP_TESTRDY");
    require_text(source, "C6OP_REQSENSE");
    require_text(source, "C10OP_READEXTENDED");
    require_text(source, "C6OP_MODESENSE");
    require_text(source, "AHCI_SCSI_START_STOP_UNIT");
    require_text(source, "AHCI_SCSI_PREVENT_ALLOW");
    require_text(source, "SENSE_NOTREADY");
    require_text(source, "SR_IOST_CHKSV");
    require_text(source, "AHCIATAPIShouldRequestSense(request->cdb[0],");
    require_text(source, "request->ignoreChkcond))");
    require_text(source, "AHCIATAPISenseDataValid(");
    require_order(source, "senseActual = 0;",
                  "transferred:&senseActual");
    require_text(source, "request->driverStatus = SR_IOST_CHKSNV;");
    require_text(source, "if (senseResult == IO_R_OFFLINE)");
    require_text(source, "result = IO_R_OFFLINE;");
    require_absent(source, "[device setName:");
    require_absent(source, "[device setDeviceKind:");
    require_text(source, "+ (IODeviceStyle)deviceStyle");
    require_text(source, "return IO_IndirectDevice;");
    require_text(source, "registerDevice");
    require_absent(source, "publication state is uncertain; retaining");
    require_absent(source, "_publicationPinned");
    require_absent(header, "_publicationPinned");
    require_text(source, "if ([device registerDevice] == nil) {\n"
                         "        [device free];\n"
                         "        return nil;\n"
                         "    }");
    require_absent(source, "device->_deviceRegistered = YES;\n"
                           "        [device portBecameNotReady]");
    require_absent(source, "ata_hd_register");
    require_text(port, "publishATAPIFromDeviceDescription");
    require_text(port, "@interface Object(AHCIControllerRecovery)\n"
                       "- (BOOL)recoverController;");
    require_text(port, "timeout:AHCI_ATAPI_IDENTIFY_TIMEOUT_SECONDS");
    require_text(port, "AHCIPortPacketCheckCondition");
    require_text(port, "== AHCI_PXIS_TFES");
    require_text(port, "[atapi portBecameNotReady]");
    require_text(port, "unpublishATAPI");
    require_order(port, "device = atapi;", "[device portBecameNotReady]");
    require_order(port, "[device portBecameNotReady]", "atapi = nil;");
    require_absent(port, "if (result == IO_R_SUCCESS)\n"
                         "        *actual = completionSnapshot.transferred;");
    require_order(source, "result = [self performPacket:",
                  "request->bytesTransferred = (int)actual;");
    require_order(source, "request->bytesTransferred = (int)actual;",
                  "if (result == IO_R_SUCCESS)");
    require_order(port, "atapi = nil;", "[commandLock unlockWith:condition]");
    require_order(port, "[commandLock unlockWith:condition]",
                  "if ([device free] != nil)");
    require_text(controller, "publishATAPIFromDeviceDescription");
    require_text(project, "AHCIATAPI.m");
    require_text(project, "AHCIATAPI.h");
    require_text(project, "AHCIATAPILogic.c");
    require_text(project, "AHCIATAPILogic.h");
    require_text(makefile, "AHCIATAPI.m");
    require_text(makefile, "AHCIATAPI.h");
    require_text(makefile, "AHCIATAPILogic.c");
    require_text(makefile, "AHCIATAPILogic.h");
    require_text(logicHeader, "AHCI_ATAPI_READ_16");
    require_text(logic, "case AHCI_ATAPI_READ_16:");

    if (failures != 0)
        return EXIT_FAILURE;
    puts("ahci_task12_contract_test: all tests passed");
    return EXIT_SUCCESS;
}
