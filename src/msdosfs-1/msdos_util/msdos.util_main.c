/*
 * Copyright (c) 1999-2026 Apple Computer, Inc. / RhapsodiOS contributors.
 * All Rights Reserved.
 *
 * msdos.util - Workspace / autodiskmount utility for FAT12/16/32 volumes.
 * Patterned after cd9660.util and hfs.util; see kernserv/loadable_fs.h.
 */

#include <kernserv/loadable_fs.h>
#include <bsd/dev/disk.h>

#include <sys/types.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/stat.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define RAW_DEVICE_PREFIX	"/private/dev/r"
#define DEVICE_PREFIX		"/private/dev/"
#define DEVICE_SUFFIX		"a"

#define MSDOS_FS_NAME		"msdos"
#define MSDOS_FS_NAME_NAME	"MS-DOS (FAT)"
#define MSDOS_BOOT_SIZE		512

#define MOUNT_COMMAND		"/sbin/mount"
#define UMOUNT_COMMAND		"/sbin/umount"
#define FSCK_COMMAND		"/sbin/fsck_msdos"
#define MOUNT_FS_TYPE		"msdos"

static void	DoDisplayUsage(const char *argv[]);
static void	DoFileSystemFile(char *theFileNameSuffixPtr, char *theContentsPtr);
static int	DoMount(char *theDeviceNamePtr, const char *theMountPointPtr);
static int	DoProbe(char *theDeviceNamePtr);
static int	DoRepair(char *theRawDeviceNamePtr, char *theBlockDeviceNamePtr);
static int	DoUnmount(const char *theMountPointPtr);
static int	DoVerifyArgs(int argc, const char *argv[]);
static int	DeviceIsMounted(const char *deviceNamePtr);
static int	WaitChild(int pid);
static u_int16_t getle16(const u_char *p);
static u_int32_t getle32(const u_char *p);
static int	is_power_of_two(unsigned int v);

int
main(int argc, const char *argv[])
{
	const char *myActionPtr;
	int myError = FSUR_IO_SUCCESS;
	char myRawDeviceName[256];
	char myDeviceName[256];

	if ((myError = DoVerifyArgs(argc, argv)) != 0)
		goto AllDone;

	strcpy(&myDeviceName[0], DEVICE_PREFIX);
	strcat(&myDeviceName[0], argv[2]);
	strcat(&myDeviceName[0], DEVICE_SUFFIX);
	strcpy(&myRawDeviceName[0], RAW_DEVICE_PREFIX);
	strcat(&myRawDeviceName[0], argv[2]);
	strcat(&myRawDeviceName[0], DEVICE_SUFFIX);

	myActionPtr = &argv[1][1];
	(void)seteuid(0);
	(void)setegid(0);

	switch (*myActionPtr) {
	case FSUC_PROBE:
		myError = DoProbe(&myRawDeviceName[0]);
		break;

	case FSUC_MOUNT:
	case FSUC_MOUNT_FORCE:
		myError = DoMount(&myDeviceName[0], argv[3]);
		break;

	case FSUC_REPAIR:
		myError = DoRepair(&myRawDeviceName[0], &myDeviceName[0]);
		break;

	case FSUC_UNMOUNT:
		myError = DoUnmount(argv[3]);
		break;

	default:
		myError = FSUR_INVAL;
		break;
	}

AllDone:
	exit(myError);
	return myError;
}

static int
WaitChild(int pid)
{
	union wait status;
	int myError;

	if (pid == -1)
		return FSUR_IO_FAIL;

	if ((wait4(pid, (int *)&status, 0, NULL) == pid) && (WIFEXITED(status)))
		myError = status.w_retcode;
	else
		myError = -1;

	if (myError != 0)
		return FSUR_IO_FAIL;
	return FSUR_IO_SUCCESS;
}

static int
DoMount(char *theDeviceNamePtr, const char *theMountPointPtr)
{
	int pid;

	if (theMountPointPtr == NULL || *theMountPointPtr == 0x00)
		return FSUR_IO_FAIL;

	pid = fork();
	if (pid == 0) {
		execl(MOUNT_COMMAND, MOUNT_COMMAND, "-t", MOUNT_FS_TYPE,
		      theDeviceNamePtr, theMountPointPtr, NULL);
		_exit(127);
	}
	return WaitChild(pid);
}

static int
DoUnmount(const char *theMountPointPtr)
{
	int pid;

	if (theMountPointPtr == NULL || *theMountPointPtr == 0x00)
		return FSUR_IO_FAIL;

	pid = fork();
	if (pid == 0) {
		execl(UMOUNT_COMMAND, UMOUNT_COMMAND, theMountPointPtr, NULL);
		_exit(127);
	}
	return WaitChild(pid);
}

