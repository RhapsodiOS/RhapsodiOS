/*
 * generate - build.ninja generator for the RhapsodiOS source tree.
 *
 * Scans the source tree for .../apk/PKGINFO, parses dependencies, and emits
 * a static build graph for samurai (samu) or ninja.
 */

#include "generate.h"
#include "util.h"

#include <ctype.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* ------------------------------------------------------------------ */
/* Project model                                                       */
/* ------------------------------------------------------------------ */

enum arch { ARCH_UNIVERSAL, ARCH_I386, ARCH_PPC };

struct project {
	char *dir;        /* path relative to srcroot, e.g. "Commands/adv_cmds" */
	char *name;       /* filesystem-safe id (dir with '/' -> '_')           */
	char *pkg;        /* pkgname from apk/PKGINFO, lowercased               */
	char **rawdeps;   /* raw builddepend tokens (lowercased)                */
	int   nrawdeps;
	enum arch arch;
	int   is_bootstrap;

	/* resolved dependency stamp targets (strings), filled during emit */
	int   visit;      /* cycle detection: 0=unseen 1=on-stack 2=done       */
};

static struct project *projects = NULL;
static int nprojects = 0;
static int cprojects = 0;

static void reset_projects(void)
{
	int i, j;

	for (i = 0; i < nprojects; i++) {
		free(projects[i].dir);
		free(projects[i].name);
		free(projects[i].pkg);
		for (j = 0; j < projects[i].nrawdeps; j++)
			free(projects[i].rawdeps[j]);
		free(projects[i].rawdeps);
	}
	free(projects);
	projects = NULL;
	nprojects = 0;
	cprojects = 0;
}

static struct project *project_add(void)
{
	if (nprojects == cprojects) {
		cprojects = cprojects ? cprojects * 2 : 64;
		projects = xrealloc(projects, (size_t)cprojects * sizeof(*projects));
	}
	memset(&projects[nprojects], 0, sizeof(projects[nprojects]));
	return &projects[nprojects++];
}

/* The base toolchain set that "build-base" expands to. The -hdrs suffixes
 * are retained deliberately: builds depend only on the *headers* of libc,
 * architecture, kernel and objc4 (not their full builds), so userland does
 * not have to wait for e.g. a full kernel build. Dependency normalization
 * (resolve_token) maps a -hdrs token to the project's headers node. */
static const char *basedeps[] = {
	/* Compiler, Linker, Driver */
	"cc", "cctools", "gnumake",
	/* Makefiles */
	"pb-makefiles", "coreosmakefiles", "project-makefiles",
	/* Shells */
	"zsh", "tcsh",
	/* Base Tools */
	"file-cmds", "text-cmds", "shell-cmds", "developer-cmds",
	"awk", "grep", "gnutar",
	/* Base Libraries */
	"libsystem", "libc-hdrs",
	"architecture-hdrs", "kernel-hdrs",
	"csu", "objc4-hdrs",
	/* Base System */
	"files",
	/* Legacy base tools */
	"basic-cmds", "bootstrap-cmds", "system-cmds",
	NULL
};

/* Strip a -hdrs/-obj suffix from a package token into `out`. */
static void collapse_base(const char *tok, char *out, size_t outsz)
{
	size_t len = strlen(tok);
	if (len >= outsz)
		len = outsz - 1;
	memcpy(out, tok, len);
	out[len] = '\0';
	if (len > 5 && strcmp(out + len - 5, "-hdrs") == 0)
		out[len - 5] = '\0';
	else if (len > 4 && strcmp(out + len - 4, "-obj") == 0)
		out[len - 4] = '\0';
}

/* Kernel aggregate, from the top-level Makefile KERNELPROJECTS. Listed by
 * project directory name. */
static const char *kernel_projects[] = {
	"kernel-7", "machkit-1", "driverkit-3", "kernload-1",
	"driverTools-1", "boot-2",
	NULL
};

/* Is `pkg` one of the base toolchain projects? Compares against the
 * collapsed (suffix-stripped) form of each basedeps entry so that, e.g.,
 * the "kernel-hdrs" entry marks the "kernel" project as bootstrap. */
