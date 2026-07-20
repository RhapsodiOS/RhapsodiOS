/*
 * top - a top users display for Unix
 *
 * SYNOPSIS:  Any Sun running SunOS 5.x (Solaris 2.x)
 *
 * DESCRIPTION:
 * This is the machine-dependent module for SunOS 5.x (Solaris 2).
 * There is some support for MP architectures.
 * This makes top work on the following systems:
 *         SunOS 5.0 (not tested)
 *         SunOS 5.1
 *         SunOS 5.2
 *         SunOS 5.3
 *         SunOS 5.4
 *         SunOS 5.5
 *         SunOS 5.6
 *         SunOS 5.7
 *
 *     Tested on a SPARCclassic with SunOS 5.1, using gcc-2.3.3, and
 *     SPARCsystem 600 with SunOS 5.2, using Sun C
 *
 * LIBS: -lelf -lkvm -lkstat
 *
 * CFLAGS: -DHAVE_GETOPT -DORDER -DHAVE_STRERROR
 *
 *
 * AUTHORS:      Torsten Kasch 		<torsten@techfak.uni-bielefeld.de>
 *               Robert Boucher		<boucher@sofkin.ca>
 * CONTRIBUTORS: Marc Cohen 		<marc@aai.com>
 *               Charles Hedrick 	<hedrick@geneva.rutgers.edu>
 *	         William L. Jones 	<jones@chpc>
 *               Petri Kutvonen         <kutvonen@cs.helsinki.fi>
 *	         Casper Dik             <casper.dik@sun.com>
 *               Tim Pugh               <tpugh@oce.orst.edu>
 */

#define _KMEMUSER

#if (OSREV == 551)
#undef OSREV
#define OSREV 55
#endif

#define USE_NEW_PROC
#if defined(USE_NEW_PROC) && OSREV >= 56
#define _STRUCTURED_PROC 1
#define prpsinfo psinfo
#include <sys/procfs.h>
#define pr_fill pr_nlwp
/* These require an ANSI C compiler "Reisser cpp" doesn't like this */
#define pr_state pr_lwp.pr_state
#define pr_oldpri pr_lwp.pr_oldpri
#define pr_nice pr_lwp.pr_nice
#define pr_pri pr_lwp.pr_pri
#define pr_onpro pr_lwp.pr_onpro
#define ZOMBIE(p)	((p)->pr_nlwp == 0)
#define SIZE_K(p)	((p)->pr_size)
#define RSS_K(p)	((p)->pr_rssize)
#else
#undef USE_NEW_PROC
#define ZOMBIE(p)	((p)->pr_zomb)
#define SIZE_K(p)	((p)->pr_bysize/1024)
#define RSS_K(p)	((p)->pr_byrssize/1024)
#define pr_onpro 	pr_filler[5]
#endif

#include "top.h"
#include "machine.h"
#include "utils.h"
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <dirent.h>
#include <nlist.h>
#include <string.h>
#include <kvm.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/signal.h>
#include <sys/fault.h>
#include <sys/sysinfo.h>
#include <sys/sysmacros.h>
#include <sys/syscall.h>
#include <sys/user.h>
#include <sys/proc.h>
#include <sys/procfs.h>
#include <sys/vm.h>
#include <sys/var.h>
#include <sys/cpuvar.h>
#include <sys/file.h>
#include <sys/time.h>
#include <sys/priocntl.h>
#include <sys/tspriocntl.h>
#include <sys/processor.h>
#include <sys/swap.h>
#include <vm/anon.h>
#include <math.h>

#if OSREV >= 53
#define USE_KSTAT
#endif
#ifdef USE_KSTAT
#include <kstat.h>
/*
 * Some kstats are fixed at 32 bits, these will be specified as ui32; some
 * are "natural" size (32 bit on 32 bit Solaris, 64 on 64 bit Solaris
 * we'll make those unsigned long)
 * Older Solaris doesn't define KSTAT_DATA_UINT32, those are always 32 bit.
 */
# ifndef KSTAT_DATA_UINT32
#  define ui32 ul
# endif
#endif

#ifdef SC_AINFO
#undef USE_ANONINFO				/* Use swapctl() instead */
#endif

#define UNIX "/dev/ksyms"
#define KMEM "/dev/kmem"
#define PROCFS "/proc"
#define CPUSTATES     5
#ifndef PRIO_MIN
#define PRIO_MIN	-20
#endif
#ifndef PRIO_MAX
#define PRIO_MAX	20
#endif

#ifndef FSCALE
#define FSHIFT  8		/* bits to right of fixed binary point */
#define FSCALE  (1<<FSHIFT)
#endif /* FSCALE */

#define loaddouble(la) ((double)(la) / FSCALE)
#define dbl_align(x)	(((unsigned long)(x)+(sizeof(double)-1)) & \
						~(sizeof(double)-1))
#if (OSREV >= 54)
    /*
     * snarfed from <sys/procfs.h>:
     * The following percent numbers are 16-bit binary
     * fractions [0 .. 1] with the binary point to the
     * right of the high-order bit (one == 0x8000)
     */
#define percent_cpu(pp) (((double)pp->pr_pctcpu)/0x8000*100)
#define weighted_cpu(pp) (*(double *)dbl_align(pp->pr_filler))
#else
#define percent_cpu(pp) (*(double *)dbl_align(&pp->pr_filler[0]))
#define weighted_cpu(pp) (*(double *)dbl_align(&pp->pr_filler[2]))
#endif

/* definitions for indices in the nlist array */
#define X_V			 0
#define X_MPID			 1
#define X_ANONINFO		 2
#define X_MAXMEM		 3
#define X_SWAPFS_MINFREE	 4
#define X_FREEMEM		 5
#define X_AVAILRMEM		 6
#define X_AVENRUN		 7
#define X_CPU			 8
#define X_NPROC			 9
#define X_NCPUS		   	10

