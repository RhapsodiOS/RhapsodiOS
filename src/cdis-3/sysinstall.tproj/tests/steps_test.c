#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "steps.h"
#include "layout.h"

#ifdef _WIN32
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#define MKDIR(p) _mkdir(p)
#else
#include <sys/stat.h>
#include <unistd.h>
#define MKDIR(p) mkdir(p, 0777)
#endif

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

#define TREE "BUILD/st"
#define ESP_BYTES (131072ul * 512ul)

static const char *self;	/* argv[0]: the ESP "decompressor" */

/* ---- the fake runner ---- */

static char cmds[32][512];
static int ncmds;
static const char *fail_on;	/* fail the command starting with this */
static int progress_n, progress_steps[16];

static int fake_run(const char *argv0, char *const argv[], void *ctx)
{
	char *line = cmds[ncmds++];
	int i;

	(void)ctx;
	line[0] = '\0';
	for (i = 0; argv[i] != NULL; i++) {
		if (i > 0)
			strcat(line, " ");
		strcat(line, argv[i]);
	}
	CHECK(strcmp(argv0, argv[0]) == 0);
	return fail_on != NULL && strncmp(line, fail_on, strlen(fail_on)) == 0
	    ? 1 : 0;
}

static void on_progress(int step, const char *what)
{
	CHECK(what != NULL && what[0] != '\0');
	progress_steps[progress_n++] = step;
}

/* ---- the fixture: a temp tree standing in for T, I and the disk ---- */

static void mk(const char *path) { MKDIR(path); }

static void put(const char *path, const char *text, size_t n)
{
	FILE *f = fopen(path, "wb");
	if (f == NULL) { printf("cannot create %s\n", path); exit(2); }
	fwrite(text, 1, n, f);
	fclose(f);
}

static char *slurp(const char *path, size_t *n)
{
	FILE *f = fopen(path, "rb");
	char *b = (char *)malloc(ESP_BYTES + 2097152ul);
	size_t got = 0;
	if (f == NULL) { free(b); *n = 0; return NULL; }
	got = fread(b, 1, ESP_BYTES + 2097152ul, f);
	fclose(f);
	b[got] = '\0';
	*n = got;
	return b;
}

static void setup(void)
{
	static unsigned char boot0[446];
	int i;

	mk("BUILD"); mk(TREE);
	mk(TREE "/T"); mk(TREE "/T/private"); mk(TREE "/T/private/etc");
	mk(TREE "/T/private/Drivers"); mk(TREE "/T/private/Drivers/i386");
	mk(TREE "/T/private/Drivers/i386/System.config");
	mk(TREE "/I"); mk(TREE "/I/Packages"); mk(TREE "/I/CDIS");
	mk(TREE "/I/CDIS/templates");
	remove(TREE "/T/private/etc/rc.cdrom");
	for (i = 0; i < 446; i++)
		boot0[i] = (unsigned char)(i * 7 + 1);
	put(TREE "/boot0", (char *)boot0, sizeof boot0);
	put(TREE "/disk.img", "", 0);
	put(TREE "/I/Packages/files-1-universal.apk", "x", 1);
	put(TREE "/I/Packages/basic-cmds-2.0-i386.apk", "x", 1);
	put(TREE "/I/Packages/cc-1-i386.apk", "x", 1);
	put(TREE "/I/Packages/cctools-9-i386.apk", "x", 1);
	put(TREE "/I/CDIS/templates/fstab", "/dev/@DISK@a / ufs rw 1 1\n", 26);
	put(TREE "/I/CDIS/templates/Instance0-i386.table",
	    "\"Boot Args\" = \"rootdev=@DISK@a\";\n", 34);
	put(TREE "/I/CDIS/templates/hostconfig", "HOSTNAME=-AUTOMATIC-\n", 21);
	put(TREE "/T/private/etc/master.passwd",
	    "nobody:*:-2:-2::0:0:Unprivileged:/:/dev/null\n"
	    "root:*:0:0::0:0:System Administrator:/:/bin/tcsh\n", 95);
	ncmds = 0; progress_n = 0; fail_on = NULL;
}

static char esp_cmd_buf[256];

