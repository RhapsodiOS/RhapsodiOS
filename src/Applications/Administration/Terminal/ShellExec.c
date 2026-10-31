#include "ShellExec.h"

#include <ctype.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <process.h>
#else
#include <unistd.h>
#endif

static char *commandCursor;

char *cmdtok(char *command)
{
    char *start;
    char quote;

    if (command != NULL)
        commandCursor = command;

    while (*commandCursor != '\0' && isspace((unsigned char)*commandCursor))
        ++commandCursor;

    start = commandCursor;
    while (*commandCursor != '\0' &&
           !isspace((unsigned char)*commandCursor)) {
        if (*commandCursor == '\\') {
            strcpy(commandCursor, commandCursor + 1);
            if (*commandCursor == '\0')
                return NULL;
            ++commandCursor;
        } else if (*commandCursor == '\'' || *commandCursor == '"') {
            quote = *commandCursor;
            strcpy(commandCursor, commandCursor + 1);
            while (*commandCursor != '\0' && *commandCursor != quote) {
                if (*commandCursor == '\\')
                    strcpy(commandCursor, commandCursor + 1);
                if (*commandCursor != '\0')
                    ++commandCursor;
            }
            if (*commandCursor != quote)
                return NULL;
            strcpy(commandCursor, commandCursor + 1);
        } else {
            ++commandCursor;
        }
    }

    if (*commandCursor != '\0')
        *commandCursor++ = '\0';
    return start;
}

static int makeArguments(char *command, char ***arguments, int *count,
                         char **copy)
{
    char *token;
    char **argv = NULL;
    int argc = 0;

    *copy = (char *)malloc(strlen(command) + 1);
    strcpy(*copy, command);
    token = cmdtok(*copy);
    while (token != NULL && *token != '\0') {
        argv = (char **)realloc(argv, sizeof(char *) * (argc + 1));
        argv[argc] = (char *)malloc(strlen(token) + 1);
        strcpy(argv[argc], token);
        ++argc;
        token = cmdtok(NULL);
    }
    argv = (char **)realloc(argv, sizeof(char *) * (argc + 1));
    argv[argc] = NULL;
    *arguments = argv;
    *count = argc;
    return token != NULL;
}

static void freeArguments(char **argv, int argc, char *copy)
{
    while (argc >= 0)
        free(argv[argc--]);
    free(argv);
    free(copy);
}

int execs(char *command)
{
    char **argv;
    char *copy;
    int argc;
    int hasToken = makeArguments(command, &argv, &argc, &copy);

    if (hasToken)
        execvp(argv[0], argv);
    else
        errno = 63;
    freeArguments(argv, argc, copy);
    return -1;
}

int execs0(char *command)
{
    char **argv;
    char *copy;
    char *slash;
    char *program;
    char *loginName;
    char *loginArgument;
    int argc;
    int hasToken = makeArguments(command, &argv, &argc, &copy);

    if (hasToken) {
        program = argv[0];
        slash = strrchr(program, '/');
        loginName = slash == NULL ? program : slash + 1;
        loginArgument = (char *)malloc(strlen(loginName) + 2);
        strcpy(loginArgument, "-");
        strcat(loginArgument, loginName);
        argv[0] = loginArgument;
        execvp(program, argv);
        free(loginArgument);
        argv[0] = program;
    } else {
        errno = 63;
    }
    freeArguments(argv, argc, copy);
    return -1;
}