static struct nlist nlst[] =
{
  {"v"},			/* 0 */	/* replaced by dynamic allocation */
  {"mpid"},			/* 1 */
#if OSREV >= 56
  /* this structure really has some extra fields, but the first three match */
  {"k_anoninfo"},		/* 2 */
#else
  {"anoninfo"},			/* 2 */
#endif
  {"maxmem"},			/* 3 */ /* use sysconf */
  {"swapfs_minfree"},		/* 4 */	/* used only w/ USE_ANONINFO */
  {"freemem"},			/* 5 */	/* available from kstat >= 2.5 */
  {"availrmem"},		/* 6 */	/* available from kstat >= 2.5 */
  {"avenrun"},			/* 7 */ /* available from kstat */
  {"cpu"},			/* 8 */ /* available from kstat */
  {"nproc"},			/* 9 */ /* available from kstat */
  {"ncpus"},			/* 10 */ /* available from kstat */
  {0}
};

static unsigned long avenrun_offset;
static unsigned long mpid_offset;
#ifdef USE_KSTAT
#define NO_NPROC
static kstat_ctl_t *kc = NULL;
static kstat_t **cpu_ks;
static cpu_stat_t *cpu_stat;
#else
static unsigned long *cpu_offset;
#endif
static unsigned long nproc_offset;
static unsigned long freemem_offset;
static unsigned long maxmem_offset;
static unsigned long availrmem_offset;
static unsigned long swapfs_minfree_offset;
static unsigned long anoninfo_offset;
static void reallocproc(int n);
static int maxprocs;

/* get_process_info passes back a handle.  This is what it looks like: */
struct handle
  {
    struct prpsinfo **next_proc;/* points to next valid proc pointer */
    int remaining;		/* number of pointers remaining */
  };

/*
 * Structure for keeping track of CPU times from last time around
 * the program.  We keep these things in a hash table, which is
 * recreated at every cycle.
 */
struct oldproc
  {
    pid_t oldpid;
    double oldtime;
    double oldpct;
  };
int oldprocs;			/* size of table */
#define HASH(x) ((x << 1) % oldprocs)

/*
 * GCC assumes that all doubles are aligned.  Unfortunately it
 * doesn't round up the structure size to be a multiple of 8.
 * Thus we'll get a coredump when going through array.  The
 * following is a size rounded up to 8.
 */
#define PRPSINFOSIZE dbl_align(sizeof(struct prpsinfo))

/*
 *  These definitions control the format of the per-process area
 */
#if OSREV >= 58
static char header[] =
"   PID X        THR PRI NICE  SIZE   RES STATE    TIME    CPU COMMAND";
/* 0123456   -- field to fill in starts at header+6 */
#define UNAME_START 7

#define Proc_format \
        "%6d %-8.8s %3d %3d %4d %5s %5s %-6s %6s %5.2f%% %s"
#else
static char header[] =
"  PID X        THR PRI NICE  SIZE   RES STATE    TIME    CPU COMMAND";
/* 0123456   -- field to fill in starts at header+6 */
#define UNAME_START 6

#define Proc_format \
        "%5d %-8.8s %3d %3d %4d %5s %5s %-6s %6s %5.2f%% %s"
#endif

/* process state names for the "STATE" column of the display */
char *state_abbrev[] =
{"", "sleep", "run", "zombie", "stop", "start", "cpu", "swap"};

int process_states[8];
char *procstatenames[] =
{
  "", " sleeping, ", " running, ", " zombie, ", " stopped, ",
  " starting, ", " on cpu, ", " swapped, ",
  NULL
};

int cpu_states[CPUSTATES];
char *cpustatenames[] =
{"idle", "user", "kernel", "iowait", "swap", NULL};
#define CPUSTATE_IOWAIT 3
#define CPUSTATE_SWAP   4


/* these are for detailing the memory statistics */
int memory_stats[5];
char *memorynames[] =
{"K real, ", "K active, ", "K free, ", "K swap in use, ", "K swap free", NULL};

/* these are names given to allowed sorting orders -- first is default */
char *ordernames[] = 
{"cpu", "size", "res", "time", NULL};

/* forward definitions for comparison functions */
int compare_cpu();
int compare_size();
int compare_res();
int compare_time();

int (*proc_compares[])() = {
    compare_cpu,
    compare_size,
    compare_res,
    compare_time,
    NULL };

kvm_t *kd;
static DIR *procdir;
static int nproc;
static int ncpus;

/* these are for keeping track of the proc array */
static int bytes;
static struct prpsinfo *pbase;
static struct prpsinfo **pref;
static struct oldproc *oldbase;

/* pagetok function is really a pointer to an appropriate function */
static int pageshift;
static int (*p_pagetok) ();
#define pagetok(size) ((*p_pagetok)(size))

/* useful externals */
extern char *myname;
extern int check_nlist ();
extern int gettimeofday ();
extern int getkval ();
extern void perror ();
extern void getptable ();
extern void quit ();
extern int nlist ();

int pagetok_none(int size)

{
    return(size);
}

int pagetok_left(int size)

{
    return(size << pageshift);
}

int pagetok_right(int size)

{
    return(size >> pageshift);
}

