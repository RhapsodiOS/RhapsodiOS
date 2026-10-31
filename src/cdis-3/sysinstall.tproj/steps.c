/* steps.c -- sysinstall's write phase.  See steps.h. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "steps.h"
#include "layout.h"
#include "config.h"

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#define popen _popen
#define pclose _pclose
#define MKDIR(p) _mkdir(p)
#else
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#define MKDIR(p) mkdir(p, 0777)
#endif

#define SECTOR 512ul
#define PATHMAX 1024

/* ---- small helpers ---- */

/* buf = a b, truncated to len. */
static void say(char *buf, int len, const char *a, const char *b)
{
	if (buf == NULL || len <= 0)
		return;
	buf[0] = '\0';
	strncat(buf, a, len - 1);
	if (b != NULL && strlen(buf) < (size_t)len - 1)
		strncat(buf, b, len - 1 - strlen(buf));
}

/* dst (PATHMAX bytes) = a b c; 0, or -1 if it does not fit. */
static int cat3(char *dst, const char *a, const char *b, const char *c)
{
	if (strlen(a) + strlen(b) + strlen(c) >= PATHMAX)
		return -1;
	strcpy(dst, a);
	strcat(dst, b);
	strcat(dst, c);
	return 0;
}

/* The whole file, malloc'd and NUL-terminated; *n is its length. */
static char *read_file(const char *path, size_t *n)
{
	FILE *f = fopen(path, "rb");
	char *buf = NULL, *nb;
	size_t used = 0, cap = 0, got;

	if (f == NULL)
		return NULL;
	for (;;) {
		if (cap - used < 4097) {
			cap = cap ? cap * 2 : 8192;
			nb = (char *)realloc(buf, cap);
			if (nb == NULL) {
				free(buf);
				fclose(f);
				return NULL;
			}
			buf = nb;
		}
		got = fread(buf + used, 1, cap - used - 1, f);
		if (got == 0)
			break;
		used += got;
	}
	fclose(f);
	buf[used] = '\0';
	if (n != NULL)
		*n = used;
	return buf;
}

static int write_file(const char *path, const char *data, size_t n)
{
	FILE *f = fopen(path, "wb");
	int ok;

	if (f == NULL)
		return -1;
	ok = fwrite(data, 1, n, f) == n;
	return (fclose(f) == 0 && ok) ? 0 : -1;
}

/* T/private/Devices -> Drivers/i386.  Windows has no symlinks without a
 * privilege, so the host build writes a file holding the target instead. */
static int make_link(const char *target, const char *path)
{
	remove(path);
#ifdef _WIN32
	return write_file(path, target, strlen(target));
#else
	return symlink(target, path);
#endif
}

/* Directory scan: dir_open, then dir_next until NULL, then dir_close. */
#ifdef _WIN32
struct dir { HANDLE h; WIN32_FIND_DATAA fd; int first; };

static int dir_open(struct dir *d, const char *path)
{
	char pat[PATHMAX + 3];

	if (cat3(pat, path, "\\*", "") < 0)
		return -1;
	d->h = FindFirstFileA(pat, &d->fd);
	d->first = 1;
	return d->h == INVALID_HANDLE_VALUE ? -1 : 0;
}

static const char *dir_next(struct dir *d)
{
	if (!d->first && !FindNextFileA(d->h, &d->fd))
		return NULL;
	d->first = 0;
	return d->fd.cFileName;
}

static void dir_close(struct dir *d) { FindClose(d->h); }
#else
struct dir { DIR *d; };

static int dir_open(struct dir *d, const char *path)
{
	d->d = opendir(path);
	return d->d == NULL ? -1 : 0;
}

static const char *dir_next(struct dir *d)
{
	struct dirent *e = readdir(d->d);
	return e == NULL ? NULL : e->d_name;
}

static void dir_close(struct dir *d) { closedir(d->d); }
#endif

/* The path of pkgdir's apk for package pkg: "pkg-<digit>*.apk".
 * 0 and *out (malloc'd); -1 if there is none; -2 if there are two. */
