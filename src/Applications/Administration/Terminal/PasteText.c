#include "PasteText.h"

#include <string.h>

unsigned int terminalPasteTextPrepare(char *text, int convertLineFeedToCarriageReturn)
{
    unsigned int length;
    unsigned int index;

    if (text == 0)
        return 0;
    length = (unsigned int)strlen(text);
    if (convertLineFeedToCarriageReturn) {
        for (index = 0; index < length; ++index) {
            if (text[index] == '\n')
                text[index] = '\r';
        }
    }
    return length;
}
