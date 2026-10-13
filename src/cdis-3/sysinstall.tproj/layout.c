/* layout.c -- sysinstall's disk geometry, partition layout and MBR code. */

#include <string.h>
#include "layout.h"

#define MIN_SECTORS 2097152ul	/* 1 GB */

void lba_geometry(unsigned long total, unsigned *heads, unsigned *spt)
{
	unsigned long cyls;

	*spt = 63;
	if (total > 63ul * 255 * 1024) {
		*heads = 255;
		return;
	}
	cyls = (total / 63) / 1024;
	if (cyls > 128)
		*heads = 255;
	else if (cyls > 64)
		*heads = 128;
	else if (cyls > 32)
		*heads = 64;
	else if (cyls > 16)
		*heads = 32;
	else
		*heads = 16;
}

void lba_to_chs(unsigned long lba, unsigned heads, unsigned spt,
		unsigned char out[3])
{
	unsigned long cyl = lba / ((unsigned long)heads * spt);

	if (cyl > 1023) {
		out[0] = 0xfe; out[1] = 0xff; out[2] = 0xff;
		return;
	}
	out[0] = (unsigned char)((lba / spt) % heads);
	out[1] = (unsigned char)(((cyl >> 2) & 0xC0) | (lba % spt + 1));
	out[2] = (unsigned char)(cyl & 0xFF);
}

int layout_auto(unsigned long total, struct table *t)
{
	unsigned heads, spt;
	unsigned long cyl;

	if (total < MIN_SECTORS)
		return -1;
	lba_geometry(total, &heads, &spt);
	cyl = (unsigned long)heads * spt;
	memset(t, 0, sizeof *t);
	t->p[0].type = 0xEF;
	t->p[0].start = ESP_LBA;
	t->p[0].count = ESP_SECTORS;
	t->p[1].type = 0xA7;
	t->p[1].active = 1;
	t->p[1].start = A7_LBA;
	t->p[1].count = (total / cyl) * cyl - A7_LBA;
	return 0;
}

const char *layout_check(unsigned long total, const struct table *t)
{
	unsigned heads, spt;
	unsigned long cyl;
	int i, j, n_a7 = 0, a7 = -1, n_esp = 0, esp = -1;

	lba_geometry(total, &heads, &spt);
	cyl = (unsigned long)heads * spt;
	for (i = 0; i < 4; i++) {
		if (t->p[i].type == 0)
			continue;
		if (t->p[i].count == 0)
			return "A partition is empty.";
		if (t->p[i].count > total ||
		    t->p[i].start > total - t->p[i].count)
			return "A partition extends past the end of the disk.";
		if (t->p[i].type == 0xA7) {
			n_a7++;
			a7 = i;
		}
		if (t->p[i].type == 0xEF) {
			n_esp++;
			esp = i;
		}
		for (j = 0; j < i; j++) {
			if (t->p[j].type == 0)
				continue;
			if (t->p[i].start < t->p[j].start + t->p[j].count &&
			    t->p[j].start < t->p[i].start + t->p[i].count)
				return "Partitions overlap.";
		}
	}
	if (n_a7 != 1)
		return "There must be exactly one RhapsodiOS (0xA7) partition.";
	if (!t->p[a7].active)
		return "The RhapsodiOS partition must be active.";
	if ((t->p[a7].start + t->p[a7].count) % cyl != 0)
		return "The RhapsodiOS partition must end on a cylinder boundary.";
	if (n_esp != 1 || t->p[esp].count != ESP_SECTORS)
		return "The EFI system partition must be exactly 64 MB.";
	if (t->p[esp].start != ESP_LBA)
		return "The EFI system partition must start at LBA 2048.";
	return NULL;
}

int layout_free(unsigned long total, const struct table *t,
		unsigned long start[5], unsigned long count[5])
{
	unsigned long pos = 2048, s, e, best, ps[4], pe[4];
	int n = 0, i, done[4], next;

	for (i = 0; i < 4; i++) {
		done[i] = t->p[i].type == 0 && t->p[i].count == 0;
		/* clamped to the disk: no wraparound past 2^32 */
		ps[i] = t->p[i].start < total ? t->p[i].start : total;
		pe[i] = t->p[i].count > total - ps[i] ? total :
		    ps[i] + t->p[i].count;
	}
	for (;;) {
		next = -1;
		best = 0;
		for (i = 0; i < 4; i++)
			if (!done[i] && (next < 0 || ps[i] < best)) {
				next = i;
				best = ps[i];
			}
		e = next < 0 ? total : best;
		s = pos + (2048 - pos % 2048) % 2048;
		if (s < pos)		/* aligning wrapped */
			s = total;
		if (e > s && n < 5) {
			start[n] = s;
			count[n] = e - s;
			n++;
		}
		if (next < 0)
			return n;
		done[next] = 1;
		if (pe[next] > pos)
			pos = pe[next];
	}
}

static void put32(unsigned char *p, unsigned long v)
{
	p[0] = (unsigned char)v;
	p[1] = (unsigned char)(v >> 8);
	p[2] = (unsigned char)(v >> 16);
	p[3] = (unsigned char)(v >> 24);
}

static unsigned long get32(const unsigned char *p)
{
	return (unsigned long)p[0] | ((unsigned long)p[1] << 8) |
	       ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24);
}

void mbr_encode(const unsigned char boot0[446], unsigned long total,
		const struct table *t, unsigned char out[512])
{
	unsigned heads, spt;
	unsigned char *e;
	int i;

	lba_geometry(total, &heads, &spt);
	memset(out, 0, 512);
	memcpy(out, boot0, 446);
	for (i = 0; i < 4; i++) {
		const struct part *p = &t->p[i];

		if (p->type == 0 && p->count == 0)
			continue;
		e = out + 446 + 16 * i;
		e[0] = p->active ? 0x80 : 0x00;
		lba_to_chs(p->start, heads, spt, e + 1);
		e[4] = p->type;
		lba_to_chs(p->start + p->count - 1, heads, spt, e + 5);
		put32(e + 8, p->start);
		put32(e + 12, p->count);
	}
	out[510] = 0x55;
	out[511] = 0xAA;
}

int mbr_decode(const unsigned char in[512], struct table *t)
{
	const unsigned char *e;
	int i;

	if (in[510] != 0x55 || in[511] != 0xAA)
		return -1;
	memset(t, 0, sizeof *t);
	for (i = 0; i < 4; i++) {
		e = in + 446 + 16 * i;
		t->p[i].active = e[0] == 0x80;
		t->p[i].type = e[4];
		t->p[i].start = get32(e + 8);
		t->p[i].count = get32(e + 12);
	}
	return 0;
}
