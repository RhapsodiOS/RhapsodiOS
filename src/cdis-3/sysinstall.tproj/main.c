/* main.c -- sysinstall, the RhapsodiOS installer: its screens, in order
 * Welcome, Disk, Partitioning, Drivers, Sets, Root password, Summary,
 * Progress and Done, and the error screen.  The write phase is steps.c's;
 * this file gathers the plan it runs and runs its commands. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include "ui.h"
#include "disks.h"
#include "layout.h"
#include "sets.h"
#include "config.h"
#include "steps.h"

#define T		"/private/var/tmp/mnta"
#define I		"/System/Installation"
#define SETS_DIR	I "/Sets"
#define VERSION_FILE	"/System/Library/CoreServices/software_version"
#define DEVICES		"/usr/Devices"
#define DRIVERDETECT	"/usr/sbin/driverDetect"
#define BOOT0		"/usr/standalone/i386/boot0"
/* steps.c's default command, with gzip's complaints kept off the screen */
#define ESP_CMD		"gzip -dc " I "/esp.img.gz 2>/dev/null"
#define PATH		"/bin:/sbin:/usr/bin:/usr/sbin:/usr/etc:/usr/libexec"

/* The console's terminal, for when TERM names nothing termcap knows. */
#define CONSOLE_TERM	"rhapcons"
#define CONSOLE_CAP	"rhapcons|RhapsodiOS console:am:bs:co#80:li#25:" \
			"cl=^L:cm=\\E[%i%d;%dH:ce=\\E[K:ho=\\E[H:up=\\E[A:nd=\\E[C:"

#define MIN_SECTORS	2097152ul	/* 1 GB */
#define NSTEPS		9
#define MAX_DISKS	12
#define MAX_DRIVERS	256
#define MAX_SETS	32

extern int tgetent();		/* libcurses' termcap */

/* ---- text ---- */

struct text { char s[4096]; int len; };

static void add(struct text *t, const char *s)
{
	int n = (int)strlen(s);

	if (n > (int)sizeof t->s - 1 - t->len)
		n = (int)sizeof t->s - 1 - t->len;
	memcpy(t->s + t->len, s, n);
	t->len += n;
	t->s[t->len] = '\0';
}

/* The last n lines of s. */
static const char *last_lines(const char *s, int n)
{
	const char *p = s + strlen(s);

	if (p > s && p[-1] == '\n')
		p--;
	while (p > s) {
		if (p[-1] == '\n' && --n == 0)
			break;
		p--;
	}
	return p;
}

/* The whole file, malloc'd and NUL-terminated; NULL if it can't be read. */
static char *slurp(const char *path)
{
	FILE *f = fopen(path, "r");
	char *buf = NULL, *nb;
	int used = 0, cap = 0, got;

	if (f == NULL)
		return NULL;
	for (;;) {
		if (cap - used < 1025) {
			cap = cap ? cap * 2 : 4096;
			if ((nb = realloc(buf, cap)) == NULL) {
				free(buf);
				fclose(f);
				return NULL;
			}
			buf = nb;
		}
		if ((got = (int)fread(buf + used, 1, cap - used - 1, f)) <= 0)
			break;
		used += got;
	}
	fclose(f);
	buf[used] = '\0';
	return buf;
}

static int menu(const char *title, const char **items, int n);

/* ---- running commands ---- */

static int cur_step;
static const char *cur_what = "";

/* Appends n bytes of b to out (cap bytes), dropping its oldest bytes. */
static void keep_tail(char *out, int *used, int cap, const char *b, int n)
{
	int drop;

	if (n > cap - 1) {
		b += n - (cap - 1);
		n = cap - 1;
	}
	if (*used + n > cap - 1) {
		drop = *used + n - (cap - 1);
		memmove(out, out + drop, *used - drop);
		*used -= drop;
	}
	memcpy(out + *used, b, n);
	*used += n;
	out[*used] = '\0';
}

/* Runs argv with its stdout and stderr in a pipe, and its stdin from
 * /dev/null.  out (cap bytes) keeps the end of what it wrote; with show,
 * the progress box shows it as it comes.  Returns the exit status. */
