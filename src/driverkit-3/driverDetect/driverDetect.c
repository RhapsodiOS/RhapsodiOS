/*
 * driverDetect - list, load and record the drivers for the machine's PCI
 * devices.  See driverDetect.8.
 *
 *	driverDetect			list every match
 *	driverDetect -l family...	load and probe the matched drivers
 *	driverDetect -w root driver...	write root's Instance tables
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <driverkit/driverServer.h>
#include "kl_com.h"
#include "match.h"

#define DEVICE_DIR	"/usr/Devices"
#define ROOT_DEVICE_DIR	"/private/Drivers/i386"
#define TEMPLATE	"/System/Installation/CDIS/templates/Instance0-i386.table"
#define BASE_BOOT	"EISABus PCIBus PS2Keyboard"
#define MAX_DEVS	256
#define MAX_TABLES	512
#define MAX_MATCHES	64
#define MAX_LIST	1024

static struct pcidev devs[MAX_DEVS];
static int ndevs;
static char *tables[MAX_TABLES], *names[MAX_TABLES];
static int ntables;
static struct match matches[MAX_MATCHES];

static int
fail(const char *fmt, const char *arg)
{
	fprintf(stderr, "driverDetect: ");
	fprintf(stderr, fmt, arg);
	fputc('\n', stderr);
	return 1;
}

/* The whole file, NUL-terminated and malloc'd; NULL if it can't be read. */
static char *
slurp(const char *path)
{
	FILE *f = fopen(path, "r");
	char *buf = NULL;
	long n;

	if (f == NULL)
		return NULL;
	if (fseek(f, 0L, SEEK_END) == 0 && (n = ftell(f)) >= 0 &&
	    fseek(f, 0L, SEEK_SET) == 0 && (buf = malloc(n + 1)) != NULL) {
		if (fread(buf, 1, n, f) != (size_t)n) {
			free(buf);
			buf = NULL;
		} else
			buf[n] = '\0';
	}
	fclose(f);
	return buf;
}

static int
spew(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	if (f == NULL)
		return fail("can't create %s", path);
	fputs(text, f);
	if (fclose(f) != 0)
		return fail("can't write %s", path);
	return 0;
}

/*
 * PCI through the PCIBus resource driver.  Our drvPCIBus answers the doubled
 * parenthesis and DR2's the names without the underscore, so use the first
 * spelling that answers.
 */
static const char *const pciNames[][2] = {
	{ "PCI_Maximums(", "PCI_ConfigReg(Dev:%d Func:%d Bus:%d Reg:%d)" },
	{ "PCI_Maximums((", "PCI_ConfigReg((Dev:%d Func:%d Bus:%d Reg:%d)" },
	{ "PCIMaximums(", "PCIConfigReg(Dev:%d Func:%d Bus:%d Reg:%d)" },
};

static IOObjectNumber pciObj;
static const char *pciRegFormat;

static int
pciReg(int dev, int func, int bus, int reg, unsigned long *val)
{
	IOParameterName param;
	unsigned char v[16];
	unsigned int cnt = sizeof v;

	sprintf(param, pciRegFormat, dev, func, bus, reg);
	if (_IOGetCharValues(device_master_self(), pciObj, param, cnt, v,
	    &cnt) != IO_R_SUCCESS || cnt < 4)
		return -1;
	*val = v[0] | (v[1] << 8) | ((unsigned long)v[2] << 16) |
	    ((unsigned long)v[3] << 24);
	return 0;
}

