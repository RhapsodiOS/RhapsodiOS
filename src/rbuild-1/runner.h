#ifndef RBUILD_RUNNER_H
#define RBUILD_RUNNER_H
#include "toolchain.h"

typedef struct {
    int bootstrap;
    const char *sysroot;
    const char *state_dir;
    const Toolchain *toolchain;
    const char *toolchain_file;
} RunnerOptions;

int runner_manifest(const char *srclist, const char *seeddir,
                    const char *dstdir, const RunnerOptions *opt);
int runner_buildpackage(const char *type, const char *source,
                        const char *seeddir, const char *target,
                        const char *dstdir, const char *state_dir);
#ifdef RBUILD_RUNNER_TESTING
void runner_test_set_before_replay_hook(void (*hook)(void));
#endif
#endif