static int run_into(char *const argv[], char *out, int cap, int show)
{
	char buf[512];
	int fd[2], st, n, used = 0, nul;
	pid_t pid;

	out[0] = '\0';
	if (pipe(fd) < 0)
		return 127;
	if ((pid = fork()) < 0) {
		close(fd[0]);
		close(fd[1]);
		return 127;
	}
	if (pid == 0) {
		if ((nul = open("/dev/null", O_RDONLY)) >= 0) {
			dup2(nul, 0);
			close(nul);
		}
		dup2(fd[1], 1);
		dup2(fd[1], 2);
		close(fd[0]);
		close(fd[1]);
		execvp(argv[0], argv);
		fprintf(stderr, "can't run %s\n", argv[0]);
		_exit(127);
	}
	close(fd[1]);
	for (;;) {
		n = read(fd[0], buf, sizeof buf);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;
		keep_tail(out, &used, cap, buf, n);
		if (show)
			ui_progress(cur_step, NSTEPS, cur_what, out);
	}
	close(fd[0]);
	while (waitpid(pid, &st, 0) < 0)
		if (errno != EINTR)
			return 127;
	if (WIFEXITED(st))
		return WEXITSTATUS(st);
	return 128 + WTERMSIG(st);
}

static char step_out[8192];	/* the current command's output */

static int step_runner(const char *argv0, char *const argv[], void *ctx)
{
	(void)argv0;
	(void)ctx;
	return run_into(argv, step_out, sizeof step_out, 1);
}

static void step_progress(int step, const char *what)
{
	cur_step = step;
	cur_what = what;
	step_out[0] = '\0';
	ui_progress(step, NSTEPS, what, "");
}

/* ---- leaving ---- */

static void leave_to_shell(void)
{
	ui_stop();
	printf("Type \"exit\" to halt the machine.\n");
	exit(1);		/* rc.cdrom then starts a shell */
}

static void run_and_stop(const char *path)
{
	ui_stop();
	execl(path, path, (char *)0);
	fprintf(stderr, "sysinstall: can't run %s\n", path);
	exit(1);
}

/* The error screen: what failed, then start over, a shell or halt; or,
 * if again is 0, reboot, a shell or halt.  Returns only to start over. */
static void error_screen(const char *what, const char *detail, int again)
{
	static const char *items[] = { "Start over", "Quit to a shell",
				       "Halt" };
	static const char *stuck[] = { "Reboot", "Quit to a shell", "Halt" };
	struct text t;

	t.len = 0;
	t.s[0] = '\0';
	add(&t, "Installation failed\n\n");
	add(&t, what);
	if (detail != NULL && *detail != '\0') {
		add(&t, "\n\n");
		add(&t, detail);
	}
	switch (menu(t.s, again ? items : stuck, 3)) {
	case 0:
		if (again)
			return;
		run_and_stop("/sbin/reboot");
	case 1:
		leave_to_shell();
	default:
		run_and_stop("/sbin/halt");
	}
}

/* ui_menu, ui_checklist and ui_input end only if the console does. */
static int menu(const char *title, const char **items, int n)
{
	int k = ui_menu(title, items, n);

	if (k < 0)
		leave_to_shell();
	return k;
}

static void checklist(const char *title, const char **items, int *on,
		      int n, const int *locked)
{
	if (ui_checklist(title, items, on, n, locked) < 0)
		leave_to_shell();
}

static void input(const char *title, char *buf, int len, int hide)
{
	if (ui_input(title, buf, len, hide) < 0)
		leave_to_shell();
}

/* ---- driverDetect's output ---- */

/* Splits a line of driverDetect's "family\tdriver\tlocation\tids" in
 * place.  The number of fields. */
static int fields(char *line, char *f[4])
{
	int n = 0;

	f[n++] = line;
	while (n < 4 && (line = strchr(line, '\t')) != NULL) {
		*line++ = '\0';
		f[n++] = line;
	}
	return n;
}

/* ---- 1. Welcome ---- */

static char loaded[4096];	/* driverDetect -l's output */

static void release_line(char *out)
{
	char line[128], ver[128], build[128];
	FILE *f = fopen(VERSION_FILE, "r");
	int n = 0;

	ver[0] = build[0] = '\0';
	if (f != NULL) {
		while (fgets(line, sizeof line, f) != NULL) {
			line[strcspn(line, "\r\n")] = '\0';
			strcpy(n++ == 0 ? ver : build, line);
		}
		fclose(f);
	}
	if (ver[0] != '\0' && build[0] != '\0')
		sprintf(out, "%s (%s)", ver, build);
	else if (ver[0] != '\0')
		strcpy(out, ver);
	else
		strcpy(out, "RhapsodiOS");
}

