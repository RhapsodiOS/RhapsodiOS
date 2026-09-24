/* Pure helpers for choosing the Rhapsody disk: no EFI calls, so
 * tests/efi_disk_select_test.c exercises them on byte buffers. */
#ifndef _BOOTEFI_EFI_DISK_SELECT_H_
#define _BOOTEFI_EFI_DISK_SELECT_H_

/* LBA of the first NeXT label copy on a disk whose sector 0 is `mbr`:
 * 15 sectors into the first 0xA7 fdisk partition, or LBA 15 when sector 0
 * has no 0xA7 entry (a whole-disk label, like golden.img).  Mirrors the
 * walk read_label() does in src/boot-2/i386/libsaio/disk.c. */
unsigned long efi_label_lba(const unsigned char *mbr);

/* Non-zero if `disk`, a whole-disk device path, is the parent of `part`:
 * every node of `disk` before its end node is a byte-for-byte prefix of
 * `part`, and the next node of `part` is Media/HardDrive (type 4,
 * subtype 1), i.e. an fdisk partition.  Both paths end-terminated. */
int efi_dp_is_parent(const unsigned char *disk, const unsigned char *part);

#endif /* _BOOTEFI_EFI_DISK_SELECT_H_ */