static int in_basedeps(const char *pkg)
{
	char base[256];
	int i;
	for (i = 0; basedeps[i]; i++) {
		collapse_base(basedeps[i], base, sizeof(base));
		if (strcmp(base, pkg) == 0)
			return 1;
	}
	return 0;
}

/* ------------------------------------------------------------------ */
/* Package -> project lookup                                           */
/* ------------------------------------------------------------------ */

static struct project *find_by_pkg(const char *pkg)
{
	int i;
	for (i = 0; i < nprojects; i++)
		if (projects[i].pkg && strcmp(projects[i].pkg, pkg) == 0)
			return &projects[i];
	return NULL;
}

static struct project *find_by_dir(const char *dir)
{
	int i;
	for (i = 0; i < nprojects; i++)
		if (strcmp(projects[i].dir, dir) == 0)
			return &projects[i];
	return NULL;
}

/* ------------------------------------------------------------------ */
/* PKGINFO parsing                                                     */
/* ------------------------------------------------------------------ */

/* Read an entire file into a NUL-terminated buffer. Returns NULL on error. */
static char *read_file(const char *path)
{
	FILE *f = fopen(path, "rb");
	long sz;
	char *buf;
	size_t got;

	if (!f)
		return NULL;
	if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
	sz = ftell(f);
	if (sz < 0) { fclose(f); return NULL; }
	rewind(f);
	buf = xmalloc((size_t)sz + 1);
	got = fread(buf, 1, (size_t)sz, f);
	buf[got] = '\0';
	fclose(f);
	return buf;
}

static enum arch parse_arch(const char *val)
{
	if (!val)
		return ARCH_UNIVERSAL;
	if (strstr(val, "i386"))
		return ARCH_I386;
	if (strstr(val, "ppc") || strstr(val, "powerpc"))
		return ARCH_PPC;
	return ARCH_UNIVERSAL;
}

/* Split a comma-separated dependency value into lowercased tokens,
 * stripping any "(version)" constraints. */
static void parse_deps(struct project *pr, char *val)
{
	char *tok = val;
	while (tok && *tok) {
		char *comma = strchr(tok, ',');
		char *paren;
		char *t;
		if (comma)
			*comma = '\0';
		paren = strchr(tok, '(');
		if (paren)
			*paren = '\0';
		t = strtrim(tok);
		if (*t) {
			strlower(t);
			pr->rawdeps = xrealloc(pr->rawdeps,
				(size_t)(pr->nrawdeps + 1) * sizeof(char *));
			pr->rawdeps[pr->nrawdeps++] = xstrdup(t);
		}
		if (!comma)
			break;
		tok = comma + 1;
	}
}

/* Extract `key = value` from an apk/PKGINFO buffer. Skips blank lines and
 * `#` comments. Returns a newly-allocated trimmed value or NULL. */
static char *pkginfo_value(const char *buf, const char *key)
{
	const char *p = buf;

	while (*p) {
		const char *line = p;
		const char *nl = strchr(p, '\n');
		size_t linelen = nl ? (size_t)(nl - line) : strlen(line);
		char *eq;
		char *copy, *k, *v;

		if (linelen > 0 && line[linelen - 1] == '\r')
			linelen--;

		if (linelen == 0 || line[0] == '#') {
			if (!nl)
				break;
			p = nl + 1;
			continue;
		}

		copy = xmalloc(linelen + 1);
		memcpy(copy, line, linelen);
		copy[linelen] = '\0';

		eq = strchr(copy, '=');
		if (eq) {
			*eq = '\0';
			k = strtrim(copy);
			if (strcmp(k, key) == 0) {
				v = strtrim(eq + 1);
				{
					char *out = xstrdup(v);
					free(copy);
					return out;
				}
			}
		}
		free(copy);

		if (!nl)
			break;
		p = nl + 1;
	}
	return NULL;
}

/* Register a project from apk/PKGINFO at <dir>/apk/PKGINFO.
 * `dir` is relative to srcroot. */
