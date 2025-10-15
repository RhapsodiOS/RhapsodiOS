/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Server-side procedure implementation
 * Copyright (C) 1989 by NeXT, Inc.
 */
#include "ni_server.h"
#include "mm.h"
#include "system.h"
#include "ni_globals.h"
#include "checksum.h"
#include "notify.h"
#include "ni_dir.h"
#include "socket_lock.h"
#include "alert.h"
#include "getstuff.h"
#include "proxy_pids.h"
#include <sys/socket.h>
#include "sanitycheck.h"
#include "multi_call.h"
#include <sys/time.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <mach/cthreads.h>
#include <sys/wait.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/param.h>
#include <sys/signal.h>
#include <sys/stat.h>
#include <rpc/rpc.h>
#include <rpc/pmap_clnt.h>
#include "bootparam_prot.h"

#ifdef __SLICK__
/* Support the old rpcgen, which doesn't append the _svc suffix
 * to server side stubs.
 */
#define	_ni_ping_2_svc		_ni_ping_2
#define _ni_statistics_2_svc	_ni_statistics_2
#define _ni_root_2_svc		_ni_root_2
#define _ni_self_2_svc		_ni_self_2
#define _ni_parent_2_svc	_ni_parent_2
#define _ni_children_2_svc	_ni_children_2
#define _ni_create_2_svc	_ni_create_2
#define _ni_destroy_2_svc	_ni_destroy_2
#define _ni_read_2_svc		_ni_read_2
#define _ni_write_2_svc		_ni_write_2
#define _ni_lookup_2_svc	_ni_lookup_2
#define _ni_lookupread_2_svc	_ni_lookupread_2
#define _ni_list_2_svc		_ni_list_2
#define _ni_listall_2_svc	_ni_listall_2
#define _ni_readprop_2_svc	_ni_readprop_2
#define _ni_writeprop_2_svc	_ni_writeprop_2
#define _ni_listprops_2_svc	_ni_listprops_2
#define _ni_createprop_2_svc	_ni_createprop_2
#define _ni_destroyprop_2_svc	_ni_destroyprop_2
#define _ni_renameprop_2_svc	_ni_renameprop_2
#define _ni_createname_2_svc	_ni_createname_2
#define _ni_writename_2_svc	_ni_writename_2
#define _ni_readname_2_svc	_ni_readname_2
#define _ni_destroyname_2_svc	_ni_destroyname_2
#define _ni_bind_2_svc		_ni_bind_2
#define _ni_rparent_2_svc	_ni_rparent_2
#define _ni_crashed_2_svc	_ni_crashed_2
#define _ni_readall_2_svc	_ni_readall_2
#define _ni_resync_2_svc	_ni_resync_2
#endif /* __SLICK__ */

CLIENT *svctcp_getclnt(SVCXPRT *xprt);

#define MAXINTSTRSIZE sizeof("4294967296") /* size of largest integer */

#define NI_SEPARATOR '/'		/* separator for netinfo values */

/*
 * These definitions are used when doing the search for the parent. When
 * a timeout occurs because we are unable to find the parent server, we
 * sleep for 10 seconds, checking once a second to see if the user decided
 * to abort the search. After 30 seconds, the search is continued again.
 */
#define PARENT_NINTERVALS 10 	
#define PARENT_SLEEPTIME 1	

/*
 * How long to sleep after catching an rparent reply.
 * This reduces a flood of ICMP port unreachable messages.
 */
#define RPARENT_CATCH_SLEEP_SECONDS 2

/*
 * How long to wait when pinging a parent server to see if it is still
 * alive. Ping once every two seconds, ten seconds total.
 */
#define PING_TIMEOUT  10
#define PING_TRIES    5		/* number of retries for above */

/* Number of minutes to force between attempts to see if we are still / */

#define NETROOT_TIMEOUT_MINS	30

/* Hack for determining if an IP address is a broadcast address. -GRS */
/* Note that addr is network byte order (big endian) - BKM */

#define IS_BROADCASTADDR(addr)	(((unsigned char *) &addr)[0] == 0xFF)

extern bool_t readall();
static int ni_ping(u_long, ni_name);

extern void setproctitle(char *fmt, ...);

extern const char netinfod_VERS_NUM[];
extern int have_notifications_pending(void);

/* for getting language */
#define NAME_LOCALCONFIG "localconfig"
#define NAME_LANGUAGE "language"

#define BOOTPARAM_FILEID (bp_fileid_t)"netinfo_parent"
#define BOOTPARAM_TAG "-BOOTPARAMS-"

static struct in_addr bootparam_addr;
static char *bootparam_tag;

/*
 * Is this call an update from the master?
 * XXX: the method used is to look for a privileged port from the master
 * server. There is no way to distinguish this from a call from a root
 * user on the master (versus the master server process).
 */
static int
isupdate(
	 struct svc_req *req
	 )
{
	struct sockaddr_in *sin = svc_getcaller(req->rq_xprt);

	/*
	 * XXX: Do not allow the client library as root to look
	 * like an update. Since the client library always sets AUTH_UNIX,
	 * and updates never do, we can safely test for AUTH_UNIX.
	 */
	if (req->rq_cred.oa_flavor == AUTH_UNIX) {
		return (FALSE);
	}
	/*
	 * XXX: Master could have multiple addresses: should check all of
	 * them.
	 */
	return (sin->sin_addr.s_addr == master_addr && 
		ntohs(sin->sin_port) < IPPORT_RESERVED);
}

/*
 * Authenticate a NetInfo call. Only required for write operations.
 * NetInfo uses passwords for authentications, but does not send them
 * in the clear. Instead, a trivial authentication system is used to
 * defeat packet browsers.
 *
 * UNIX-style RPC authentication is used, with a gross hack that the encrypted
 * password is placed in the machine-name field.
 *
 * XXX: design a better authentication system (non-trivial!)
 */
static ni_status
authenticate(
	     void *ni,
	     struct svc_req *req
	     )
{
	struct sockaddr_in *sin = svc_getcaller(req->rq_xprt);
	struct authunix_parms *aup;
	char *p;
	ni_namelist nl;
	ni_status status;
	ni_id id;
	ni_idlist idl;
	char uidstr[MAXINTSTRSIZE];
	int u, found;

	/*
	 * Root on the local machine can do anything
	 */
	if (sys_ismyaddress(sin->sin_addr.s_addr) && 
	    ntohs(sin->sin_port) < IPPORT_RESERVED) {
		ni_setuser(ni, ACCESS_USER_SUPER);
		return (NI_OK);
	}
	if (req->rq_cred.oa_flavor != AUTH_UNIX) {
		ni_setuser(ni, NULL);
		return (NI_OK);
	}
	aup = (struct authunix_parms *)req->rq_clntcred;
	/*
	 * Pull user-supplied password out of RPC message.
	 * Our trivial encryption scheme just inverts the bits
	 */
	for (p = aup->aup_machname; *p; p++) *p = ~(*p);

	status = ni_root(ni, &id);
	if (status != NI_OK) {
		return (status);
	}

	/*
	 * Get /users directory
	 */
	NI_INIT(&idl);
	status = ni_lookup(ni, &id, NAME_NAME, NAME_USERS, &idl);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ERR,
		       "Cannot authenticate user %d from %s:%hu - no /%s "
		       "directory: %s", aup->aup_uid,
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port),
		       NAME_USERS,
		       ni_error(status));
		auth_count[BAD]++;
		return (status == NI_NODIR ? NI_NOUSER : status);
	}

	id.nii_object = idl.niil_val[0];
	ni_idlist_free(&idl);

	/*
	 * Find all users with this uid
	 */
	sprintf(uidstr, "%d", aup->aup_uid);
	NI_INIT(&idl);
	status = ni_lookup(ni, &id, NAME_UID, uidstr, &idl);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ERR, "Cannot find user %d from %s:%hu: %s",
		       aup->aup_uid,
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port),
		       ni_error(status));
		auth_count[BAD]++;
		return (status == NI_NODIR ? NI_NOUSER : status);
	}

	/*
	 * Check each user for a password match
	 */
	found = 0;
	for (u = 0; u < idl.ni_idlist_len; u++) {
		id.nii_object = idl.ni_idlist_val[u];
		NI_INIT(&nl);
		status = ni_lookupprop(ni, &id, NAME_PASSWD, &nl);
		if (status == NI_OK) {
			if ((nl.ninl_len == 0) || (nl.ninl_val[0][0] == '\0'))
			{
				/*
				 * Free Parking: user has no password
				 */
				found = 1;
				ni_namelist_free(&nl);
				break;
			}

			if (!strcmp(nl.ninl_val[0],
				crypt(aup->aup_machname, nl.ninl_val[0])) != 0)
			{
				/*
				 * Password match
				 */
				found = 1;
				ni_namelist_free(&nl);
				break;
			}
		}
		ni_namelist_free(&nl);
	}

	ni_idlist_free(&idl);
	if (!found) {
		/*
		 * No user with this uid with no password or a matching password
		 */
		sys_msg(debug, LOG_ERR, "Authentication error for user "
		       "%d from %s:%hu",
		       aup->aup_uid,
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port),
		       ni_error(status));
		auth_count[BAD]++;
		return (NI_AUTHERROR);
	}

	NI_INIT(&nl);
	status = ni_lookupprop(ni, &id, NAME_NAME, &nl);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ERR,
		       "User %d from %s:%hu - name prop not found during "
		       "authentication",
		       aup->aup_uid,
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port),
		       ni_error(status));
		auth_count[BAD]++;
		return (status == NI_NOPROP ? NI_NOUSER : status);
	}
	if (nl.ninl_len == 0) {
		sys_msg(debug, LOG_ERR,
		       "User %d from %s:%hu - name value not found during "
		       "authentication",
		       aup->aup_uid,
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port));
		auth_count[BAD]++;
		return (NI_NOUSER);
	}

	/* If the user has uid 0, allow root access */
	if (aup->aup_uid == 0) ni_setuser(ni, ACCESS_USER_SUPER); 
	else ni_setuser(ni, nl.ninl_val[0]);

	auth_count[GOOD]++;
	sys_msg(debug, LOG_NOTICE,
		"Authenticated user %s [%d] from %s:%hu", 
		nl.ninl_val[0], aup->aup_uid,
		inet_ntoa(sin->sin_addr), ntohs(sin->sin_port));

	ni_namelist_free(&nl);
	return (NI_OK);
}

