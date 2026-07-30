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

static void require_text(const char *file, const char *needle)
{
    char *text;

    text = read_file(file);
    if (text == NULL || strstr(text, needle) == NULL) {
        fprintf(stderr, "%s: missing %s\n", file, needle);
        ++failures;
    }
    free(text);
}

static void require_absent(const char *file, const char *needle)
{
    char *text;

    text = read_file(file);
    if (text == NULL || strstr(text, needle) != NULL) {
        fprintf(stderr, "%s: unexpected %s\n", file, needle);
        ++failures;
    }
    free(text);
}

static void require_order(const char *file, const char *first,
                          const char *second)
{
    char *text;
    char *a;
    char *b;

    text = read_file(file);
    a = text == NULL ? NULL : strstr(text, first);
    b = a == NULL ? NULL : strstr(a + strlen(first), second);
    if (b == NULL) {
        fprintf(stderr, "%s: missing order %s -> %s\n", file, first,
                second);
        ++failures;
    }
    free(text);
}

static int scoped_order(const char *text, const char *scope_begin,
                        const char *scope_end, const char *first,
                        const char *second)
{
    const char *begin;
    const char *end;
    const char *a;
    const char *b;

    begin = strstr(text, scope_begin);
    end = begin == NULL ? NULL : strstr(begin + strlen(scope_begin),
                                        scope_end);
    a = begin == NULL ? NULL : strstr(begin, first);
    b = a == NULL ? NULL : strstr(a + strlen(first), second);
    return begin != NULL && end != NULL && a != NULL && b != NULL &&
           a < end && b < end;
}

static int scoped_absent(const char *text, const char *scope_begin,
                         const char *scope_end, const char *needle)
{
    const char *begin;
    const char *end;
    const char *match;

    begin = strstr(text, scope_begin);
    end = begin == NULL ? NULL : strstr(begin + strlen(scope_begin),
                                        scope_end);
    match = begin == NULL ? NULL : strstr(begin, needle);
    return begin != NULL && end != NULL &&
           (match == NULL || match >= end);
}