int
machine_init (struct statics *statics)
{
    static struct var v;
    struct oldproc *op, *endbase;
    int i;
    char *p;
#ifndef USE_KSTAT
    int offset;
#endif

    /* There's a buffer overflow bug in curses that can be exploited when
       we run as root.  By making sure that TERMINFO is set to something
       this bug is avoided.  This code thanks to Casper */
    if ((p = getenv("TERMINFO")) == NULL || *p == '\0')
    {
        putenv("TERMINFO=/usr/share/lib/terminfo/");
    }

    /* perform the kvm_open - suppress error here */
    kd = kvm_open (NULL, NULL, NULL, O_RDONLY, NULL);

    /*
     * turn off super group/user privs - but beware; we might
     * want the privs back later and we still have a fd to
     * /dev/kmem open so we can't use setgid()/setuid() as that
     * would allow a debugger to attach to this process. CD
     */
    setegid(getgid());
    seteuid(getuid()); /* super user not needed for NEW_PROC */

    /* fill in the statics information */
    statics->procstate_names = procstatenames;
    statics->cpustate_names = cpustatenames;
    statics->memory_names = memorynames;
    statics->order_names = ordernames;

    /*
     * test kvm_open return value - print error message and exit
     * when we need to read kernel memory (older releases)
     */
    if (kd == NULL)
      {
#ifndef USE_KSTAT
	/* Print the failure message here */
	(void) kvm_open (NULL, NULL, NULL, O_RDONLY, "top");
	perror("kvm_open");
	return (-1);
#endif
      }
    if (kd)
      {
      if (kvm_nlist (kd, nlst) < 0)
        {
	  perror ("kvm_nlist");
	  return (-1);
        }
      if (check_nlist (nlst) != 0)
        return (-1);
      }

#ifndef NO_NPROC
    /* NPROC Tuning parameter for max number of processes */
    (void) getkval (nlst[X_V].n_value, &v, sizeof (struct var), nlst[X_V].n_name);
    nproc = v.v_proc;

    reallocproc(nproc);
#endif

    /* stash away certain offsets for later use */
    mpid_offset = nlst[X_MPID].n_value;
    nproc_offset = nlst[X_NPROC].n_value;
    avenrun_offset = nlst[X_AVENRUN].n_value;
    anoninfo_offset = nlst[X_ANONINFO].n_value;
    freemem_offset = nlst[X_FREEMEM].n_value;
    maxmem_offset = nlst[X_MAXMEM].n_value;
    availrmem_offset = nlst[X_AVAILRMEM].n_value;
    swapfs_minfree_offset = nlst[X_SWAPFS_MINFREE].n_value;


#ifndef USE_KSTAT
    (void) getkval (nlst[X_NCPUS].n_value, (int *) (&ncpus),
		    sizeof (ncpus), "ncpus");

    cpu_offset = (unsigned long *) malloc (ncpus * sizeof (unsigned long));
    for (i = offset = 0; i < ncpus; offset += sizeof(unsigned long)) {
        (void) getkval (nlst[X_CPU].n_value + offset,
                        &cpu_offset[i], sizeof (unsigned long),
                        nlst[X_CPU].n_name );
        if (cpu_offset[i] != 0)
            i++;
    }
#endif

    /* calculate pageshift value */
    i = sysconf(_SC_PAGESIZE);
    pageshift = 0;
    while ((i >>= 1) > 0)
    {
	pageshift++;
    }

    /* calculate an amount to shift to K values */
    /* remember that log base 2 of 1024 is 10 (i.e.: 2^10 = 1024) */
    pageshift -= 10;

    /* now determine which pageshift function is appropriate for the 
       result (have to because x << y is undefined for y < 0) */
    if (pageshift > 0)
    {
	/* this is the most likely */
	p_pagetok = pagetok_left;
    }
    else if (pageshift == 0)
    {
	p_pagetok = pagetok_none;
    }
    else
    {
	p_pagetok = pagetok_right;
	pageshift = -pageshift;
    }

    if (!(procdir = opendir (PROCFS)))
      {
	(void) fprintf (stderr, "Unable to open %s\n", PROCFS);
	return (-1);
      }

    if (chdir (PROCFS))
      {				/* handy for later on when we're reading it */
	(void) fprintf (stderr, "Unable to chdir to %s\n", PROCFS);
	return (-1);
      }

    /* all done! */
    return (0);
  }

char *
format_header (register char *uname_field)
{
  register char *ptr;

  ptr = header + UNAME_START;
  while (*uname_field != '\0')
    *ptr++ = *uname_field++;

  return (header);
}

#ifdef USE_KSTAT

#define UPDKCID(nk,ok) \
if (nk == -1) { \
  perror("kstat_read "); \
  quit(1); \
} \
if (nk != ok)\
  goto kcid_changed;

