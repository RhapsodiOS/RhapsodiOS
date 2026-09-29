#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_support.h"

typedef void (*CopyTypedRows)(const void *, int, void *, int, int, int);
typedef void (*CopyRows)(const void *, int, void *, int, int);

static void *LoadSelectedFramework(void)
{
    const char *root = getenv("FRAMEWORK_ROOT");
    char path[4096];
    if (!root || !*root || strlen(root) + sizeof("/Versions/A/Interceptor") >= sizeof(path))
        return 0;
    strcpy(path, root);
    strcat(path, "/Versions/A/Interceptor");
    {
        void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (!handle) fprintf(stderr, "cannot load %s: %s\n", path, dlerror());
        return handle;
    }
}

int main(void)
{
    void *handle = LoadSelectedFramework();
    CopyTypedRows copyLong = handle ? (CopyTypedRows)dlsym(handle, "CopyLong") : 0;
    CopyTypedRows copyShort = handle ? (CopyTypedRows)dlsym(handle, "CopyShort") : 0;
    CopyTypedRows copyByte = handle ? (CopyTypedRows)dlsym(handle, "CopyByte") : 0;
    CopyRows copyRows = handle ? (CopyRows)dlsym(handle, "CopySrcToDst") : 0;
    unsigned int longSource[8] = { 0x12345678, 0x90ABCDEF, 0x0F1E2D3C,
                                   0x87654321, 0x13579BDF, 0x2468ACE0,
                                   0xAAAAAAAA, 0xBBBBBBBB };
    unsigned int longDestination[10];
    unsigned short shortSource[12];
    unsigned short shortDestination[14];
    unsigned char byteSource[32];
    unsigned char byteDestination[40];
    unsigned char rowSource[20];
    unsigned char rowDestination[20];
    int i;

    TestCheck(handle != 0, "loads selected framework for copy checks");
    TestCheck(copyLong != 0 && copyShort != 0 && copyByte != 0 && copyRows != 0,
              "resolves all exported copy helpers");

    for (i = 0; i < 10; i++) longDestination[i] = 0xEEEEEEEE;
    copyLong(longSource, 16, longDestination, 20, 3, 2);
    TestCheck(longDestination[0] == longSource[0] &&
              longDestination[1] == longSource[1] &&
              longDestination[2] == longSource[2] &&
              longDestination[3] == 0xEEEEEEEE &&
              longDestination[5] == longSource[4] &&
              longDestination[8] == 0xEEEEEEEE,
              "long copy preserves row padding and copies requested words");

    for (i = 0; i < 12; i++) shortSource[i] = (unsigned short)(0x1200 + i * 0x31);
    for (i = 0; i < 14; i++) shortDestination[i] = 0xEEEE;
    copyShort(shortSource, 14, shortDestination, 16, 5, 2);
    TestCheck(shortDestination[0] == shortSource[0] &&
              shortDestination[4] == shortSource[4] &&
              shortDestination[5] == 0xEEEE &&
              shortDestination[8] == shortSource[7] &&
              shortDestination[13] == 0xEEEE,
              "short copy preserves row padding and copies requested elements");

    for (i = 0; i < 32; i++) byteSource[i] = (unsigned char)(0xD3 - i * 7);
    memset(byteDestination, 0xEE, sizeof(byteDestination));
    copyByte(byteSource + 1, 11, byteDestination + 3, 13, 7, 2);
    TestCheck(byteDestination[3] == byteSource[1] &&
              byteDestination[9] == byteSource[7] &&
              byteDestination[10] == 0xEE &&
              byteDestination[16] == byteSource[12] &&
              byteDestination[22] == 0xEE,
              "byte copy handles unaligned rows and preserves padding");

    for (i = 0; i < 20; i++) rowSource[i] = (unsigned char)(i + 0x41);
    memset(rowDestination, 0xEE, sizeof(rowDestination));
    copyRows(rowSource, 10, rowDestination, 8, 2);
    TestCheck(rowDestination[0] == rowSource[0] && rowDestination[7] == rowSource[7] &&
              rowDestination[8] == 0xEE && rowDestination[10] == rowSource[10] &&
              rowDestination[15] == rowSource[17] && rowDestination[17] == 0xEE,
              "row copy copies the smaller stride for each row");

    return TestFinish();
}