static int find_apk(const char *pkgdir, const char *pkg, char **out)
{
	struct dir d;
	const char *name;
	size_t pl = strlen(pkg), nl;
	char path[PATHMAX];
	int rc = -1;

	*out = NULL;
	if (dir_open(&d, pkgdir) < 0)
		return -1;
	while ((name = dir_next(&d)) != NULL) {
		nl = strlen(name);
		if (nl > pl + 5 && strncmp(name, pkg, pl) == 0 &&
		    name[pl] == '-' && name[pl + 1] >= '0' &&
		    name[pl + 1] <= '9' && strcmp(name + nl - 4, ".apk") == 0 &&
		    cat3(path, pkgdir, "/", name) == 0) {
			if (rc == 0) {
				free(*out);
				*out = NULL;
				rc = -2;
				break;
			}
			*out = (char *)malloc(strlen(path) + 1);
			if (*out != NULL) {
				strcpy(*out, path);
				rc = 0;
			}
		}
	}
	dir_close(&d);
	return rc;
}

/* ---- the install log: in memory until the target is mounted, then also
 * appended to T/private/var/log/sysinstall.log ---- */

static struct {
	char *buf;
	size_t n, cap;
	char path[PATHMAX];
	int to_file;
} lg;

static void log_reset(void)
{
	free(lg.buf);
	memset(&lg, 0, sizeof lg);
}

static void log_raw(const char *s)
{
	size_t l = strlen(s);
	char *nb;
	FILE *f;

	if (lg.n + l + 1 > lg.cap) {
		nb = (char *)realloc(lg.buf, (lg.n + l + 1) * 2);
		if (nb != NULL) {
			lg.buf = nb;
			lg.cap = (lg.n + l + 1) * 2;
		}
	}
	if (lg.n + l + 1 <= lg.cap) {
		memcpy(lg.buf + lg.n, s, l + 1);
		lg.n += l;
	}
	if (lg.to_file && (f = fopen(lg.path, "ab")) != NULL) {
		fputs(s, f);
		fclose(f);
	}
}

/* Create T/private/var/log and write the log so far there.  0 or -1. */
static int log_start_file(const struct plan *p)
{
	static const char *dirs[] = { "/private", "/private/var",
	    "/private/var/log" };
	char d[PATHMAX];
	FILE *f;
	int i;

	for (i = 0; i < 3; i++) {
		if (cat3(d, p->root, dirs[i], "") < 0)
			return -1;
		MKDIR(d);	/* fails harmlessly if it exists */
	}
	if (cat3(lg.path, p->root, "/private/var/log/sysinstall.log", "") < 0)
		return -1;
	f = fopen(lg.path, "wb");
	if (f == NULL)
		return -1;
	if (lg.n > 0 && fwrite(lg.buf, 1, lg.n, f) != lg.n) {
		fclose(f);
		return -1;
	}
	lg.to_file = 1;
	return fclose(f) == 0 ? 0 : -1;
}

/* ---- running commands ---- */

/* Runs argv; on a non-zero status, failed holds the command line. */
static int do_cmd(runner run, char *const argv[], char *failed, int len)
{
	int i, rc;
	size_t used;
	char num[16];

	log_raw("$");
	for (i = 0; argv[i] != NULL; i++) {
		log_raw(" ");
		log_raw(argv[i]);
	}
	rc = run(argv[0], argv, NULL);
	sprintf(num, " -> %d\n", rc);
	log_raw(num);

	if (rc != 0 && failed != NULL && len > 0) {
		failed[0] = '\0';
		for (i = 0; argv[i] != NULL; i++) {
			used = strlen(failed);
			if (used + 1 >= (size_t)len)
				break;
			if (i > 0)
				strncat(failed, " ", len - 1 - used);
			strncat(failed, argv[i], len - 1 - strlen(failed));
		}
	}
	return rc;
}

/* ---- steps 1 and 2: the MBR and the ESP ---- */

