#ifndef IDE_MODE_UTILS_H
#define IDE_MODE_UTILS_H

static unsigned char ideHighestModeBit(unsigned short supported,
    unsigned char maxMode)
{
    int mode;

    for (mode=(int)maxMode; mode>=0; mode--)
        if (supported & (1U<<mode))
            return (unsigned char)(1U<<mode);
    return 0;
}

#endif