static int
DeviceIsMounted(const char *deviceNamePtr)
{
	struct statfs *mntbuf;
	int count;
	int i;
	const char *base;

	count = getmntinfo(&mntbuf, 0);
	if (count <= 0)
		return 0;

	base = deviceNamePtr;
	if (strncmp(base, "/private", 8) == 0)
		base += 8;	/* compare "/dev/..." forms too */

	for (i = 0; i < count; i++) {
		if (strcmp(mntbuf[i].f_mntfromname, deviceNamePtr) == 0)
			return 1;
		if (strcmp(mntbuf[i].f_mntfromname, base) == 0)
			return 1;
	}
	return 0;
}

static int
DoRepair(char *theRawDeviceNamePtr, char *theBlockDeviceNamePtr)
{
	int pid;

	if (DeviceIsMounted(theBlockDeviceNamePtr) ||
	    DeviceIsMounted(theRawDeviceNamePtr))
		return FSUR_INVAL;

	pid = fork();
	if (pid == 0) {
		execl(FSCK_COMMAND, FSCK_COMMAND, "-y", theRawDeviceNamePtr, NULL);
		_exit(127);
	}
	return WaitChild(pid);
}

static u_int16_t
getle16(const u_char *p)
{
	return (u_int16_t)(p[0] | (p[1] << 8));
}

static u_int32_t
getle32(const u_char *p)
{
	return ((u_int32_t)p[0]) |
	       ((u_int32_t)p[1] << 8) |
	       ((u_int32_t)p[2] << 16) |
	       ((u_int32_t)p[3] << 24);
}

static int
is_power_of_two(unsigned int v)
{
	return (v != 0) && ((v & (v - 1)) == 0);
}

/*
 * Recognize FAT12/16/32 from the boot-sector BPB.
 * Returns 1 if recognized, 0 if not. On success, copies a trimmed volume
 * label into labelOut (at least 12 bytes).
 */
static int
RecognizeFAT(const u_char *boot, char *labelOut)
{
	u_int16_t bytesPerSec;
	u_int8_t fats;
	u_int8_t secPerClust;
	u_int16_t rootDirEnts;
	u_int16_t sectors;
	u_int32_t hugeSectors;
	u_int16_t fatSmall;
	u_int32_t rootClust;
	const u_char *fileSysType;
	const u_char *volLab;
	u_char bootSig;
	int isFat32;
	int i;

	labelOut[0] = '\0';

	if (boot[510] != 0x55 || boot[511] != 0xaa)
		return 0;

	/* Accept common jump prefixes; reject obvious non-FAT (e.g. exFAT). */
	if (boot[0] != 0xeb && boot[0] != 0xe9)
		return 0;
	if (memcmp(boot + 3, "EXFAT   ", 8) == 0)
		return 0;

	bytesPerSec = getle16(boot + 11);
	secPerClust = boot[13];
	fats = boot[16];
	rootDirEnts = getle16(boot + 17);
	sectors = getle16(boot + 19);
	fatSmall = getle16(boot + 22);
	hugeSectors = getle32(boot + 32);

	if (bytesPerSec < 512 || bytesPerSec > 4096 ||
	    !is_power_of_two(bytesPerSec))
		return 0;
	if (fats < 1)
		return 0;
	if (secPerClust == 0 || !is_power_of_two(secPerClust))
		return 0;
	if (sectors == 0 && hugeSectors == 0)
		return 0;

	isFat32 = (rootDirEnts == 0);
	if (isFat32) {
		rootClust = getle32(boot + 44);
		fileSysType = boot + 82;
		bootSig = boot[66];
		volLab = boot + 71;
		if (rootClust == 0 && memcmp(fileSysType, "FAT32   ", 8) != 0)
			return 0;
		if (memcmp(fileSysType, "FAT32   ", 8) != 0 &&
		    rootClust < 2)
			return 0;
	} else {
		fileSysType = boot + 54;
		bootSig = boot[38];
		volLab = boot + 43;
		if (fatSmall == 0)
			return 0;
		/* Accept FileSysType when present; otherwise BPB shape is enough. */
		if (memcmp(fileSysType, "FAT12   ", 8) != 0 &&
		    memcmp(fileSysType, "FAT16   ", 8) != 0 &&
		    memcmp(fileSysType, "FAT     ", 8) != 0) {
			/* Many floppies leave FileSysType blank/OEM; still OK. */
			;
		}
	}

	if (bootSig == 0x29) {
		for (i = 0; i < 11; i++)
			labelOut[i] = (char)volLab[i];
		labelOut[11] = '\0';
		/* Treat "NO NAME" as empty for WSM. */
		if (strncmp(labelOut, "NO NAME", 7) == 0)
			labelOut[0] = '\0';
	}

	return 1;
}

