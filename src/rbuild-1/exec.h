#ifndef RBUILD_EXEC_H
#define RBUILD_EXEC_H

extern int exec_dry_run;

void exec_printcmd(char *const argv[]);
int exec_run(char *const argv[]);
int exec_runv(const char *arg0, ...);
char *exec_checkret(int status);
int exec_check(int status);
int exec_run_checked(char *const argv[]);

#endif