static void welcome(void)
{
	static char *detect[] = { DRIVERDETECT, "-l", "Network", "SCSI", NULL };
	char rel[300], line[256], copy[sizeof loaded], *p, *e, *f[4];
	struct text t;
	int rc, any = 0;

	ui_progress(0, 0, "Looking for network and SCSI cards...", NULL);
	rc = run_into(detect, loaded, sizeof loaded, 0);
	release_line(rel);
	t.len = 0;
	t.s[0] = '\0';
	add(&t, "Release: ");
	add(&t, rel);
	add(&t, "\n\nThis program installs RhapsodiOS on a hard disk.  It asks "
	    "which disk, how to partition it, which drivers and sets to "
	    "install, and a password for root, and changes nothing until you "
	    "confirm the summary.\n\n");
	if (rc != 0) {
		add(&t, "Loading the network and SCSI drivers failed:\n");
		add(&t, last_lines(loaded, 4));
		loaded[0] = '\0';
	} else {
		strcpy(copy, loaded);
		for (p = copy; *p != '\0'; p = e) {
			e = p + strcspn(p, "\n");
			if (*e != '\0')
				*e++ = '\0';
			if (fields(p, f) < 3)
				continue;
			if (!any++)
				add(&t, "Drivers loaded for this machine's cards:\n");
			sprintf(line, "  %.60s (%.30s, %.60s)\n", f[1], f[0],
				f[2]);
			add(&t, line);
		}
		if (!any)
			add(&t, "No network or SCSI cards were found that need "
			    "a driver loaded.\n");
	}
	ui_message("Welcome to RhapsodiOS", t.s);
}

/* ---- 2. Disk ---- */

/* 0 with p->disk and p->total set, or -1 if there is no disk. */
static int choose_disk(struct plan *p)
{
	char names[MAX_DISKS][8], lines[MAX_DISKS][80], msg[200];
	unsigned long sizes[MAX_DISKS];
	const char *items[MAX_DISKS];
	int n, i, k;

	ui_progress(0, 0, "Looking for disks...", NULL);
	n = disks_list(names, sizes, MAX_DISKS);
	if (n == 0)
		return -1;
	for (i = 0; i < n; i++) {
		sprintf(lines[i], "%-4s %8lu MB%s", names[i], sizes[i] / 2048,
			sizes[i] < MIN_SECTORS ? "   too small" : "");
		items[i] = lines[i];
	}
	for (;;) {
		k = menu("Disk\n\nChoose the disk to install RhapsodiOS on.  "
			 "It must hold at least 1 GB.", items, n);
		if (sizes[k] >= MIN_SECTORS)
			break;
		sprintf(msg, "%s holds %lu MB.  RhapsodiOS needs a disk of at "
			"least 1 GB.", names[k], sizes[k] / 2048);
		ui_message("Disk", msg);
	}
	strcpy(p->disk, names[k]);
	p->total = sizes[k];
	return 0;
}

/* ---- 3. Partitioning ---- */

static int advanced;		/* the layout came from the editor */

static const char *type_name(unsigned char type, char *buf)
{
	if (type == 0xEF)
		return "EFI system";
	if (type == 0xA7)
		return "RhapsodiOS";
	if (type == 0)
		return "unused";
	sprintf(buf, "type 0x%02X", type);
	return buf;
}

/* One line for entry i. */
static void entry_line(const struct table *t, int i, char *out)
{
	const struct part *e = &t->p[i];
	char tb[16];

	if (e->type == 0 && e->count == 0)
		sprintf(out, "%d  unused", i + 1);
	else
		sprintf(out, "%d  %-10s  start %10lu  %7lu MB%s", i + 1,
			type_name(e->type, tb), e->start, e->count / 2048,
			e->active ? "  active" : "");
}

static void add_table(struct text *t, const struct table *tb)
{
	char line[100];
	int i;

	for (i = 0; i < 4; i++) {
		add(t, "  ");
		entry_line(tb, i, line);
		add(t, line);
		add(t, "\n");
	}
}

/* An entry chosen from the four, or -1 for Cancel. */
static int pick_entry(const struct table *t, const char *title)
{
	char lines[4][100];
	const char *items[5];
	int i, k;

	for (i = 0; i < 4; i++) {
		entry_line(t, i, lines[i]);
		items[i] = lines[i] + 3;	/* the item's key is its number */
	}
	items[4] = "Cancel";
	k = menu(title, items, 5);
	return k == 4 ? -1 : k;
}

