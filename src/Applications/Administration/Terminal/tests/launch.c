#include <assert.h>
#include <string.h>

typedef int (*TerminalChangeDirectoryFunction)(const char *path);
typedef const char *(*TerminalProcessNameFunction)(void);
typedef int (*TerminalPathAccessFunction)(const char *path, int mode);

int TerminalCheckWrapperLaunch(const char *directory,
    TerminalChangeDirectoryFunction changeDirectory,
    TerminalProcessNameFunction processName,
    TerminalPathAccessFunction pathAccess);

static int changeDirectoryResult;
static int pathAccessResult;
static int changeDirectoryCalls;
static int processNameCalls;
static int pathAccessCalls;

static int testChangeDirectory(const char *path)
{
    assert(strcmp(path, "wrapper") == 0);
    ++changeDirectoryCalls;
    return changeDirectoryResult;
}

static const char *testProcessName(void)
{
    ++processNameCalls;
    return "Terminal";
}

static int testPathAccess(const char *path, int mode)
{
    assert(strcmp(path, "Terminal") == 0);
    assert(mode == 4);
    ++pathAccessCalls;
    return pathAccessResult;
}

int main(void)
{
    changeDirectoryResult = -1;
    pathAccessResult = 0;
    assert(TerminalCheckWrapperLaunch("wrapper", testChangeDirectory,
        testProcessName, testPathAccess) == 0);
    assert(changeDirectoryCalls == 1);
    assert(processNameCalls == 0);
    assert(pathAccessCalls == 0);

    changeDirectoryResult = 0;
    pathAccessResult = -1;
    assert(TerminalCheckWrapperLaunch("wrapper", testChangeDirectory,
        testProcessName, testPathAccess) == 0);
    assert(changeDirectoryCalls == 2);
    assert(processNameCalls == 1);
    assert(pathAccessCalls == 1);

    pathAccessResult = 0;
    assert(TerminalCheckWrapperLaunch("wrapper", testChangeDirectory,
        testProcessName, testPathAccess) == 1);
    assert(changeDirectoryCalls == 3);
    assert(processNameCalls == 2);
    assert(pathAccessCalls == 2);
    return 0;
}
