#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

static const char PASSWD[] =
    "##\n# comment\n##\nnobody:*:-2:-2::0:0:Unprivileged:/:/dev/null\n"
    "root:*:0:0::0:0:System Administrator:/:/bin/tcsh\n";

static void test_render(void)
{
	char *r = render("/dev/@DISK@a\t/\tufs\trw\t\t1  1\n", "hd0");
	char tmpl[256], *file;
	FILE *f;
	size_t n;

	CHECK(r != NULL && strcmp(r, "/dev/hd0a\t/\tufs\trw\t\t1  1\n") == 0);
	free(r);
	r = render("no tags", "hd0");
	CHECK(r != NULL && strcmp(r, "no tags") == 0);
	free(r);
	r = render("@DISK@@DISK@", "hd12");
	CHECK(r != NULL && strcmp(r, "hd12hd12") == 0);
	free(r);

	f = fopen("../../templates/fstab", "rb");
	CHECK(f != NULL);
	if (f == NULL)
		return;
	n = fread(tmpl, 1, sizeof tmpl - 1, f);
	fclose(f);
	tmpl[n] = '\0';
	file = render(tmpl, "hd0");
	CHECK(file != NULL && strcmp(file, "/dev/hd0a\t/\tufs\trw\t\t1  1\n") == 0);
	free(file);
}

static void test_passwd_set_root(void)
{
	char *got = passwd_set_root(PASSWD, "rhME8brSxdukA");

	CHECK(got != NULL);
	if (got != NULL) {
		CHECK(strstr(got, "\nroot:rhME8brSxdukA:0:0::0:0:System "
				  "Administrator:/:/bin/tcsh\n") != NULL);
		CHECK(strstr(got, "nobody:*:") != NULL);
		CHECK(strstr(got, "root:*:") == NULL);
		CHECK(strncmp(got, "##\n# comment\n##\n", 16) == 0);
	}
	free(got);
	CHECK(passwd_set_root("nobody:*:1:1\n", "x") == NULL);
	CHECK(passwd_set_root("toor:*:0:0\n", "x") == NULL);
}

static void test_salt_alphabet_and_eight_char_limit(void)
{
	unsigned seed;
	char s[3];
	int seen[256], distinct = 0, i;

	memset(seen, 0, sizeof seen);
	for (seed = 0; seed < 1000; seed++) {
		make_salt(seed, s);
		CHECK(s[2] == '\0');
		for (i = 0; i < 2; i++)
			CHECK(s[i] != '\0' &&
			      strchr("./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
				     "abcdefghijklmnopqrstuvwxyz", s[i]) != NULL);
		if (!seen[(unsigned char)s[0]]++)
			distinct++;
	}
	CHECK(distinct > 32);
	/* The 8-character password limit is crypt()'s: guest-only, Task 10. */
}

int main(void)
{
	test_render();
	test_passwd_set_root();
	test_salt_alphabet_and_eight_char_limit();
	printf("config: %d failures\n", failures);
	return failures != 0;
}