static int write_mbr(const struct plan *p, char *failed, int len)
{
	unsigned char boot0[446], mbr[512];
	size_t n = 0;
	char *b = read_file(p->boot0_path, &n);
	FILE *f;
	int ok;

	if (b == NULL || n < sizeof boot0) {
		free(b);
		say(failed, len, "read ", p->boot0_path);
		return -1;
	}
	memcpy(boot0, b, sizeof boot0);
	free(b);
	mbr_encode(boot0, p->total, &p->t, mbr);
	f = fopen(p->rawdisk, "r+b");
	if (f == NULL) {
		say(failed, len, "open ", p->rawdisk);
		return -1;
	}
	ok = fwrite(mbr, 1, sizeof mbr, f) == sizeof mbr;
	if (fclose(f) != 0 || !ok) {
		say(failed, len, "write MBR to ", p->rawdisk);
		return -1;
	}
	return 0;
}

/* Streams the ESP image to its LBA.  Never writes past ESP_SECTORS, and
 * refuses an image that is not exactly that long. */
static int write_esp(const struct plan *p, char *failed, int len)
{
	char cmd[PATHMAX], buf[8192];
	const char *c = p->esp_cmd;
	unsigned long total = 0, want = ESP_SECTORS * SECTOR;
	size_t got, room;
	FILE *in, *out;
	int ok = 1;

	if (c == NULL) {
		if (cat3(cmd, "gzip -dc ", p->inst, "/esp.img.gz") < 0) {
			say(failed, len, "esp command too long", NULL);
			return -1;
		}
		c = cmd;
	}
	out = fopen(p->rawdisk, "r+b");
	if (out == NULL) {
		say(failed, len, "open ", p->rawdisk);
		return -1;
	}
	in = popen(c, POPEN_MODE);
	if (in == NULL) {
		fclose(out);
		say(failed, len, "run ", c);
		return -1;
	}
	if (fseek(out, (long)(ESP_LBA * SECTOR), SEEK_SET) != 0)
		ok = 0;
	while (ok && (got = fread(buf, 1, sizeof buf, in)) > 0) {
		room = (size_t)(want - total);
		if (got > room) {	/* more than 131072 sectors: refuse */
			total = want + 1;
			break;
		}
		total += (unsigned long)got;
		if (fwrite(buf, 1, got, out) != got)
			ok = 0;
	}
	pclose(in);
	if (fclose(out) != 0)
		ok = 0;
	if (!ok) {
		say(failed, len, "write ESP to ", p->rawdisk);
		return -1;
	}
	if (total != want) {
		say(failed, len, "ESP image is not exactly 131072 sectors: ", c);
		return -1;
	}
	return 0;
}

/* ---- step 5: packages ---- */

/* Look up every node in the live system's /dev.  checkalias() hands an
 * in-use device vnode that no file system has claimed -- the live root's
 * own device, which bdevvp() made at boot -- to the first file system that
 * looks up a node for that device.  The media never looks up its root's
 * node, so apk's chown of files' private/dev/hd1a on the target would take
 * it, and umount T would then fail with EBUSY.  Looked up here, it goes to
 * the live root, as it does at an installed system's boot. */
static void claim_live_devices(void)
{
#ifndef _WIN32
	struct dir d;
	struct stat st;
	const char *name;
	char path[PATHMAX];

	if (dir_open(&d, "/dev/") < 0)
		return;
	while ((name = dir_next(&d)) != NULL)
		if (cat3(path, "/dev/", name, "") == 0)
			(void)stat(path, &st);
	dir_close(&d);
#endif
}

