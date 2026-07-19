#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graph.h"   /* MTIME_MISSING */
#include "os.h"
#include "util.h"

/* NT4 SDK does not define INVALID_FILE_ATTRIBUTES */
#ifndef INVALID_FILE_ATTRIBUTES
#define INVALID_FILE_ATTRIBUTES ((DWORD)0xFFFFFFFF)
#endif

void
osgetcwd(char *buf, size_t len)
{
	DWORD r = GetCurrentDirectoryA((DWORD)len, buf);
	if (r == 0 || r >= (DWORD)len)
		fatal("getcwd:");
}

void
oschdir(const char *dir)
{
	if (!SetCurrentDirectoryA(dir))
		fatal("chdir %s:", dir);
}

int
osmkdirs(struct string *path, bool parent)
{
	int ret;
	char *s, *end;
	DWORD attr;

	ret = 0;
	end = path->s + path->n;
	for (s = end - parent; s > path->s; --s) {
		if (*s != '/' && *s)
			continue;
		*s = '\0';
		attr = GetFileAttributesA(path->s);
		if (attr != INVALID_FILE_ATTRIBUTES)
			break;
	}
	if (s > path->s && s < end)
		*s = '/';
	while (++s <= end - parent) {
		if (*s != '\0')
			continue;
		if (ret == 0 && !CreateDirectoryA(path->s, NULL) &&
		    GetLastError() != ERROR_ALREADY_EXISTS) {
			warn("mkdir %s:", path->s);
			ret = -1;
		}
		if (s < end)
			*s = '/';
	}

	return ret;
}

int64_t
osmtime(const char *name)
{
	WIN32_FILE_ATTRIBUTE_DATA fad;
	int64_t t;
	DWORD e;

	if (!GetFileAttributesExA(name, GetFileExInfoStandard, &fad)) {
		e = GetLastError();
		if (e != ERROR_FILE_NOT_FOUND && e != ERROR_PATH_NOT_FOUND)
			fatal("stat %s:", name);
		return MTIME_MISSING;
	}
	/* FILETIME: 100ns ticks since 1601-01-01. Convert to ns since 1970. */
	t = (int64_t)(((uint64_t)fad.ftLastWriteTime.dwHighDateTime << 32) |
	    (uint64_t)fad.ftLastWriteTime.dwLowDateTime);
	t -= UINT64_C(116444736000000000);  /* 1601->1970 in 100ns units */
	return t * 100;
}

long
osnproc(void)
{
	SYSTEM_INFO si;

	GetSystemInfo(&si);
	return (long)si.dwNumberOfProcessors;
}

void *
osspawn(const char *cmd, void *out)
{
	STARTUPINFOA si;
	PROCESS_INFORMATION pi;
	SECURITY_ATTRIBUTES sa;
	HANDLE outh, nul;
	char *cmdline;
	size_t len;

	outh = (HANDLE)out;
	len = strlen(cmd);
	cmdline = xmalloc(len + 8);          /* "cmd /c " + cmd + NUL */
	memcpy(cmdline, "cmd /c ", 7);
	memcpy(cmdline + 7, cmd, len + 1);

	memset(&si, 0, sizeof si);
	si.cb = sizeof si;
	nul = INVALID_HANDLE_VALUE;
	if (outh != INVALID_HANDLE_VALUE) {
		sa.nLength = sizeof sa;
		sa.lpSecurityDescriptor = NULL;
		sa.bInheritHandle = TRUE;
		nul = CreateFileA("NUL", GENERIC_READ,
		    FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
		si.dwFlags = STARTF_USESTDHANDLES;
		si.hStdInput = (nul != INVALID_HANDLE_VALUE) ? nul : GetStdHandle(STD_INPUT_HANDLE);
		si.hStdOutput = outh;
		si.hStdError = outh;
	}
	if (!CreateProcessA(NULL, cmdline, NULL, NULL, TRUE, 0, NULL, NULL,
	    &si, &pi)) {
		warn("CreateProcess:");
		free(cmdline);
		if (nul != INVALID_HANDLE_VALUE)
			CloseHandle(nul);
		return NULL;
	}
	free(cmdline);
	if (nul != INVALID_HANDLE_VALUE)
		CloseHandle(nul);
	CloseHandle(pi.hThread);
	return pi.hProcess;
}

/* compat.h shims, implemented once here */
int
clock_gettime(int clk, struct timespec *ts)
{
	LARGE_INTEGER freq, ctr;

	(void)clk;
	if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&ctr))
		return -1;
	ts->tv_sec = (long)(ctr.QuadPart / freq.QuadPart);
	ts->tv_nsec = (long)(((ctr.QuadPart % freq.QuadPart) * 1000000000) /
	    freq.QuadPart);
	return 0;
}

int
samu_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
	va_list aq;
	int n;
	size_t cap;
	char *tmp;

	if (buf && size) {
		aq = ap;                       /* x86 va_list is a pointer: copy */
		n = _vsnprintf(buf, size, fmt, aq);
		if (n >= 0 && (size_t)n < size)
			return n;
	}
	cap = (size > 64) ? size * 2 : 128;
	for (;;) {
		tmp = malloc(cap);
		if (!tmp)
			return -1;
		aq = ap;
		n = _vsnprintf(tmp, cap, fmt, aq);
		if (n >= 0 && (size_t)n < cap) {
			if (buf && size) {
				size_t c = ((size_t)n < size) ? (size_t)n : size - 1;
				memcpy(buf, tmp, c);
				buf[c] = '\0';
			}
			free(tmp);
			return n;
		}
		free(tmp);
		cap *= 2;
	}
}

int
samu_snprintf(char *buf, size_t size, const char *fmt, ...)
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = samu_vsnprintf(buf, size, fmt, ap);
	va_end(ap);
	return n;
}

/* 64-bit strtol (the NT4 CRT has neither strtoll nor _strtoi64). Handles an
 * optional sign, optional 0x prefix for base 16/0, and bases 2-36. No overflow
 * clamping (samu's .ninja_log values are well-formed and in range). */
uint64_t
samu_strtoull(const char *s, char **end, int base)
{
	const char *p = s;
	uint64_t acc = 0;
	int any = 0, neg = 0, c;

	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ||
	    *p == '\v' || *p == '\f')
		++p;
	if (*p == '+' || *p == '-') {
		neg = (*p == '-');
		++p;
	}
	if ((base == 0 || base == 16) && p[0] == '0' &&
	    (p[1] == 'x' || p[1] == 'X')) {
		p += 2;
		base = 16;
	} else if (base == 0) {
		base = (p[0] == '0') ? 8 : 10;
	}
	for (;; ++p) {
		c = (unsigned char)*p;
		if (c >= '0' && c <= '9')
			c -= '0';
		else if (c >= 'a' && c <= 'z')
			c = c - 'a' + 10;
		else if (c >= 'A' && c <= 'Z')
			c = c - 'A' + 10;
		else
			break;
		if (c >= base)
			break;
		acc = acc * (unsigned)base + c;
		any = 1;
	}
	if (end)
		*end = (char *)(any ? p : s);
	return neg ? (uint64_t)(-(int64_t)acc) : acc;
}

int64_t
samu_strtoll(const char *s, char **end, int base)
{
	return (int64_t)samu_strtoull(s, end, base);
}