static void create_entry(struct table *t, unsigned long total)
{
	static const char *types[] = { "EFI system partition (0xEF, 64 MB)",
				       "RhapsodiOS UFS (0xA7)",
				       "Another type, in hex", "Cancel" };
	unsigned long start[5], count[5], mb, n, end, cyl;
	char lines[6][80], buf[32], *e;
	const char *items[6];
	unsigned heads, spt;
	int slot, nr, i, k, type;

	for (slot = 0; slot < 4; slot++)
		if (t->p[slot].type == 0 && t->p[slot].count == 0)
			break;
	if (slot == 4) {
		ui_message("Create an entry", "All four entries are in use.  "
			   "Delete one first.");
		return;
	}
	nr = layout_free(total, t, start, count);
	if (nr == 0) {
		ui_message("Create an entry", "The disk has no free space.");
		return;
	}
	for (i = 0; i < nr; i++) {
		sprintf(lines[i], "start %10lu  %7lu MB free", start[i],
			count[i] / 2048);
		items[i] = lines[i];
	}
	items[nr] = "Cancel";
	k = menu("Create an entry\n\nChoose the free space for it.", items,
		 nr + 1);
	if (k == nr)
		return;
	switch (menu("Create an entry\n\nChoose its type.", types, 4)) {
	case 0:			/* step 2 writes it at ESP_LBA only */
		if (start[k] != ESP_LBA || count[k] < ESP_SECTORS) {
			ui_message("Create an entry", "The EFI system "
				   "partition starts at LBA 2048, and that "
				   "space doesn't hold 64 MB from there.");
			return;
		}
		t->p[slot].type = 0xEF;
		t->p[slot].active = 0;
		t->p[slot].start = ESP_LBA;
		t->p[slot].count = ESP_SECTORS;
		return;
	case 1:
		type = 0xA7;
		break;
	case 2:
		buf[0] = '\0';
		input("Create an entry\n\nType the partition type in hex, "
		      "for example 07 or 0C.", buf, 3, 0);
		type = (int)strtoul(buf, &e, 16);
		if (buf[0] == '\0' || *e != '\0' || type == 0) {
			ui_message("Create an entry", "That is not a partition "
				   "type.");
			return;
		}
		break;
	default:
		return;
	}
	sprintf(buf, "%lu", count[k] / 2048);
	sprintf(lines[5], "Create an entry\n\nType its size in MB, at most "
		"%lu.", count[k] / 2048);
	input(lines[5], buf, 12, 0);
	mb = strtoul(buf, &e, 10);
	if (buf[0] == '\0' || *e != '\0' || mb == 0 ||
	    mb > count[k] / 2048) {
		ui_message("Create an entry", "That size doesn't fit.");
		return;
	}
	n = mb * 2048;
	if (type == 0xA7) {		/* end it on a cylinder */
		lba_geometry(total, &heads, &spt);
		cyl = (unsigned long)heads * spt;
		end = (start[k] + n) / cyl * cyl;
		if (end <= start[k]) {
			ui_message("Create an entry", "That size is too small "
				   "to end on a cylinder.");
			return;
		}
		n = end - start[k];
	}
	t->p[slot].type = (unsigned char)type;
	t->p[slot].active = 0;
	t->p[slot].start = start[k];
	t->p[slot].count = n;
}

/* The editor over the disk's MBR.  0 with p->t set, or -1 for Cancel. */
static int edit_table(struct plan *p)
{
	static const char *actions[] = { "Delete an entry",
		"Create an entry in free space", "Mark an entry active",
		"Use this table", "Cancel" };
	unsigned char sec[512];
	struct table t;
	struct text tx;
	char path[32], head[100];
	const char *why;
	int fd, i, k;

	memset(&t, 0, sizeof t);
	sprintf(path, "/dev/r%sh", p->disk);
	if ((fd = open(path, O_RDONLY)) >= 0) {
		if (read(fd, sec, sizeof sec) != (int)sizeof sec ||
		    mbr_decode(sec, &t) < 0)
			memset(&t, 0, sizeof t);
		close(fd);
	}
	for (;;) {
		tx.len = 0;
		tx.s[0] = '\0';
		sprintf(head, "Advanced partitioning: %s, %lu MB\n\n", p->disk,
			p->total / 2048);
		add(&tx, head);
		add_table(&tx, &t);
		k = menu(tx.s, actions, 5);
		switch (k) {
		case 0:
			i = pick_entry(&t, "Delete which entry?");
			if (i >= 0)
				memset(&t.p[i], 0, sizeof t.p[i]);
			break;
		case 1:
			create_entry(&t, p->total);
			break;
		case 2:
			i = pick_entry(&t, "Mark which entry active?");
			if (i >= 0 && t.p[i].type != 0)
				for (k = 0; k < 4; k++)
					t.p[k].active = k == i;
			break;
		case 3:
			if ((why = layout_check(p->total, &t)) != NULL) {
				ui_message("Advanced partitioning", why);
				break;
			}
			p->t = t;
			return 0;
		default:
			return -1;
		}
	}
}

