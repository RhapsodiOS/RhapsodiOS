#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "match.h"

int ids_match(const char *autoDetectIDs, unsigned long pid, unsigned long sid)
{
	char *optr = NULL, *ptr = (char *)autoDetectIDs;
	unsigned long ptest, pmask, stest, smask;

	ptest = pmask = stest = smask = 0;
	if (((pid & 0xffff) == 0xffff) || ((pid & 0xffff) == 0))
		return 0;
	while (*ptr) {
		if (optr == ptr)
			return 0;	/* no progress: avoid an endless loop */
		optr = ptr;
		if (*ptr == ' ' || *ptr == '\t') {
			ptr++;
			ptest = pmask = 0;
			continue;
		}
		if (*ptr != ':') {
			ptest = strtoul(ptr, &ptr, 0);
			if (*ptr == '&') {
				ptr++;
				pmask = strtoul(ptr, &ptr, 0);
			} else
				pmask = 0xffffffff;
		}
		if (*ptr == ':') {
			ptr++;
			stest = strtoul(ptr, &ptr, 0);
			if (*ptr == '&') {
				ptr++;
				smask = strtoul(ptr, &ptr, 0);
			} else
				smask = 0xffffffff;
		} else
			stest = smask = 0;

		if (((pid & pmask) == (ptest & pmask)) &&
		    ((sid & smask) == (stest & smask)))
			return 1;
	}
	return 0;
}

/* Skip whitespace and C comments. */
static const char *skip_ws(const char *p)
{
	for (;;) {
		while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
			p++;
		if (p[0] == '/' && p[1] == '*') {
			p += 2;
			while (*p && !(p[0] == '*' && p[1] == '/'))
				p++;
			if (*p)
				p += 2;
			continue;
		}
		return p;
	}
}

/* p is at an opening quote; returns the closing quote (or the NUL). */
static const char *string_end(const char *p)
{
	for (p++; *p && *p != '"'; p++)
		if (*p == '\\' && p[1])
			p++;
	return p;
}

/*
 * Find key's value in the table; sets *vs and *ve to the span between the
 * value's quotes.  Entries without a value ("Boot Driver";) are skipped.
 */
static int find_value(const char *table, const char *key,
    const char **vs, const char **ve)
{
	size_t klen = strlen(key);
	const char *p = table, *ks, *ke;
	int hit;

	for (;;) {
		p = skip_ws(p);
		if (*p != '"')
			return 0;	/* end of table, or malformed */
		ks = p + 1;
		ke = string_end(p);
		if (*ke == '\0')
			return 0;
		hit = (size_t)(ke - ks) == klen && strncmp(ks, key, klen) == 0;
		p = skip_ws(ke + 1);
		if (*p == '=') {
			p = skip_ws(p + 1);
			if (*p != '"')
				return 0;
			if (hit) {
				*vs = p + 1;
				*ve = string_end(p);
				return **ve == '"';
			}
			p = string_end(p);
			if (*p == '\0')
				return 0;
			p = skip_ws(p + 1);
		}
		if (*p != ';')
			return 0;
		p++;
	}
}

int table_value(const char *table, const char *key, char *out, int outlen)
{
	const char *vs, *ve;
	int n;

	if (!find_value(table, key, &vs, &ve))
		return -1;
	n = (int)(ve - vs);
	if (n >= outlen)
		return -1;
	memcpy(out, vs, (size_t)n);
	out[n] = '\0';
	return n;
}

int match_all(const char **tables, const char **names, int ntables,
    const struct pcidev *devs, int ndevs, struct match *out, int max)
{
	char bus[16], family[32], ids[1024];
	int t, i, n = 0, inst;

	for (t = 0; t < ntables; t++) {
		if (table_value(tables[t], "Bus Type", bus, sizeof bus) < 0 ||
		    strcmp(bus, "PCI") != 0)
			continue;
		if (table_value(tables[t], "Auto Detect IDs", ids,
		    sizeof ids) < 0)
			continue;
		if (table_value(tables[t], "Family", family, sizeof family) < 0)
			family[0] = '\0';
		inst = 0;
		for (i = 0; i < ndevs && n < max; i++) {
			if (!ids_match(ids, devs[i].pid, devs[i].sid))
				continue;
			strncpy(out[n].driver, names[t],
			    sizeof out[n].driver - 1);
			out[n].driver[sizeof out[n].driver - 1] = '\0';
			strcpy(out[n].family, family);
			out[n].d = devs[i];
			out[n].instance = inst++;
			n++;
		}
	}
	return n;
}

int write_location(const char *table, const struct pcidev *d, char **out)
{
	char line[64], *r;
	const char *vs, *ve;
	size_t tlen = strlen(table), llen;

	sprintf(line, "Dev:%u Func:%u Bus:%u", d->dev, d->func, d->bus);
	llen = strlen(line);
	if (find_value(table, "Location", &vs, &ve)) {
		r = malloc(tlen - (size_t)(ve - vs) + llen + 1);
		if (r == NULL)
			return -1;
		memcpy(r, table, (size_t)(vs - table));
		memcpy(r + (vs - table), line, llen);
		strcpy(r + (vs - table) + llen, ve);
	} else {
		r = malloc(tlen + llen + 32);
		if (r == NULL)
			return -1;
		strcpy(r, table);
		if (tlen > 0 && r[tlen - 1] != '\n')
			strcat(r, "\n");
		strcat(r, "\"Location\" = \"");
		strcat(r, line);
		strcat(r, "\";\n");
	}
	*out = r;
	return 0;
}
