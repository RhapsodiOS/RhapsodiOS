/* steps.h -- sysinstall's write phase.  No curses and no crypt(): the
 * caller passes the password already hashed, and every external command
 * goes through a runner, so the host test substitutes a fake one. */

#ifndef STEPS_H
#define STEPS_H

#include "layout.h"

struct plan {
	char disk[8];		/* "hd0", "sd1": the target disk */
	struct table t;		/* its partition table */
	unsigned long total;	/* the disk's size in 512-byte sectors */
	const char *pw_hash;	/* root's crypt()ed password */
	char **pkgs;		/* package names, "files" first (set_union) */
	int npkgs;
	char **drivers;		/* driver names for driverDetect -w */
	int ndrivers;
	/* Where things are.  The host test points these at a temp tree. */
	const char *root;	/* T: the mount point of the target */
	const char *inst;	/* I: /System/Installation */
	const char *rawdisk;	/* /dev/rhdNh: where the MBR and ESP go */
	const char *boot0_path;	/* /usr/standalone/i386/boot0 */
	const char *esp_cmd;	/* command that writes the ESP image to its
				 * stdout; NULL means "gzip -dc I/esp.img.gz" */
};

/* popen mode for the ESP pipe.  Rhapsody's popen takes a one-character
 * mode, so "r" there; the Windows host needs "rb" for the binary image. */
#define POPEN_MODE_NATIVE "r"
#ifdef _WIN32
#define POPEN_MODE "rb"
#else
#define POPEN_MODE POPEN_MODE_NATIVE
#endif

/* Runs argv[0] with argv (NULL-terminated); returns its exit status.
 * steps_run passes NULL as ctx. */
typedef int (*runner)(const char *argv0, char *const argv[], void *ctx);

/* Runs write phase steps 1-9 in order.  progress, if not NULL, is called
 * before each step.  Returns 0, or the number of the step that failed,
 * after which nothing runs; failed_cmd (len bytes) then holds the command
 * or action that failed.  The target stays mounted on failure. */
int steps_run(const struct plan *p, runner run,
	      void (*progress)(int step, const char *what),
	      char *failed_cmd, int len);

#endif
