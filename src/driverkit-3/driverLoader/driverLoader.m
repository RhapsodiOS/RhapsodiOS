/*
 * driverLoader.m - load or configure DriverKit drivers after boot.
 *
 * Reconstructed from Apple's Rhapsody DR2 (i386) and Mac OS X Server
 * 1.2v3 (ppc) binaries; see reconstruction/ in this directory.
 */

#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import <driverkit/driverServer.h>
#import <mach/mach.h>
#import <bsd/sys/types.h>
#import <bsd/sys/stat.h>
#import <bsd/sys/dir.h>
#import <bsd/libc.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import "kl_com.h"

#define DEVICE_DIR	"/usr/Devices/"
#define CONFIG_EXT	".config"
#define RELOC_EXT	"_reloc"
#define TABLE_EXT	".table"
#define DEFAULT_TABLE	"Default.table"

/*
 * configDriver's and prePostExec's results.  Both references compare them
 * unsigned, as gcc does for an enum with no negative members.
 */
typedef enum {
	PP_OK = 0,
	PP_NONE = 1,		/* no Instance table for this unit */
	PP_FAILED = 2,		/* a Pre-/Post-Load file or the probe failed */
	PP_REFUSED = 3		/* absolute or ".." path: never run */
} loadResult;

int verbose = 0;		/* check width: byte or long accesses in the dumps */
int interactive = 0;
static int instruction = 0;
char *progName;

static void usage(char **argv);
static BOOL inquire(const char *question);
static int processDriverList(const char *list, BOOL isBoot, BOOL load);
static int processDriver(const char *driverName, BOOL isBoot, BOOL load);
static int loadDriver(const char *driverName);
static int unloadDriver(const char *driverName);
static int getInstanceFile(const char *driverName, char *path, int unit,
	struct stat *statBuf);
static loadResult configDriver(const char *driverName, int unit, BOOL probe,
	BOOL runPreLoad);
static BOOL securityCheck(const char *driverName);
static BOOL securityCheckDir(char *dir);
static loadResult prePostExec(const char *driverName, int unit, int post);