/* Fill devs with every function present; 0, or 1 if there's no PCI bus. */
static int
scan(void)
{
	IOString kind;
	unsigned char maxima[16];
	unsigned int cnt;
	unsigned long pid, hdr;
	int i, dev, func, bus, nfunc;

	if (_IOLookupByDeviceName(device_master_self(), "PCI0", &pciObj,
	    &kind) != IO_R_SUCCESS)
		return fail("no PCI bus%s", "");
	for (i = 0; i < 3; i++) {
		cnt = sizeof maxima;
		if (_IOGetCharValues(device_master_self(), pciObj,
		    (char *)pciNames[i][0], cnt, maxima, &cnt) ==
		    IO_R_SUCCESS && cnt >= 2)
			break;
	}
	if (i == 3)
		return fail("the PCI bus doesn't answer%s", "");
	pciRegFormat = pciNames[i][1];
	for (bus = 0; bus <= maxima[1]; bus++)
	    for (dev = 0; dev <= maxima[0]; dev++)
		for (func = 0, nfunc = 1; func < nfunc; func++) {
			if (pciReg(dev, func, bus, 0x00, &pid) ||
			    (pid & 0xffff) == 0xffff || (pid & 0xffff) == 0)
				continue;
			/* Header type bit 7: a multi-function device. */
			if (func == 0 && pciReg(dev, 0, bus, 0x0c, &hdr) == 0 &&
			    (hdr & 0x00800000))
				nfunc = 8;
			if (ndevs == MAX_DEVS)
				return 0;
			devs[ndevs].dev = dev;
			devs[ndevs].func = func;
			devs[ndevs].bus = bus;
			devs[ndevs].pid = pid;
			if (pciReg(dev, func, bus, 0x2c, &devs[ndevs].sid))
				devs[ndevs].sid = 0;
			ndevs++;
		}
	return 0;
}

/* Read every /usr/Devices/<name>.config/Default.table. */
static void
readTables(void)
{
	DIR *d = opendir(DEVICE_DIR);
	struct dirent *e;
	char path[1024];
	int len;

	if (d == NULL)
		return;
	while (ntables < MAX_TABLES && (e = readdir(d)) != NULL) {
		len = strlen(e->d_name);
		if (len <= 7 || strcmp(e->d_name + len - 7, ".config") != 0 ||
		    len + sizeof DEVICE_DIR + 16 > sizeof path)
			continue;
		sprintf(path, "%s/%s/Default.table", DEVICE_DIR, e->d_name);
		if ((tables[ntables] = slurp(path)) == NULL)
			continue;
		names[ntables] = malloc(len - 6);
		strncpy(names[ntables], e->d_name, len - 7);
		names[ntables][len - 7] = '\0';
		ntables++;
	}
	closedir(d);
}

static const char *
tableFor(const char *driver)
{
	int i;

	for (i = 0; i < ntables; i++)
		if (strcmp(names[i], driver) == 0)
			return tables[i];
	return "";
}

static void
serverName(const char *driver, char *server, int len)
{
	if (table_value(tableFor(driver), "Server Name", server, len) <= 0) {
		strncpy(server, driver, len - 1);
		server[len - 1] = '\0';
	}
}

static void
printMatch(const struct match *m)
{
	printf("%s\t%s\tDev:%u Func:%u Bus:%u\t0x%08lx\n", m->family,
	    m->driver, m->d.dev, m->d.func, m->d.bus, m->d.pid);
}

/* Load m's driver (kl_com skips a loaded one), then probe m's location. */
static int
probe(const struct match *m)
{
	static IOConfigData data;
	char path[1024], server[64], *t;
	IOReturn r;

	serverName(m->driver, server, sizeof server);
	sprintf(path, "%s/%s.config/%s_reloc", DEVICE_DIR, m->driver,
	    m->driver);
	if (kl_com_add(path, server))
		return fail("can't add %s", path);
	if (kl_com_load(server))
		return fail("can't load %s", server);
	if (write_location(tableFor(m->driver), &m->d, &t))
		return fail("out of memory%s", "");
	if (strlen(t) >= sizeof data) {
		free(t);
		return fail("%s's table is too large", m->driver);
	}
	strcpy((char *)data, t);
	r = _IOProbeDriver(device_master_self(), data, strlen(t));
	free(t);
	if (r != IO_R_SUCCESS)
		return fail("%s found no device", m->driver);
	printMatch(m);
	return 0;
}