static int valid_port_lifecycle(const char *text)
{
    return scoped_order(text, "- free", "- (void)finishDeferredFree",
                        "destroying = YES;",
                        "AHCIPortStopHardware(&ops, portNumber)") &&
           scoped_order(text, "- free", "- (void)finishDeferredFree",
                        "AHCIPortStopHardware(&ops, portNumber)",
                        "quiesceComplete = YES;") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "generation = AHCICommandBegin(&commandArbiter)",
                        "IOScheduleFunc(AHCIPortTimeout, self, 1)") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "IOScheduleFunc(AHCIPortTimeout, self, 1)",
                        "AHCIPortMMIOBarrier(mmio);") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "AHCIPortMMIOBarrier(mmio);",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U)") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "[commandLock lock];",
                        "status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS)") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "activeAtInterrupt = activeExecutors != 0",
                        "status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS)") &&
           scoped_order(text,
                        "- (AHCIU32)snapshotCommandState:(AHCIU32)status\n{",
                        "- (void)timeoutFired",
                        "completionSnapshot.commandIssue =",
                        "AHCIPortMMIOBarrier(mmio);") &&
           scoped_order(text,
                        "- (AHCIU32)snapshotCommandState:(AHCIU32)status\n{",
                        "- (void)timeoutFired",
                        "AHCIPortMMIOBarrier(mmio);",
                        "completionSnapshot.transferred =") &&
           scoped_order(text,
                        "- (AHCIU32)snapshotCommandState:(AHCIU32)status\n{",
                        "- (void)timeoutFired",
                        "completionSnapshot.transferred =",
                        "AHCICopyVolatileBytes(receivedFISSnapshot") &&
           scoped_order(text,
                        "- (AHCIU32)snapshotCommandState:(AHCIU32)status\n{",
                        "- (void)timeoutFired",
                        "AHCICopyVolatileBytes(receivedFISSnapshot",
                        "return linkStatus;") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "[self snapshotCommandState:status]",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "AHCIAsyncInterruptAction(",
                        "[commandLock unlockWith:condition]") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "[commandLock unlockWith:condition]",
                        "[controller recoverController]") &&
           scoped_absent(text, "- (void)controllerWillReset",
                         "- (void)timeoutFired",
                         "AHCICommandFinishIRQ(&commandArbiter") &&
           scoped_order(text, "- (BOOL)controllerDidReset",
                        "- (void)controllerResetFailed",
                        "AHCIPortInitializeHardware(&ops",
                        "controllerResetting = NO;") &&
           scoped_order(text, "- (BOOL)controllerDidReset",
                        "- (void)controllerResetFailed",
                        "controllerResetting = NO;",
                        "[self validateRecoveredKind:recoveredKind") &&
           scoped_order(text, "- (BOOL)controllerDidReset",
                        "- (void)controllerResetFailed",
                        "[self validateRecoveredKind:recoveredKind",
                        "AHCICommandFinishIRQ(&commandArbiter") &&
           scoped_order(text, "- (void)timeoutFired\n{",
                        "- (void)recoverCommand",
                        "AHCITimeoutChainCallbackMayEvaluate(&timeoutChain)",
                        "AHCICommandTimeoutAction(") &&
           scoped_order(text, "- (void)timeoutFired\n{",
                        "- (void)recoverCommand",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE, 0)",
                        "AHCIPortMMIOBarrier(mmio);") &&
           scoped_order(text, "- (void)timeoutFired\n{",
                        "- (void)recoverCommand",
                        "AHCIPortMMIOBarrier(mmio);",
                        "[self snapshotCommandState:status]") &&
           scoped_order(text, "- (void)timeoutFired\n{",
                        "- (void)recoverCommand",
                        "[self snapshotCommandState:status]",
                        "AHCICommandFinishTimeout(&commandArbiter") &&
           scoped_absent(text, "- (void)timeoutFired\n{",
                         "- (void)recoverCommand",
                         "timeoutChain.armedGeneration =") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "if (destroying) {",
                        "if (!online || mmio == 0") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "[controller beginSubmission]",
                        "[controller commitSubmission]") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "[controller commitSubmission]",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U)") &&
           scoped_order(text, "- (IOReturn)executeATA:",
                        "- (unsigned int)portNumber",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U)",
                        "[controller finishSubmissionCommit]") &&
           scoped_order(text, "matchesKind:(BOOL)sameKind\n{",
                        "- (BOOL)controllerDidReset",
                        "if (!sameKind || destroying)",
                        "AHCIPortRecoveryIdentify(&ops") &&
           scoped_absent(text, "matchesKind:(BOOL)sameKind\n{",
                         "- (BOOL)controllerDidReset", "commandArbiter") &&
           scoped_absent(text, "matchesKind:(BOOL)sameKind\n{",
                         "- (BOOL)controllerDidReset", "unlockWith") &&
           scoped_order(text, "- (void)handleInterrupt", "@end",
                        "AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE, 0)",
                        "AHCICommandFinishIRQ(&commandArbiter") &&
           scoped_order(text, "- (void)recoverCommand",
                        "- (IOReturn)executeATA:",
                        "AHCILocalRecoveryAllowed(destroying, controllerResetting)",
                        "AHCIRecoveryFor(completionSnapshot.portIS") &&
           scoped_order(text, "- (void)recoverCommand",
                        "- (IOReturn)executeATA:",
                        "AHCI_RECOVERY_HBA", "[controller recoverController]") &&
           scoped_order(text, "- (void)recoverCommand",
                        "- (IOReturn)executeATA:",
                        "validationResult == AHCI_PORT_ENGINE_TIMEOUT",
                        "[controller recoverController]");
}