int
main(int argc, char **argv)
{
	int i;
	const char *driverName = NULL;
	BOOL load = YES;
	id systemTable, deviceMaster;
	const char *list;
	BOOL haveDisplay;
	IOObjectNumber objectNumber;
	IOString deviceKind;

	if (argc <= 1)
		usage(argv);
	progName = argv[0];
	for (i = 1; i < argc; i++) {
		switch (argv[i][0]) {
		    case 'D':
		    case 'd':
			/* both references compare the letter with 'u' here;
			 * check the jump table in the dumps for a 'u' case */
			driverName = argv[i] + 2;
			interactive = (argv[i][0] == 'd');
			load = (argv[i][0] != 'u');
			break;
		    case 'a':
			continue;
		    case 'i':
			interactive = 1;
			break;
		    case 'v':
			verbose = 1;
			break;
		    default:
			usage(argv);
		}
	}
	if (driverName != NULL)
		return processDriver(driverName, NO, load);

	systemTable = [IOConfigTable newFromSystemConfig];
	if (systemTable == nil) {
		fprintf(stderr, "%s: can't get system config table\n", argv[0]);
		exit(1);
	}
	if (inquire("Configure Boot Drivers")) {
		list = [systemTable valueForStringKey:"Boot Drivers"];
		if (list == NULL) {
			fprintf(stderr, "%s: can't get Boot Driver list\n", argv[0]);
			exit(1);
		}
		processDriverList(list, YES, YES);
	}
	if (inquire("Configure Active Drivers")) {
		list = [systemTable valueForStringKey:"Active Drivers"];
		if (list == NULL) {
			fprintf(stderr, "%s: can't get Active Driver list\n", argv[0]);
			exit(1);
		}
		processDriverList(list, NO, YES);
	}
	if (interactive)
		return 0;

	deviceMaster = [IODeviceMaster new];
	haveDisplay = NO;
	if ([deviceMaster lookUpByDeviceName:"Display0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS
	    || [deviceMaster lookUpByDeviceName:"VGADisplay0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS
	    || [deviceMaster lookUpByDeviceName:"SVGADisplay0"
			objectNumber:&objectNumber deviceKind:&deviceKind] == IO_R_SUCCESS)
		haveDisplay = YES;
	if (haveDisplay)
		return 0;
	fprintf(stderr, "%s: No display driver added, trying VGA\n", argv[0]);
	return processDriver("VGA", NO, YES);
}

static void
usage(char **argv)
{
	printf("Usage: %s <operation> [v(verbose)]\n", argv[0]);
	printf("Operations:\n");
	printf("\ta               Configure All Devices\n");
	printf("\ti               Interactive mode\n");
	printf("\td=deviceName    Configure one device (implies interactive)\n");
	printf("\tD=deviceName    Configure one device (non-interactive)\n");
	exit(1);
}

static BOOL
inquire(const char *question)
{
	char answer[80];

	if (!interactive)
		return YES;
	if (!instruction) {
		printf("Answer queries with 'y' for 'yes', anything else is 'no'.\n");
		instruction = 1;
	}
	printf("%s? ", question);
	gets(answer);
	return (answer[0] == 'y');
}

static int
processDriverList(const char *list, BOOL isBoot, BOOL load)
{
	char name[100];
	char *p;
	BOOL inName;

	if (verbose)
		printf("Configuring %s Drivers\n", isBoot ? "Boot" : "Active");
	p = name;
	inName = NO;
	for (;;) {
		if (*list != ' ' && *list != '\0') {
			inName = YES;
			*p++ = *list;
		}
		else if (!inName) {
			if (*list == '\0')
				break;
		}
		else {
			*p = '\0';
			processDriver(name, isBoot, load);
			p = name;
			inName = NO;
		}
		if (*list == '\0')
			break;
		list++;
	}
	return 0;
}

static int
processDriver(const char *driverName, BOOL isBoot, BOOL load)
{
	int configured = 0;
	int unit;
	loadResult rtn;

	if (!load)
		return unloadDriver(driverName);
	switch (prePostExec(driverName, 0, NO)) {
	    case PP_FAILED:
		fprintf(stderr, "driverLoader: driver %s Pre-Load file returned "
			"non-zero status; aborting\n", driverName);
		/* fall through */
	    case PP_REFUSED:
		return 1;
	    case PP_OK:
		break;
	    default:
		return 1;
	}
	if (!isBoot) {
		rtn = loadDriver(driverName);
		if (rtn)
			return rtn;
	}
	/*
	 * Mac OS X Server 1.2 counts the units it configured and fails when
	 * there were none; DR2 returned 0 regardless.  This follows 1.2.
	 */
	unit = 0;
	do {
		rtn = configDriver(driverName, unit, !isBoot, unit > 0);
		switch (rtn) {
		    case 0:
			configured++;
			break;
		    case 1:
			break;
		    case 2:
			break;
		    case PP_REFUSED:
			return 1;
		}
		unit++;
	} while (rtn != 1);
	return (rtn != 1 || configured <= 0);
}

static int
loadDriver(const char *driverName)
{
	char question[100];
	struct stat statBuf;
	char path[1024];
	id table;
	const char *serverName;

	sprintf(path, "%s%s%s/%s%s", DEVICE_DIR, driverName, CONFIG_EXT,
		driverName, RELOC_EXT);
	if (stat(path, &statBuf)) {
		if (verbose)
			printf("No Relocatable for %s\n", driverName);
		return 0;
	}
	sprintf(question, "Load driver %s", driverName);
	if (!inquire(question))
		return 0;
	if (verbose)
		printf("Loading %s for driver %s\n", path, driverName);
	if (kl_com_add(path, (char *)driverName)) {
		fprintf(stderr, "%s: kl_com_add() failed on %s\n", progName, path);
		return 1;
	}
	table = [IOConfigTable newForDriver:driverName unit:0];
	if (table == nil)
		table = [IOConfigTable newDefaultTableForDriver:driverName];
	if (table == nil) {
		fprintf(stderr, "%s: Can't get config table for %s\n",
			progName, driverName);
		return 1;
	}
	serverName = [table valueForStringKey:"Server Name"];
	if (serverName == NULL) {
		fprintf(stderr, "%s: No Server Name for %s\n", progName, driverName);
		return 1;
	}
	if (kl_com_load((char *)serverName)) {
		fprintf(stderr, "%s: kl_com_load() failed on %s\n", progName, path);
		[table free];
		return 1;
	}
	[table free];
	return 0;
}

static int
unloadDriver(const char *driverName)
{
	char path[1024];
	struct stat statBuf;
	char question[100];
	vm_offset_t data;
	int fd;
	IOReturn rtn;
	int krtn;

	if (verbose)
		printf("Unloading driver %s\n", driverName);
	if (getInstanceFile(driverName, path, 0, &statBuf)) {
		fprintf(stderr, "%s: couldn't get instance file for driver %s\n",
			progName, driverName);
		return 1;
	}
	sprintf(question, "Unload driver %s", driverName);
	if (!inquire(question))
		return 0;
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		if (verbose)
			printf("Can't open Instance file for %s instance %d "
				"(errno %d)\n", driverName, 0, errno);
		return 1;
	}
	if (map_fd(fd, 0, &data, TRUE, statBuf.st_size)) {
		if (verbose)
			printf("Can't read Instance file for %s instance %d "
				"(errno %d)\n", driverName, 0, errno);
		close(fd);
		return 1;
	}
	rtn = _IOUnloadDriver(device_master_self(), (unsigned char *)data,
		statBuf.st_size);
	vm_deallocate(task_self(), data, statBuf.st_size);
	close(fd);
	if (rtn) {
		fprintf(stderr, "%s: IOUnloadDriver() failed with code %d on %s\n",
			progName, rtn, driverName);
		return 1;
	}
	krtn = kl_com_unload((char *)driverName);
	if (krtn) {
		fprintf(stderr, "%s: kl_com_unload() failed with code %d on %s\n",
			progName, krtn, driverName);
		return 1;
	}
	krtn = kl_com_delete((char *)driverName);
	if (krtn) {
		fprintf(stderr, "%s: kl_com_delete() failed with code %d on %s\n",
			progName, krtn, driverName);
		return 1;
	}
	return 0;
}

static int
getInstanceFile(const char *driverName, char *path, int unit,
	struct stat *statBuf)
{
	sprintf(path, "%s%s%s/Instance%d%s", DEVICE_DIR, driverName, CONFIG_EXT,
		unit, TABLE_EXT);
	if (stat(path, statBuf)) {
		if (verbose)
			printf("No Instance file for %s instance %d\n",
				driverName, unit);
		if (unit)
			return 1;
		sprintf(path, "%s%s%s/%s", DEVICE_DIR, driverName, CONFIG_EXT,
			DEFAULT_TABLE);
		if (stat(path, statBuf)) {
			if (verbose)
				printf("No Default table for %s\n", driverName);
			return 1;
		}
		fprintf(stderr, "Using Default table for %s\n", driverName);
	}
	return 0;
}

static loadResult
configDriver(const char *driverName, int unit, BOOL probe, BOOL runPreLoad)
{
	char path[1024];
	struct stat statBuf;
	char question[100];
	vm_offset_t data;
	int fd;
	loadResult rtn;
	IOReturn ioRtn;

	rtn = getInstanceFile(driverName, path, unit, &statBuf);
	if (rtn)
		return rtn;
	sprintf(question, "Configure driver %s unit %d", driverName, unit);
	if (!inquire(question))
		return 0;
	if (runPreLoad) {
		switch (prePostExec(driverName, unit, NO)) {
		    case PP_FAILED:
			return 1;
		    case PP_REFUSED:
			return PP_REFUSED;
		    case PP_OK:
			break;
		    default:
			return 1;
		}
	}
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		if (verbose)
			printf("Can't open Instance file for %s instance %d "
				"(errno %d)\n", driverName, unit, errno);
		return 1;
	}
	if (probe) {
		if (map_fd(fd, 0, &data, TRUE, statBuf.st_size)) {
			if (verbose)
				printf("Can't read Instance file for %s instance %d "
					"(errno %d)\n", driverName, unit, errno);
			return 2;
		}
		ioRtn = _IOProbeDriver(device_master_self(), (unsigned char *)data,
			statBuf.st_size);
		if (ioRtn) {
			fprintf(stderr, "_IOProbeDriver: %s, device %s unit %d\n",
				[IODevice stringFromReturn:ioRtn], driverName, unit);
			rtn = 2;
		}
		vm_deallocate(task_self(), data, statBuf.st_size);
	}
	close(fd);
	if (rtn == PP_OK) {
		switch (prePostExec(driverName, unit, YES)) {
		    case PP_OK:
			break;
		    case PP_FAILED:
			break;
		    case PP_REFUSED:
			rtn = PP_REFUSED;
			break;
		}
	}
	return rtn;
}