static void fill(struct plan *p, char **pkgs, int npkgs, char **drv, int ndrv,
		 unsigned long esp_bytes)
{
	char *s;
	memset(p, 0, sizeof *p);
	strcpy(p->disk, "hd0");
	p->total = 2097152ul;
	layout_auto(p->total, &p->t);
	p->pw_hash = "rhME8brSxdukA";
	p->pkgs = pkgs; p->npkgs = npkgs;
	p->drivers = drv; p->ndrivers = ndrv;
	p->root = TREE "/T"; p->inst = TREE "/I";
	p->rawdisk = TREE "/disk.img"; p->boot0_path = TREE "/boot0";
#ifdef _WIN32
	/* cmd.exe wants a .\ prefix and backslashes; the Makefile
	 * gives the test an .exe name */
	sprintf(esp_cmd_buf, ".\\%s --emit %lu", self, esp_bytes);
#else
	sprintf(esp_cmd_buf, "./%s --emit %lu", self, esp_bytes);
#endif
#ifdef _WIN32
	for (s = esp_cmd_buf; *s; s++)
		if (*s == '/')
			*s = '\\';
#else
	(void)s;
#endif
	p->esp_cmd = esp_cmd_buf;
}

static int has(int i, const char *want)
{
	return i < ncmds && strcmp(cmds[i], want) == 0;
}

/* ---- tests ---- */

static void test_command_order_and_stop_on_failure(void)
{
	char *pkgs[] = { "files", "basic-cmds" };
	char *drv[] = { "NE2K", "EIDE" };
	struct plan p;
	char failed[256], *disk, *fstab, *tbl, *pw, *host;
	struct table back;
	size_t n, i;
	int rc;

	setup();
	fill(&p, pkgs, 2, drv, 2, ESP_BYTES);
	rc = steps_run(&p, fake_run, on_progress, failed, sizeof failed);
	CHECK(rc == 0);
	CHECK(ncmds == 8);
	CHECK(has(0, "disk -i -b /dev/rhd0h"));
	CHECK(has(1, "mount /dev/hd0a " TREE "/T"));
	CHECK(has(2, "apk add --root " TREE "/T --initdb "
	    TREE "/I/Packages/files-1-universal.apk"));
	CHECK(has(3, "apk add --root " TREE "/T "
	    TREE "/I/Packages/basic-cmds-2.0-i386.apk"));
	CHECK(has(4, "chroot " TREE "/T /usr/sbin/pwd_mkdb -p /etc/master.passwd"));
	CHECK(has(5, "/usr/sbin/driverDetect -w " TREE "/T NE2K EIDE"));
	CHECK(has(6, "umount " TREE "/T"));
	CHECK(has(7, "sync"));
	CHECK(progress_n == 9);
	for (i = 0; i < 9 && i < (size_t)progress_n; i++)
		CHECK(progress_steps[i] == (int)i + 1);

	/* step 1: boot0, the table, 0x55AA at sector 0 */
	disk = slurp(TREE "/disk.img", &n);
	CHECK(disk != NULL && n == ESP_LBA * 512ul + ESP_BYTES);
	if (disk != NULL && n >= 512) {
		CHECK(mbr_decode((unsigned char *)disk, &back) == 0);
		CHECK(back.p[0].type == 0xEF && back.p[0].start == ESP_LBA);
		CHECK(back.p[1].type == 0xA7 && back.p[1].start == A7_LBA);
		CHECK((unsigned char)disk[0] == 1 &&
		    (unsigned char)disk[445] == (unsigned char)(445 * 7 + 1));
	}
	/* step 2: the ESP image sits at its LBA, byte for byte, and ends there */
	if (disk != NULL && n == ESP_LBA * 512ul + ESP_BYTES) {
		const unsigned char *e = (unsigned char *)disk + ESP_LBA * 512ul;
		CHECK(e[0] == 0 && e[1] == 1 && e[250] == 250 && e[251] == 0);
		CHECK(e[ESP_BYTES - 1] == (unsigned char)((ESP_BYTES - 1) % 251));
	}
	free(disk);

	/* step 6: files */
	fstab = slurp(TREE "/T/private/etc/fstab", &n);
	CHECK(fstab != NULL && strcmp(fstab, "/dev/hd0a / ufs rw 1 1\n") == 0);
	free(fstab);
	tbl = slurp(TREE "/T/private/Drivers/i386/System.config/Instance0.table",
	    &n);
	CHECK(tbl != NULL && strstr(tbl, "rootdev=hd0a") != NULL);
	free(tbl);
	host = slurp(TREE "/T/private/etc/hostconfig", &n);
	CHECK(host != NULL && strcmp(host, "HOSTNAME=-AUTOMATIC-\n") == 0);
	free(host);
	pw = slurp(TREE "/T/private/etc/master.passwd", &n);
	CHECK(pw != NULL && strstr(pw, "root:rhME8brSxdukA:0:0:") != NULL);
	CHECK(pw != NULL && strstr(pw, "nobody:*:") != NULL);
	free(pw);
	{
		/* the Devices link; the Windows build stores a file, not a link */
		char buf[64];
		int k = 0;
#ifdef _WIN32
		FILE *f = fopen(TREE "/T/private/Devices", "rb");
		if (f != NULL) { k = (int)fread(buf, 1, 63, f); fclose(f); }
#else
		k = (int)readlink(TREE "/T/private/Devices", buf, 63);
#endif
		if (k < 0) k = 0;
		buf[k] = '\0';
		CHECK(strcmp(buf, "Drivers/i386") == 0);
	}

	/* a failed mount is step 4, and nothing runs after it */
	setup();
	fill(&p, pkgs, 2, drv, 2, ESP_BYTES);
	fail_on = "mount";
	rc = steps_run(&p, fake_run, on_progress, failed, sizeof failed);
	CHECK(rc == 4);
	CHECK(ncmds == 2);
	CHECK(has(1, "mount /dev/hd0a " TREE "/T"));
	CHECK(strcmp(failed, "mount /dev/hd0a " TREE "/T") == 0);
	CHECK(progress_n == 4);

	/* a failed package install is step 5; a failed disk is step 3 */
	setup();
	fill(&p, pkgs, 2, drv, 2, ESP_BYTES);
	fail_on = "apk add --root " TREE "/T --initdb";
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 5);
	CHECK(ncmds == 3);
	setup();
	fill(&p, pkgs, 2, drv, 2, ESP_BYTES);
	fail_on = "disk";
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 3);
	CHECK(ncmds == 1);
}

