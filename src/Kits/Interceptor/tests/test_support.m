#import <stdio.h>
#import "test_support.h"

static int failureCount = 0;

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