/* Neither reference calls securityCheck; it is kept for parity. */
static BOOL
securityCheck(const char *driverName)
{
	char dir[1024];

	sprintf(dir, "%s%s%s", DEVICE_DIR, driverName, CONFIG_EXT);
	return securityCheckDir(dir);
}

static BOOL
securityCheckDir(char *dir)
{
	char cwd[MAXPATHLEN];
	struct direct **names = NULL;
	struct stat statBuf;
	char subdir[1024];
	char *name;
	int count, i;
	BOOL rtn;

	if (getwd(cwd) == NULL) {
		fprintf(stderr, cwd);
		fprintf(stderr, "driverLoader: getwd() failed\n");
		return YES;
	}
	chdir(dir);
	count = scandir(dir, &names, NULL, NULL);
	if (count < 0) {
		fprintf(stderr, "driverLoader: scandir(%s) error\n", dir);
		rtn = YES;
		goto out;
	}
	for (i = 0; names[i] != NULL; i++) {
		name = names[i]->d_name;
		name[names[i]->d_namlen] = '\0';
		if (strcmp(name, "..") == 0)
			continue;
		if (stat(name, &statBuf)) {
			fprintf(stderr, "Could not access %s/%s\n", dir, name);
			rtn = YES;
			goto out;
		}
		if (statBuf.st_uid != 0) {
			fprintf(stderr, "driverLoader: file %s/%s is not owned by "
				"root; aborting\n", dir, names[i]->d_name);
			rtn = YES;
			goto out;
		}
		if (statBuf.st_mode & (S_IWGRP | S_IWOTH)) {
			fprintf(stderr, "driverLoader: file %s/%s is writable; "
				"aborting\n", dir, names[i]->d_name);
			rtn = YES;
			goto out;
		}
		if (strcmp(name, ".") && (statBuf.st_mode & S_IFMT) == S_IFDIR) {
			sprintf(subdir, "%s/%s", dir, name);
			if (securityCheckDir(subdir)) {
				rtn = YES;
				goto out;
			}
		}
	}
	rtn = NO;
out:
	chdir(cwd);
	if (names != NULL) {
		for (i = 0; i < count; i++)
			free(names[i]);
		free(names);
	}
	return rtn;
}