static int
DoProbe(char *theDeviceNamePtr)
{
	int myError;
	int myFD = -1;
	int isFormated = 0;
	u_char myBuffer[MSDOS_BOOT_SIZE];
	char label[12];

	myFD = open(theDeviceNamePtr, O_RDONLY | O_NDELAY, 0);
	if (myFD < 0) {
		myError = FSUR_IO_FAIL;
		goto ExitThisRoutine;
	}

	if (ioctl(myFD, DKIOCGFORMAT, &isFormated) != 0) {
		myError = FSUR_IO_FAIL;
		goto ExitThisRoutine;
	}
	if (isFormated == 0) {
		myError = FSUR_UNRECOGNIZED;
		goto ExitThisRoutine;
	}

	if (read(myFD, myBuffer, MSDOS_BOOT_SIZE) != MSDOS_BOOT_SIZE) {
		myError = FSUR_IO_FAIL;
		goto ExitThisRoutine;
	}

	if (!RecognizeFAT(myBuffer, label)) {
		myError = FSUR_UNRECOGNIZED;
		goto ExitThisRoutine;
	}

	DoFileSystemFile(FS_NAME_SUFFIX, MSDOS_FS_NAME_NAME);
	DoFileSystemFile(FS_LABEL_SUFFIX, label);
	myError = FSUR_RECOGNIZED;

ExitThisRoutine:
	if (myFD >= 0)
		close(myFD);
	return myError;
}

static int
DoVerifyArgs(int argc, const char *argv[])
{
	int myError = FSUR_INVAL;
	int myDeviceLength;

	if (argc == 1) {
		DoDisplayUsage(argv);
		goto ExitThisRoutine;
	}

	if ((argc < 3) || (argv[1][0] != '-'))
		goto ExitThisRoutine;

	if (!((argv[1][1] == FSUC_PROBE) ||
	      (argv[1][1] == FSUC_MOUNT) ||
	      (argv[1][1] == FSUC_UNMOUNT) ||
	      (argv[1][1] == FSUC_MOUNT_FORCE) ||
	      (argv[1][1] == FSUC_REPAIR)))
		goto ExitThisRoutine;

	if ((argv[1][1] == FSUC_MOUNT) || (argv[1][1] == FSUC_MOUNT_FORCE) ||
	    (argv[1][1] == FSUC_UNMOUNT)) {
		if (argc < 4)
			goto ExitThisRoutine;
	}

	myDeviceLength = strlen(argv[2]);
	if (myDeviceLength < 2 || myDeviceLength > 6)
		goto ExitThisRoutine;

	myError = 0;

ExitThisRoutine:
	return myError;
}

static void
DoDisplayUsage(const char *argv[])
{
	printf("usage: %s action_arg device_arg [mount_point_arg] \n", argv[0]);
	printf("action_arg:\n");
	printf("       -%c (Probe for mounting)\n", FSUC_PROBE);
	printf("       -%c (Mount)\n", FSUC_MOUNT);
	printf("       -%c (Repair)\n", FSUC_REPAIR);
	printf("       -%c (Unmount)\n", FSUC_UNMOUNT);
	printf("       -%c (Force Mount)\n", FSUC_MOUNT_FORCE);
	printf("device_arg:\n");
	printf("       device we are acting upon (for example, \"sd2\")\n");
	printf("mount_point_arg:\n");
	printf("       required for Mount, Force Mount, and Unmount\n");
	printf("Examples:\n");
	printf("       %s -p sd2 \n", argv[0]);
	printf("       %s -m sd2 /Volumes/FAT \n", argv[0]);
	printf("       %s -r sd2 \n", argv[0]);
}

static void
DoFileSystemFile(char *theFileNameSuffixPtr, char *theContentsPtr)
{
	int myFD;
	char myFileName[MAXPATHLEN];

	if (strlen(theContentsPtr)) {
		char *myPtr;

		myPtr = theContentsPtr + strlen(theContentsPtr) - 1;
		while (myPtr >= theContentsPtr && *myPtr == ' ') {
			*myPtr = 0x00;
			myPtr--;
		}
	}
	sprintf(&myFileName[0], "%s/%s%s/%s", FS_DIR_LOCATION, MSDOS_FS_NAME,
		FS_DIR_SUFFIX, MSDOS_FS_NAME);
	strcat(&myFileName[0], theFileNameSuffixPtr);
	unlink(&myFileName[0]);

	if (strlen(theFileNameSuffixPtr)) {
		int myOldMask = umask(0);

		myFD = open(&myFileName[0], O_CREAT | O_TRUNC | O_WRONLY, 0644);
		umask(myOldMask);
		if (myFD >= 0) {
			write(myFD, theContentsPtr, strlen(theContentsPtr));
			close(myFD);
		} else {
			perror(myFileName);
		}
	}
}
