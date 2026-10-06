#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sets.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

static char *slurp(const char *path)
{
	FILE *f = fopen(path, "rb");
	long n;
	char *b;

	if (f == NULL)
		return NULL;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	b = malloc(n + 1);
	if (fread(b, 1, n, f) != (size_t)n)
		n = 0;
	b[n] = '\0';
	fclose(f);
	return b;
}

static int has_pkg(const struct set *s, const char *p)
{
	int i;
	for (i = 0; i < s->npkgs; i++)
		if (strcmp(s->pkgs[i], p) == 0)
			return 1;
	return 0;
}

static void test_parse_base_set(void)
{
	struct set s;
	char *text = slurp("../../sets/base.set");

	CHECK(text != NULL);
	if (text == NULL)
		return;
	CHECK(set_parse("base", text, &s) == 0);
	CHECK(strcmp(s.name, "base") == 0);
	CHECK(strcmp(s.title, "Base system") == 0);
	CHECK(strcmp(s.desc, "Console system with networking and SSH") == 0);
	CHECK(s.required == 1);
	CHECK(s.npkgs > 0 && strcmp(s.pkgs[0], "files") == 0);
	CHECK(has_pkg(&s, "driverkit"));
	CHECK(has_pkg(&s, "libcurses"));
	set_free(&s);
	free(text);
}

static void test_parse_syntax(void)
{
	struct set s;

	CHECK(set_parse("x", "# c\n\ntitle  T\r\nrequired no\n  a  \n\n# z\nb\n",
			&s) == 0);
	CHECK(strcmp(s.title, "T") == 0 && s.required == 0 && s.npkgs == 2);
	CHECK(strcmp(s.pkgs[0], "a") == 0 && strcmp(s.pkgs[1], "b") == 0);
	set_free(&s);
	CHECK(set_parse("x", "required maybe\n", &s) == -1);
}

static void test_union_lists_each_package_once(void)
{
	struct set sets[2];
	int chosen[2];
	char **out;
	const char *want[] = { "files", "a", "b", "c" };
	int n, i;

	CHECK(set_parse("s1", "a\nb\nfiles\n", &sets[0]) == 0);
	CHECK(set_parse("s2", "b\nc\n", &sets[1]) == 0);
	chosen[0] = 0; chosen[1] = 1;
	n = set_union(sets, chosen, 2, &out);
	CHECK(n == 4);
	for (i = 0; i < n && i < 4; i++)
		CHECK(strcmp(out[i], want[i]) == 0);
	for (i = 0; i < n; i++)
		free(out[i]);
	free(out);
	set_free(&sets[0]);
	set_free(&sets[1]);
}

int main(void)
{
	test_parse_base_set();
	test_parse_syntax();
	test_union_lists_each_package_once();
	printf("sets: %d failures\n", failures);
	return failures != 0;
}
