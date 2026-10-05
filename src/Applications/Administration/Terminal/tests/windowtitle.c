#include "../WindowTitle.h"
#include "../PathCompress.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

static void setEnvironment(const char *name, const char *value)
{
#if defined(_WIN32)
    _putenv_s(name, value);
#else
    setenv(name, value, 1);
#endif
}

int main(void)
{
    static const char expected[] =
        "My Shell  \xD0\x20 ~/bin  (ttys001)  80x24  \xD0\x20 ~/Documents/log";
    char *title;
    char compressed[64];

    setEnvironment("HOME", "/Users/ray");
    setEnvironment("TERMINAL_TEST_PROCESS_NAME", "Terminal");
    assert(pathCompress("/Users/ray/a/b/c/file", compressed, 6) == compressed);
    assert(strcmp(compressed, ".../c/file") == 0);
    setEnvironment("HOME", "/root");
    pathCompress("/root/a", compressed, 64);
    assert(strcmp(compressed, "/root/a") == 0);
    setEnvironment("HOME", "/Users/ray");
    title = winTitle(0, 0, 0, 0, 0, 0, 0, 0);
    assert(strcmp(title, "Terminal") == 0);

    title = winTitle(0, 0, 0, 0, 0, 1, 0, 0);
    assert(strcmp(title, "Terminal \xD0 (Key Stealer)") == 0);

    title = winTitle("/Users/ray/bin", "/dev/ttys001", 80, 24, 0x1f, 0,
                     "My Shell", "/Users/ray/Documents/log");
    assert(strcmp(title, expected) == 0);
    return 0;
}