static loadResult
prePostExec(const char *driverName, int unit, int post)
{
	char dir[1024];
	char command[2048];
	char question[100];
	id table;
	const char *file;
	loadResult rtn;

	table = [IOConfigTable newForDriver:driverName unit:unit];
	if (table == nil) {
		if (unit)
			return PP_OK;
		table = [IOConfigTable newDefaultTableForDriver:driverName];
		if (table == nil)
			return PP_OK;
	}
	file = [table valueForStringKey:post == 0 ? "Pre-Load" : "Post-Load"];
	if (file == NULL)
		return PP_OK;
	if (*file == '/' || strstr(file, "..") != NULL) {
		rtn = PP_REFUSED;
	}
	else {
		sprintf(question, "Execute %s file (%s)",
			post == 0 ? "Pre-Load" : "Post-Load", file);
		if (!inquire(question))
			return PP_OK;
		sprintf(dir, "%s%s%s", DEVICE_DIR, driverName, CONFIG_EXT);
		chdir(dir);
		sprintf(command, "%s/%s Instance=%d", dir, file, unit);
		/* __cstring holds "prePostExec: execString %s\n" and
		 * "   cwd %s\n" right here, but no code uses them: a debug
		 * printf the compiler removed.  Reproduce it the same way. */
		if (0) {
			printf("prePostExec: execString %s\n", command);
			printf("   cwd %s\n", dir);
		}
		rtn = system(command) ? PP_FAILED : PP_OK;
	}
	[table free];
	return rtn;
}