static int valid_controller_recovery(const char *text)
{
    return scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "AHCIRecoveryGateStart(&recoveryGate)",
                        "AHCIRecoveryGateDrained(&recoveryGate)") &&
           scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "AHCIRecoveryGateDrained(&recoveryGate)",
                        "ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC)") &&
           scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "[ports[port] controllerWillReset]",
                        "resetResult = AHCIHBAInitialize(&ops, &hbaInfo)") &&
           scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "if (resetResult != AHCI_HBA_SUCCESS)",
                        "[ports[port] controllerResetFailed]") &&
           scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "[ports[port] controllerDidReset]",
                        "globalInterruptsEnabled = YES;") &&
           scoped_order(text, "- (void)recoverController",
                        "- (BOOL)beginSubmission",
                        "[ports[port] controllerDidReset]",
                        "AHCIRecoveryGateComplete(&recoveryGate, 1)") &&
           scoped_order(text, "- (BOOL)commitSubmission",
                        "- (void)finishSubmissionCommit",
                        "AHCIRecoveryGateCommitSubmission(&recoveryGate)",
                        "if (!allowed)") &&
           scoped_order(text, "- (BOOL)commitSubmission",
                        "- (void)finishSubmissionCommit",
                        "if (!allowed)", "[recoveryLock unlock]") &&
           scoped_order(text, "- (void)finishSubmissionCommit",
                        "- (void)interruptOccurred",
                        "[recoveryLock unlock]", "}");
}

static int valid_polling_identify(const char *text)
{
    return scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "ahci_port_write(ops, port, AHCI_PX_IE, 0)",
                        "AHCI_PX_TFD") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "waited < AHCI_TFD_TIMEOUT_MS",
                        "ahci_port_write(ops, port, AHCI_PX_CI, 1U)") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "waited < AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS",
                        "portIS = ahci_port_read(ops, port, AHCI_PX_IS)") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "portIS = ahci_port_read(ops, port, AHCI_PX_IS)",
                        "transferred = ((volatile AHCICommandHeader *)") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "transferred = ((volatile AHCICommandHeader *)",
                        "ahci_port_write(ops, port, AHCI_PX_IS, portIS)") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "ahci_port_write(ops, port, AHCI_PX_IS, portIS)",
                        "ahci_port_write(ops, port, AHCI_PX_SERR, serr)") &&
           scoped_order(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                        "unsigned int AHCIPortCountImplemented",
                        "AHCIPortStopHardware(ops, port)",
                        "return AHCI_PORT_ENGINE_TIMEOUT") &&
           scoped_absent(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                         "unsigned int AHCIPortCountImplemented",
                         "AHCICommandFinishIRQ") &&
           scoped_absent(text, "AHCIPortResult AHCIPortRecoveryIdentify(",
                         "unsigned int AHCIPortCountImplemented",
                         "IOScheduleFunc");
}

static int replace_once(char *out, size_t capacity, const char *source,
                        const char *old_text, const char *new_text)
{
    const char *match;
    size_t prefix;
    size_t bytes;

    match = strstr(source, old_text);
    if (match == NULL)
        return 0;
    prefix = (size_t)(match - source);
    bytes = prefix + strlen(new_text) + strlen(match + strlen(old_text)) + 1U;
    if (bytes > capacity)
        return 0;
    memcpy(out, source, prefix);
    strcpy(out + prefix, new_text);
    strcpy(out + prefix + strlen(new_text), match + strlen(old_text));
    return 1;
}

static void test_lifecycle_mutations(const char *portm)
{
    char *source;
    char *mutation;
    size_t capacity;
    const char *old_text[7];
    const char *new_text[7];
    unsigned int index;

    source = read_file(portm);
    if (source == NULL || !valid_port_lifecycle(source)) {
        fprintf(stderr, "production Task 10 lifecycle rejected\n");
        ++failures;
        free(source);
        return;
    }
    capacity = strlen(source) + 256U;
    mutation = (char *)malloc(capacity);
    if (mutation == NULL) {
        free(source);
        ++failures;
        return;
    }
    old_text[0] = "destroying = YES;";
    new_text[0] = "destroying = NO;";
    old_text[1] = "AHCIPortMMIOBarrier(mmio);\n    volatileCommandList";
    new_text[1] = "volatileCommandList";
    old_text[2] = "if (commandArbiter.state == AHCI_COMMAND_PENDING) {\n        skipCommandRecovery = YES;";
    new_text[2] = "if (commandArbiter.state == AHCI_COMMAND_PENDING) {\n        AHCICommandFinishIRQ(&commandArbiter, commandArbiter.generation);\n        skipCommandRecovery = YES;";
    old_text[3] = "AHCI_RECOVERY_HBA";
    new_text[3] = "AHCI_RECOVERY_PORT";
    old_text[4] = "result = AHCIPortInitializeHardware(&ops, portNumber, portCapabilities,\n                                        &arena, &recoveredKind);";
    new_text[4] = "result = AHCI_PORT_SUCCESS; recoveredKind = AHCI_DEVICE_NONE;";
    old_text[5] = "AHCIPortRecoveryIdentify(&ops";
    new_text[5] = "AHCIPortRecoveryIdentifyMissing(&ops";
    old_text[6] = "if (!sameKind || destroying)\n        return AHCI_PORT_COMMAND_ERROR;";
    new_text[6] = "if (!sameKind || destroying)\n        return AHCI_PORT_COMMAND_ERROR;\n    AHCICommandFinishIRQ(&commandArbiter, 1U);";
    for (index = 0; index < 7U; ++index) {
        if (!replace_once(mutation, capacity, source, old_text[index],
                          new_text[index]) ||
            valid_port_lifecycle(mutation)) {
            fprintf(stderr, "lifecycle mutation %u survived\n", index);
            ++failures;
        }
    }
    free(mutation);
    free(source);
}

