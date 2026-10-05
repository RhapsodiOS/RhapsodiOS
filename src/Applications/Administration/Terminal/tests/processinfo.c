#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define CTL_KERN 1
#define KERN_PROC 14
#define KERN_PROC_PID 1

#if defined(TERMINAL_PROCESSINFO_PPC_TEST)
struct kinfo_proc {
    unsigned char bytes[468];
};
#else
struct kinfo_proc {
    struct {
        int p_pid;
        unsigned char p_stat;
        char p_comm[16];
    } kp_proc;
    struct {
        int e_pgid;
        int e_tpgid;
        int e_tdev;
    } kp_eproc;
};
#endif

static struct kinfo_proc testProcess;
static int sysctlCalls;
static int failCall;
static int perrorCalls;
static int lastMib[4];
static size_t requestedSize;

int terminalTestSysctl(int *mib, unsigned int mibLength, void *oldValue,
    size_t *oldLength, void *newValue, size_t newLength);
void terminalTestPerror(const char *message);

#define sysctl terminalTestSysctl
#define perror terminalTestPerror
#define TERMINAL_PROCESSINFO_TEST 1
#if defined(TERMINAL_PROCESSINFO_PPC_TEST)
#define TERMINAL_PROCESSINFO_FORCE_PPC 1
#endif
#include "../ProcessInfo.c"
#undef TERMINAL_PROCESSINFO_FORCE_PPC
#undef TERMINAL_PROCESSINFO_TEST
#undef perror
#undef sysctl

int terminalTestSysctl(int *mib, unsigned int mibLength, void *oldValue,
    size_t *oldLength, void *newValue, size_t newLength)
{
    unsigned int mibIndex;

    assert(mibLength == 4);
    assert(newValue == 0);
    assert(newLength == 0);
    for (mibIndex = 0; mibIndex < 4; ++mibIndex)
        lastMib[mibIndex] = mib[mibIndex];
    ++sysctlCalls;
    if (sysctlCalls == failCall) {
        errno = EINVAL;
        return -1;
    }
    if (oldValue == 0) {
        assert(sysctlCalls == 1);
        *oldLength = sizeof(testProcess);
        requestedSize = sizeof(testProcess);
    } else {
        assert(*oldLength == sizeof(testProcess));
        memcpy(oldValue, &testProcess, sizeof(testProcess));
    }
    return 0;
}

void terminalTestPerror(const char *message)
{
    assert(strcmp(message, "Failure calling sysctl") == 0);
    ++perrorCalls;
}

static void resetTest(void)
{
    free(processBuffer);
    processBuffer = 0;
    processBufferSize = 0;
    memset(&testProcess, 0, sizeof(testProcess));
    sysctlCalls = 0;
    failCall = 0;
    perrorCalls = 0;
    memset(lastMib, 0, sizeof(lastMib));
    requestedSize = 0;
}

#if defined(TERMINAL_PROCESSINFO_PPC_TEST)
static void storeRecordInteger(unsigned int offset, int value)
{
    memcpy(testProcess.bytes + offset, &value, sizeof(value));
}
#endif

int main(void)
{
    TerminalProcessInfo output;

    resetTest();
    memset(&output, 0, sizeof(output));
    failCall = 1;
    get_process_info_from_pid(41, &output);
    assert(sysctlCalls == 1);
    assert(perrorCalls == 1);
    assert(output.pid == 0);

    resetTest();
#if defined(TERMINAL_PROCESSINFO_PPC_TEST)
    testProcess.bytes[20] = 2;
    storeRecordInteger(24, 41);
    storeRecordInteger(392, 42);
    storeRecordInteger(396, 44);
    storeRecordInteger(404, 43);
    testProcess.bytes[163] = 's';
    testProcess.bytes[164] = 'h';
#else
    testProcess.kp_proc.p_stat = 2;
    testProcess.kp_proc.p_pid = 41;
    testProcess.kp_proc.p_comm[0] = 's';
    testProcess.kp_proc.p_comm[1] = 'h';
    testProcess.kp_eproc.e_pgid = 42;
    testProcess.kp_eproc.e_tdev = 43;
    testProcess.kp_eproc.e_tpgid = 44;
#endif
    memset(&output, 0, sizeof(output));
    get_process_info_from_pid(41, &output);
    assert(sysctlCalls == 2);
    assert(perrorCalls == 0);
    assert(requestedSize == sizeof(testProcess));
    assert(lastMib[0] == CTL_KERN);
    assert(lastMib[1] == KERN_PROC);
    assert(lastMib[2] == KERN_PROC_PID);
    assert(lastMib[3] == 41);
    assert(output.pid == 41);
    assert(output.processGroup == 42);
    assert(output.terminalDevice == 43);
    assert(output.terminalProcessGroup == 44);
    assert(output.isRunnable == 1);
    assert(output.command[0] == 's' && output.command[1] == 'h');

    resetTest();
#if defined(TERMINAL_PROCESSINFO_PPC_TEST)
    testProcess.bytes[20] = 3;
#else
    testProcess.kp_proc.p_stat = 3;
#endif
    failCall = 2;
    get_process_info_from_pid(52, &output);
    assert(sysctlCalls == 2);
    assert(perrorCalls == 1);
    assert(output.pid == 41);

    return 0;
}
