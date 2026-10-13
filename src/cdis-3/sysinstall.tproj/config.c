/* config.c -- see config.h. */

#include <stdlib.h>
#include <string.h>
#include "config.h"

char *render(const char *tmpl, const char *disk)
{
	static const char tag[] = "@DISK@";
	size_t taglen = sizeof tag - 1, dlen = strlen(disk);
	size_t n = 0;
	const char *p;
	char *out, *o;

	for (p = tmpl; (p = strstr(p, tag)) != NULL; p += taglen)
		n++;
	out = malloc(strlen(tmpl) + n * dlen + 1);
	if (out == NULL)
		return NULL;
	o = out;
	for (;;) {
		p = strstr(tmpl, tag);
		if (p == NULL)
			break;
		memcpy(o, tmpl, p - tmpl);
		o += p - tmpl;
		memcpy(o, disk, dlen);
		o += dlen;
		tmpl = p + taglen;
	}
	memcpy(o, tmpl, strlen(tmpl) + 1);
	return out;
}

char *passwd_set_root(const char *passwd, const char *hash)
{
	const char *l = passwd;
	size_t hlen = strlen(hash);

	while (*l) {
		const char *nl = strchr(l, '\n');

		if (strncmp(l, "root:", 5) == 0) {
			const char *f = l + 5;
			const char *end = strchr(f, ':');
			size_t head = f - passwd, tail;
			char *out;

			if (end == NULL || (nl != NULL && end > nl))
				end = nl ? nl : f + strlen(f);
			tail = strlen(end);
			out = malloc(head + hlen + tail + 1);
			if (out == NULL)
				return NULL;
			memcpy(out, passwd, head);
			memcpy(out + head, hash, hlen);
			memcpy(out + head + hlen, end, tail + 1);
			return out;
		}
		if (nl == NULL)
			break;
		l = nl + 1;
	}
	return NULL;
}

void make_salt(unsigned seed, char out[3])
{
	static const char alpha[] =
	    "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

	seed = seed * 2654435761u;
	seed ^= seed >> 15;
	out[0] = alpha[seed & 63];
	out[1] = alpha[(seed >> 6) & 63];
	out[2] = '\0';
}