/*
 * Validate a read-only call. A read-only call is 
 * allowed from any trusted host, but the authentication
 * information needs to be reset.
 */
static ni_status
validate_read(
	      struct svc_req *req
	      )
{
	ni_status status;
	struct sockaddr_in *sin = svc_getcaller(req->rq_xprt);
	bool_t unprivileged = (ntohs(sin->sin_port) >= IPPORT_RESERVED);
	bool_t remote = !sys_ismyaddress(sin->sin_addr.s_addr);

	status = NI_OK;
	ni_setuser(db_ni, NULL);
	ni_setunprivileged(db_ni, unprivileged);
	ni_setremote(db_ni, remote);
	return (status);
}	

/*
 * Validate that a privileged call is allowed. A privileged call is 
 * allowed only from a privileged port on a trusted host.
 * Privileged calls include LISTALL, CRASHED, READALL, and RESYNC.
 */
static ni_status
validate_privileged(
	 	    struct svc_req *req
		    )
{
	ni_status status;
	struct sockaddr_in *sin = svc_getcaller(req->rq_xprt);
	bool_t unprivileged = (ntohs(sin->sin_port) >= IPPORT_RESERVED);
	bool_t remote = !sys_ismyaddress(sin->sin_addr.s_addr);

	status = NI_OK;
	ni_setuser(db_ni, NULL);
	ni_setunprivileged(db_ni, unprivileged);
	ni_setremote(db_ni, remote);
	if (unprivileged) {
		status = NI_AUTHERROR;
		sys_msg(debug, LOG_ERR, "Privileged call from unprivileged port "
		       "%s:%hu: %s",
		       inet_ntoa(sin->sin_addr), ntohs(sin->sin_port),
		       ni_error(status));
	}
	return (status);
}

/*
 * Validate that a write-call is allowed. A write call is allowed
 * to the master if the user is correctly authenticated and permission
 * is allowed. To the clone, the write is only allowed if it comes
 * from the master (an update).
 */
static ni_status
validate_write(
	       struct svc_req *req
	       )
{
	ni_status status;

	status = NI_OK;
	ni_setuser(db_ni, NULL);
	ni_setunprivileged(db_ni, FALSE);
	ni_setremote(db_ni, FALSE);
	if (i_am_clone) {
		if (!isupdate(req)) {
			status = NI_RDONLY;
		} else {
			ni_setuser(db_ni, ACCESS_USER_SUPER);
		}
	} else {
		status = authenticate(db_ni, req);
	}
	/*
	 * Do master side of readall in separate process.
	 * We need to lock out modifications during a readall, to
	 * avoid just needing another one far too soon.  Since all
	 * the modifcations come through here, this is a good place
	 * to enforce things.
	 */
	if ((sending_all > 0) || db_lockup) {
	    status = NI_MASTERBUSY;
	}
	return (status);
}

/*
 * The NetInfo PING procedure
 */
void *
_ni_ping_2_svc(
	   void *arg,
	   struct svc_req *req
	   )
{
	return ((void *)~0);
}

/*
 * The NetInfo statistics procedure
 */