static int apk_steps(const struct plan *p, runner run, char *failed, int len)
{
	char pkgdir[PATHMAX], **av = NULL;
	int i, k, rc;

	if (cat3(pkgdir, p->inst, "/Packages", "") < 0) {
		say(failed, len, "Packages path too long", NULL);
		return -1;
	}
	/* One apk run, files first: files depends on basic-cmds, csu and
	 * libsystem, and apk resolves a dependency only among the apks it is
	 * given. */
	av = (char **)calloc((size_t)p->npkgs + 7, sizeof *av);
	if (av == NULL) {
		say(failed, len, "out of memory", NULL);
		return -1;
	}
	av[0] = "apk"; av[1] = "add"; av[2] = "--root";
	av[3] = (char *)p->root; av[4] = "--initdb";
	k = 5;
	rc = find_apk(pkgdir, "files", &av[k]);
	if (rc < 0)
		say(failed, len, rc == -2 ? "two apks for package files in " :
		    "no files apk in ", pkgdir);
	else
		k++;
	for (i = 0; rc == 0 && i < p->npkgs; i++) {
		if (strcmp(p->pkgs[i], "files") == 0)
			continue;
		rc = find_apk(pkgdir, p->pkgs[i], &av[k]);
		if (rc < 0)
			say(failed, len, rc == -2 ? "two apks for package " :
			    "no apk for package ", p->pkgs[i]);
		else
			k++;
	}
	if (rc < 0)
		rc = -1;
	else {
		claim_live_devices();
		rc = do_cmd(run, av, failed, len);
	}
	for (i = 5; i < k; i++)
		free(av[i]);
	free(av);
	return rc;
}

/* ---- step 6: configure ---- */

/* Copy template name from I/CDIS/templates to dest under T, rendered for
 * the disk if do_render. */
static int put_template(const struct plan *p, const char *name,
			const char *dest, int do_render)
{
	char src[PATHMAX], dst[PATHMAX], *text, *out;
	int rc;

	if (cat3(src, p->inst, "/CDIS/templates/", name) < 0 ||
	    cat3(dst, p->root, dest, "") < 0)
		return -1;
	text = read_file(src, NULL);
	if (text == NULL)
		return -1;
	out = do_render ? render(text, p->disk) : text;
	if (out == NULL) {
		free(text);
		return -1;
	}
	rc = write_file(dst, out, strlen(out));
	if (out != text)
		free(out);
	free(text);
	return rc;
}

static int configure_files(const struct plan *p, char *failed, int len)
{
	char path[PATHMAX], *pw, *np;

	if (put_template(p, "fstab", "/private/etc/fstab", 1) < 0) {
		say(failed, len, "write /private/etc/fstab", NULL);
		return -1;
	}
	if (put_template(p, "Instance0-i386.table",
	    "/private/Drivers/i386/System.config/Instance0.table", 1) < 0) {
		say(failed, len, "write System.config/Instance0.table", NULL);
		return -1;
	}
	if (put_template(p, "hostconfig", "/private/etc/hostconfig", 0) < 0) {
		say(failed, len, "write /private/etc/hostconfig", NULL);
		return -1;
	}
	if (cat3(path, p->root, "/private/Devices", "") < 0 ||
	    make_link("Drivers/i386", path) < 0) {
		say(failed, len, "link /private/Devices", NULL);
		return -1;
	}
	if (cat3(path, p->root, "/private/etc/master.passwd", "") < 0 ||
	    (pw = read_file(path, NULL)) == NULL) {
		say(failed, len, "read /private/etc/master.passwd", NULL);
		return -1;
	}
	np = passwd_set_root(pw, p->pw_hash);
	free(pw);
	if (np == NULL || write_file(path, np, strlen(np)) < 0) {
		free(np);
		say(failed, len, "set root's password in master.passwd", NULL);
		return -1;
	}
	free(np);
	return 0;
}

/* ---- the write phase ---- */

static void log_step(int step, const char *what)
{
	char num[16];

	sprintf(num, "step %d: ", step);
	log_raw(num);
	log_raw(what);
	log_raw("\n");
}

#define STEP(n, what) do { step = (n); log_step(step, what); \
	if (progress) progress(step, what); } while (0)