static void choose_layout(struct plan *p)
{
	static const char *how[] = {
		"Auto: erase the disk and use the standard layout",
		"Advanced: edit the partition table" };
	static const char *yes[] = { "Yes, use this layout",
				     "No, choose again" };
	struct text t;
	char line[200];

	for (;;) {
		if (menu("Partitioning\n\nAuto makes a 64 MB EFI system "
			 "partition and gives the rest of the disk to "
			 "RhapsodiOS.  Advanced keeps the other entries of the "
			 "disk's table, for sharing it with other systems.",
			 how, 2) == 0) {
			layout_auto(p->total, &p->t);
			advanced = 0;
		} else if (edit_table(p) == 0)
			advanced = 1;
		else
			continue;
		t.len = 0;
		t.s[0] = '\0';
		sprintf(line, "Partitioning\n\nThe partition table of %s (%lu MB) "
			"will be replaced with this one:\n\n", p->disk,
			p->total / 2048);
		add(&t, line);
		add_table(&t, &p->t);
		add(&t, advanced ? "\nThe RhapsodiOS and EFI system partitions "
		    "will be erased." : "\nEverything on the disk will be "
		    "erased.");
		if (menu(t.s, yes, 2) == 0)
			return;
	}
}

/* ---- 4. Drivers ---- */

struct driver {
	char name[64], family[32], loc[64];
	int detected, on;
};

static struct driver drivers[MAX_DRIVERS];
static int ndrivers = -1;	/* -1: not looked for yet */
static char detect_out[16384];
static int detect_rc;

static struct driver *find_driver(const char *name)
{
	int i;

	for (i = 0; i < ndrivers; i++)
		if (strcmp(drivers[i].name, name) == 0)
			return &drivers[i];
	return NULL;
}

static struct driver *add_driver(const char *name, const char *family)
{
	struct driver *d;

	if (ndrivers >= MAX_DRIVERS || strlen(name) >= sizeof d->name ||
	    strlen(family) >= sizeof d->family)
		return NULL;
	d = &drivers[ndrivers++];
	memset(d, 0, sizeof *d);
	strcpy(d->name, name);
	strcpy(d->family, family);
	return d;
}

/* A table's "Family" value, into out (32 bytes); "" if it has none. */
static void table_family(const char *table, char *out)
{
	const char *p = strstr(table, "\"Family\""), *q;

	out[0] = '\0';
	if (p == NULL || (p = strchr(p + 8, '=')) == NULL ||
	    (p = strchr(p, '"')) == NULL || (q = strchr(++p, '"')) == NULL ||
	    q - p >= 32)
		return;
	memcpy(out, p, q - p);
	out[q - p] = '\0';
}

/* The matches driverDetect lists, then every other driver /usr/Devices
 * holds, unmatched. */