static void test_controller_recovery(const char *ctrlm)
{
    char *source;

    source = read_file(ctrlm);
    if (source == NULL || !valid_controller_recovery(source)) {
        fprintf(stderr, "production controller recovery lifecycle rejected\n");
        ++failures;
    }
    free(source);
}

static void test_polling_identify(const char *logicc)
{
    char *source;
    char *mutation;
    size_t capacity;
    const char *old_text[3];
    const char *new_text[3];
    unsigned int index;

    source = read_file(logicc);
    if (source == NULL || !valid_polling_identify(source)) {
        fprintf(stderr, "production polling IDENTIFY rejected\n");
        ++failures;
        free(source);
        return;
    }
    capacity = strlen(source) + 256U;
    mutation = (char *)malloc(capacity);
    if (mutation == NULL) {
        free(source);
        ++failures;
        return;
    }
    old_text[0] = "waited < AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS)";
    new_text[0] = "waited < 0)";
    old_text[1] = "ahci_port_write(ops, port, AHCI_PX_IS, portIS);";
    new_text[1] = "ops->barrier(ops->context);";
    old_text[2] = "return AHCI_PORT_SUCCESS;\n}\n\nunsigned int AHCIPortCountImplemented";
    new_text[2] = "IOScheduleFunc(0, 0, 0);\n    return AHCI_PORT_SUCCESS;\n}\n\nunsigned int AHCIPortCountImplemented";
    for (index = 0; index < 3U; ++index) {
        if (!replace_once(mutation, capacity, source, old_text[index],
                          new_text[index]) ||
            valid_polling_identify(mutation)) {
            fprintf(stderr, "polling IDENTIFY mutation %u survived\n",
                    index);
            ++failures;
        }
    }
    free(mutation);
    free(source);
}

