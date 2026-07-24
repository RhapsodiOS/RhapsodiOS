/* apk_applet.h - Alpine Package Keeper (APK)
 *
 * Copyright (C) 2005-2008 Natanael Copa <n@tanael.org>
 * Copyright (C) 2008 Timo Teräs <timo.teras@iki.fi>
 * All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify it 
 * under the terms of the GNU General Public License version 2 as published
 * by the Free Software Foundation. See http://www.gnu.org/ for details.
 */

#ifndef APK_APPLET_H
#define APK_APPLET_H

#include <getopt.h>
#include "apk_defines.h"

extern const char *apk_root;

struct apk_repository_url {
	struct list_head list;
	const char *url;
};

extern struct apk_repository_url apk_repository_list;

struct apk_applet {
	const char *name;
	const char *usage;

	int context_size;
	int num_options;
	struct option *options;

	int (*parse)(void *ctx, int optch, int optindex, const char *optarg);
	int (*main)(void *ctx, int argc, char **argv);
};

#if defined(__linux__)
extern struct apk_applet *__start_apkapplets, *__stop_apkapplets;
#else
/* Mach-O has no auto-generated section boundary symbols like GNU ld;
 * ld64 provides the equivalent via the section$start$/section$end$
 * magic symbol names instead. */
extern struct apk_applet *__start_apkapplets __asm("section$start$__DATA$apkapplets");
extern struct apk_applet *__stop_apkapplets __asm("section$end$__DATA$apkapplets");
#endif

#if defined(__linux__)
#define APK_DEFINE_APPLET(x) \
	static struct apk_applet *__applet_##x \
	__attribute__((__section__("apkapplets"))) __attribute((used)) = &x;
#else
#define APK_DEFINE_APPLET(x) \
	static struct apk_applet *__applet_##x \
	__attribute__((__section__("__DATA,apkapplets"))) __attribute((used)) = &x;
#endif

#endif