static void find_drivers(void)
{
	static char *detect[] = { DRIVERDETECT, NULL };
	char *copy, *p, *e, *f[4], path[300], family[32], name[64], *table;
	struct dirent *de;
	struct driver *d;
	DIR *dir;
	int len;

	ui_progress(0, 0, "Matching drivers to this machine's cards...", NULL);
	ndrivers = 0;
	detect_rc = run_into(detect, detect_out, sizeof detect_out, 0);
	if (detect_rc == 0 && (copy = malloc(strlen(detect_out) + 1)) != NULL) {
		strcpy(copy, detect_out);
		for (p = copy; *p != '\0'; p = e) {
			e = p + strcspn(p, "\n");
			if (*e != '\0')
				*e++ = '\0';
			if (fields(p, f) < 3)
				continue;
			if ((d = find_driver(f[1])) == NULL &&
			    (d = add_driver(f[1], f[0])) == NULL)
				continue;
			if (!d->detected && strlen(f[2]) < sizeof d->loc)
				strcpy(d->loc, f[2]);
			d->detected = 1;
		}
		free(copy);
	}
	if ((dir = opendir(DEVICES)) == NULL)
		return;
	while ((de = readdir(dir)) != NULL) {
		len = (int)strlen(de->d_name);
		if (len <= 7 || len - 7 >= (int)sizeof name ||
		    strcmp(de->d_name + len - 7, ".config") != 0)
			continue;
		memcpy(name, de->d_name, len - 7);
		name[len - 7] = '\0';
		if (find_driver(name) != NULL)
			continue;
		sprintf(path, "%s/%s/Default.table", DEVICES, de->d_name);
		if ((table = slurp(path)) == NULL)
			continue;
		table_family(table, family);
		free(table);
		add_driver(name, family);
	}
	closedir(dir);
}

/* The disk controller the target sits on: for sdN the SCSI driver that
 * driverDetect -l loaded, for hdN AHCI if driverDetect matched it, else
 * EIDE. */
static const char *target_controller(const struct plan *p)
{
	static char scsi[64];
	char copy[sizeof loaded], *q, *e, *f[4];
	struct driver *d;
	int i;

	if (strncmp(p->disk, "sd", 2) == 0) {
		strcpy(copy, loaded);
		for (q = copy; *q != '\0'; q = e) {
			e = q + strcspn(q, "\n");
			if (*e != '\0')
				*e++ = '\0';
			if (fields(q, f) >= 2 && strcmp(f[0], "SCSI") == 0 &&
			    strlen(f[1]) < sizeof scsi) {
				strcpy(scsi, f[1]);
				return scsi;
			}
		}
		for (i = 0; i < ndrivers; i++)
			if (drivers[i].detected &&
			    strcmp(drivers[i].family, "SCSI") == 0)
				return drivers[i].name;
		return NULL;
	}
	d = find_driver("AHCI");
	return d != NULL && d->detected ? "AHCI" : "EIDE";
}

static void choose_drivers(struct plan *p)
{
	static const char *families[] = { "Disk", "SCSI", "Network", "Display",
					  "Audio" };
	static char *chosen[MAX_DRIVERS];
	static char lines[MAX_DRIVERS][160];
	const char *items[MAX_DRIVERS], *ctl;
	struct driver *idx[MAX_DRIVERS];
	char title[300];
	int on[MAX_DRIVERS], fi, i, n, disk;

	if (ndrivers < 0)
		find_drivers();
	if (detect_rc != 0) {
		sprintf(title, "driverDetect failed, so no drivers are ticked:"
			"\n\n%.200s", last_lines(detect_out, 4));
		ui_message("Drivers", title);
	}
	ctl = target_controller(p);
	for (i = 0; i < ndrivers; i++) {
		disk = strcmp(drivers[i].family, "Disk") == 0 ||
		       strcmp(drivers[i].family, "SCSI") == 0;
		for (fi = 0; fi < 5; fi++)
			if (strcmp(drivers[i].family, families[fi]) == 0)
				break;
		/* only drivers shown on a checklist may be ticked */
		drivers[i].on = fi == 5 ? 0 : disk ? ctl != NULL &&
				strcmp(drivers[i].name, ctl) == 0 :
				drivers[i].detected;
	}
	for (fi = 0; fi < 5; fi++) {
		n = 0;
		for (i = 0; i < ndrivers; i++) {
			if (strcmp(drivers[i].family, families[fi]) != 0)
				continue;
			idx[n] = &drivers[i];
			on[n] = drivers[i].on;
			if (drivers[i].detected)
				sprintf(lines[n], "%-24s found at %s",
					drivers[i].name, drivers[i].loc);
			else
				sprintf(lines[n], "%s", drivers[i].name);
			items[n] = lines[n];
			n++;
		}
		if (n == 0)
			continue;
		sprintf(title, "Drivers: %s\n\nTicked drivers are set up on the "
			"installed system.  \"found\" marks a driver that matches "
			"a card in this machine.%s", families[fi],
			fi < 2 ? "  Tick the controller of the disk you install "
			"on." : "");
		checklist(title, items, on, n, NULL);
		for (i = 0; i < n; i++)
			idx[i]->on = on[i];
	}
	p->ndrivers = 0;
	for (i = 0; i < ndrivers; i++)
		if (drivers[i].on)
			chosen[p->ndrivers++] = drivers[i].name;
	p->drivers = chosen;
}

