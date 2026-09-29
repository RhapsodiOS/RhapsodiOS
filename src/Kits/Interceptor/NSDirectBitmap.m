#import "Private/InterceptorCopy.h"

void CopyLong(const void *source, int sourceStride, void *destination,
              int destinationStride, int longCount, int rowCount)
{
    const unsigned int *sourceWords = (const unsigned int *)source;
    unsigned int *destinationWords = (unsigned int *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < longCount; column++)
            destinationWords[column] = sourceWords[column];
        sourceWords = (const unsigned int *)((const unsigned char *)sourceWords + sourceStride);
        destinationWords = (unsigned int *)((unsigned char *)destinationWords + destinationStride);
    }
}

void CopyShort(const void *source, int sourceStride, void *destination,
               int destinationStride, int shortCount, int rowCount)
{
    const unsigned short *sourceShorts = (const unsigned short *)source;
    unsigned short *destinationShorts = (unsigned short *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < shortCount; column++)
            destinationShorts[column] = sourceShorts[column];
        sourceShorts = (const unsigned short *)((const unsigned char *)sourceShorts + sourceStride);
        destinationShorts = (unsigned short *)((unsigned char *)destinationShorts + destinationStride);
    }
}

void CopyByte(const void *source, int sourceStride, void *destination,
              int destinationStride, int byteCount, int rowCount)
{
    const unsigned char *sourceBytes = (const unsigned char *)source;
    unsigned char *destinationBytes = (unsigned char *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < byteCount; column++)
            destinationBytes[column] = sourceBytes[column];
        sourceBytes += sourceStride;
        destinationBytes += destinationStride;
    }
}