static void register_project(const char *srcroot, const char *dir)
{
	char path[4096];
	char *buf, *pkg, *bdeps, *archv;
	struct project *pr;
	char *safe;
	size_t i;

	snprintf(path, sizeof(path), "%s/%s/apk/PKGINFO", srcroot, dir);
	buf = read_file(path);
	if (!buf)
		return; /* no PKGINFO; not a buildable project */

	pkg = pkginfo_value(buf, "pkgname");
	if (!pkg) {
		fprintf(stderr, "rhap-build: warning: %s has no pkgname; skipping\n", dir);
		free(buf);
		return;
	}

	pr = project_add();
	pr->dir = xstrdup(dir);

	safe = xstrdup(dir);
	for (i = 0; safe[i]; i++)
		if (safe[i] == '/' || safe[i] == '\\')
			safe[i] = '_';
	pr->name = safe;

	{
		char *t = strtrim(pkg);
		strlower(t);
		pr->pkg = xstrdup(t);
	}
	free(pkg);

	archv = pkginfo_value(buf, "arch");
	pr->arch = parse_arch(archv);
	free(archv);

	bdeps = pkginfo_value(buf, "builddepend");
	if (bdeps) {
		char *p;
		/* Space- or comma-separated; normalize to commas for parse_deps. */
		for (p = bdeps; *p; p++)
			if (*p == ',' || isspace((unsigned char)*p))
				*p = ',';
		parse_deps(pr, bdeps);
		free(bdeps);
	}

	free(buf);
}

/* ------------------------------------------------------------------ */
/* Tree scanning                                                       */
/* ------------------------------------------------------------------ */

static int is_dir(const char *path)
{
	struct stat st;
	if (stat(path, &st) != 0)
		return 0;
	return S_ISDIR(st.st_mode);
}

