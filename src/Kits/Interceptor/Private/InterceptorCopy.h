#ifndef _INTERCEPTOR_COPY_PRIVATE_H_
#define _INTERCEPTOR_COPY_PRIVATE_H_

/* The stride arguments are extra bytes to skip after each copied row. */
void CopyLong(const void *source, int sourcePadding, void *destination,
              int destinationPadding, int longCount, int rowCount);
void CopyShort(const void *source, int sourcePadding, void *destination,
               int destinationPadding, int shortCount, int rowCount);
void CopyByte(const void *source, int sourcePadding, void *destination,
              int destinationPadding, int byteCount, int rowCount);
void CopySrcToDst(const void *source, int sourceStride, void *destination,
                  int destinationStride, int rowCount);

#endif