/* ---- 5. Sets ---- */

static struct set sets[MAX_SETS];
static int nsets = -1;
static int set_on[MAX_SETS];	/* the sets chosen */

static void read_sets(void)
{
	struct dirent *de;
	struct set s;
	char path[300], name[64], *text;
	DIR *dir;
	int len, i;

	nsets = 0;
	if ((dir = opendir(SETS_DIR)) == NULL)
		return;
	while ((de = readdir(dir)) != NULL && nsets < MAX_SETS) {
		len = (int)strlen(de->d_name);
		if (len <= 4 || len - 4 >= (int)sizeof name ||
		    strcmp(de->d_name + len - 4, ".set") != 0)
			continue;
		memcpy(name, de->d_name, len - 4);
		name[len - 4] = '\0';
		sprintf(path, "%s/%s", SETS_DIR, de->d_name);
		if ((text = slurp(path)) == NULL)
			continue;
		if (set_parse(name, text, &s) == 0) {
			for (i = nsets; i > 0 &&		/* by name */
			     strcmp(sets[i - 1].name, s.name) > 0; i--)
				sets[i] = sets[i - 1];
			sets[i] = s;
			nsets++;
		}
		free(text);
	}
	closedir(dir);
}

/* 0 with p->pkgs set, or -1 if there are no sets. */
static int choose_sets(struct plan *p)
{
	/* title[64] ": " desc[128] " (required)": at most 204 bytes */
	static char lines[MAX_SETS][sizeof sets[0].title + 2 +
				    sizeof sets[0].desc + 11];
	const char *items[MAX_SETS];
	int on[MAX_SETS], locked[MAX_SETS], chosen[MAX_SETS], i, n;

	if (nsets < 0)
		read_sets();
	if (nsets == 0)
		return -1;
	for (i = 0; i < nsets; i++) {
		sprintf(lines[i], "%s: %s%s", sets[i].title, sets[i].desc,
			sets[i].required ? " (required)" : "");
		items[i] = lines[i];
		on[i] = locked[i] = sets[i].required;
	}
	checklist("Sets\n\nChoose the sets of packages to install.", items, on,
		  nsets, locked);
	for (i = n = 0; i < nsets; i++)
		if ((set_on[i] = on[i] || sets[i].required) != 0)
			chosen[n++] = i;
	p->npkgs = set_union(sets, chosen, n, &p->pkgs);
	return p->npkgs < 0 ? -1 : 0;
}

static void free_pkgs(struct plan *p)
{
	int i;

	for (i = 0; i < p->npkgs; i++)
		free(p->pkgs[i]);
	free(p->pkgs);
	p->pkgs = NULL;
	p->npkgs = 0;
}

/* ---- 6. Root password ---- */

static char pw_hash[64];

/* 0 with p->pw_hash set, or -1 if crypt() fails. */
static int choose_password(struct plan *p)
{
	char a[64], b[64], first8[9], salt[3], *h;

	for (;;) {
		a[0] = b[0] = '\0';
		input("Root password\n\nType a password for root.  It is not "
		      "shown, and only its first 8 characters count.", a,
		      sizeof a, 1);
		if (a[0] == '\0') {
			ui_message("Root password", "The password can't be "
				   "empty.");
			continue;
		}
		input("Root password\n\nType the same password again.", b,
		      sizeof b, 1);
		if (strcmp(a, b) == 0)
			break;
		ui_message("Root password", "The two passwords differ.  Try "
			   "again.");
	}
	make_salt((unsigned)time(NULL) ^ ((unsigned)getpid() << 16), salt);
	strncpy(first8, a, 8);
	first8[8] = '\0';
	h = crypt(first8, salt);
	memset(a, 0, sizeof a);
	memset(b, 0, sizeof b);
	memset(first8, 0, sizeof first8);
	if (h == NULL || strlen(h) >= sizeof pw_hash)
		return -1;
	strcpy(pw_hash, h);
	p->pw_hash = pw_hash;
	return 0;
}

/* ---- 7. Summary ---- */

