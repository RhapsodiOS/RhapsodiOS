#include "WindowTitle.h"

#include "PathCompress.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__NeXT__)
typedef struct _NSZone NSZone;
extern NSZone *NSDefaultMallocZone(void);
extern void *NSZoneRealloc(NSZone *zone, void *ptr, unsigned int size);
#endif

static char *retString;
static unsigned int retStringLength;
static const char separator[] = { ' ', ' ', (char)0xD0, 0x20, ' ', '\0' };

#if defined(__NeXT__)
extern const char *terminalProcessName(void);
extern const char *terminalKeyStealerSuffix(void);
#else
static const char *terminalProcessName(void)
{
    const char *name = getenv("TERMINAL_TEST_PROCESS_NAME");
    return name != 0 ? name : "";
}

static const char *terminalKeyStealerSuffix(void)
{
    return " \xD0 (Key Stealer)";
}
#endif

static void appendSeparator(char *title)
{
    strcat(title, separator);
}

char *winTitle(const char *command, const char *pty,
               int columns, int rows, int options, char debugging,
               const char *customTitle, const char *fileName)
{
    char title[256];
    char component[268];
    const char *ptyName;
    const char *slash;
    unsigned int hasComponent = 0;
    size_t length;

    if (options != 0) {
        title[0] = '\0';
        if ((options & 8) != 0 && customTitle != 0 &&
            strlen(customTitle) <= 255 && customTitle[0] != '\0') {
            strcat(title, customTitle);
            hasComponent = 1;
        }
        if ((options & 1) != 0 && command != 0) {
            if (strlen(command) + strlen(title) + 5 <= 255) {
                if (hasComponent)
                    appendSeparator(title);
                pathCompress(command, title + strlen(title), 12);
                ++hasComponent;
            }
        }
        if ((options & 2) != 0) {
            ptyName = pty;
            slash = pty != 0 ? strrchr(pty, '/') : 0;
            if (slash != 0)
                ptyName = slash + 1;
            if (hasComponent)
                sprintf(component, "  (%s)", ptyName != 0 ? ptyName : "(null)");
            else
                sprintf(component, "%s", ptyName != 0 ? ptyName : "(null)");
            strcat(title, component);
            ++hasComponent;
        }
        if ((options & 4) != 0) {
            if (hasComponent)
                sprintf(component, "  %dx%d", columns, rows);
            else
                sprintf(component, "%dx%d", columns, rows);
            strcat(title, component);
            ++hasComponent;
        }
        if ((options & 0x10) != 0 && fileName != 0 &&
            fileName[0] != '\0' && strlen(fileName) <= 255) {
            if (hasComponent)
                appendSeparator(title);
            pathCompress(fileName, component, 26);
            strcat(title, component);
        }
    } else {
        strcpy(title, terminalProcessName());
    }
    if (debugging != 0)
        strcat(title, terminalKeyStealerSuffix());

    length = strlen(title) + 1;
    if (retStringLength < length) {
        retStringLength = (unsigned int)length + 32;
#if defined(__NeXT__)
        retString = (char *)NSZoneRealloc(NSDefaultMallocZone(), retString,
            retStringLength);
#else
        retString = (char *)realloc(retString, retStringLength);
#endif
    }
    strcpy(retString, title);
    return retString;
}