ni_proplist *
_ni_statistics_2_svc(
		 void *arg,
		 struct svc_req *req
		 )
{
	/*
	 * Statistics are updated in ni_prog_2_svc() in ni_prot_svc.c,
	 * which lives in SYMS/netinfod_syms.
	 *
	 * XXX This definition really belongs in ni.x, but we're not
	 * going to muck with the protocol definition file at this time.
	 * This definition must be shared with ni_prot_svc.c
	 */
	extern struct ni_stats {
		unsigned long ncalls;
		unsigned long time;
	    } netinfod_stats[];
	#define STATS_PROCNUM	0
	#define STATS_NCALLS	1
	#define STATS_TIME	2
	#define N_STATS_VALS	(STATS_TIME+1)
	int total_calls = 0;		/* We'll total things here */

	extern char *procname(int);

	static struct in_addr addr;		/* For our address */

	/*
	 * Sizes of values, excluding call stats
	 * Note: for properties with multiple values the size should reflect the
	 *       max space required for any one value.
	 */
	static int props_sizes[] = {
	    MAXINTSTRSIZE,	/* checksum: */
	    BUFSIZ,		/* server_version: */
	    NI_NAME_MAXLEN+1,	/* tag: max(NI_NAME_MAXLEN+1, 7, MAXINTSTRSIZE) */
	    16,			/* ip_address: "xxx.yyy.zzz.www" */
	    MAXHOSTNAMELEN + 1,	/* hostname: */
	    MAXINTSTRSIZE + 17,	/* write_locked: strlen(SENDING_ALLn_STG)+MAXINTSTRSIZE */
	    MAXINTSTRSIZE,	/* notify_threads: 3 of MAXINTSTRSIZE */
	    MAXINTSTRSIZE,	/* notifications_pending: */
	    MAXINTSTRSIZE,	/* authentications: 4 of MAXINTRSTRSIZE */
	    MAXINTSTRSIZE,	/* readall_proxies: max(MAXINTSTRSIZE, "strict"|"loose") */
	    MAXINTSTRSIZE,	/* cleanup_wait: */
	    MAXINTSTRSIZE,	/* total_calls: */
	    NI_NAME_MAXLEN+1+16	/* binding: "xxx.yyy.zzz.www/tag" */
	};

#define wProps(i, fmt, val) \
	wPropsN(i,0, fmt, val)
#define wPropsN(i, j, fmt, val) \
	(void)sprintf(props[i].nip_val.ni_namelist_val[j], fmt, val)

	static ni_property props[] = {
	    {"checksum", {1, NULL}},
#define P_CHECKSUM 0
	    {"server_version", {1, NULL}},
#define P_VERSION 1
	    /*
	     * tag can have two or three values.  If master, there'll
	     * be 3; if clone, 2.  We'll allocate space for 3, to
	     * simplify the code.
	     */
	    {"tag", {3, NULL}},	/* tag; master & #clones, or clone */
#define P_TAG 2
#define STATS_TAG 0
#define STATS_MASTER 1
#define STATS_NCLONES 2
	    {"ip_address", {1, NULL}},
#define P_ADDR 3
	    {"hostname", {1, NULL}},
#define P_HOST 4
	    {"write_locked", {1, NULL}},
#define P_LOCKED 5
#define SENDING_ALL1_STG "Yes (a readall)"
#define SENDING_ALLn_STG "Yes (%u readalls)"
#define READING_ALL_STG "clone%s"
	    {"notify_threads", {3, NULL}},	/* max, current, latency */
#define P_THREADS 6
#define STATS_THREADS_USED 0
#define STATS_THREADS_MAX 1
#define STATS_THREADS_LATENCY 2
	    {"notifications_pending", {1, NULL}},
#define P_PENDING 7
	    {"authentications", {4, NULL}},	/* {user,dir}:{good,bad} */
#define P_AUTHS 8
	    {"readall_proxies", {2, NULL}},	/* max, strict */
#define P_PROXIES 9
#define STATS_PROXIES 0
#define STATS_PROXIES_STRICT 1
	    {"cleanup_wait", {2, NULL}},	/* minutes (!), remaining */
#define P_CLEANUP 10
#define STATS_CLEANUPTIME 0
#define STATS_CLEANUP_TOGO 1
	    {"total_calls", {1, NULL}},
#define P_CALLS 11
	    {"binding", {1, NULL}},		/* unknown, notResponding, addr/tag, root, forcedRoot */
#define P_BINDING 12
	    /*
	     * 3 values of following properties:
	     * procnum, ncalls, time (usec)
	     */
#define PROC_STATS_START	13
	    {NULL, {N_STATS_VALS, NULL}},	/* 0: ping */
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},	/* 10: lookup */
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},	/* 20: readname */
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}},
	    {NULL, {N_STATS_VALS, NULL}}	/* 28: lookupread */
	};

	int i, j;
	static unsigned char first_time = TRUE;
	static ni_proplist res;

	if (req == NULL) {
		return (NULL);
	}
	if (validate_read(req) != NI_OK) {
		return (NULL);
	}

	if (first_time) {
	    /* Save myself some typing (and static memory)... */
	    first_time = FALSE;
	    for (i = 0; i < PROC_STATS_START; i++) {
		/* Initialize the props other than call stats */
		if (NULL == (props[i].nip_val.ni_namelist_val =
			(ni_name *)malloc(props[i].nip_val.ni_namelist_len *
					  sizeof(ni_name)))) {
		    sys_msg(debug, LOG_ALERT, 
				"Couldn't allocate memory for statistics");
		}
		for (j = 0; j < props[i].nip_val.ni_namelist_len; j++) {
		    if (NULL == (props[i].nip_val.ni_namelist_val[j] =
				    (ni_name)malloc(props_sizes[i]))) {
				sys_msg(debug, LOG_ALERT, 
					"Couldn't allocate memory for statistics");
		    }
		}
	    }
	    for (i = PROC_STATS_START;
		 i <= PROC_STATS_START+_NI_LOOKUPREAD;
		 i++) {
		/* Initialize the call stats */
		props[i].nip_name = procname(i - PROC_STATS_START);
		if (NULL == (props[i].nip_val.ni_namelist_val =
				(ni_name *)malloc(sizeof(ni_name) *
						    N_STATS_VALS))) {
				sys_msg(debug, LOG_ALERT, 
					"Couldn't allocate memory for statistics");
		}
		for (j = 0; j < N_STATS_VALS; j++) {
		    if (NULL == (props[i].nip_val.ni_namelist_val[j] = 
				    (ni_name)malloc(MAXINTSTRSIZE+1))) {
				sys_msg(debug, LOG_ALERT, 
					"Couldn't allocate memory for statistics");
		    }
		}
		/* Set up the (static) procedure number */
		wPropsN(i, STATS_PROCNUM, "%u", i - PROC_STATS_START);
	    }

	    /* generate static information */

	    /* server_version */
	    wProps(P_VERSION, "%s", netinfod_VERS_NUM);

	    /* tag: tag, master (w/# clones) or clone */
	    wPropsN(P_TAG, STATS_TAG, "%s", db_tag);
	    if (!i_am_clone) {
		wPropsN(P_TAG, STATS_MASTER, "%s", "master");
		props[P_TAG].nip_val.ni_namelist_len = 3;
	    } else {
		wPropsN(P_TAG, STATS_MASTER, "%s", "clone");
		props[P_TAG].nip_val.ni_namelist_len = 2;
	    }

	    /* ip_address */
	    addr.s_addr = sys_address();
	    wProps(P_ADDR, "%s", inet_ntoa(addr));

	    /* hostname */
	    wProps(P_HOST, "%s", sys_hostname());

	}

	/* checksum */
	wProps(P_CHECKSUM, "%u", db_checksum);

	/* identify whether the extended statistics should be returned */
	if (req->rq_cred.oa_flavor == AUTH_UNIX) {
		struct authunix_parms *aup;
		char *p;
		
		aup = (struct authunix_parms *)req->rq_clntcred;
		/*
		 * Pull the user-supplied password out of RPC message
		 * and undo the (trivial) encryption scheme.
		 */
		for (p = aup->aup_machname; *p; p++) *p = ~(*p);

		if (strcmp(aup->aup_machname, "checksum") == 0) {
			res.ni_proplist_len =  1;	/* assumes "checksum" is first property */
			res.ni_proplist_val = props;
			return (&res);
		}
	}

	/* tag: tag, master (w/# clones) or clone */
	if (!i_am_clone) {
	    wPropsN(P_TAG, STATS_NCLONES, "%d", count_clones());
	}

	/* write_locked */
	if (i_am_clone) {
	    wProps(P_LOCKED, READING_ALL_STG,
		   reading_all ? " (reading all)" : "");
	} else if (sending_all > 0) {
	    wProps(P_LOCKED,
		   1 == sending_all ? SENDING_ALL1_STG : SENDING_ALLn_STG,
		   sending_all);
	} else if (db_lockup) {
	    /* If this is longer than SENDING_ALLn_STG, change props_sizes */
	    wProps(P_LOCKED, "%s", "Yes (due to SIGINT)");
	} else {
	    wProps(P_LOCKED, "%s", "No");
	}

	/* notify_threads: current, max, latency */
	wPropsN(P_THREADS, STATS_THREADS_USED, "%u",
		count_notify_subthreads());
	wPropsN(P_THREADS, STATS_THREADS_MAX, "%u", max_subthreads);
	wPropsN(P_THREADS, STATS_THREADS_LATENCY, "%u", update_latency_secs);

	/* notifications_pending */
	wProps(P_PENDING, "%u", notifications_pending());

	/* Authentications, good and bad */
	wPropsN(P_AUTHS, GOOD, "%u", auth_count[GOOD]);
	wPropsN(P_AUTHS, BAD, "%u", auth_count[BAD]);
	wPropsN(P_AUTHS, WGOOD, "%u", auth_count[WGOOD]);
	wPropsN(P_AUTHS, WBAD, "%u", auth_count[WBAD]);

	/* readall_proxies: max, strict */
	wPropsN(P_PROXIES, STATS_PROXIES, "%d", max_readall_proxies);
	wPropsN(P_PROXIES, STATS_PROXIES_STRICT, "%s",
		      strict_proxies ? "strict" : "loose");

	/* cleanup_wait (in seconds internally, in minutes externally!) */
	wPropsN(P_CLEANUP, STATS_CLEANUPTIME, "%d", cleanupwait/60);
	wPropsN(P_CLEANUP, STATS_CLEANUP_TOGO, "%ld",
	       cleanupwait < 0 ? -1 : (cleanuptime - sys_time())/60);

	/* current binding status */
	if (forcedIsRoot)
	{
		wProps(P_BINDING, "%s", "forcedRoot");
	}
	else
	{
		switch ((ni_status) latestParentStatus)
		{
			case NI_NORESPONSE:
				wProps(P_BINDING,  "%s", "notResponding");
				break;
			case NI_NETROOT:
				wProps(P_BINDING,  "%s", "root");
				break;
			case NI_OK:
				wProps(P_BINDING, "%s", latestParentInfo);
				break;
			case NI_NOTMASTER:
			default:
				wProps(P_BINDING,  "%s", "unknown");
				break;
		}
	}

	/* We'll return to total_calls later */

	/* Loop through the call stats. */
	for (i = PROC_STATS_START;
	     i <= PROC_STATS_START + _NI_LOOKUPREAD;
	     i++) {
	    wPropsN(i, STATS_NCALLS, "%lu",
		    netinfod_stats[i - PROC_STATS_START].ncalls);
	    wPropsN(i, STATS_TIME, "%lu",
		    netinfod_stats[i - PROC_STATS_START].time);
	    total_calls += netinfod_stats[i - PROC_STATS_START].ncalls;
	}
	wProps(P_CALLS, "%u", total_calls);

	res.ni_proplist_len = PROC_STATS_START+(_NI_LOOKUPREAD+1);
	res.ni_proplist_val = props;

	return (&res);
}

/*
 * The NetInfo ROOT procedure
 */
ni_id_res *
_ni_root_2_svc(
	   void *arg,
	   struct svc_req *req
	   )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.status = ni_root(db_ni, &res.ni_id_res_u.id);
	return (&res);
}

/*
 * The NetInfo SELF procedure
 */
ni_id_res *
_ni_self_2_svc(
	   ni_id *arg,
	   struct svc_req *req
	   )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = *arg;
	res.status = ni_self(db_ni, &res.ni_id_res_u.id);
	return (&res);
}

/*
 * The NetInfo PARENT procedure
 */
ni_parent_res * 
_ni_parent_2_svc(
	     ni_id *arg,
	     struct svc_req *req
	     )
{
	static ni_parent_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_parent_res_u.stuff.self_id = *arg;
	res.status = ni_parent(db_ni, &res.ni_parent_res_u.stuff.self_id,
			       &res.ni_parent_res_u.stuff.object_id);
	return (&res);
}

/*
 * The NetInfo CHILDREN procedure
 */
ni_children_res *
_ni_children_2_svc(
	       ni_id *arg,
	       struct svc_req *req
	       )
{
	static ni_children_res res;

	ni_idlist_free(&res.ni_children_res_u.stuff.children);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_children_res_u.stuff.self_id = *arg;
	res.status = ni_children(db_ni, &res.ni_children_res_u.stuff.self_id, 
				 &res.ni_children_res_u.stuff.children);
	return (&res);
}

/*
 * The NetInfo CREATE procedure
 */