/* 0 to install, 1 to start over. */
static int summary(const struct plan *p)
{
	static const char *items[] = { "Install", "Start over",
				       "Quit to a shell" };
	struct text t;
	char line[200];
	int i;

	t.len = 0;
	t.s[0] = '\0';
	sprintf(line, "Summary\n\nDisk:     %s, %lu MB\nLayout:   %s\n",
		p->disk, p->total / 2048, advanced ? "Advanced" : "Auto");
	add(&t, line);
	add_table(&t, &p->t);
	add(&t, "Drivers: ");
	for (i = 0; i < p->ndrivers; i++) {
		add(&t, " ");
		add(&t, p->drivers[i]);
	}
	add(&t, p->ndrivers ? "\nSets:    " : " none\nSets:    ");
	for (i = 0; i < nsets; i++)
		if (set_on[i]) {
			add(&t, " ");
			add(&t, sets[i].name);
		}
	add(&t, "\n\nInstall?");
	switch (menu(t.s, items, 3)) {
	case 0:
		return 0;
	case 1:
		return 1;
	default:
		leave_to_shell();
		return 1;
	}
}

/* ---- 8, 9. Progress and Done ---- */

static void done(const struct plan *p)
{
	static const char *items[] = { "Reboot", "Quit to a shell", "Halt" };
	char text[300];

	sprintf(text, "Done\n\nRhapsodiOS is installed on %s.  Remove the "
		"install media, then reboot.", p->disk);
	switch (menu(text, items, 3)) {
	case 0:
		run_and_stop("/sbin/reboot");
	case 1:
		leave_to_shell();
	default:
		run_and_stop("/sbin/halt");
	}
}

/* ---- the sequence ---- */

/* 1 if T is a mount point (or can't be told apart from one). */
static int still_mounted(void)
{
	struct stat a, b;

	if (stat(T, &a) < 0 || stat(T "/..", &b) < 0)
		return 1;
	return a.st_dev != b.st_dev;
}

static void setup_env(void)
{
	char buf[1024], *term = getenv("TERM");

	setenv("PATH", PATH, 1);
	if (term == NULL || *term == '\0' || tgetent(buf, term) != 1) {
		setenv("TERM", CONSOLE_TERM, 1);
		setenv("TERMCAP", CONSOLE_CAP, 1);
	}
	umask(022);
}

int main(void)
{
	static char *umount_cmd[] = { "umount", T, NULL };
	struct plan p;
	char rawdisk[32], failed[512], what[300], detail[1200];
	int rc, stuck;

	setup_env();
	if (ui_start() < 0) {
		fprintf(stderr, "sysinstall: can't use this terminal\n");
		return 1;
	}
	welcome();
	memset(&p, 0, sizeof p);
	for (;;) {
		free_pkgs(&p);
		memset(&p, 0, sizeof p);
		if (choose_disk(&p) < 0) {
			error_screen("No disk was found to install on.", NULL,
				     1);
			continue;
		}
		choose_layout(&p);
		choose_drivers(&p);
		if (choose_sets(&p) < 0) {
			error_screen("No sets were found in " SETS_DIR ".", NULL,
				     1);
			continue;
		}
		if (choose_password(&p) < 0) {
			error_screen("crypt() could not hash the password.",
				     NULL, 1);
			continue;
		}
		if (summary(&p) != 0)
			continue;
		sprintf(rawdisk, "/dev/r%sh", p.disk);
		p.root = T;
		p.inst = I;
		p.rawdisk = rawdisk;
		p.boot0_path = BOOT0;
		p.esp_cmd = ESP_CMD;
		rc = steps_run(&p, step_runner, step_progress, failed,
			       sizeof failed);
		if (rc == 0)
			done(&p);
		sprintf(what, "Step %d of %d failed: %.200s", rc, NSTEPS,
			cur_what);
		sprintf(detail, "%.300s\n\nIts last output:\n%.700s", failed,
			last_lines(step_out, 6));
		stuck = 0;
		if (rc >= 4) {		/* the target may be mounted */
			run_into(umount_cmd, step_out, sizeof step_out, 0);
			/* Steps 1-3 must not run under a mounted T: once apk
			 * has run, the kernel can keep it busy until reboot */
			if ((stuck = still_mounted()) != 0)
				strcat(detail, "\n\nThe target is still "
				       "mounted; reboot to start over.");
		}
		error_screen(what, detail, !stuck);
	}
}
