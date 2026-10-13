/* sets.c -- see sets.h. */

#include <stdlib.h>
#include <string.h>
#include "sets.h"

static int put(char *dst, size_t size, const char *src, size_t len)
{
	if (len >= size)
		return -1;
	memcpy(dst, src, len);
	dst[len] = '\0';
	return 0;
}

static int add_pkg(struct set *s, const char *p, size_t len)
{
	char **np = realloc(s->pkgs, (s->npkgs + 1) * sizeof *np);
	char *copy;

	if (np == NULL)
		return -1;
	s->pkgs = np;
	copy = malloc(len + 1);
	if (copy == NULL)
		return -1;
	memcpy(copy, p, len);
	copy[len] = '\0';
	s->pkgs[s->npkgs++] = copy;
	return 0;
}

/* Is the line's first word kw?  If so, *rest is the text after it. */
static int keyword(const char *l, size_t len, const char *kw,
		   const char **rest, size_t *rlen)
{
	size_t k = strlen(kw);

	if (len < k || memcmp(l, kw, k) != 0)
		return 0;
	if (len > k && l[k] != ' ' && l[k] != '\t')
		return 0;
	l += k;
	len -= k;
	while (len > 0 && (*l == ' ' || *l == '\t')) {
		l++;
		len--;
	}
	*rest = l;
	*rlen = len;
	return 1;
}

int set_parse(const char *name, const char *text, struct set *s)
{
	int in_pkgs = 0;

	memset(s, 0, sizeof *s);
	if (put(s->name, sizeof s->name, name, strlen(name)) < 0)
		return -1;
	while (*text) {
		const char *nl = strchr(text, '\n');
		size_t len = nl ? (size_t)(nl - text) : strlen(text);
		const char *line = text, *rest;
		size_t rlen;

		text += len + (nl ? 1 : 0);
		while (len > 0 && (line[len - 1] == '\r' ||
				   line[len - 1] == ' ' || line[len - 1] == '\t'))
			len--;
		while (len > 0 && (*line == ' ' || *line == '\t')) {
			line++;
			len--;
		}
		if (len == 0 || *line == '#')
			continue;
		if (!in_pkgs && keyword(line, len, "title", &rest, &rlen)) {
			if (put(s->title, sizeof s->title, rest, rlen) < 0)
				goto bad;
		} else if (!in_pkgs &&
			   keyword(line, len, "description", &rest, &rlen)) {
			if (put(s->desc, sizeof s->desc, rest, rlen) < 0)
				goto bad;
		} else if (!in_pkgs &&
			   keyword(line, len, "required", &rest, &rlen)) {
			if (rlen == 3 && memcmp(rest, "yes", 3) == 0)
				s->required = 1;
			else if (rlen == 2 && memcmp(rest, "no", 2) == 0)
				s->required = 0;
			else
				goto bad;
		} else {
			in_pkgs = 1;
			if (add_pkg(s, line, len) < 0)
				goto bad;
		}
	}
	return 0;
bad:
	set_free(s);
	return -1;
}

void set_free(struct set *s)
{
	int i;

	for (i = 0; i < s->npkgs; i++)
		free(s->pkgs[i]);
	free(s->pkgs);
	s->pkgs = NULL;
	s->npkgs = 0;
}

static int has(char **list, int n, const char *p)
{
	int i;

	for (i = 0; i < n; i++)
		if (strcmp(list[i], p) == 0)
			return 1;
	return 0;
}

int set_union(const struct set *sets, const int *chosen, int n, char ***out)
{
	char **list = NULL;
	int count = 0, i, j, k;

	/* Two passes: "files" first, then every other package in order. */
	for (k = 0; k < 2; k++) {
		for (i = 0; i < n; i++) {
			const struct set *s = &sets[chosen[i]];

			for (j = 0; j < s->npkgs; j++) {
				const char *p = s->pkgs[j];
				char **nl;
				char *copy;

				if ((strcmp(p, "files") == 0) != (k == 0))
					continue;
				if (has(list, count, p))
					continue;
				nl = realloc(list, (count + 1) * sizeof *nl);
				if (nl == NULL)
					goto oom;
				list = nl;
				copy = malloc(strlen(p) + 1);
				if (copy == NULL)
					goto oom;
				memcpy(copy, p, strlen(p) + 1);
				list[count++] = copy;
			}
		}
	}
	*out = list;
	return count;
oom:
	for (i = 0; i < count; i++)
		free(list[i]);
	free(list);
	return -1;
}