int kupdate(int avenrun[3])
{
    kstat_t *ks;
    kid_t nkcid;
    int i;
    int changed = 0;
    static int ncpu = 0;
    static kid_t kcid = 0;
    kstat_named_t *kn;


    /*
     * 0. kstat_open
     */

    if (!kc)
    {
	kc = kstat_open();
	if (!kc)
	{
	    perror("kstat_open ");
	    quit(1);
	}
	changed = 1;
	kcid = kc->kc_chain_id;
    }

    /* keep doing it until no more changes */
  kcid_changed:

    /*
     * 1.  kstat_chain_update
     */
    nkcid = kstat_chain_update(kc);
    if (nkcid)
    {
	/* UPDKCID will abort if nkcid is -1, so no need to check */
	changed = 1;
	kcid = nkcid;
    }
    UPDKCID(nkcid,0);

    ks = kstat_lookup(kc, "unix", 0, "system_misc");
    if (kstat_read(kc, ks, 0) == -1) {
	perror("kstat_read");
	quit(1);
    }

    /* load average */
    kn = kstat_data_lookup(ks, "avenrun_1min");
    if (kn)
	avenrun[0] = kn->value.ui32;
    kn = kstat_data_lookup(ks, "avenrun_5min");
    if (kn)
	avenrun[1] = kn->value.ui32;
    kn = kstat_data_lookup(ks, "avenrun_15min");
    if (kn)
	avenrun[2] = kn->value.ui32;

    /* nproc */
    kn = kstat_data_lookup(ks, "nproc");
    if (kn) {
	nproc = kn->value.ui32;
#ifdef NO_NPROC
	if (nproc > maxprocs)
	    reallocproc(2 * nproc);
#endif
    }

    if (changed) {

	/*
	 * 2. get data addresses
	 */

	ncpu = 0;

	kn = kstat_data_lookup(ks, "ncpus");
	if (kn && kn->value.ui32 > ncpus) {
	    ncpus = kn->value.ui32;
	    cpu_ks = (kstat_t **) realloc (cpu_ks, ncpus * sizeof (kstat_t *));
	    cpu_stat = (cpu_stat_t *) realloc (cpu_stat,
			ncpus * sizeof (cpu_stat_t));
	}

	for (ks = kc->kc_chain; ks; 
	     ks = ks->ks_next)
	{
	    if (strncmp(ks->ks_name, "cpu_stat", 8) == 0)
	    {
		nkcid = kstat_read(kc, ks, NULL);
		/* if kcid changed, pointer might be invalid */
		UPDKCID(nkcid, kcid);

		cpu_ks[ncpu] = ks;
		ncpu++;
		if (ncpu > ncpus)
		{
		    fprintf(stderr, "kstat finds too many cpus: should be %d\n",
			    ncpus);
		    quit(1);
		}
	    }
	}
	/* note that ncpu could be less than ncpus, but that's okay */
	changed = 0;
    }

    /*
     * 3. get data
     */

    for (i = 0; i < ncpu; i++)
    {
	nkcid = kstat_read(kc, cpu_ks[i], &cpu_stat[i]);
	/* if kcid changed, pointer might be invalid */
	UPDKCID(nkcid, kcid);
    }

    /* return the number of cpus found */
    return(ncpu);
}

#endif /* USE_KSTAT */

void
get_system_info (struct system_info *si)
{
  int avenrun[3];
  static long freemem;
  static long maxmem;
  static long availrmem;
  static long swapfs_minfree;
  static int swap_total;
  static int swap_free;
  struct anoninfo anoninfo;
  static long cp_time[CPUSTATES];
  static long cp_old[CPUSTATES];
  static long cp_diff[CPUSTATES];
  register int j, i;
#ifdef USE_KSTAT
  kstat_t *ks;
  kstat_named_t *kn;
  int cpus_found;
#else
  struct cpu cpu;
#endif

  /* get the cp_time array */
  for (j = 0; j < CPUSTATES; j++)
    cp_time[j] = 0L;

#ifdef USE_KSTAT
  /* use kstat to update all processor information */
  cpus_found = kupdate(avenrun);
  for (i = 0; i < cpus_found; i++)
    {
      /* sum counters up to, but not including, wait state counter */
      for (j = 0; j < CPU_WAIT; j++)
	cp_time[j] += (long) cpu_stat[i].cpu_sysinfo.cpu[j];

      /* add in wait state breakdown counters */
      cp_time[CPUSTATE_IOWAIT] += (long) cpu_stat[i].cpu_sysinfo.wait[W_IO] +
                                  (long) cpu_stat[i].cpu_sysinfo.wait[W_PIO];
      cp_time[CPUSTATE_SWAP] += (long) cpu_stat[i].cpu_sysinfo.wait[W_SWAP];
    }
    /* avenrun */

#if OSREV >= 55
    /*
     * The system_pages kstat is extremely expensive on systems with large
     * amounts of physical memory.  But since we only need freemem/availrmem
     * and those are readily avaiable in the kernel cheaply, we read the
     * kernel if kvm_open succeeded.
     */
    if (kd == NULL) {
	ks = kstat_lookup(kc, "unix", 0, "system_pages");
	if (kstat_read(kc, ks, 0) == -1) {
	    perror("kstat_read");
	    quit(1);
	}
#ifdef USE_ANONINFO
	kn = kstat_data_lookup(ks, "availrmem");
	if (kn)
	    availrmem = kn->value.ul;
#endif
	kn = kstat_data_lookup(ks, "freemem");
	if (kn)
	    freemem = kn->value.ul;
    }
#endif /* OSREV >= 55 */

#else /* !USE_KSTAT */

  for (i = 0; i < ncpus; i++)
    if (cpu_offset[i] != 0)
    {
      /* get struct cpu for this processor */
      (void) getkval (cpu_offset[i], &cpu, sizeof (struct cpu), "cpu");

      /* sum counters up to, but not including, wait state counter */
      for (j = 0; j < CPU_WAIT; j++)
	cp_time[j] += (long) cpu.cpu_stat.cpu_sysinfo.cpu[j];

      /* add in wait state breakdown counters */
      cp_time[CPUSTATE_IOWAIT] += (long) cpu.cpu_stat.cpu_sysinfo.wait[W_IO] +
                                  (long) cpu.cpu_stat.cpu_sysinfo.wait[W_PIO];
      cp_time[CPUSTATE_SWAP] += (long) cpu.cpu_stat.cpu_sysinfo.wait[W_SWAP];
    }

  /* get load average array */
  (void) getkval (avenrun_offset, (int *) avenrun, sizeof (avenrun), "avenrun");


#endif /* USE_KSTAT */

  /* convert cp_time counts to percentages */
  (void) percentages (CPUSTATES, cpu_states, cp_time, cp_old, cp_diff);

   /* get mpid -- process id of last process */
  if (kd)
    (void) getkval(mpid_offset, &(si->last_pid), sizeof (si->last_pid), "mpid");
  else
    si->last_pid = -1;

  /* convert load averages to doubles */
  for (i = 0; i < 3; i++)
    si->load_avg[i] = loaddouble (avenrun[i]);

  /* get system wide main memory usage structure */
#if 1
  maxmem = sysconf(_SC_PHYS_PAGES);
#else
  (void) getkval (maxmem_offset, (int *) (&maxmem), sizeof (maxmem), "maxmem");
#endif

#if defined(USE_KSTAT) && OSREV >= 55
   if (kd != NULL)		/* always get freemem from kvm if we can*/
#endif
      (void) getkval (freemem_offset, (int *) (&freemem),
		    sizeof (freemem), "freemem");

  memory_stats[0] = pagetok (maxmem);
  memory_stats[1] = 0;
  memory_stats[2] = pagetok (freemem);

#ifdef USE_ANONINFO
  (void) getkval (anoninfo_offset, (int *) (&anoninfo), sizeof (anoninfo), "anoninfo");
#if defined(USE_KSTAT) && OSREV >= 55
   if (kd != NULL)		/* always get availrmem from kvm if we can*/
#endif
      (void) getkval (availrmem_offset, (int *) (&availrmem),
		    sizeof (availrmem), "availrmem");

  (void) getkval (swapfs_minfree_offset, (int *) (&swapfs_minfree), sizeof (swapfs_minfree), "swapfs_minfree");
  memory_stats[3] = pagetok (anoninfo.ani_resv);
  memory_stats[4] = pagetok (MAX ((int) (anoninfo.ani_max - anoninfo.ani_resv), 0) + availrmem - swapfs_minfree);
#else
  get_swapinfo(&swap_total, &swap_free);
  memory_stats[3] = pagetok(swap_total - swap_free);
  memory_stats[4] = pagetok(swap_free);
#endif

  /* set arrays and strings */
  si->cpustates = cpu_states;
  si->memory = memory_stats;
}