ni_create_res *
_ni_create_2_svc(
	     ni_create_args *arg,
	     struct svc_req *req
	     )
{
	static ni_create_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	if (arg->target_id != NULL) {
		res.ni_create_res_u.stuff.id = *arg->target_id;
	} else {
		res.ni_create_res_u.stuff.id.nii_object = NI_INDEX_NULL;
	}
	res.ni_create_res_u.stuff.self_id = arg->id;
	res.status = ni_create(db_ni, &res.ni_create_res_u.stuff.self_id, 
			       arg->props, &res.ni_create_res_u.stuff.id,
			       arg->where);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			if (arg->target_id == NULL) {
				MM_ALLOC(arg->target_id);
				*arg->target_id = res.ni_create_res_u.stuff.id;
			}
			notify_clients(_NI_CREATE, arg);
		}
		checksum_inc(&db_checksum, 
			     res.ni_create_res_u.stuff.self_id);
		checksum_add(&db_checksum, res.ni_create_res_u.stuff.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo DESTROY procedure
 */
ni_id_res *
_ni_destroy_2_svc(
	      ni_destroy_args *arg,
	      struct svc_req *req
	      )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->parent_id;
	res.status = ni_destroy(db_ni, &res.ni_id_res_u.id, arg->self_id);
	if (res.status == NI_OK) {
		/* 
		 * Must compute checksum first, because notify_clients
		 * destroys argument
		 */
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
		checksum_rem(&db_checksum, arg->self_id);
		if (!i_am_clone) {
			notify_clients(_NI_DESTROY, arg);
		}
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo READ procedure
 */
ni_proplist_res *
_ni_read_2_svc(
	   ni_id *arg,
	   struct svc_req *req
	   )
{
	static ni_proplist_res res;

#if !ENABLE_CACHE
	ni_proplist_free(&res.ni_proplist_res_u.stuff.props);
#endif
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_proplist_res_u.stuff.id = *arg;
	res.status = ni_read(db_ni, &res.ni_proplist_res_u.stuff.id, 
			     &res.ni_proplist_res_u.stuff.props);
	return (&res);
}

/*
 * The NetInfo WRITE procedure
 */
ni_id_res *
_ni_write_2_svc(
	    ni_proplist_stuff *arg,
	    struct svc_req *req
	    )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_write(db_ni, &res.ni_id_res_u.id, arg->props);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_WRITE, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo LOOKUP procedure
 */
ni_lookup_res *
_ni_lookup_2_svc(
	     ni_lookup_args *arg,
	     struct svc_req *req
	     )
{
	static ni_lookup_res res;

	ni_idlist_free(&res.ni_lookup_res_u.stuff.idlist);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_lookup_res_u.stuff.self_id = arg->id;
	res.status = ni_lookup(db_ni, &res.ni_lookup_res_u.stuff.self_id,
			       arg->key, arg->value, 
			       &res.ni_lookup_res_u.stuff.idlist);
	return (&res);
}

/*
 * The NetInfo LOOKUPREAD procedure
 */
ni_proplist_res *
_ni_lookupread_2_svc(
		 ni_lookup_args *arg,
		 struct svc_req *req
		 )
{
	static ni_proplist_res res;

#if !ENABLE_CACHE
	ni_proplist_free(&res.ni_proplist_res_u.stuff.props);
#endif
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_proplist_res_u.stuff.id = arg->id;
	res.status = ni_lookupread(db_ni, 
				   &res.ni_proplist_res_u.stuff.id,
				   arg->key, arg->value, 
				   &res.ni_proplist_res_u.stuff.props);
	return (&res);
}

/*
 * The NetInfo LIST procedure
 */
ni_list_res *
_ni_list_2_svc(
	   ni_name_args *arg,
	   struct svc_req *req
	   )
{
	static ni_list_res res;

	if (req == NULL) {
		ni_list_const_free(db_ni);
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_list_res_u.stuff.self_id = arg->id;
	res.status = ni_list_const(db_ni, &res.ni_list_res_u.stuff.self_id,
				   arg->name, 
				   &res.ni_list_res_u.stuff.entries);
	return (&res);
}

/*
 * WARNING: this function is dangerous and may be removed in future
 * implementations of the protocol.
 * While it is easier on the network, it eats up too much time on the
 * server and interrupts service for others.
 * 
 * PLEASE DO NOT CALL IT!!!
 */
ni_listall_res *
_ni_listall_2_svc(
	      ni_id *id,
	      struct svc_req *req
	      )
{
	static ni_listall_res res;

	ni_proplist_list_free(&res.ni_listall_res_u.stuff.entries);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_privileged(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_listall_res_u.stuff.self_id = *id;
	res.status = ni_listall(db_ni, &res.ni_listall_res_u.stuff.self_id,
			     &res.ni_listall_res_u.stuff.entries);
	return (&res);
}

/*
 * The NetInfo READPROP procedure
 */
ni_namelist_res *
_ni_readprop_2_svc(
	       ni_prop_args *arg,
	       struct svc_req *req
	       )
{
	static ni_namelist_res res;

	ni_namelist_free(&res.ni_namelist_res_u.stuff.values);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_namelist_res_u.stuff.self_id = arg->id;
	res.status = ni_readprop(db_ni, &res.ni_namelist_res_u.stuff.self_id,
				 arg->prop_index,
				 &res.ni_namelist_res_u.stuff.values);
	return (&res);
}

/*
 * The NetInfo WRITEPROP procedure
 */
ni_id_res *
_ni_writeprop_2_svc(
		ni_writeprop_args *arg,
		struct svc_req *req
		)
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_writeprop(db_ni, &res.ni_id_res_u.id,
				  arg->prop_index,
				  arg->values);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_WRITEPROP, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo LISTPROPS procedure
 */
ni_namelist_res *
_ni_listprops_2_svc(
		ni_id *arg,
		struct svc_req *req
		)
{
	static ni_namelist_res res;

	ni_namelist_free(&res.ni_namelist_res_u.stuff.values);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_namelist_res_u.stuff.self_id = *arg;
	res.status = ni_listprops(db_ni, &res.ni_namelist_res_u.stuff.self_id, 
				  &res.ni_namelist_res_u.stuff.values);
	return (&res);
}
	

/*
 * The NetInfo CREATEPROP procedure
 */	
ni_id_res *
_ni_createprop_2_svc(
		 ni_createprop_args *arg,
		 struct svc_req *req
		 )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_createprop(db_ni, &res.ni_id_res_u.id, arg->prop, arg->where);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_CREATEPROP, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo DESTROYPROP procedure
 */
ni_id_res *
_ni_destroyprop_2_svc(
		  ni_prop_args *arg,
		  struct svc_req *req
		  )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_destroyprop(db_ni, &res.ni_id_res_u.id, arg->prop_index);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_DESTROYPROP, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo RENAMEPROP procedure
 */
ni_id_res *
_ni_renameprop_2_svc(
		 ni_propname_args *arg,
		 struct svc_req *req
		 )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_renameprop(db_ni, &res.ni_id_res_u.id, 
				   arg->prop_index, arg->name);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_RENAMEPROP, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
		
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo CREATENAME procedure
 */
ni_id_res *
_ni_createname_2_svc(
		 ni_createname_args *arg,
		 struct svc_req *req
		 )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_createname(db_ni, &res.ni_id_res_u.id, arg->prop_index, arg->name,
				   arg->where);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_CREATENAME, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo WRITENAME procedure
 */
ni_id_res *
_ni_writename_2_svc(
		ni_writename_args *arg,
		struct svc_req *req
		)
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_writename(db_ni, &res.ni_id_res_u.id, 
				    arg->prop_index, arg->name_index,
				    arg->name);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_WRITENAME, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * The NetInfo READNAME procedure 
 */
ni_readname_res *
_ni_readname_2_svc(
	       ni_nameindex_args *arg,
	       struct svc_req *req
		)
{
	static ni_readname_res res;

	ni_name_free(&res.ni_readname_res_u.stuff.name);
	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_read(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_readname_res_u.stuff.id = arg->id;
	res.status = ni_readname(db_ni, &res.ni_readname_res_u.stuff.id, 
				 arg->prop_index, arg->name_index,
				 &res.ni_readname_res_u.stuff.name);
	return (&res);
}

/*
 * The NetInfo DESTROYNAME procedure
 */
ni_id_res *
_ni_destroyname_2_svc(
		  ni_nameindex_args *arg,
		  struct svc_req *req
		  )
{
	static ni_id_res res;

	if (req == NULL) {
		return (NULL);
	}
	res.status = validate_write(req);
	if (res.status != NI_OK) {
		return (&res);
	}
	res.ni_id_res_u.id = arg->id;
	res.status = ni_destroyname(db_ni, &res.ni_id_res_u.id, 
				    arg->prop_index, arg->name_index);
	if (res.status == NI_OK) {
		if (!i_am_clone) {
			notify_clients(_NI_DESTROYNAME, arg);
		}
		checksum_inc(&db_checksum, res.ni_id_res_u.id);
	} else if (i_am_clone) {
		dir_clonecheck();
	}
	return (&res);
}

/*
 * Given a NetInfo "serves" value (contains a slash character), does
 * the given tag match the field on the right of the value?
 */
static int
tag_match(
	  ni_name slashtag,
	  ni_name tag
	  )
{
	ni_name sep;
	int len;

	sep = index(slashtag, NI_SEPARATOR);
	if (sep == NULL) {
		return (0);
	}
	if (!ni_name_match(sep + 1, tag)) {
		return (0);
	}

	/*
	 * Ignore special values "." and ".."
	 */
	len = sep - slashtag;
	if (ni_name_match_seg(NAME_DOT, slashtag, len) ||
	    ni_name_match_seg(NAME_DOTDOT, slashtag, len)) {
		return (0);
	}

	return (1);
}

/*
 * The NetInfo BIND procedure.
 *
 * Only reply if served to avoid creating unnecessary net traffic. This
 * is implemented by returned ~NULL if served, NULL otherwise (an rpcgen
 * convention).
 */
void *
_ni_bind_2_svc(
	   ni_binding *binding,
	   struct svc_req *req
	   )
{
	ni_id id;
	ni_idlist ids;
	ni_namelist nl;
	ni_index i;
	ni_name address;
	struct in_addr inaddr;
	ni_status status;

	if (req == NULL) {
		return (NULL);
	}
	status = validate_read(req);
	if (status != NI_OK) {
		return (NULL);
	}
	if (db_ni == NULL) {
		return (NULL);
	}
	if (ni_root(db_ni, &id) != NI_OK) {
		return (NULL);
	}
	NI_INIT(&ids);
	if (ni_lookup(db_ni, &id, NAME_NAME, NAME_MACHINES, 
		      &ids) != NI_OK) {
		return (NULL);
	}
	id.nii_object = ids.niil_val[0];
	ni_idlist_free(&ids);
	inaddr.s_addr = htonl(binding->addr);
	address = inet_ntoa(inaddr);
	NI_INIT(&ids);
	status = ni_lookup(db_ni, &id, NAME_IP_ADDRESS, address, &ids);
	if (status != NI_OK) {
		return (NULL);
	}
	id.nii_object = ids.niil_val[0];
	ni_idlist_free(&ids);
	NI_INIT(&nl);
	status = ni_lookupprop(db_ni, &id, NAME_SERVES, &nl);
	if (status != NI_OK) {
		return (NULL);
	}
	for (i = 0; i < nl.ninl_len; i++) {
		if (tag_match(nl.ninl_val[i], binding->tag)) {
			ni_namelist_free(&nl);
			return ((void *)~0);
		}
	}
	ni_namelist_free(&nl);
	return (NULL);
}

/*
 * Data structure used to hold arguments and results needed for calling
 * the BIND procedure which is broadcast and receives many replies.
 */
typedef struct ni_rparent_stuff {
	nibind_bind_args *bindings; /* arguements to BIND */
	ni_rparent_res *res;	    /* result from BIND */
} ni_rparent_stuff;

/*
 * Catches a BIND reply
 */
static bool_t
catch(
      void *vstuff,
      struct sockaddr_in *raddr,
      int which
      )
{
	ni_rparent_stuff *stuff = (ni_rparent_stuff *)vstuff;

	ni_name_free(&stuff->res->ni_rparent_res_u.binding.tag);
	(stuff->res->ni_rparent_res_u.binding.tag =
	 ni_name_dup(stuff->bindings[which].server_tag));
	stuff->res->ni_rparent_res_u.binding.addr = 
		ntohl(raddr->sin_addr.s_addr);
	stuff->res->status = NI_OK;

	/*
	 * Wait just a moment here to decrease the number of ICMP
	 * Port Unreachable messages that flood the network.
	 */
	sleep(RPARENT_CATCH_SLEEP_SECONDS);

	return (TRUE);
}

static bool_t
getfile_catch(struct bp_getfile_res *res, struct sockaddr_in *from)
{
	union
	{
		char c[4];
		unsigned int i;
	} ci;

	if (res == NULL) return FALSE;

	ci.c[0] = res->server_address.bp_address_u.ip_addr.net;
	ci.c[1] = res->server_address.bp_address_u.ip_addr.host;
	ci.c[2] = res->server_address.bp_address_u.ip_addr.lh;
	ci.c[3] = res->server_address.bp_address_u.ip_addr.impno;

	bootparam_addr.s_addr = ci.i;
	bootparam_tag = (char *)(res->server_path);

	return TRUE;
}

/*
 * Determine if this entry serves ".." (i.e. it has a serves property of
 * which one of the values looks like ../SOMETAG.
 */       
static unsigned
servesdotdot(
	     ni_entry entry,
	     ni_name *tag
	     )
{
	ni_name name;
	ni_name sep;
	unsigned addr;
	ni_namelist nl;
	ni_index i;
	ni_id id;
	if (entry.names == NULL || forcedIsRoot) {
		return (0);
	}
	id.nii_object = entry.id;
	for (i = 0; i < entry.names->ninl_len; i++) {
		name = entry.names->ninl_val[i];
		sep = index(name, NI_SEPARATOR);
		if (sep == NULL) {
			continue;
		}

		if (!ni_name_match_seg(NAME_DOTDOT, name, sep - name)) {
			continue;
		}
		NI_INIT(&nl);
		if (ni_lookupprop(db_ni, &id, NAME_IP_ADDRESS, &nl) != NI_OK) {
			continue;
		}
		if (nl.ninl_len == 0) {
			continue;
		}
		addr = inet_addr(nl.ninl_val[0]);
		ni_namelist_free(&nl);
		*tag = ni_name_dup(sep + 1);
		return (addr);
	}
	return (0);
}

static char *
sys_language(void *ni)
{
	static char language[128];
	ni_status status;
	ni_namelist nl;
	ni_idlist l;
	ni_id id;

	strcpy(language, "English");

	/* We do this the slow and painful way inside netinfod */
	status = ni_root(ni, &id);
	if (status != NI_OK) return language;

	NI_INIT(&l);
	status = ni_lookup(ni, &id, NAME_NAME, NAME_LOCALCONFIG, &l);
	if ((status != NI_OK) || (l.ni_idlist_len == 0)) return language;

	id.nii_object = l.ni_idlist_val[0];
	ni_idlist_free(&l);

	NI_INIT(&l);
	status = ni_lookup(ni, &id, NAME_NAME, NAME_LANGUAGE, &l);
	if ((status != NI_OK) || (l.ni_idlist_len == 0)) return language;

	id.nii_object = l.ni_idlist_val[0];
	ni_idlist_free(&l);

	NI_INIT(&nl);
	status = ni_lookupprop(ni, &id, NAME_LANGUAGE, &nl);
	if (status == NI_OK && nl.ni_namelist_len > 0)
	{
		strcpy(language, nl.ni_namelist_val[0]);
		ni_namelist_free(&nl);
	}

	return (language);
}

/*
 * Find the addresses for the parent servers and call the BIND procedure
 * on each of them. Return 0 if no parent servers are wired into the local
 * database, 1 otherwise.
 */
static int
hardwired(
	  void *ni,
	  ni_rparent_res *res
	  )
{
	ni_name tag = NULL;
	ni_id id;
	ni_idlist ids;
	ni_entrylist entries;
	ni_index i;
	unsigned long addr;
	ni_rparent_stuff stuff;
	ni_status status;
	ni_name server_tag;
	ni_name temptag;
	struct in_addr *addrs;
	struct bp_getfile_arg getfile_arg;
	struct bp_getfile_res getfile_res;
	unsigned nbootparam;
	unsigned nlocal;
	unsigned nnetwork;
	unsigned naddrs;
	unsigned long myaddr;
	unsigned long mynetwork;
	unsigned long mynetmask;
	unsigned long tempaddr;
	enum clnt_stat stat;
	static ni_rparent_res old_res = { NI_NOTMASTER };
	static struct in_addr tmp1;	/* Temp addresses for reporting */
	static struct in_addr tmp2;

	if (ni_root(ni, &id) != NI_OK) {
		old_res.status = NI_NETROOT;
		latestParentStatus = NI_NETROOT;
		return (0);
	}
	NI_INIT(&ids);
	if (ni_lookup(ni, &id, NAME_NAME, NAME_MACHINES, &ids) != NI_OK) {
		old_res.status = NI_NETROOT;
		latestParentStatus = NI_NETROOT;
		return (0);
	}
	id.nii_object = ids.niil_val[0];
	ni_idlist_free(&ids);
	status = ni_list_const(ni, &id, NAME_SERVES, &entries);
	if (status != NI_OK) {
		old_res.status = NI_NETROOT;
		latestParentStatus = NI_NETROOT;
		return (0);
	}
	tag = ni_tagname(ni);

	nbootparam = 0;

	getfile_arg.client_name = (bp_machine_name_t)sys_hostname();
	getfile_arg.file_id = BOOTPARAM_FILEID;
	bzero(&getfile_res, sizeof(struct bp_getfile_res));

	addrs = NULL;
	naddrs = 0;
	stuff.bindings = NULL;
	myaddr = sys_address();	/* returned in net format */
	for (i = 0; i < entries.niel_len; i++) {
		addr = servesdotdot(entries.niel_val[i], &server_tag);
		if (addr != 0) {
			if ((!strcmp(server_tag, BOOTPARAM_TAG)) && (nbootparam == 0))
			{
				nbootparam = 1;
				stat = clnt_broadcast(BOOTPARAMPROG, BOOTPARAMVERS,
					BOOTPARAMPROC_GETFILE,
					xdr_bp_getfile_arg, (char *)&getfile_arg,
					xdr_bp_getfile_res, (char *)&getfile_res,
					getfile_catch);
				if (stat != RPC_SUCCESS) continue;

				addr = bootparam_addr.s_addr;
				server_tag = strdup(bootparam_tag);
				sys_msg(debug, LOG_INFO,
					"-BOOTPARAMS- bind lookup returned %s/%s",
					inet_ntoa(bootparam_addr), bootparam_tag);
			}

			MM_GROW_ARRAY(addrs, naddrs);
			addrs[naddrs].s_addr = addr;
			MM_GROW_ARRAY(stuff.bindings, naddrs);
			stuff.bindings[naddrs].client_tag = tag;
			stuff.bindings[naddrs].client_addr = ntohl(myaddr);
			stuff.bindings[naddrs].server_tag = server_tag;
			naddrs++;
		}
	}

	if ((naddrs == 0) && (nbootparam == 0))
	{
		ni_name_free(&tag);
		ni_list_const_free(ni);
		old_res.status = NI_NETROOT;
		latestParentStatus = NI_NETROOT;
		return (0);
	}

	/*
	 * Majka - 1994.04.27
	 * re-order the servers so that:
	 * servers on the local host are first, then
	 * servers on the local network are next, then
	 * all other servers are next
	 */

	mynetmask = sys_netmask();
	mynetwork = myaddr & mynetmask;

	/*
	 * move local servers to the head of the list
	 */
	nlocal = 0;
	for (i = nlocal; i < naddrs; i++) {
		if ((addrs[i].s_addr == myaddr) ||
			(addrs[i].s_addr == INADDR_LOOPBACK)) {
			tempaddr = addrs[nlocal].s_addr;
			addrs[nlocal].s_addr = addrs[i].s_addr;
			addrs[i].s_addr = tempaddr;
			temptag = stuff.bindings[nlocal].server_tag;
			stuff.bindings[nlocal].server_tag = stuff.bindings[i].server_tag;
			stuff.bindings[i].server_tag = temptag;
			nlocal++;
		}
	}

	/*
	 * move servers on this network to follow local servers
	 */
	nnetwork = nlocal;
	for (i = nnetwork; i < naddrs; i++) {
		if (((addrs[i].s_addr & mynetmask) == mynetwork) ||
			IS_BROADCASTADDR(addrs[i].s_addr))
		{
			tempaddr = addrs[nnetwork].s_addr;
			addrs[nnetwork].s_addr = addrs[i].s_addr;
			addrs[i].s_addr = tempaddr;
			temptag = stuff.bindings[nnetwork].server_tag;
			stuff.bindings[nnetwork].server_tag = stuff.bindings[i].server_tag;
			stuff.bindings[i].server_tag = temptag;
			nnetwork++;
		}
	}

	/*
	 * Found the addresses and committed to multicalling now
	 */
	stuff.res = res;

	/* 
	 * Try binding to a server using -BOOTPARAMS-,
	 * if that fails, try binding to a server on this host,
	 * if that fails, try binding to a server on the local subnet,
	 * if that fails, try all servers.
	 */
	stat = RPC_TIMEDOUT; /* start with stat != RPC_SUCCESS */

	getfile_arg.client_name = (bp_machine_name_t)sys_hostname();
	getfile_arg.file_id = BOOTPARAM_FILEID;
	bzero(&getfile_res, sizeof(struct bp_getfile_res));

	if (nbootparam > 0)
	{
		sys_msg(debug, LOG_INFO, "-BOOTPARAMS- bind");
		stat = clnt_broadcast(BOOTPARAMPROG, BOOTPARAMVERS,
			BOOTPARAMPROC_GETFILE,
			xdr_bp_getfile_arg, (char *)&getfile_arg,
			xdr_bp_getfile_res, (char *)&getfile_res,
			getfile_catch);
	}
	if (stat == RPC_SUCCESS)
	{
		res->ni_rparent_res_u.binding.addr = bootparam_addr.s_addr;
		res->ni_rparent_res_u.binding.tag = bootparam_tag;
	}

	if ((stat != RPC_SUCCESS) && (nlocal > 0)) {
		for (i = 0; i < nlocal; i++) {
			sys_msg(debug, LOG_INFO, "local bind try %d: %s/%s",
			       i + 1, inet_ntoa(addrs[i]),
			       stuff.bindings[i].server_tag);
		}
		stat = ni_multi_call(nlocal, addrs,
			NIBIND_PROG, NIBIND_VERS, NIBIND_BIND,
			xdr_nibind_bind_args, stuff.bindings, 
			sizeof(nibind_bind_args),
			xdr_void, &stuff, 
			catch, -1);
	}

	if (stat != RPC_SUCCESS && nnetwork > 0) {
		for (i = 0; i < nnetwork; i++) {
			sys_msg(debug, LOG_INFO, "network bind try %d: %s/%s",
			       i + 1, inet_ntoa(addrs[i]),
			       stuff.bindings[i].server_tag);
		}
		stat = ni_multi_call(nnetwork, addrs,
			NIBIND_PROG, NIBIND_VERS, NIBIND_BIND,
			xdr_nibind_bind_args, stuff.bindings, 
			sizeof(nibind_bind_args),
			xdr_void, &stuff, 
			catch, -1);
	}

	if (stat != RPC_SUCCESS) {
		for (i = 0; i < naddrs; i++) {
			sys_msg(debug, LOG_INFO, "world bind try %d: %s/%s",
			       i + 1, inet_ntoa(addrs[i]),
			       stuff.bindings[i].server_tag);
		}
		stat = ni_multi_call(naddrs, addrs,
			NIBIND_PROG, NIBIND_VERS, NIBIND_BIND,
			xdr_nibind_bind_args, stuff.bindings, 
			sizeof(nibind_bind_args),
			xdr_void, &stuff, 
			catch, -1);
	}

	if (stat != RPC_SUCCESS) {
#ifdef NOTDEF
		alert_open((const char *)sys_language(ni));
#endif
		alert_open("English");
		res->status = NI_NORESPONSE;
	}
	else {
		alert_close();
		res->status = NI_OK;
	}
	ni_name_free(&tag);

	MM_FREE_ARRAY(addrs, naddrs);
	for (i = 0; i < naddrs; i++) {
		ni_name_free(&stuff.bindings[i].server_tag);
	}
	MM_FREE_ARRAY(stuff.bindings, naddrs);

	ni_list_const_free(ni);
	tmp1.s_addr = ntohl(old_res.ni_rparent_res_u.binding.addr);
	if (NI_OK == res->status) {
		/* Successfully bound */
		tmp2.s_addr = ntohl(res->ni_rparent_res_u.binding.addr);
		switch (old_res.status) {
		case NI_NOTMASTER:
			/* Initial binding */
			sys_msg(debug, LOG_NOTICE, "bound to %s/%s",
				inet_ntoa(tmp2),
				res->ni_rparent_res_u.binding.tag);
			old_res.ni_rparent_res_u.binding.tag =
				(ni_name)malloc(NI_NAME_MAXLEN+1);
			break;
		case NI_NETROOT:
			/* New ".." serves property, new binding */
			sys_msg(debug, LOG_NOTICE, "bound to (new parent) %s/%s",
				inet_ntoa(tmp2),
				res->ni_rparent_res_u.binding.tag);
			old_res.ni_rparent_res_u.binding.tag =
				(ni_name)malloc(NI_NAME_MAXLEN+1);
			break;
		default:
			/* We just rebound */
			sys_msg(debug, LOG_WARNING, "rebound to %s/%s (was to %s/%s)",
				inet_ntoa(tmp2),
				res->ni_rparent_res_u.binding.tag,
				inet_ntoa(tmp1),
				old_res.ni_rparent_res_u.binding.tag);
			break;
		}
		old_res.status = res->status;
		old_res.ni_rparent_res_u.binding.addr =
			res->ni_rparent_res_u.binding.addr;
		(void)strcpy(old_res.ni_rparent_res_u.binding.tag,
			res->ni_rparent_res_u.binding.tag);

		/* keep track of latest parent for statistics */
		latestParentStatus = res->status;
		if (latestParentInfo == NULL)
			latestParentInfo = malloc(sizeof("xxx.xxx.xxx.xxx") + 1 + NI_NAME_MAXLEN + 1);
		(void) sprintf(latestParentInfo, "%s/%s",
					inet_ntoa(tmp2),
					res->ni_rparent_res_u.binding.tag);
	} else {
		/* Binding failed (!) */
		switch (old_res.status) {
		case NI_NOTMASTER:
			sys_msg(debug, LOG_ERR, "unable to bind to parent - %s",
				clnt_sperrno(stat));
			break;
		default:
			sys_msg(debug, LOG_ERR, "unable to rebind from %s/%s - %s",
				inet_ntoa(tmp1), old_res.ni_rparent_res_u.binding.tag,
				clnt_sperrno(stat));
			latestParentStatus = res->status;
			break;
		}
	}
	return (1);
}

/*
 * The NetInfo RPARENT procedure
 */
ni_rparent_res *
_ni_rparent_2_svc(
	      void *arg,
	      struct svc_req *req
	      )
{
	static ni_rparent_res res = { NI_FAILED };
	static long root_time = -1;
	long now;
	
	if (req == NULL) {
		return (NULL);
	}

	/*
	 * If standalone (i.e. no network attached), then stop here
	 */
	if (alert_aborted() || sys_standalone()) {
		res.status = NI_NETROOT;
		latestParentStatus = NI_NETROOT;
		return (&res);
	}

	/*
	 * If already have the result, return it.
	 *
	 * Note: As long as the parent NetInfo server which we were
	 *       previously bound to is still up and running there
	 *       will be no calls to hardwired() which might detect
	 *       that we are now the root domain.
	 */
	if (res.status == NI_OK) {
		if (ni_ping(res.ni_rparent_res_u.binding.addr,
			    res.ni_rparent_res_u.binding.tag)) {
			return (&res);
		}
	}
	
	/*
	 * If we were the network root before, we probably still are.
	 * Throttle back attempts to find the parent domain.  I saw over 
	 * 2500 calls to hardwired in just a few hours while scatterloading
	 * netinfod.  GRS 3/2/92.
	 */
	
	if ((res.status == NI_NETROOT) && (root_time != -1)) {
	    time(&now);
	    if ((now - root_time) < (NETROOT_TIMEOUT_MINS * 60)) {
		return (&res);
	    }
	}

	/*
	 * If there are hard-wired addresses, use them.
	 */
	if (hardwired(db_ni, &res)) {
		return (&res);
	}

	/*
	 * Otherwise, we've hit the network root
	 */
	res.status = NI_NETROOT;
	time(&root_time);
	return (&res);
}

/*
 * Called at startup: try to locate a parent server, allowing for user
 * to abort search if timeouts occur.
 */
void
waitforparent(void)
{
	ni_rparent_res *res;
	int i;

	alert_enable(1);
	for (;;) {
		res = _ni_rparent_2_svc(NULL, (struct svc_req *)(~0));
		if (res->status != NI_NORESPONSE) {
			alert_enable(0);
			return;
		}
		for (i = 0; i < PARENT_NINTERVALS; i++) {
			if (alert_aborted()) {
				alert_enable(0);
				return;
			}
			sleep(PARENT_SLEEPTIME);
		}
	}
}		   

/*
 * The NetInfo CRASHED procedure
 * If master, do nothing. If clone, check that our database is up to date.
 */
void *
_ni_crashed_2_svc(
	      unsigned *checksum,
	      struct svc_req *req
	      )
{
	if (req == NULL) {
		return (NULL);
	}
	if (validate_privileged(req) != NI_OK) {
		return (NULL);
	}
	if (i_am_clone) {
		if (*checksum != db_checksum) {
			/*
			 * If we get a crashed, it means the master's coming
			 * up.  If our database is out-of-sync, we should
			 * sync up, regardless of when we last got a new
			 * database.
			 */
			have_transferred = 0;
			dir_clonecheck();
		}
	}
	return ((void *)~0);
}

/*
 * The NetInfo READALL procedure
 *
 * XXX: doing a readall takes a long time. We should really
 * fork a thread to do this and disable writes until it is done.
 * Since there are bunches of thread-safety issues (especially
 * with the RPC libraries) we will do the master side in a
 * separate process.
 */
void proxy_term(void);
ni_readall_res *
_ni_readall_2_svc(
	      unsigned *checksum,
	      struct svc_req *req
	      )
{
	static ni_readall_res res;
	int didit;
	struct stat stat_buf;
	int i;
	static int kpid;

	if (req == NULL) return (NULL);
	res.status = validate_privileged(req);
	if (res.status != NI_OK) {
		return (&res);
	}

	/*
	 * Allow a clone to answer a readall. This means that a
	 * program can be written which does a readall but can
	 * request the information from a clone (rather than
	 * always having to go to the master).
	 */
	if (i_am_clone && !cloneReadallResponseOK)
	{
		res.status = NI_NOTMASTER;
		return (&res);
	}

	if (*checksum == db_checksum)
	{
		res.status = NI_OK;
		res.ni_readall_res_u.stuff.checksum = 0;
		res.ni_readall_res_u.stuff.list = NULL;
		return (&res);
	}

	/*  if notifications are pending, then fail transfer. */
	if (have_notifications_pending())
	{
		res.status = NI_MASTERBUSY;
		return (&res);
	}

	sys_msg(debug, LOG_WARNING, "readall %s {%u} to %s:%hu {%u}",
		db_tag, db_checksum,
		inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
		ntohs(svc_getcaller(req->rq_xprt)->sin_port), *checksum);

	/*
	 * Do master side of readall in separate process.
	 * We'll use a separate process to ensure we don't run
	 * into any RPC thread-safe problems.  This will be controlled
	 * by a property in the domain's root directory, readall_proxies
	 * if > 0, it denotes the maximum number of readall subprocesses
	 * we'll have forked at once.
	 */

	mutex_lock(readall_mutex);

	sending_all++;	/* Turn off writing for duration of readall */

	if (max_readall_proxies != 0)
	{
		/* Perhaps use a proxy */
		if ((max_readall_proxies == -1) || 
			(max_readall_proxies > readall_proxies))
		{
			/* We'll fork a new process to do this readall */
			readall_proxies++;	/* Assume things work; elim races? */
			mutex_unlock(readall_mutex);
			kpid = fork();
			
			if (kpid == 0)
			{
				/* Child */
				/* Right now, if we get a SIGTERM, we'll just set the
				 * shutdown flag, which is examined at the top of the
				 * run loop in svc_run().  We really ought to clean up
				 * and disappear when we get a SIGTERM as a readall
				 * proxy.
				 */
				signal(SIGTERM, (void *)proxy_term);
				if (setpgrp(0, process_group) != 0)
					sys_msg(debug, LOG_ERR, "proxy can't setpgrp - %m");

				/*
				 * XXX FIX THIS! XXX
				 * sleeping does not fix race conditions!!!
				 *
				 * Possible race condition: It's possible for the
				 * readall proxy to finish sending the database before
				 * the parent process updates its list of proxy PIDs.
				 * Sleep 1 sec to decrease the chances of this.
				 */
				sleep(1);

				i_am_proxy = TRUE;

				/*
				 * Identify that we're responding to a readall in argv.
				 *
				 * N.B. This needs to be shorter than invocation string!
				 * As long as we're invoked with our full pathname as
				 * argv[0], that's fine; if we're invoked with a relative
				 * pathname, this will likely be truncated.  Note that
				 * if we've a maximum size clone address (xxx.xxx.xxx.xxx),
				 * this string is as long as it can be!
				 */
				setproctitle("%s->%s", db_tag,
					inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr));
    
				/*
				 * We need to reopen the collection file stream since
				 * it will make our siblings and our parent unhappy
				 * if we seek around in it while they are trying to do 
				 * likewise. Right now, we're sharing the file descriptor,
				 * after the ni_db_reopen call, we'll have our own
				 * file descriptor for the collection file!
				 *
				 * To ensure we don't inappropriately keep a connection
				 * open that our parent wants to close, let's close all
				 * the FDs that are sockets, except the one we'll use to
				 * answer the clone.
				 */
				for (i = 0; i < NOFILE; i++)
				{
					/* Might not have std* */
					if (i != req->rq_xprt->xp_sock)
					{
						/* Do we need to socket_lock()? We're child... */
						/*
						 * According to the BUGS section of the fstat()
						 * man page, and according to the code in the
						 * kernel [bsd/netinet/tcp_usrreq.c, the PRU_SENSE
						 * case of tcp_usrreq()], the whole fstat buffer
						 * will be zero, except for st_blksize (which
						 * will be the socket's high water mark).  So,
						 * in case this bug is ever fixed and the mode is
						 * really set properly, we check for either IFSOCK
						 * set in the mode, or the whole mode being zero
						 * (which it can't otherwise be, since ALL files
						 * have a type set in the high-order bits of the
						 * mode field, and type of 0 isn't defined).
						 */

						if (fstat(i, &stat_buf) == 0)
						{
							/* Successful; check it */
							if ((S_IFSOCK == (S_IFMT & stat_buf.st_mode)) ||
								!stat_buf.st_mode)
							close(i);
						}
						else
						{
							switch(errno)
							{
								/* Error; report it */
								case 0:			/* Whoops; no error? */
									sys_msg(debug, LOG_WARNING,
										"proxy: fstat(%d) return of 0, and errno of 0");
									break;

								case EBADF:		/* Not an open fd; ignore */
									break;

								default:		/* Real error: report it */
									sys_msg(debug, LOG_ERR, "proxy: fstat(%d) - %m", i);
									break;
							}
						}
					}
				}

				if (!ni_db_reopen(db_ni))
				{
					sys_msg(debug, LOG_ERR, "readall %s to %s:%hu failed "
						"(reopen failed!)", db_tag,
						inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
						ntohs(svc_getcaller(req->rq_xprt)->sin_port));
					exit(NI_SYSTEMERR);	/* Tell parent we failed */
				}

				/*
				 * Normally, we'd surround this with a socket_lock() and
				 * socket_unlock() pair.  But, we KNOW there weren't any
				 * notifications pending in the parent, and we've no
				 * other threads.  In addition, there's a slim race
				 * condition found during testing which leaves the
				 * socket_mutex locked; with no other thread running
				 * to unlock it, we just sit forever, eating up bits
				 * of CPU time.
				 */
				didit = svc_sendreply(req->rq_xprt, readall, db_ni);
				if (!didit)
				{
					sys_msg(debug, LOG_ERR, "readall %s to %s:%hu failed",
						db_tag, inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
						ntohs(svc_getcaller(req->rq_xprt)->sin_port));
					exit(NI_SYSTEMERR);	/* Tell parent we failed */
				}
				else
				{
					sys_msg(debug, LOG_NOTICE, "readall %s to %s:%hu complete",
						db_tag, inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
						ntohs(svc_getcaller(req->rq_xprt)->sin_port));
				}

				exit(0);	/* Tell parent all's ok */
			}
			else if (kpid == -1)
			{
				/* Error in fork()*/
				mutex_lock(readall_mutex);
				readall_proxies--;
				mutex_unlock(readall_mutex);
				sys_msg(debug, LOG_ERR, "Can't fork for readall [%p], retaining");
				/* Fall through so we do readall anyway, in this process */
			}
			else
			{
				/* Parent */
				sys_msg(debug, LOG_DEBUG, "readall proxy pid %d", kpid);

				/* Retain the proxy's pid to kill it if we shutdown */
				mutex_lock(readall_mutex);
		   		add_proxy(kpid, svc_getcaller(req->rq_xprt)-> sin_addr.s_addr);
				mutex_unlock(readall_mutex);

				/*
				 * Just in case (?!), close this here; child has it open.
				 * But, it's really destruction of the RPC transport. But,
				 * we surely can't do this, because ni_prot_svc does a
				 * svc_freeargs() right after we return even return(NULL),
				 * and this will just fail, and so we'll exit(1). Maybe
				 * we need to do what svctcp_destroy() does, but that
				 * grossly violates encapsulation.
				 * XXX Do we need to do something to the LRU cache, or the
				 * FDs interesting to svc_run's select()?...
				 */

				return(NULL);	/* Just keep listening */
			}
		}
		else
		{
			/* Out of proxies */
			sys_msg(debug, LOG_WARNING, "readall proxy limit (%d) reached; %s "
				"request from %s:%hu", max_readall_proxies,
				strict_proxies ? "proroguing" : "retaining",
				inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
				ntohs(svc_getcaller(req->rq_xprt)->sin_port));

			if (strict_proxies)
			{
				/* Strict proxies says we can't do it */
				sending_all--; /* We're not doing anything; decrement */
				mutex_unlock(readall_mutex);
				res.status = NI_MASTERBUSY;
				return (&res);
			}

			mutex_unlock(readall_mutex);
		}
	    /* If not strict proxies, retain and run in this process */
	}

	/*
	 * Either proxies disabled, or we're out and loose, or the fork()
	 * of the proxy failed.  Do it here, regardless.
	 */
	mutex_unlock(readall_mutex);
	socket_lock();
	didit = svc_sendreply(req->rq_xprt, readall, db_ni);
	socket_unlock();
	mutex_lock(readall_mutex);
	sending_all--;	/* Let writing resume (well, once we're at 0) */
	mutex_unlock(readall_mutex);
	if (!didit)
	{
		sys_msg(debug, LOG_ERR, "readall %s to %s:%hu failed", db_tag,
			inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
			ntohs(svc_getcaller(req->rq_xprt)->sin_port));
	}
	else
	{
		sys_msg(debug, LOG_NOTICE, "readall %s to %s:%hu complete", db_tag,
			inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
			ntohs(svc_getcaller(req->rq_xprt)->sin_port));
	}

	return (NULL);
}

void
readall_catcher(void)
{
    /*
     * We can't just clean up the proxy's pid: remove_proxy() calls
     * [HashTable removeKey:] which calls free(), which waits on the
     * (global) malloc lock.  So, just post that we need to clean up.
     * And, make the posting as atomic as possible, so we don't ever
     * lose anything, and we avoid possible race conditions.
     */
    readall_done = TRUE;
}

void
readall_cleanup(void)
{
	int p;
	union wait wait_stat;
	unsigned int addr;

    /*
     * A readall fork finished doing its job.  Note the **ASSUMPTION**
     * that the only child processes we fork are for readalls.
     */
    mutex_lock(readall_mutex);
    while (TRUE)
	{
		p = wait4(0, (int *)&wait_stat, WNOHANG, NULL);
		switch (p)
		{
			case 0:		/* All dead children reaped */
				mutex_unlock(readall_mutex);
				return;
				break;

			case -1:	/* Error */
				mutex_unlock(readall_mutex);
				if (ECHILD != errno)
					sys_msg(debug, LOG_WARNING, "problem reaping proxy: %m");
				return;
				break;

			default:	/* Someone's done */
				if ((wait_stat.w_retcode == 0) && (wait_stat.w_termsig == 0))
				{
					/* transfer was successful */
					addr = get_proxy(p);
					if (addr == 0)
					{
						sys_msg(debug, LOG_WARNING,
							"child process %d not a readall proxy", p);
					}
					else
					{
						notify_mark_clone(addr);
						remove_proxy(p);
					}
				}
				else
				{
					sys_msg(debug, LOG_ERR, "readall proxy terminated with status %u, "
						"signal %u", wait_stat.w_retcode, wait_stat.w_termsig);
				}

				if (sending_all > 0) sending_all--;
				if ((readall_proxies > 0) && (0 == --readall_proxies))
					readall_done = FALSE;	/* No more readalls can be pending */
				break;
		}
	}

    mutex_unlock(readall_mutex);
    return;
}

/*
 * Allow SIGINT to turn off updates
 */
void
dblock_catcher(void)
{
    if (i_am_clone) {
	sys_msg(debug, LOG_ERR, "SIGINT to clone ignored");
	return;
    } else if (i_am_proxy) {
	sys_msg(debug, LOG_ERR, "SIGINT to readall proxy ignored");
	return;
    }
    mutex_lock(lockup_mutex);
    db_lockup = ! db_lockup;
    sys_msg(debug, LOG_WARNING, "Master database is now %s", 
	   db_lockup ? "locked" : "unlocked");
    mutex_unlock(lockup_mutex);
    return;
}

/*
 * The NetInfo RESYNC procedure
 */
ni_status *
_ni_resync_2_svc(
	     void *arg,
	     struct svc_req *req
	     )
{
	static ni_status status;

	if (req == NULL) return (NULL);
	status = validate_privileged(req);
	if (status != NI_OK) {
		return (&status);
	}

	sys_msg(debug, LOG_NOTICE, "got a resync from %s:%hu",
	       inet_ntoa(svc_getcaller(req->rq_xprt)->sin_addr),
	       ntohs(svc_getcaller(req->rq_xprt)->sin_port));

	cleanupwait = get_cleanupwait(db_ni);
	forcedIsRoot = get_forced_root(db_ni);
	cloneReadallResponseOK = get_clone_readall(db_ni);

	if (i_am_clone)
	{
		if (get_sanitycheck(db_ni)) sanitycheck(db_tag);
		dir_clonecheck();
	}
	else
	{
		notify_resync();
	} 

	status = NI_OK;
	return (&status);
}

/*
 * Ping the server at the given address/tag
 */
static int
ni_ping(
	u_long address,			/* host byte order! */
	ni_name tag
	)
{
	struct sockaddr_in sin;
	struct timeval tv;
	enum clnt_stat stat;
	int sock;
	nibind_getregister_res res;
	CLIENT *cl;

	sin.sin_family = AF_INET;
	sin.sin_port = 0;
	sin.sin_addr.s_addr = htonl(address);
	bzero(sin.sin_zero, sizeof(sin.sin_zero));
	sock = socket_open(&sin, NIBIND_PROG, NIBIND_VERS);
	if (sock < 0) {
		return (0);
	}
	tv.tv_usec = 0;
	tv.tv_sec = PING_TIMEOUT / PING_TRIES;
	cl = clntudp_create(&sin, NIBIND_PROG, NIBIND_VERS, 
			    tv, &sock);
	if (cl == NULL) {
		(void)socket_close(sock);
		return (0);
	}
	tv.tv_sec = PING_TIMEOUT;
	stat = clnt_call(cl, NIBIND_GETREGISTER, 
			 xdr_ni_name, &tag, xdr_nibind_getregister_res,
			 &res, tv);
	clnt_destroy(cl);
	(void)socket_close(sock);
	if (stat != RPC_SUCCESS || res.status != NI_OK) {
		return(0);
	}

	/*
	 * Actually talk to parent during ni_ping
	 */
	sin.sin_port = htons(res.nibind_getregister_res_u.addrs.udp_port);
	sock = socket_open(&sin, NI_PROG, NI_VERS);
	if (sock < 0) {
		return (0);
	}
	cl = clntudp_create(&sin, NI_PROG, NI_VERS, tv, &sock);
	if (cl == NULL) {
		socket_close(sock);
		return (0);
	}
	stat = clnt_call(cl, _NI_PING, xdr_void, (void *)NULL,
			 xdr_void, (void *)NULL, tv);
	clnt_destroy(cl);
	socket_close(sock);
	return (stat == RPC_SUCCESS);
}