static void test_package_without_apk_is_step_5(void)
{
	char *pkgs[] = { "files", "nosuchpkg" };
	struct plan p;
	char failed[256];

	setup();
	fill(&p, pkgs, 2, NULL, 0, ESP_BYTES);
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 5);
	CHECK(ncmds == 3);	/* disk, mount, apk --initdb; no second apk */
	CHECK(strstr(failed, "nosuchpkg") != NULL);
}

static void test_prefix_names_do_not_match(void)
{
	/* "cc" must pick cc-1-i386.apk, not cctools-9-i386.apk */
	char *pkgs[] = { "files", "cc" };
	struct plan p;
	char failed[256];

	setup();
	fill(&p, pkgs, 2, NULL, 0, ESP_BYTES);
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 0);
	CHECK(has(3, "apk add --root " TREE "/T " TREE "/I/Packages/cc-1-i386.apk"));
}

static void test_esp_of_the_wrong_size_is_refused(void)
{
	char *pkgs[] = { "files" };
	struct plan p;
	char failed[256];

	setup();
	fill(&p, pkgs, 1, NULL, 0, ESP_BYTES - 1);
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 2);
	CHECK(ncmds == 0);
	CHECK(strstr(failed, "131072") != NULL);

	setup();
	fill(&p, pkgs, 1, NULL, 0, ESP_BYTES + 1);
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 2);
	CHECK(ncmds == 0);
	{
		size_t n;
		char *d = slurp(TREE "/disk.img", &n);
		/* nothing past the ESP's end was written */
		CHECK(n <= ESP_LBA * 512ul + ESP_BYTES);
		free(d);
	}
}

static void test_refuses_a_live_rc_cdrom(void)
{
	char *pkgs[] = { "files" };
	struct plan p;
	char failed[256];

	setup();
	put(TREE "/T/private/etc/rc.cdrom", "#!/bin/sh\n", 10);
	fill(&p, pkgs, 1, NULL, 0, ESP_BYTES);
	CHECK(steps_run(&p, fake_run, NULL, failed, sizeof failed) == 8);
	CHECK(strstr(failed, "rc.cdrom") != NULL);
	/* the driverDetect step ran; umount and sync did not */
	CHECK(ncmds == 5);
	CHECK(strncmp(cmds[ncmds - 1], "/usr/sbin/driverDetect", 22) == 0);
	remove(TREE "/T/private/etc/rc.cdrom");
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "--emit") == 0) {
		/* the stand-in for "gzip -dc esp.img.gz": n patterned bytes */
		unsigned long n = strtoul(argv[2], NULL, 10), i;
#ifdef _WIN32
		_setmode(_fileno(stdout), _O_BINARY);
#endif
		for (i = 0; i < n; i++)
			putchar((int)(i % 251));
		return 0;
	}
	self = argv[0];
	test_command_order_and_stop_on_failure();
	test_package_without_apk_is_step_5();
	test_prefix_names_do_not_match();
	test_esp_of_the_wrong_size_is_refused();
	test_refuses_a_live_rc_cdrom();
	printf("%s: %d failure%s\n", "steps_test", failures,
	    failures == 1 ? "" : "s");
	return failures != 0;
}