static struct handle handle;

caddr_t
get_process_info (
		   struct system_info *si,
		   struct process_select *sel,
		   int (*compare) ())
{
  register int i;
  register int total_procs;
  register int active_procs;
  register struct prpsinfo **prefp;
  register struct prpsinfo *pp;

  /* these are copied out of sel for speed */
  int show_idle;
  int show_system;
  int show_uid;

#ifndef USE_KSTAT
  /* Get current number of processes */
  /* Got this when calling system info if using kstat */
  (void) getkval (nproc_offset, (int *) (&nproc), sizeof (nproc), "nproc");
#endif

  /* read all the proc structures */
  getptable (pbase);

  /* get a pointer to the states summary array */
  si->procstates = process_states;

  /* set up flags which define what we are going to select */
  show_idle = sel->idle;
  show_system = sel->system;
  show_uid = sel->uid != -1;

  /* count up process states and get pointers to interesting procs */
  total_procs = 0;
  active_procs = 0;
  (void) memset (process_states, 0, sizeof (process_states));
  prefp = pref;

  for (pp = pbase, i = 0; i < nproc;
       i++, pp = (struct prpsinfo *) ((char *) pp + PRPSINFOSIZE))
    {
      /*
	 *  Place pointers to each valid proc structure in pref[].
	 *  Process slots that are actually in use have a non-zero
	 *  status field.  Processes with SSYS set are system
	 *  processes---these get ignored unless show_sysprocs is set.
	 */
      if (pp->pr_state != 0 &&
	  (show_system || ((pp->pr_flag & SSYS) == 0)))
	{
	  total_procs++;
	  process_states[pp->pr_state]++;
	  if ((!ZOMBIE(pp)) &&
	      (show_idle || percent_cpu (pp) || (pp->pr_state == SRUN) || (pp->pr_state == SONPROC)) &&
	      (!show_uid || pp->pr_uid == (uid_t) sel->uid))
	    {
	      *prefp++ = pp;
	      active_procs++;
	    }
	}
    }

  /* if requested, sort the "interesting" processes */
  if (compare != NULL)
    qsort ((char *) pref, active_procs, sizeof (struct prpsinfo *), compare);

  /* remember active and total counts */
  si->p_total = total_procs;
  si->p_active = active_procs;

  /* pass back a handle */
  handle.next_proc = pref;
  handle.remaining = active_procs;
  return ((caddr_t) & handle);
}

char fmt[MAX_COLS];			/* static area where result is built */

char *
format_next_process (
		      caddr_t handle,
		      char *(*get_userid) ())
{
  register struct prpsinfo *pp;
  struct handle *hp;
  register long cputime;
  register double pctcpu;
  char sb[10];

  /* find and remember the next proc structure */
  hp = (struct handle *) handle;
  pp = *(hp->next_proc++);
  hp->remaining--;

  /* get the cpu usage and calculate the cpu percentages */
  cputime = pp->pr_time.tv_sec;
  pctcpu = percent_cpu (pp);

  if (pp->pr_state == SONPROC && ncpus > 1)
    sprintf(sb,"cpu/%-2d", pp->pr_onpro); /* XXX large #s may overflow colums */
  else
    *sb = '\0';

  /* format this entry */
  sprintf (fmt,
	   Proc_format,
	   pp->pr_pid,
	   (*get_userid) (pp->pr_uid),
	   (u_short)pp->pr_fill < 999 ? (u_short)pp->pr_fill : 999,
	   pp->pr_pri,
	   pp->pr_nice - NZERO,
	   format_k(SIZE_K(pp)),
	   format_k(RSS_K(pp)),
	   *sb ? sb : state_abbrev[pp->pr_state],
	   format_time(cputime),
	   pctcpu,
	   pp->pr_fname);

  /* return the result */
  return (fmt);
}