static int
loadFamilies(char **families, int nfamilies, int n)
{
	static int wasLoaded[MAX_MATCHES];
	char server[64];
	int i, k, rtn = 0;

	/* Leave alone the drivers loaded before we started. */
	for (k = 0; k < n; k++) {
		serverName(matches[k].driver, server, sizeof server);
		wasLoaded[k] = kl_com_get_state(server) == KSS_LOADED;
	}
	for (k = 0; k < n; k++)
		for (i = 0; i < nfamilies; i++)
			if (strcasecmp(families[i], matches[k].family) == 0) {
				if (!wasLoaded[k])
					rtn |= probe(&matches[k]);
				break;
			}
	return rtn;
}

/* Append word to the space-separated list; -1 if it doesn't fit. */
static int
append(char *list, const char *word)
{
	if (strlen(list) + strlen(word) + 2 > MAX_LIST)
		return -1;
	if (*list)
		strcat(list, " ");
	strcat(list, word);
	return 0;
}

/* s with every "@DISK@" replaced by disk, malloc'd. */
static char *
replaceDisk(const char *s, const char *disk)
{
	const char *p, *q;
	char *r;
	int n = 0;

	for (p = s; (p = strstr(p, "@DISK@")) != NULL; p += 6)
		n++;
	if ((r = malloc(strlen(s) + n * strlen(disk) + 1)) == NULL)
		return NULL;
	*r = '\0';
	for (p = s; (q = strstr(p, "@DISK@")) != NULL; p = q + 6) {
		strncat(r, p, q - p);
		strcat(r, disk);
	}
	strcat(r, p);
	return r;
}

/* The disk of root's fstab "/" line: /dev/hd0a gives hd0.  0, or -1. */
static int
rootDisk(const char *root, char *disk)
{
	char path[1024], spec[64], dir[64], *text, *line;
	int len;

	sprintf(path, "%s/private/etc/fstab", root);
	if ((text = slurp(path)) == NULL)
		return -1;
	for (line = strtok(text, "\n"); line; line = strtok(NULL, "\n")) {
		if (sscanf(line, "%63s %63s", spec, dir) != 2 ||
		    strcmp(dir, "/") != 0 || strncmp(spec, "/dev/", 5) != 0)
			continue;
		len = strlen(spec + 5) - 1;	/* drop the partition letter */
		if (len < 1)
			continue;
		strncpy(disk, spec + 5, len);
		disk[len] = '\0';
		free(text);
		return 0;
	}
	free(text);
	return -1;
}

static int
isBootFamily(const char *family)
{
	return strcasecmp(family, "Disk") == 0 ||
	    strcasecmp(family, "SCSI") == 0;
}

/* A template Active Driver whose family a chosen driver replaces. */
static int
replaced(const char *root, const char *driver, char **chosen,
    char families[][32], int nchosen)
{
	char path[1024], family[32], *t;
	int i;

	for (i = 0; i < nchosen; i++)
		if (strcmp(chosen[i], driver) == 0)
			return 1;
	if (strlen(root) + strlen(driver) + 64 > sizeof path)
		return 0;
	sprintf(path, "%s%s/%s.config/Default.table", root, ROOT_DEVICE_DIR,
	    driver);
	if ((t = slurp(path)) == NULL)
		return 0;
	i = table_value(t, "Family", family, sizeof family);
	free(t);
	if (i < 0 || (strcasecmp(family, "Network") != 0 &&
	    strcasecmp(family, "Display") != 0 &&
	    strcasecmp(family, "Audio") != 0))
		return 0;
	for (i = 0; i < nchosen; i++)
		if (strcasecmp(families[i], family) == 0)
			return 1;
	return 0;
}