static int has_pkginfo(const char *srcroot, const char *rel)
{
	char path[4096];
	struct stat st;
	snprintf(path, sizeof(path), "%s/%s/apk/PKGINFO", srcroot, rel);
	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Recursively scan `rel` (relative to srcroot) for directories that contain
 * apk/PKGINFO. Each such directory is registered as a project; we do not
 * descend into a project's own subdirectories. */
static void scan_tree(const char *srcroot, const char *rel, int depth)
{
	char full[4096];
	DIR *d;
	struct dirent *de;

	if (depth > 6)
		return;

	if (rel && *rel)
		snprintf(full, sizeof(full), "%s/%s", srcroot, rel);
	else
		snprintf(full, sizeof(full), "%s", srcroot);

	d = opendir(full);
	if (!d)
		return;

	while ((de = readdir(d)) != NULL) {
		char child[4096];
		char childfull[4096];

		if (de->d_name[0] == '.')
			continue; /* skip ., .., and hidden dirs (.git etc) */
		if (strcmp(de->d_name, "apk") == 0 ||
		    strcmp(de->d_name, "CVS") == 0)
			continue;

		if (rel && *rel)
			snprintf(child, sizeof(child), "%s/%s", rel, de->d_name);
		else
			snprintf(child, sizeof(child), "%s", de->d_name);

		snprintf(childfull, sizeof(childfull), "%s/%s", srcroot, child);
		if (!is_dir(childfull))
			continue;

		if (has_pkginfo(srcroot, child)) {
			register_project(srcroot, child);
			/* do not descend into a registered project */
			continue;
		}

		/* container directory (Commands/, drivers/x86/, ...) */
		scan_tree(srcroot, child, depth + 1);
	}
	closedir(d);
}

/* ------------------------------------------------------------------ */
/* Dependency resolution                                               */
/* ------------------------------------------------------------------ */

/* A resolved dependency: which project, and whether we need its headers
 * node (installhdrs) or full node (install). */
struct resdep {
	struct project *pr;
	int headers; /* 1 = depend on <pr>.hdrs, 0 = depend on <pr>.full */
};

/* Resolve one raw dependency token into 0..1 resdeps appended to *out.
 * build-base is expanded by the caller. */
static void resolve_token(const char *tok, struct project *self,
			  struct resdep **out, int *nout, int *cout)
{
	char base[256];
	int headers = 0;
	struct project *dep;
	size_t len = strlen(tok);

	if (len >= sizeof(base))
		len = sizeof(base) - 1;
	memcpy(base, tok, len);
	base[len] = '\0';

	/* collapse -hdrs / -obj suffixes to the base package */
	if (len > 5 && strcmp(base + len - 5, "-hdrs") == 0) {
		base[len - 5] = '\0';
		headers = 1;
	} else if (len > 4 && strcmp(base + len - 4, "-obj") == 0) {
		base[len - 4] = '\0';
	}

	dep = find_by_pkg(base);
	if (!dep) {
		fprintf(stderr,
			"rhap-build: warning: %s: unknown builddepend '%s' "
			"(no project provides '%s'); skipping\n",
			self->dir, tok, base);
		return;
	}
	if (dep == self)
		return; /* self dependency (e.g. foo-hdrs in foo) is implicit */

	if (*nout == *cout) {
		*cout = *cout ? *cout * 2 : 8;
		*out = xrealloc(*out, (size_t)*cout * sizeof(struct resdep));
	}
	(*out)[*nout].pr = dep;
	(*out)[*nout].headers = headers;
	(*nout)++;
}

/* Compute the resolved full-build dependencies for a project.
 * Bootstrap projects only depend on other bootstrap projects (their
 * cross-dependencies on the wider tree are satisfied by the host bootstrap
 * toolchain); this keeps the base toolchain free of build-order cycles.
 * Non-bootstrap projects depend on the "build-base" aggregate plus their
 * explicit builddepend entries. */
static struct resdep *resolve_deps(struct project *self, int *ndeps)
{
	struct resdep *out = NULL;
	int n = 0, c = 0;
	int i, j;

	for (i = 0; i < self->nrawdeps; i++) {
		const char *tok = self->rawdeps[i];

		if (strcmp(tok, "build-base") == 0) {
			if (self->is_bootstrap)
				continue; /* handled via curated bootstrap order */
			for (j = 0; basedeps[j]; j++)
				resolve_token(basedeps[j], self, &out, &n, &c);
			continue;
		}

		if (self->is_bootstrap) {
			/* only honor deps that are themselves bootstrap projects */
			char base[256];
			size_t len = strlen(tok);
			struct project *dep;
			if (len >= sizeof(base)) len = sizeof(base) - 1;
			memcpy(base, tok, len); base[len] = '\0';
			if (len > 5 && strcmp(base + len - 5, "-hdrs") == 0)
				base[len - 5] = '\0';
			else if (len > 4 && strcmp(base + len - 4, "-obj") == 0)
				base[len - 4] = '\0';
			dep = find_by_pkg(base);
			if (!dep || !dep->is_bootstrap)
				continue;
		}

		resolve_token(tok, self, &out, &n, &c);
	}

	*ndeps = n;
	return out;
}

/* ------------------------------------------------------------------ */
/* Cycle detection                                                     */
/* ------------------------------------------------------------------ */

/* Detect cycles over the full-build dependency graph (headers deps never
 * create cycles because a headers node has no dependants that force the
 * full node first). Prints any cycle found. Returns number of cycles. */
static int *cyc_stack;
static int cyc_top;
static int cyc_count;

static void dfs(struct project *pr)
{
	int ndeps, i;
	struct resdep *deps;
	int idx = (int)(pr - projects);

	pr->visit = 1;
	cyc_stack[cyc_top++] = idx;

	deps = resolve_deps(pr, &ndeps);
	for (i = 0; i < ndeps; i++) {
		struct project *dep = deps[i].pr;
		if (deps[i].headers)
			continue; /* headers edges cannot close a full cycle */
		if (dep->visit == 0) {
			dfs(dep);
		} else if (dep->visit == 1) {
			int k;
			cyc_count++;
			fprintf(stderr, "rhap-build: warning: dependency cycle:\n  ");
			for (k = 0; k < cyc_top; k++)
				fprintf(stderr, "%s -> ", projects[cyc_stack[k]].dir);
			fprintf(stderr, "%s\n", dep->dir);
		}
	}
	free(deps);

	cyc_top--;
	pr->visit = 2;
}

static void detect_cycles(void)
{
	int i;
	cyc_stack = xmalloc((size_t)nprojects * sizeof(int));
	cyc_top = 0;
	cyc_count = 0;
	for (i = 0; i < nprojects; i++)
		projects[i].visit = 0;
	for (i = 0; i < nprojects; i++)
		if (projects[i].visit == 0)
			dfs(&projects[i]);
	free(cyc_stack);
	if (cyc_count)
		fprintf(stderr,
			"rhap-build: %d cycle(s) detected; emitted as order-only "
			"edges (build order among them is unspecified)\n",
			cyc_count);
}

/* ------------------------------------------------------------------ */
/* Emit build.ninja                                                    */
/* ------------------------------------------------------------------ */

static void mark_bootstrap(void)
{
	int i;
	for (i = 0; i < nprojects; i++)
		projects[i].is_bootstrap = in_basedeps(projects[i].pkg);
}

static void topo_visit(int idx, int *state, int *order, int *count);

/* Topologically order the bootstrap projects using their inter-bootstrap
 * dependencies so we can emit a curated, acyclic bootstrap sequence.
 * Fills order[] with project indices; returns count. */
static int topo_bootstrap(int *order)
{
	int count = 0;
	int i;
	int *state; /* 0 unseen, 1 on-stack, 2 done */

	state = xmalloc((size_t)nprojects * sizeof(int));
	for (i = 0; i < nprojects; i++)
		state[i] = 0;

	for (i = 0; i < nprojects; i++)
		if (projects[i].is_bootstrap && state[i] == 0)
			topo_visit(i, state, order, &count);

	free(state);
	return count;
}

static void topo_visit(int idx, int *state, int *order, int *count)
{
	struct project *pr = &projects[idx];
	int j;

	state[idx] = 1;
	for (j = 0; j < pr->nrawdeps; j++) {
		const char *tok = pr->rawdeps[j];
		char base[256];
		size_t len;
		struct project *dep;
		int di;

		if (strcmp(tok, "build-base") == 0)
			continue;
		len = strlen(tok);
		if (len >= sizeof(base)) len = sizeof(base) - 1;
		memcpy(base, tok, len); base[len] = '\0';
		if (len > 5 && strcmp(base + len - 5, "-hdrs") == 0)
			base[len - 5] = '\0';
		else if (len > 4 && strcmp(base + len - 4, "-obj") == 0)
			base[len - 4] = '\0';
		dep = find_by_pkg(base);
		if (!dep || !dep->is_bootstrap || dep == pr)
			continue;
		di = (int)(dep - projects);
		if (state[di] == 0)
			topo_visit(di, state, order, count);
	}
	state[idx] = 2;
	order[(*count)++] = idx;
}

static const char *arch_name(enum arch a)
{
	switch (a) {
	case ARCH_I386: return "i386";
	case ARCH_PPC:  return "ppc";
	default:        return "universal";
	}
}

static void emit(const struct config *cfg)
{
	FILE *f = fopen(cfg->outfile, "wb");
	int i, j;
	int *border;
	int bcount;

	if (!f)
		die(cfg->outfile);

	fprintf(f, "# build.ninja - generated by rhap-build. DO NOT EDIT.\n");
	fprintf(f, "# Regenerate with: ninja/rhap-build generate (see ninja/README.md)\n\n");
	fprintf(f, "ninja_required_version = 1.3\n\n");

	fprintf(f, "srcroot = %s\n", cfg->srcroot);
	fprintf(f, "dstroot = %s\n", cfg->dstroot);
	fprintf(f, "objroot = %s\n", cfg->objroot);
	fprintf(f, "symroot = %s\n", cfg->symroot);
	fprintf(f, "srcbase = %s\n", cfg->srcbase);
	fprintf(f, "toolroot = %s\n", cfg->toolroot);
	fprintf(f, "apkrepo = %s\n", cfg->apkrepo);
	fprintf(f, "rc_archs = %s\n", cfg->rc_archs);
	fprintf(f, "rc_os = %s\n", cfg->rc_os);
	fprintf(f, "wrapper = %s\n", cfg->wrapper);
	fprintf(f, "stampdir = $objroot/.stamps\n\n");

	fprintf(f, "rule buildproj\n");
	fprintf(f, "  command = SRCROOT_TREE=\"$srcroot\" APKREPO=\"$apkrepo\" "
		   "DSTROOT=\"$dstroot\" TOOLROOT=\"$toolroot\" "
		   "sh $wrapper "
		   "\"$proj\" \"$target\" \"$parch\" "
		   "\"$srcbase\" \"$objroot\" \"$symroot\" \"$dstroot\" "
		   "\"$toolroot\" \"$rc_archs\" \"$rc_os\" \"$stamp\"\n");
	fprintf(f, "  description = %s $proj\n\n", "$target");

	fprintf(f, "rule apkindex\n");
	fprintf(f, "  command = APKREPO=\"$apkrepo\" DSTROOT=\"$dstroot\" "
		   "TOOLROOT=\"$toolroot\" "
		   "ninja/rhap-build index \"$apkrepo\"\n");
	fprintf(f, "  description = apk index $apkrepo\n\n");

	/* Per-project edges: a headers node and a full node. */
	for (i = 0; i < nprojects; i++) {
		struct project *pr = &projects[i];
		struct resdep *deps;
		int ndeps;
		const char *an = arch_name(pr->arch);

		/* headers node: make installhdrs */
		fprintf(f, "build $stampdir/%s.hdrs.stamp: buildproj || $wrapper",
			pr->name);
		deps = resolve_deps(pr, &ndeps);
		for (j = 0; j < ndeps; j++) {
			/* headers only need the headers of their deps */
			fprintf(f, " $stampdir/%s.hdrs.stamp", deps[j].pr->name);
		}
		fprintf(f, "\n");
		fprintf(f, "  proj = %s\n", pr->dir);
		fprintf(f, "  target = installhdrs\n");
		fprintf(f, "  parch = %s\n", an);
		fprintf(f, "  stamp = $stampdir/%s.hdrs.stamp\n\n", pr->name);

		/* full node: make install (+ automatic .apk into $apkrepo) */
		fprintf(f, "build $stampdir/%s.full.stamp: buildproj "
			   "$srcroot/%s/apk/PKGINFO || "
			   "$stampdir/%s.hdrs.stamp $wrapper",
			pr->name, pr->dir, pr->name);
		for (j = 0; j < ndeps; j++) {
			if (deps[j].headers)
				fprintf(f, " $stampdir/%s.hdrs.stamp", deps[j].pr->name);
			else
				fprintf(f, " $stampdir/%s.full.stamp", deps[j].pr->name);
		}
		fprintf(f, "\n");
		fprintf(f, "  proj = %s\n", pr->dir);
		fprintf(f, "  target = install\n");
		fprintf(f, "  parch = %s\n", an);
		fprintf(f, "  stamp = $stampdir/%s.full.stamp\n\n", pr->name);

		free(deps);

		/* convenience alias: `samu <dir>` builds the full node */
		fprintf(f, "build %s: phony $stampdir/%s.full.stamp\n\n",
			pr->dir, pr->name);
	}

	/* build-base aggregate: all bootstrap full stamps, emitted in a curated
	 * (topologically sorted) order for readability. */
	border = xmalloc((size_t)nprojects * sizeof(int));
	bcount = topo_bootstrap(border);
	fprintf(f, "build build-base: phony");
	for (i = 0; i < bcount; i++)
		fprintf(f, " $stampdir/%s.full.stamp", projects[border[i]].name);
	fprintf(f, "\n\n");
	free(border);

	/* apkindex: regenerate APK_INDEX.gz whenever any package rebuilds */
	fprintf(f, "build $apkrepo/APK_INDEX.gz: apkindex");
	for (i = 0; i < nprojects; i++)
		fprintf(f, " $stampdir/%s.full.stamp", projects[i].name);
	fprintf(f, "\n\n");
	fprintf(f, "build apkindex: phony $apkrepo/APK_INDEX.gz\n\n");

	/* buildworld: everything (apkindex already waits on all full stamps) */
	fprintf(f, "build buildworld: phony apkindex\n\n");

	/* buildkernel: the kernel project set */
	fprintf(f, "build buildkernel: phony");
	for (i = 0; kernel_projects[i]; i++) {
		struct project *pr = find_by_dir(kernel_projects[i]);
		if (pr)
			fprintf(f, " $stampdir/%s.full.stamp", pr->name);
		else
			fprintf(stderr, "rhap-build: warning: kernel project '%s' "
				"not found\n", kernel_projects[i]);
	}
	fprintf(f, "\n\n");

	fprintf(f, "default buildworld\n");

	fclose(f);
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

static void usage(void)
{
	fprintf(stderr,
"usage: rhap-build generate [options]\n"
"  Generates build.ninja for the RhapsodiOS source tree.\n\n"
"  Options (defaults in brackets; env vars of the same name also honored):\n"
"    --srcroot DIR    source tree root [src]\n"
"    --dstroot DIR    shared install/staging tree [/tmp/rhapsody/dst]\n"
"    --objroot DIR    per-project object roots base [/tmp/rhapsody/obj]\n"
"    --symroot DIR    per-project symbol roots base [/tmp/rhapsody/sym]\n"
"    --srcbase DIR    per-project source roots base [/tmp/rhapsody/src]\n"
"    --toolroot DIR   staged toolchain prefix [=dstroot]\n"
"    --apkrepo DIR    directory for generated .apk files [/tmp/rhapsody/apk]\n"
"    --rc-archs STR   target architectures [\"ppc i386\"]\n"
"    --rc-os STR      RC_OS value [teflon]\n"
"    --wrapper PATH   per-project build wrapper [ninja/buildproj.sh]\n"
"    -o, --out FILE   output ninja file [build.ninja]\n"
"    -h, --help       this help\n");
}

void generate_config_defaults(struct config *cfg)
{
	cfg->srcroot  = env_or("SRCROOT",  "src");
	cfg->dstroot  = env_or("DSTROOT",  "/tmp/rhapsody/dst");
	cfg->objroot  = env_or("OBJROOT",  "/tmp/rhapsody/obj");
	cfg->symroot  = env_or("SYMROOT",  "/tmp/rhapsody/sym");
	cfg->srcbase  = env_or("SRCBASE",  "/tmp/rhapsody/src");
	cfg->toolroot = env_or("TOOLROOT", NULL);
	cfg->apkrepo  = env_or("APKREPO",  "/tmp/rhapsody/apk");
	cfg->rc_archs = env_or("RC_ARCHS", "ppc i386");
	cfg->rc_os    = env_or("RC_OS",    "teflon");
	cfg->wrapper  = env_or("WRAPPER",  "ninja/buildproj.sh");
	cfg->outfile  = "build.ninja";
}

int generate_parse_args(struct config *cfg, int argc, char **argv, int *argi)
{
	int i = *argi;

	for (; i < argc; i++) {
		const char *a = argv[i];

		if (a[0] != '-')
			break;

		if      (!strcmp(a, "--srcroot")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->srcroot = argv[i];
		} else if (!strcmp(a, "--dstroot")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->dstroot = argv[i];
		} else if (!strcmp(a, "--objroot")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->objroot = argv[i];
		} else if (!strcmp(a, "--symroot")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->symroot = argv[i];
		} else if (!strcmp(a, "--srcbase")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->srcbase = argv[i];
		} else if (!strcmp(a, "--toolroot")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->toolroot = argv[i];
		} else if (!strcmp(a, "--apkrepo")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->apkrepo = argv[i];
		} else if (!strcmp(a, "--rc-archs")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->rc_archs = argv[i];
		} else if (!strcmp(a, "--rc-os")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->rc_os = argv[i];
		} else if (!strcmp(a, "--wrapper")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->wrapper = argv[i];
		} else if (!strcmp(a, "-o") || !strcmp(a, "--out")) {
			if (++i >= argc) { usage(); return 1; }
			cfg->outfile = argv[i];
		} else if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
			usage();
			return -1;
		} else {
			fprintf(stderr, "rhap-build: unknown option '%s'\n", a);
			usage();
			return 1;
		}
	}

	*argi = i;
	return 0;
}

int generate_build_ninja(const struct config *cfg)
{
	struct config local = *cfg;

	reset_projects();

	if (!local.toolroot)
		local.toolroot = local.dstroot;

	scan_tree(local.srcroot, "", 0);
	if (nprojects == 0) {
		fprintf(stderr, "rhap-build: no projects found under '%s' "
			"(looked for .../apk/PKGINFO)\n",
			local.srcroot);
		return 1;
	}

	mark_bootstrap();
	detect_cycles();
	emit(&local);

	fprintf(stderr, "rhap-build: wrote %s (%d projects)\n",
		local.outfile, nprojects);
	return 0;
}
