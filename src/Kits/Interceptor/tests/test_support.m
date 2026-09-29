#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import "test_support.h"

static int failureCount = 0;

void *TestLoadSelectedFramework(void)
{
    const char *root = getenv("FRAMEWORK_ROOT");
    char path[4096];
    struct stat info;
    void *handle;

    if (!root || !*root)
        return 0;

    if (stat(root, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG) {
        if (strlen(root) >= sizeof(path))
            return 0;
        strcpy(path, root);
    } else {
        if (strlen(root) + sizeof("/Versions/A/Interceptor") > sizeof(path))
            return 0;
        strcpy(path, root);
        strcat(path, "/Versions/A/Interceptor");
    }

    handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle)
        fprintf(stderr, "cannot load selected framework %s: %s\n", path, dlerror());
    return handle;
}

int TestCheck(int condition, const char *name)
{
    if (condition)
        return 1;

    fprintf(stderr, "FAIL: %s\n", name);
    failureCount++;
    return 0;
}

int TestFinish(void)
{
    if (failureCount != 0)
        fprintf(stderr, "%d checks failed\n", failureCount);
    else
        printf("all checks passed\n");
    return failureCount == 0 ? 0 : 1;
}
