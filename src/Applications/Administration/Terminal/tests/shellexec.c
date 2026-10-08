#include <stdio.h>
#include <string.h>
#include <errno.h>

#include "../ShellExec.h"

#define MAX_CAPTURED_ARGUMENTS 8
#define MAX_CAPTURED_LENGTH 64

static char capturedPath[MAX_CAPTURED_LENGTH];
static char capturedArguments[MAX_CAPTURED_ARGUMENTS][MAX_CAPTURED_LENGTH];
static unsigned capturedCount;

int terminalTestExecvp(const char *program,
#if defined(_WIN32)
                       const char *const *arguments
#else
                       char *const arguments[]
#endif
                       )
{
    unsigned i;

    strcpy(capturedPath, program == NULL ? "<null>" : program);
    capturedCount = 0;
    while (capturedCount < MAX_CAPTURED_ARGUMENTS - 1 &&
           arguments[capturedCount] != NULL) {
        strcpy(capturedArguments[capturedCount], arguments[capturedCount]);
        ++capturedCount;
    }
    for (i = capturedCount; i < MAX_CAPTURED_ARGUMENTS; ++i)
        capturedArguments[i][0] = '\0';
    errno = EACCES;
    return -1;
}

static int check_execs(void)
{
    char command[] = "echo 'two words' third\\ argument";

    if (execs(command) != -1 || strcmp(capturedPath, "echo") != 0 ||
        capturedCount != 3 || strcmp(capturedArguments[0], "echo") != 0 ||
        strcmp(capturedArguments[1], "two words") != 0 ||
        strcmp(capturedArguments[2], "third argument") != 0 || errno != EACCES) {
        fputs("execs argument vector mismatch\n", stderr);
        return 0;
    }
    return 1;
}

static int check_execs0(void)
{
    char command[] = "/bin/sh -c 'echo two words'";

    if (execs0(command) != -1 || strcmp(capturedPath, "/bin/sh") != 0 ||
        capturedCount != 3 || strcmp(capturedArguments[0], "-sh") != 0 ||
        strcmp(capturedArguments[1], "-c") != 0 ||
        strcmp(capturedArguments[2], "echo two words") != 0 || errno != EACCES) {
        fputs("execs0 login argument vector mismatch\n", stderr);
        return 0;
    }
    return 1;
}

static int check_tokens(char *input, const char **expected, unsigned count)
{
    unsigned i;
    char *token = cmdtok(input);

    for (i = 0; i < count; ++i) {
        if (token == NULL || strcmp(token, expected[i]) != 0) {
            fprintf(stderr, "token %u mismatch: expected <%s>, got <%s>\n",
                    i, expected[i], token == NULL ? "NULL" : token);
            return 0;
        }
        token = cmdtok(NULL);
    }
    if (token != NULL && *token != '\0') {
        fprintf(stderr, "unexpected trailing token <%s>\n", token);
        return 0;
    }
    return 1;
}

int main(void)
{
    static const char *basic[] = {"echo", "one", "two"};
    static const char *quoted[] = {"echo", "two words", "three words"};
    static const char *escaped[] = {"echo", "a b", "c\"d", "e'f"};
    char basicInput[] = "  echo\tone  two  ";
    char quotedInput[] = "echo 'two words' \"three words\"";
    char escapedInput[] = "echo a\\ b \"c\\\"d\" 'e\\'f'";
    char incompleteQuote[] = "echo 'unfinished";
    char trailingEscape[] = "echo tail\\";
    char *token;

    if (!check_tokens(basicInput, basic, 3))
        return 1;
    if (!check_tokens(quotedInput, quoted, 3))
        return 1;
    if (!check_tokens(escapedInput, escaped, 4))
        return 1;
    token = cmdtok(incompleteQuote);
    if (token == NULL || strcmp(token, "echo") != 0 || cmdtok(NULL) != NULL) {
        fputs("unterminated quote was accepted\n", stderr);
        return 1;
    }
    token = cmdtok(trailingEscape);
    if (token == NULL || strcmp(token, "echo") != 0 || cmdtok(NULL) != NULL) {
        fputs("outside-quote trailing escape behavior changed\n", stderr);
        return 1;
    }
    if (!check_execs() || !check_execs0())
        return 1;
    return 0;
}