/*
 * check_nlist(nlst) - checks the nlist to see if any symbols were not
 *		found.  For every symbol that was not found, a one-line
 *		message is printed to stderr.  The routine returns the
 *		number of symbols NOT found.
 */
int
check_nlist (register struct nlist *nlst)
{
  register int i;

  /* check to see if we got ALL the symbols we requested */
  /* this will write one line to stderr for every symbol not found */

  i = 0;
  while (nlst->n_name != NULL)
    {
      if (nlst->n_type == 0)
	{
	  /* this one wasn't found */
	  fprintf (stderr, "kernel: no symbol named `%s'\n", nlst->n_name);
	  i = 1;
	}
      nlst++;
    }
  return (i);
}


/*
 *  getkval(offset, ptr, size, refstr) - get a value out of the kernel.
 *	"offset" is the byte offset into the kernel for the desired value,
 *  	"ptr" points to a buffer into which the value is retrieved,
 *  	"size" is the size of the buffer (and the object to retrieve),
 *  	"refstr" is a reference string used when printing error meessages,
 *	    if "refstr" starts with a '!', then a failure on read will not
 *  	    be fatal (this may seem like a silly way to do things, but I
 *  	    really didn't want the overhead of another argument).
 *
 */
int
getkval (unsigned long offset,
	 int *ptr,
	 int size,
	 char *refstr)
{
  if (kvm_read (kd, offset, (char *) ptr, size) != size)
    {
      if (*refstr == '!')
	{
	  return (0);
	}
      else
	{
	  fprintf (stderr, "top: kvm_read for %s: %s\n", refstr, strerror(errno));
	  quit (23);
	}
    }
  return (1);

}

/* comparison routines for qsort */

/*
 * There are currently four possible comparison routines.  main selects
 * one of these by indexing in to the array proc_compares.
 *
 * Possible keys are defined as macros below.  Currently these keys are
 * defined:  percent cpu, cpu ticks, process state, resident set size,
 * total virtual memory usage.  The process states are ordered as follows
 * (from least to most important):  WAIT, zombie, sleep, stop, start, run.
 * The array declaration below maps a process state index into a number
 * that reflects this ordering.
 */

/* First, the possible comparison keys.  These are defined in such a way
   that they can be merely listed in the source code to define the actual
   desired ordering.
 */

#define ORDERKEY_PCTCPU  if (dresult = percent_cpu (p2) - percent_cpu (p1),\
			     (result = dresult > 0.0 ? 1 : dresult < 0.0 ? -1 : 0) == 0)
#define ORDERKEY_CPTICKS if ((result = p2->pr_time.tv_sec - p1->pr_time.tv_sec) == 0)
#define ORDERKEY_STATE   if ((result = (long) (sorted_state[p2->pr_state] - \
			       sorted_state[p1->pr_state])) == 0)
#define ORDERKEY_PRIO    if ((result = p2->pr_oldpri - p1->pr_oldpri) == 0)
#define ORDERKEY_RSSIZE  if ((result = p2->pr_rssize - p1->pr_rssize) == 0)
#define ORDERKEY_MEM     if ((result = (p2->pr_size - p1->pr_size)) == 0)

/* Now the array that maps process state to a weight */

unsigned char sorted_state[] =
{
  0,				/* not used		*/
  3,				/* sleep		*/
  6,				/* run			*/
  2,				/* zombie		*/
  4,				/* stop			*/
  5,				/* start		*/
  7,				/* run on a processor   */
  1				/* being swapped (WAIT)	*/
};


/* compare_cpu - the comparison function for sorting by cpu percentage */

int
compare_cpu (
	       struct prpsinfo **pp1,
	       struct prpsinfo **pp2)
  {
    register struct prpsinfo *p1;
    register struct prpsinfo *p2;
    register long result;
    double dresult;

    /* remove one level of indirection */
    p1 = *pp1;
    p2 = *pp2;

    ORDERKEY_PCTCPU
    ORDERKEY_CPTICKS
    ORDERKEY_STATE
    ORDERKEY_PRIO
    ORDERKEY_RSSIZE
    ORDERKEY_MEM
    ;

    return (result);
  }

/* compare_size - the comparison function for sorting by total memory usage */

int
compare_size (
	       struct prpsinfo **pp1,
	       struct prpsinfo **pp2)
  {
    register struct prpsinfo *p1;
    register struct prpsinfo *p2;
    register long result;
    double dresult;

    /* remove one level of indirection */
    p1 = *pp1;
    p2 = *pp2;

    ORDERKEY_MEM
    ORDERKEY_RSSIZE
    ORDERKEY_PCTCPU
    ORDERKEY_CPTICKS
    ORDERKEY_STATE
    ORDERKEY_PRIO
    ;

    return (result);
  }

/* compare_res - the comparison function for sorting by resident set size */

int
compare_res (
	       struct prpsinfo **pp1,
	       struct prpsinfo **pp2)
  {
    register struct prpsinfo *p1;
    register struct prpsinfo *p2;
    register long result;
    double dresult;

    /* remove one level of indirection */
    p1 = *pp1;
    p2 = *pp2;

    ORDERKEY_RSSIZE
    ORDERKEY_MEM
    ORDERKEY_PCTCPU
    ORDERKEY_CPTICKS
    ORDERKEY_STATE
    ORDERKEY_PRIO
    ;

    return (result);
  }

/* compare_time - the comparison function for sorting by total cpu time */

int
compare_time (
	       struct prpsinfo **pp1,
	       struct prpsinfo **pp2)
  {
    register struct prpsinfo *p1;
    register struct prpsinfo *p2;
    register long result;
    double dresult;

    /* remove one level of indirection */
    p1 = *pp1;
    p2 = *pp2;

    ORDERKEY_CPTICKS
    ORDERKEY_PCTCPU
    ORDERKEY_STATE
    ORDERKEY_PRIO
    ORDERKEY_MEM
    ORDERKEY_RSSIZE
    ;

    return (result);
  }