int main(void)
{
    const char *porth = "../AHCI.drvproj/AHCI.lksproj/AHCIPort.h";
    const char *portm = "../AHCI.drvproj/AHCI.lksproj/AHCIPort.m";
    const char *logicc = "../AHCI.drvproj/AHCI.lksproj/AHCIPortLogic.c";
    const char *logich = "../AHCI.drvproj/AHCI.lksproj/AHCIPortLogic.h";
    const char *ctrlh = "../AHCI.drvproj/AHCI.lksproj/AHCIController.h";
    const char *ctrlm = "../AHCI.drvproj/AHCI.lksproj/AHCIController.m";

    require_text(porth, "- (IOReturn)executeATA:(unsigned char)command");
    require_text(porth, "transferred:(unsigned int *)actual;");
    require_absent(porth, "executeRecoveryATA:");
    require_absent(porth, "AHCIRecoveryValidator");
    require_absent(portm, "recoveryValidationInProgress");
    require_text(portm, "AHCIPortBuildSegments(");
    require_text(portm, "AHCIPortBuildSlot(");
    require_text(portm, "AHCI_TFD_TIMEOUT_MS");
    require_text(portm, "IOScheduleFunc(AHCIPortTimeout, self, 1)");
    require_text(portm, "AHCICommandFinishTimeout(&commandArbiter");
    require_text(portm, "AHCICommandFinishIRQ(&commandArbiter");
    require_order(portm, "completionSnapshot.portIS =", "AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS");
    require_order(portm, "completionSnapshot.transferred = volatileCommandList[0].prdbc", "AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS");
    require_order(portm, "[commandLock lock];", "destroying = YES;");
    require_order(portm, "destroying = YES;", "AHCIPortStopHardware(&ops, portNumber)");
    require_text(portm, "AHCICommandAbort(&commandArbiter)");
    require_order(portm, "AHCIPortMMIOBarrier(mmio);", "AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U)");
    require_text(portm, "AHCIPortRecoverHardware(&ops, portNumber, &arena)");
    require_text(portm, "AHCIRecoveryFor(completionSnapshot.portIS");
    require_text(portm, "AHCIRecoveredKindValid(");
    require_text(portm, "portCapabilities");
    require_order(ctrlm, "resetResult = AHCIHBAInitialize(&ops, &hbaInfo)",
                  "[ports[port] controllerDidReset]");
    require_order(ctrlm, "if (resetResult != AHCI_HBA_SUCCESS)",
                  "[ports[port] controllerResetFailed]");
    require_text(portm, "[commandLock unlockWith:AHCI_LOCK_PENDING]");
    require_text(portm, "if (controllerResetting)");
    require_text(portm, "AHCICommandTimeoutAction(");
    require_text(portm, "AHCITimeoutChainArm(&timeoutChain, generation)");
    require_text(portm, "AHCITimeoutChainInit(&timeoutChain);");
    require_text(portm, "[controller beginSubmission]");
    require_text(portm, "[controller commitSubmission]");
    require_text(portm, "[controller finishSubmissionCommit]");
    require_text(portm, "[self validateRecoveredKind:recoveredKind");
    require_text(portm, "AHCIPortRecoveryIdentify(&ops");
    require_text(portm, "rawArena = IOMallocLow(rawArenaBytes)");
    require_text(logich, "AHCI_PORT_IDENTIFY_BYTES             512U");
    require_text(logich, "AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS");
    require_text(logicc, "AHCIBuildIdentifyFIS(fis");
    require_text(logicc, "offsets[6] = AHCI_PORT_IDENTIFY_OFFSET");
    require_text(logicc, "offsets[7] = AHCI_PORT_IDENTIFY_OFFSET +");
    require_text(logicc, "ahci_port_write(ops, port, AHCI_PX_IE, 0)");
    require_order(logicc, "ahci_port_write(ops, port, AHCI_PX_IE, 0)",
                  "ahci_port_write(ops, port, AHCI_PX_CI, 1U)");
    require_order(logicc, "AHCI_PX_CI, 1U)",
                  "waited < AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS");
    require_order(logicc, "waited < AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS",
                  "portIS = ahci_port_read(ops, port, AHCI_PX_IS)");
    require_text(logicc, "transferred != AHCI_PORT_IDENTIFY_BYTES");
    require_text(logicc, "ahci_identify_data_valid(");
    require_absent(logicc, "AHCICommandFinishIRQ");
    require_absent(logicc, "IOScheduleFunc");
    require_text(portm, "AHCICopyVolatileBytes(receivedFISSnapshot");
    require_text(ctrlm, "AHCIRecoveryGateStart(&recoveryGate)");
    require_text(ctrlm, "AHCIRecoveryGateDrained(&recoveryGate)");
    require_text(ctrlh, "NXLock *recoveryLock;");
    require_text(ctrlm, "[recoveryLock lock]");
    require_text(ctrlm, "AHCIHBAInitialize(&ops, &hbaInfo)");
    require_text(ctrlm, "hbaResetAlreadyTried = YES");
    require_text(ctrlm, "controllerOffline = YES");
    test_lifecycle_mutations(portm);
    test_controller_recovery(ctrlm);
    test_polling_identify(logicc);
    if (failures != 0)
        return EXIT_FAILURE;
    printf("ahci_task10_contract_test: all tests passed\n");
    return EXIT_SUCCESS;
}
