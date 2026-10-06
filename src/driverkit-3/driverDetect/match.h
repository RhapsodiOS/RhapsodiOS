/*
 * match.h - PCI ID matching for driverDetect.
 *
 * Host-testable: libc only.  ids_match reproduces boot-2's testIDs
 * (src/boot-2/i386/libsaio/drivers.c).
 */
#ifndef DRIVERDETECT_MATCH_H
#define DRIVERDETECT_MATCH_H

struct pcidev {
	unsigned dev, func, bus;
	unsigned long pid, sid;		/* pid = config reg 0x00, sid = reg 0x2c */
};

struct match {
	char driver[64], family[32];
	struct pcidev d;
	int instance;
};

/* Nonzero if (pid, sid) satisfies an "Auto Detect IDs" string. */
int ids_match(const char *autoDetectIDs, unsigned long pid, unsigned long sid);

/*
 * Copy the value of `"key" = "value";` into out (NUL-terminated).  Returns
 * the value length, or -1 if the key is absent or the value does not fit.
 */
int table_value(const char *table, const char *key, char *out, int outlen);

/*
 * Match devs against PCI driver tables (names[i] is table i's driver name).
 * Instances count per driver from 0.  Returns the number of matches stored
 * in out (at most max).
 */
int match_all(const char **tables, const char **names, int ntables,
    const struct pcidev *devs, int ndevs, struct match *out, int max);

/*
 * Set key's value to value, replacing the old value or appending the key.
 * *out is a malloc'd copy; returns 0, or -1 on failure.
 */
int table_set(const char *table, const char *key, const char *value,
    char **out);

/*
 * Set the "Location" key to "Dev:%d Func:%d Bus:%d", replacing the old value
 * or appending the key.  *out is a malloc'd copy; returns 0, or -1 on failure.
 */
int write_location(const char *table, const struct pcidev *d, char **out);

#endif