/*
get process table
 V.4 only has a linked list of processes so we want to follow that
 linked list, get all the process structures, and put them in our own
 table
*/
void
getptable (struct prpsinfo *baseptr)
{
  struct prpsinfo *currproc;	/* pointer to current proc structure	*/
#ifndef USE_NEW_PROC
  struct prstatus prstatus;     /* for additional information */
#endif
  int numprocs = 0;
  int i;
  struct dirent *direntp;
  struct oldproc *op;
  static struct timeval lasttime =
  {0, 0};
  struct timeval thistime;
  double timediff;
  double alpha, beta;
  struct oldproc *endbase;

  gettimeofday (&thistime, NULL);
  /*
   * To avoid divides, we keep times in nanoseconds.  This is
   * scaled by 1e7 rather than 1e9 so that when we divide we
   * get percent.
   */
  if (lasttime.tv_sec)
    timediff = ((double) thistime.tv_sec * 1.0e7 +
		((double) thistime.tv_usec * 10.0)) -
      ((double) lasttime.tv_sec * 1.0e7 +
       ((double) lasttime.tv_usec * 10.0));
  else
    timediff = 1.0e7;

  /*
     * constants for exponential average.  avg = alpha * new + beta * avg
     * The goal is 50% decay in 30 sec.  However if the sample period
     * is greater than 30 sec, there's not a lot we can do.
     */
  if (timediff < 30.0e7)
    {
      alpha = 0.5 * (timediff / 30.0e7);
      beta = 1.0 - alpha;
    }
  else
    {
      alpha = 0.5;
      beta = 0.5;
    }

  endbase = oldbase + oldprocs;
  currproc = baseptr;

  /* before reading /proc files, turn on root privs */
  /* (we don't care if this fails since it will be caught later) */
#ifndef USE_NEW_PROC
  seteuid(0);
#endif

  for (rewinddir (procdir); (direntp = readdir (procdir));)
    {
      int fd;
      char buf[30];

      if (direntp->d_name[0] == '.')
	continue;

#ifdef USE_NEW_PROC
      snprintf(buf, sizeof(buf), "%s/psinfo", direntp->d_name);

      if ((fd = open (buf, O_RDONLY)) < 0)
	continue;

      if (read(fd, currproc, sizeof(psinfo_t)) != sizeof(psinfo_t))
	{
	  (void) close (fd);
	  continue;
	}
       
#else
      if ((fd = open (direntp->d_name, O_RDONLY)) < 0)
	continue;

      if (ioctl (fd, PIOCPSINFO, currproc) < 0)
	{
	  (void) close (fd);
	  continue;
	}

      if (ioctl (fd, PIOCSTATUS, &prstatus) < 0)
      {
	  /* not a show stopper -- just fill in the needed values */
	  currproc->pr_fill = 0;
	  currproc->pr_onpro = 0;
       } else {
	  /* copy over the values we need from prstatus */
	  currproc->pr_fill = (short)prstatus.pr_nlwp;
	  currproc->pr_onpro = prstatus.pr_processor;
       }
#endif

      /*
       * SVr4 doesn't keep track of CPU% in the kernel, so we have
       * to do our own.  See if we've heard of this process before.
       * If so, compute % based on CPU since last time.
       * NOTE:  Solaris 2.4 and higher do maintain CPU% in prpsinfo.
       */
      op = oldbase + HASH (currproc->pr_pid);
      while (1)
	{
	  if (op->oldpid == -1)	/* not there */
	    break;
	  if (op->oldpid == currproc->pr_pid)
	    {			/* found old data */
#if (OSREV < 54)
	      percent_cpu (currproc) =
		((currproc->pr_time.tv_sec * 1.0e9 +
		  currproc->pr_time.tv_nsec)
		 - op->oldtime) / timediff;
#endif
	      weighted_cpu (currproc) =
		op->oldpct * beta + percent_cpu (currproc) * alpha;

	      break;
	    }
	  op++;			/* try next entry in hash table */
	  if (op == endbase)	/* table wrapped around */
	    op = oldbase;
	}

      /* Otherwise, it's new, so use all of its CPU time */
      if (op->oldpid == -1)
	{
#if (OSREV >= 54)
	  weighted_cpu (currproc) =
	    percent_cpu (currproc);
#else
	  if (lasttime.tv_sec)
	    {
	      percent_cpu (currproc) =
		(currproc->pr_time.tv_sec * 1.0e9 +
		 currproc->pr_time.tv_nsec) / timediff;
	      weighted_cpu (currproc) =
		percent_cpu (currproc);
	    }
	  else
	    {			/* first screen -- no difference is possible */
	      percent_cpu (currproc) = 0.0;
	      weighted_cpu (currproc) = 0.0;
	    }
#endif
	}

      numprocs++;
      currproc = (struct prpsinfo *) ((char *) currproc + PRPSINFOSIZE);
      (void) close (fd);
#ifdef NO_NPROC
      /* Atypical place for growth */
      if (numprocs >= maxprocs) {
	    reallocproc(2 * numprocs);
	    currproc = (struct prpsinfo *)
		    ((char *)baseptr + PRPSINFOSIZE * numprocs);
      }
#endif
    }

#ifndef USE_NEW_PROC
  /* turn off root privs */
  seteuid(getuid());
#endif

  if (nproc != numprocs)
    nproc = numprocs;

  /*
   * Save current CPU time for next time around
   * For the moment recreate the hash table each time, as the code
   * is easier that way.
   */
  oldprocs = 2 * nproc;
  endbase = oldbase + oldprocs;
  for (op = oldbase; op < endbase; op++)
    op->oldpid = -1;
  for (i = 0, currproc = baseptr;
       i < nproc;
     i++, currproc = (struct prpsinfo *) ((char *) currproc + PRPSINFOSIZE))
    {
      /* find an empty spot */
      op = oldbase + HASH (currproc->pr_pid);
      while (1)
	{
	  if (op->oldpid == -1)
	    break;
	  op++;
	  if (op == endbase)
	    op = oldbase;
	}
      op->oldpid = currproc->pr_pid;
      op->oldtime = (currproc->pr_time.tv_sec * 1.0e9 +
		     currproc->pr_time.tv_nsec);
      op->oldpct = weighted_cpu (currproc);
    }
  lasttime = thistime;
}

