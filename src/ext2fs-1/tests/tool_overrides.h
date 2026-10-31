/* Compile-time providers confined to native tests. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/ioctl.h>
int tool_stat(const char *,struct stat *);
int tool_getmntinfo(struct statfs **,int);
char *tool_realpath(const char *,char *);
ssize_t tool_read(int,void *,size_t);
#define stat(p,s) tool_stat(p,s)
#define getmntinfo(p,f) tool_getmntinfo(p,f)
#define realpath(p,b) tool_realpath(p,b)
#define read(f,p,n) tool_read(f,p,n)
int tool_open(const char *,int);
int tool_ioctl(int,unsigned long,void *);
#define open(p,f) tool_open(p,f)
#define ioctl(f,c,p) tool_ioctl(f,c,p)
int tool_fstat(int,struct stat *);
#define fstat(f,s) tool_fstat(f,s)