static int
writeRoot(const char *root, char **chosen, int nchosen)
{
	static char families[MAX_TABLES][32];
	char path[1024], disk[64], num[16], boot[MAX_LIST], active[MAX_LIST];
	char old[MAX_LIST], *sys, *t, *t2, *word;
	int i, k, n;

	if (nchosen > MAX_TABLES || strlen(root) + 128 > sizeof path)
		return fail("too many drivers or too long a root%s", "");
	for (i = 0; i < nchosen; i++) {
		if (strlen(chosen[i]) > 64)
			return fail("bad driver name %s", chosen[i]);
		sprintf(path, "%s%s/%s.config/Default.table", root,
		    ROOT_DEVICE_DIR, chosen[i]);
		if ((tables[i] = slurp(path)) == NULL)
			return fail("can't read %s", path);
		if (table_value(tables[i], "Family", families[i], 32) < 0)
			families[i][0] = '\0';
	}
	if (scan())
		return 1;

	/* Each chosen PCI driver's Instance<N>.table. */
	n = match_all((const char **)tables, (const char **)chosen, nchosen,
	    devs, ndevs, matches, MAX_MATCHES);
	for (k = 0; k < n; k++) {
		for (i = 0; strcmp(chosen[i], matches[k].driver) != 0; i++)
			;
		sprintf(num, "%d", matches[k].instance);
		if (write_location(tables[i], &matches[k].d, &t))
			return fail("out of memory%s", "");
		if (table_set(t, "Instance", num, &t2))
			return fail("out of memory%s", "");
		free(t);
		sprintf(path, "%s%s/%s.config/Instance%d.table", root,
		    ROOT_DEVICE_DIR, chosen[i], matches[k].instance);
		if (spew(path, t2))
			return 1;
		free(t2);
	}

	/* The system table, from CDIS's template. */
	sprintf(path, "%s%s", root, TEMPLATE);
	if ((sys = slurp(path)) == NULL && (sys = slurp(TEMPLATE)) == NULL)
		return fail("can't read %s", TEMPLATE);
	if (strstr(sys, "@DISK@")) {
		if (rootDisk(root, disk))
			return fail("no / line in %s/private/etc/fstab", root);
		if ((t = replaceDisk(sys, disk)) == NULL)
			return fail("out of memory%s", "");
		free(sys);
		sys = t;
	}
	strcpy(boot, BASE_BOOT);
	active[0] = '\0';
	for (i = 0; i < nchosen; i++)
		if (append(isBootFamily(families[i]) ? boot : active,
		    chosen[i]))
			return fail("too many drivers%s", "");
	if (table_value(sys, "Active Drivers", old, sizeof old) < 0)
		old[0] = '\0';
	for (word = strtok(old, " "); word; word = strtok(NULL, " "))
		if (!replaced(root, word, chosen, families, nchosen) &&
		    append(active, word))
			return fail("too many drivers%s", "");
	if (table_set(sys, "Boot Drivers", boot, &t) ||
	    table_set(t, "Active Drivers", active, &t2))
		return fail("out of memory%s", "");
	sprintf(path, "%s%s/System.config/Instance0.table", root,
	    ROOT_DEVICE_DIR);
	return spew(path, t2);
}

static int
usage(void)
{
	fprintf(stderr, "usage: driverDetect\n"
	    "       driverDetect -l family ...\n"
	    "       driverDetect -w root [driver ...]\n");
	return 1;
}

int
main(int argc, char **argv)
{
	int k, n;

	if (argc >= 3 && strcmp(argv[1], "-w") == 0)
		return writeRoot(argv[2], argv + 3, argc - 3);
	if (argc != 1 && (argc < 3 || strcmp(argv[1], "-l") != 0))
		return usage();
	if (scan())
		return 1;
	readTables();
	n = match_all((const char **)tables, (const char **)names, ntables,
	    devs, ndevs, matches, MAX_MATCHES);
	if (argc > 1)
		return loadFamilies(argv + 2, argc - 2, n);
	for (k = 0; k < n; k++)
		printMatch(&matches[k]);
	return 0;
}