static int steps_inner(const struct plan *p, runner run,
		       void (*progress)(int step, const char *what),
		       char *failed_cmd, int len)
{
	char rawh[16], hda[16], path[PATHMAX], **av;
	char *disk_cmd[5], *mount_cmd[4], *chroot_cmd[6], *umount_cmd[3];
	char *sync_cmd[2];
	FILE *f;
	int step = 0, i;

	if (failed_cmd != NULL && len > 0)
		failed_cmd[0] = '\0';
	if (strlen(p->disk) < 2 || strlen(p->disk) > 4) {
		say(failed_cmd, len, "bad disk name", NULL);
		return 1;
	}
	sprintf(rawh, "/dev/r%sh", p->disk);	/* at most 11 characters */
	sprintf(hda, "/dev/%sa", p->disk);

	STEP(1, "Writing the partition table");
	if (write_mbr(p, failed_cmd, len) < 0)
		return step;

	STEP(2, "Writing the EFI system partition");
	if (write_esp(p, failed_cmd, len) < 0)
		return step;

	STEP(3, "Labelling and creating the filesystem");
	disk_cmd[0] = "disk"; disk_cmd[1] = "-i"; disk_cmd[2] = "-b";
	disk_cmd[3] = rawh; disk_cmd[4] = NULL;
	if (do_cmd(run, disk_cmd, failed_cmd, len) != 0)
		return step;

	STEP(4, "Mounting the new filesystem");
	mount_cmd[0] = "mount"; mount_cmd[1] = hda;
	mount_cmd[2] = (char *)p->root; mount_cmd[3] = NULL;
	if (do_cmd(run, mount_cmd, failed_cmd, len) != 0)
		return step;
	if (log_start_file(p) < 0) {
		say(failed_cmd, len, "write the log under ", p->root);
		return step;
	}

	STEP(5, "Installing packages");
	if (apk_steps(p, run, failed_cmd, len) != 0)
		return step;

	STEP(6, "Configuring the system");
	if (configure_files(p, failed_cmd, len) < 0)
		return step;
	chroot_cmd[0] = "chroot"; chroot_cmd[1] = (char *)p->root;
	chroot_cmd[2] = "/usr/sbin/pwd_mkdb"; chroot_cmd[3] = "-p";
	chroot_cmd[4] = "/etc/master.passwd"; chroot_cmd[5] = NULL;
	if (do_cmd(run, chroot_cmd, failed_cmd, len) != 0)
		return step;

	STEP(7, "Recording the drivers");
	av = (char **)calloc((size_t)p->ndrivers + 4, sizeof *av);
	if (av == NULL) {
		say(failed_cmd, len, "out of memory", NULL);
		return step;
	}
	av[0] = "/usr/sbin/driverDetect"; av[1] = "-w";
	av[2] = (char *)p->root;
	for (i = 0; i < p->ndrivers; i++)
		av[3 + i] = p->drivers[i];
	av[3 + i] = NULL;
	i = do_cmd(run, av, failed_cmd, len);
	free(av);
	if (i != 0)
		return step;

	STEP(8, "Checking the installed system");
	if (cat3(path, p->root, "/private/etc/rc.cdrom", "") < 0) {
		say(failed_cmd, len, "path too long", NULL);
		return step;
	}
	f = fopen(path, "rb");
	if (f != NULL) {
		fclose(f);
		say(failed_cmd, len, "the target has an active ", path);
		return step;
	}

	STEP(9, "Finishing");
	sync_cmd[0] = "sync"; sync_cmd[1] = NULL;
	if (do_cmd(run, sync_cmd, failed_cmd, len) != 0 ||
	    do_cmd(run, sync_cmd, failed_cmd, len) != 0)
		return step;
	/* Best effort: once apk has run the files package's scripts, the
	 * kernel can keep T busy until shutdown, whose forced unmount the
	 * Done screen's reboot and halt start.  T is synced either way. */
	umount_cmd[0] = "umount"; umount_cmd[1] = (char *)p->root;
	umount_cmd[2] = NULL;
	if (do_cmd(run, umount_cmd, NULL, 0) != 0)
		log_raw("warning: the target is still mounted; rebooting or "
			"halting unmounts it\n");
	return 0;
}

int steps_run(const struct plan *p, runner run,
	      void (*progress)(int step, const char *what),
	      char *failed_cmd, int len)
{
	int rc;

	log_reset();
	rc = steps_inner(p, run, progress, failed_cmd, len);
	log_reset();
	return rc;
}