/*
 * proc_owner(pid) - returns the uid that owns process "pid", or -1 if
 *              the process does not exist.
 *              It is EXTREMLY IMPORTANT that this function work correctly.
 *              If top runs setuid root (as in SVR4), then this function
 *              is the only thing that stands in the way of a serious
 *              security problem.  It validates requests for the "kill"
 *              and "renice" commands.
 */
uid_t
proc_owner (pid_t pid)
{
  register struct prpsinfo *p;
  int i;
  for (i = 0, p = pbase; i < nproc;
       i++, p = (struct prpsinfo *) ((char *) p + PRPSINFOSIZE)) {
    if (p->pr_pid == pid)
      return (p->pr_uid);
  }
  return (-1);
}

#if OSREV < 55
int
setpriority (int dummy, int who, int niceval)
{
  int scale;
  int prio;
  pcinfo_t pcinfo;
  pcparms_t pcparms;
  tsparms_t *tsparms;

  strcpy (pcinfo.pc_clname, "TS");
  if (priocntl (0, 0, PC_GETCID, (caddr_t) & pcinfo) == -1)
    return (-1);

  prio = niceval;
  if (prio > PRIO_MAX)
    prio = PRIO_MAX;
  else if (prio < PRIO_MIN)
    prio = PRIO_MIN;

  tsparms = (tsparms_t *) pcparms.pc_clparms;
  scale = ((tsinfo_t *) pcinfo.pc_clinfo)->ts_maxupri;
  tsparms->ts_uprilim = tsparms->ts_upri = -(scale * prio) / 20;
  pcparms.pc_cid = pcinfo.pc_cid;

  if (priocntl (P_PID, who, PC_SETPARMS, (caddr_t) & pcparms) == -1)
    return (-1);

  return (0);
}
#endif

#ifndef USE_ANONINFO
get_swapinfo(int *total, int *fr)

{
#ifdef SC_AINFO
    struct anoninfo anon;

    if (swapctl(SC_AINFO, &anon) == -1) {
	*total = *fr = 0;
	return;
    }
    *total = anon.ani_max;
    *fr = anon.ani_max - anon.ani_resv;
#else
    register int cnt, i;
    register int t, f;
    struct swaptable *swt;
    struct swapent *ste;
    static char path[256];

    /* get total number of swap entries */
    cnt = swapctl(SC_GETNSWP, 0);

    /* allocate enough space to hold count + n swapents */
    swt = (struct swaptable *)malloc(sizeof(int) +
				     cnt * sizeof(struct swapent));
    if (swt == NULL)
    {
	*total = 0;
	*fr = 0;
	return;
    }
    swt->swt_n = cnt;

    /* fill in ste_path pointers: we don't care about the paths, so we point
       them all to the same buffer */
    ste = &(swt->swt_ent[0]);
    i = cnt;
    while (--i >= 0)
    {
	ste++->ste_path = path;
    }

    /* grab all swap info */
    swapctl(SC_LIST, swt);

    /* walk thru the structs and sum up the fields */
    t = f = 0;
    ste = &(swt->swt_ent[0]);
    i = cnt;
    while (--i >= 0)
    {
	/* dont count slots being deleted */
	if (!(ste->ste_flags & ST_INDEL) &&
	    !(ste->ste_flags & ST_DOINGDEL))
	{
	    t += ste->ste_pages;
	    f += ste->ste_free;
	}
	ste++;
    }

    /* fill in the results */
    *total = t;
    *fr = f;
    free(swt);
#endif /* SC_AINFO */
}
#endif /* USE_ANONINFO */

/*
 * When we reach a proc limit, we need to realloc the stuff.
 */
static void reallocproc(int n)
{
    int bytes;
    struct oldproc *op, *endbase;

    if (n < maxprocs)
	return;

    maxprocs = n;

    /* allocate space for proc structure array and array of pointers */
    bytes = maxprocs * PRPSINFOSIZE;
    pbase = (struct prpsinfo *) realloc(pbase, bytes);
    pref = (struct prpsinfo **) realloc(pref,
			maxprocs * sizeof(struct prpsinfo *));
    oldbase = (struct oldproc *) realloc(oldbase,
			2 * maxprocs * sizeof(struct oldproc));

    /* Just in case ... */
    if (pbase == (struct prpsinfo *) NULL || pref == (struct prpsinfo **) NULL
	|| oldbase == (struct oldproc *) NULL)
      {
	fprintf (stderr, "%s: can't allocate sufficient memory\n", myname);
	quit(1);
      }

    /*
     * We're growing from 0 to some number, only then we need to
     * init the oldproc stuff
     */
    if (!oldprocs) {
	oldprocs = 2 * maxprocs;

	endbase = oldbase + oldprocs;
	for (op = oldbase; op < endbase; op++)
	  op->oldpid = -1;
    }
}
