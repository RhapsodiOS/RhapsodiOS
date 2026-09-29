#ifndef _INTERCEPTOR_COPY_PRIVATE_H_
#define _INTERCEPTOR_COPY_PRIVATE_H_

void CopyLong(const void *source, int sourceStride, void *destination,
              int destinationStride, int longCount, int rowCount);
void CopyShort(const void *source, int sourceStride, void *destination,
               int destinationStride, int shortCount, int rowCount);
void CopyByte(const void *source, int sourceStride, void *destination,
              int destinationStride, int byteCount, int rowCount);
void CopySrcToDst(const void *source, int sourceStride, void *destination,
                  int destinationStride, int rowCount);

#endif
