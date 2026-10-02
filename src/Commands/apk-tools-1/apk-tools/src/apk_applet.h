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

/* Applets are collected in an explicit table (apk.c) rather than via
   linker-section magic, so the build is portable across GNU ld, ld64,
   and Rhapsody's cctools ld, and works for fat i386+ppc. */
extern struct apk_applet *apk_applets[];
extern const int apk_num_applets;

#endif
