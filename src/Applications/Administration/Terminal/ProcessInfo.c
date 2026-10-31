#include "ProcessInfo.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef TERMINAL_PROCESSINFO_TEST
#include <sys/sysctl.h>
#endif

static size_t processBufferSize;
static void *processBuffer;

void get_process_info_from_pid(int pid, TerminalProcessInfo *output)
{
    int mib[4];
#if defined(TERMINAL_PROCESSINFO_FORCE_PPC) || defined(__ppc__) || \
    defined(__powerpc__) || defined(__POWERPC__)
    const char *record;
#else
    struct kinfo_proc *process;
#endif

    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = pid;

    if (processBufferSize == 0) {
        if (sysctl(mib, 4, 0, &processBufferSize, 0, 0) < 0) {
            perror("Failure calling sysctl");
            return;
        }
        processBuffer = malloc(processBufferSize);
    }
    if (sysctl(mib, 4, processBuffer, &processBufferSize, 0, 0) < 0) {
        perror("Failure calling sysctl");
        return;
    }

#if defined(TERMINAL_PROCESSINFO_FORCE_PPC) || defined(__ppc__) || \
    defined(__powerpc__) || defined(__POWERPC__)
    record = (const char *)processBuffer;
    memcpy(&output->pid, record + 24, sizeof(output->pid));
    memcpy(&output->processGroup, record + 392,
        sizeof(output->processGroup));
    memcpy(&output->terminalProcessGroup, record + 396,
        sizeof(output->terminalProcessGroup));
    memcpy(&output->terminalDevice, record + 404,
        sizeof(output->terminalDevice));
    output->isRunnable = (unsigned char)record[20] == 2;
    strncpy(output->command, record + 163,
        TERMINAL_PROCESS_COMMAND_LENGTH);
#else
    process = (struct kinfo_proc *)processBuffer;
    output->pid = process->kp_proc.p_pid;
    output->processGroup = process->kp_eproc.e_pgid;
    output->terminalProcessGroup = process->kp_eproc.e_tpgid;
    output->terminalDevice = process->kp_eproc.e_tdev;
    output->isRunnable = process->kp_proc.p_stat == 2;
    strncpy(output->command, process->kp_proc.p_comm,
        TERMINAL_PROCESS_COMMAND_LENGTH);
#endif
}
