/* layout.h -- sysinstall's disk geometry, partition layout and MBR code.
 * Pure logic: no curses, no I/O. */

#ifndef LAYOUT_H
#define LAYOUT_H

#define ESP_LBA      2048u
#define ESP_SECTORS  131072u
#define A7_LBA       133120u

struct part { unsigned char type, active; unsigned long start, count; };
struct table { struct part p[4]; };

/* LBA-assisted geometry; must equal vm/build_uefi_image.py. */
void lba_geometry(unsigned long total, unsigned *heads, unsigned *spt);
void lba_to_chs(unsigned long lba, unsigned heads, unsigned spt,
		unsigned char out[3]);

/* Replace *t with the ESP + 0xA7 layout.  0, or -1 if the disk is < 1 GB. */
int layout_auto(unsigned long total, struct table *t);

/* NULL if the table is an acceptable install target, else the reason. */
const char *layout_check(unsigned long total, const struct table *t);

void mbr_encode(const unsigned char boot0[446], unsigned long total,
		const struct table *t, unsigned char out[512]);
int mbr_decode(const unsigned char in[512], struct table *t); /* -1: no 0x55AA */

#endif
