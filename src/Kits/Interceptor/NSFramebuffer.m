#import "Private/InterceptorCopy.h"

void CopySrcToDst(const void *source, int sourceStride, void *destination,
                  int destinationStride, int rowCount)
{
    const unsigned char *sourceBytes = (const unsigned char *)source;
    unsigned char *destinationBytes = (unsigned char *)destination;
    int copyBytes = sourceStride < destinationStride ? sourceStride : destinationStride;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < copyBytes; column++)
            destinationBytes[column] = sourceBytes[column];
        sourceBytes += sourceStride;
        destinationBytes += destinationStride;
    }
}
