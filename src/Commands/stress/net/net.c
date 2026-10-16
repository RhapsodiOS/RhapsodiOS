/* stress-net: loopback network tests. Every byte that crosses a socket is
 * patterned and checked at its stream offset (tcp, unix), datagrams are
 * checked and counted (udp), select must wake for every ready socket,
 * connection storms must not leak descriptors, and descriptors passed over
 * AF_UNIX must name the same file. Only 127.0.0.1 and AF_UNIX are used. */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

#define MB	(1024UL * 1024)
#define CHUNK	16384
#define MAXCONN	200		/* tcp: root forking past ~500 processes panics this kernel */
#define NSOCK	32
#define HDR	16
#define MAXPAY	200
#define UDPMAX	1400
#define UDPBATCH 8
#define FDFILE	16384

/* What bail() cleans up before a failure is reported. */
static pid_t *g_kids;
static int g_nk;
static char g_path[300];

static void
bail(void)
{
	int e = errno, i, st;

	for (i = 0; i < g_nk; i++)
		if (g_kids[i] > 0)
			kill(g_kids[i], SIGKILL);
	for (i = 0; i < g_nk; i++)
		if (g_kids[i] > 0)
			while (waitpid(g_kids[i], &st, 0) < 0 && errno == EINTR)
				;
	g_nk = 0;
	if (g_path[0] != '\0') {
		unlink(g_path);
		g_path[0] = '\0';
	}
	errno = e;
}

static void
nfail(struct st_ctx *c, const char *fmt, ...)
{
	char buf[400];
	va_list ap;

	bail();
	va_start(ap, fmt);
	vsprintf(buf, fmt, ap);
	va_end(ap);
	st_fail(c, "%s", buf);
}

static void
efail(struct st_ctx *c, const char *call)
{
	bail();
	st_fail_errno(c, call);
}

static void
dfail(struct st_ctx *c, const char *what, const unsigned char *got, unsigned long len,
      unsigned long key, unsigned long off, long bad)
{
	bail();
	st_fail_data(c, what, got, len, key, off, bad);
}

/* Reaps kid i, which must have exited 0. */
static void
waitkid(struct st_ctx *c, int i)
{
	int status;

	while (waitpid(g_kids[i], &status, 0) < 0) {
		if (errno != EINTR) {
			g_kids[i] = 0;
			efail(c, "waitpid");
		}
	}
	g_kids[i] = 0;
	if (status != 0)
		nfail(c, "what=peer status=0x%x", status);
}

static unsigned long
key3(unsigned long a, unsigned long b)
{
	return st_mix(st_mix(st_opt.seed ^ a) + b * 0x9e3779b1UL) & ST_MASK;
}

static void
put32(unsigned char *p, unsigned long v)
{
	p[0] = v >> 24;
	p[1] = v >> 16;
	p[2] = v >> 8;
	p[3] = v;
}

static unsigned long
get32(const unsigned char *p)
{
	return (((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
		((unsigned long)p[2] << 8) | p[3]) & ST_MASK;
}

static int
writeall(int fd, const unsigned char *b, long n)
{
	long w;

	while (n > 0) {
		w = write(fd, b, n);
		if (w < 0 && errno == EINTR)
			continue;
		if (w < 0)
			return -1;
		b += w;
		n -= w;
	}
	return 0;
}

/* 0: n bytes read; 1: EOF first; -1: error. */
static int
readfull(int fd, unsigned char *b, unsigned long n)
{
	unsigned long got = 0;
	int r;

	while (got < n) {
		r = read(fd, b + got, n - got);
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0)
			return -1;
		if (r == 0)
			return 1;
		got += r;
	}
	return 0;
}

static void
local_addr(struct sockaddr_in *sa, unsigned short nport)
{
	memset(sa, 0, sizeof *sa);
	sa->sin_family = AF_INET;
	sa->sin_addr.s_addr = htonl(0x7f000001UL);
	sa->sin_port = nport;
}

/* A TCP listener on 127.0.0.1 and an ephemeral port (network order in *nport). */
static int
listen_local(struct st_ctx *c, unsigned short *nport)
{
	struct sockaddr_in sa;
	int s, sl = sizeof sa;

	s = socket(AF_INET, SOCK_STREAM, 0);
	if (s < 0)
		efail(c, "socket");
	local_addr(&sa, 0);
	if (bind(s, (struct sockaddr *)&sa, sizeof sa) < 0)
		efail(c, "bind");
	if (getsockname(s, (struct sockaddr *)&sa, &sl) < 0)
		efail(c, "getsockname");
	if (listen(s, 16) < 0)
		efail(c, "listen");
	*nport = sa.sin_port;
	return s;
}

/* -1 with errno on failure. */
static int
connect_local(unsigned short nport)
{
	struct sockaddr_in sa;
	int s, e;

	s = socket(AF_INET, SOCK_STREAM, 0);
	if (s < 0)
		return -1;
	local_addr(&sa, nport);
	if (connect(s, (struct sockaddr *)&sa, sizeof sa) < 0) {
		e = errno;
		close(s);
		errno = e;
		return -1;
	}
	return s;
}

static int
accept_fd(struct st_ctx *c, int ls)
{
	int s;

	while ((s = accept(ls, NULL, NULL)) < 0 && errno == EINTR)
		;
	if (s < 0)
		efail(c, "accept");
	return s;
}

/* Child side of a stream: 1 MB keyed by key in random 1 B-16 KB writes; the
 * byte at offset bad (if >= 0) is flipped. */
static void
sendstream(int fd, unsigned long key, long bad)
{
	struct st_rng r;
	unsigned char buf[CHUNK];
	unsigned long off, n;

	st_rng_init(&r, key, "netw", 0);
	for (off = 0; off < MB; off += n) {
		n = st_range(&r, 1, CHUNK);
		if (n > MB - off)
			n = MB - off;
		st_fill(buf, n, key, off);
		if (bad >= (long)off && bad < (long)(off + n))
			buf[bad - off] ^= 1;
		if (writeall(fd, buf, n) < 0)
			_exit(1);
	}
}

/* Reads 1 MB in random sizes, checking each chunk at its stream offset, then EOF. */
static void
recvstream(struct st_ctx *c, int fd, unsigned long key)
{
	struct st_rng r;
	unsigned char buf[CHUNK];
	unsigned long off = 0, want;
	long bad;
	int got;

	st_rng_init(&r, key, "netr", 0);
	while (off < MB) {
		want = st_range(&r, 1, CHUNK);
		if (want > MB - off)
			want = MB - off;
		got = read(fd, buf, want);
		if (got < 0 && errno == EINTR)
			continue;
		if (got < 0)
			efail(c, "read");
		if (got == 0)
			nfail(c, "reason=short off=0x%lx", off);
		bad = st_check(buf, got, key, off);
		if (bad >= 0)
			dfail(c, "stream", buf, got, key, off, bad);
		off += got;
	}
	while ((got = read(fd, buf, 1)) < 0 && errno == EINTR)
		;
	if (got < 0)
		efail(c, "read");
	if (got > 0)
		nfail(c, "reason=extra off=0x%lx", off);
}

/* tcp: procs clients each send 1 MB over their own connection. A client
 * announces its number first, so the server can key what it expects. */
static void
t_tcp(struct st_ctx *c)
{
	pid_t kids[MAXCONN];
	int fds[MAXCONN], seen[MAXCONN];
	unsigned short nport;
	unsigned char hb[4];
	long i, badi, bad;
	int n = st_opt.procs > MAXCONN ? MAXCONN : st_opt.procs, k, j, ls, s, badk;
	unsigned long id;

	g_kids = kids;
	badi = st_range(&c->rng, 0, c->iters - 1);
	badk = st_range(&c->rng, 0, n - 1);
	bad = st_range(&c->rng, 0, MB - 1);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		ls = listen_local(c, &nport);
		g_nk = 0;
		for (k = 0; k < n; k++) {
			seen[k] = 0;
			kids[k] = fork();
			if (kids[k] < 0) {
				kids[k] = 0;
				g_nk = k;
				efail(c, "fork");
			}
			if (kids[k] == 0) {
				for (j = 0; j < k; j++)
					close(fds[j]);
				close(ls);
				s = connect_local(nport);
				if (s < 0)
					_exit(1);
				put32(hb, k);
				if (writeall(s, hb, 4) < 0)
					_exit(1);
				sendstream(s, key3(i, k), c->selfcheck && i == badi && k == badk ? bad : -1);
				close(s);
				_exit(0);
			}
			g_nk = k + 1;
			fds[k] = accept_fd(c, ls);
		}
		close(ls);
		for (k = 0; k < n; k++) {
			j = readfull(fds[k], hb, 4);
			if (j < 0)
				efail(c, "read");
			if (j > 0)
				nfail(c, "reason=short off=0x0");
			id = get32(hb);
			if (id >= (unsigned long)n || seen[id])
				nfail(c, "reason=badid id=%lu", id);
			seen[id] = 1;
			recvstream(c, fds[k], key3(i, id));
			close(fds[k]);
		}
		for (k = 0; k < n; k++)
			waitkid(c, k);
		st_op_end(c, n * MB);
	}
}

/* udp: datagrams to ourselves in batches; seq(4) len(2) payload keyed by seq. */
static void
t_udp(struct st_ctx *c)
{
	struct sockaddr_in sa;
	struct timeval tv;
	fd_set rd;
	unsigned char msg[6 + UDPMAX], *seen;
	long i, badi, sent = 0, rcvd = 0, got0, bp;
	unsigned long seq, len, key;
	int s, sl = sizeof sa, batch = 0, n;

	badi = st_range(&c->rng, 0, c->iters - 1);
	seen = calloc(c->iters, 1);
	if (seen == NULL)
		st_fail_errno(c, "calloc");
	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0)
		st_fail_errno(c, "socket");
	local_addr(&sa, 0);
	if (bind(s, (struct sockaddr *)&sa, sizeof sa) < 0 ||
	    getsockname(s, (struct sockaddr *)&sa, &sl) < 0)
		st_fail_errno(c, "bind");
	for (i = 0; ; i++) {
		if (st_more(c, i)) {
			len = st_range(&c->rng, 1, UDPMAX);
			bp = st_range(&c->rng, 0, len - 1);
			st_op_begin(c);
			put32(msg, i);
			msg[4] = len >> 8;
			msg[5] = len;
			st_fill(msg + 6, len, key3(c->idx, i), 0);
			if (c->selfcheck && i == badi)
				msg[6 + bp] ^= 1;
			if (sendto(s, msg, 6 + len, 0, (struct sockaddr *)&sa, sizeof sa) < 0)
				st_fail_errno(c, "sendto");
			sent++;
			batch++;
		}
		if (batch == UDPBATCH || (batch > 0 && !st_more(c, i))) {
			got0 = rcvd;
			while (batch > 0) {
				FD_ZERO(&rd);
				FD_SET(s, &rd);
				tv.tv_sec = 1;
				tv.tv_usec = 0;
				n = select(s + 1, &rd, NULL, NULL, &tv);
				if (n < 0 && errno == EINTR)
					continue;
				if (n < 0)
					st_fail_errno(c, "select");
				if (n == 0)
					break;		/* the rest of the batch is lost */
				n = recvfrom(s, msg, sizeof msg, 0, NULL, NULL);
				if (n < 0 && errno == EINTR)
					continue;
				if (n < 0)
					st_fail_errno(c, "recvfrom");
				batch--;
				rcvd++;
				if (n < 6)
					st_fail(c, "reason=runt len=%d", n);
				seq = get32(msg);
				len = (msg[4] << 8) | msg[5];
				if (seq >= (unsigned long)c->iters)
					st_fail(c, "reason=badseq seq=%lu", seq);
				if (len + 6 != (unsigned long)n)
					st_fail(c, "reason=badlen seq=%lu len=%lu got=%d", seq, len, n);
				if (seen[seq])
					st_fail(c, "reason=dup seq=%lu", seq);
				seen[seq] = 1;
				key = key3(c->idx, seq);
				bp = st_check(msg + 6, len, key, 0);
				if (bp >= 0)
					st_fail_data(c, "dgram", msg + 6, len, key, 0, bp);
			}
			if (rcvd == got0)
				st_fail(c, "reason=no-delivery sent=%ld", sent);
			batch = 0;
			st_op_end(c, UDPBATCH);
		}
		if (!st_more(c, i))
			break;
	}
	close(s);
	if (c->selfcheck && !seen[badi])
		st_fail(c, "reason=no-delivery seq=%ld", badi);
	if (st_opt.verbose)
		fprintf(stderr, "stress-net udp: worker %d sent=%ld lost=%ld\n", c->idx, sent, sent - rcvd);
	free(seen);
}

/* unix: as tcp, over a socketpair and then over a bound path socket. */
static void
t_unix(struct st_ctx *c)
{
	pid_t kid;
	struct sockaddr_un su;
	int sv[2], ls, s;
	long i, badi, bad;

	g_kids = &kid;
	badi = st_range(&c->rng, 0, c->iters - 1);
	bad = st_range(&c->rng, 0, MB - 1);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0)
			efail(c, "socketpair");
		g_nk = 0;
		kid = fork();
		if (kid < 0)
			efail(c, "fork");
		if (kid == 0) {
			close(sv[0]);
			sendstream(sv[1], key3(i, 0), c->selfcheck && i == badi ? bad : -1);
			_exit(0);
		}
		g_nk = 1;
		close(sv[1]);
		recvstream(c, sv[0], key3(i, 0));
		close(sv[0]);
		waitkid(c, 0);
		g_nk = 0;

		st_path(c, g_path, sizeof g_path, "sock");
		unlink(g_path);
		memset(&su, 0, sizeof su);
		su.sun_family = AF_UNIX;
		if (strlen(g_path) >= sizeof su.sun_path) {
			g_path[0] = '\0';
			nfail(c, "reason=path-too-long");
		}
		strcpy(su.sun_path, g_path);
		ls = socket(AF_UNIX, SOCK_STREAM, 0);
		if (ls < 0)
			efail(c, "socket");
		if (bind(ls, (struct sockaddr *)&su, sizeof su) < 0) {
			g_path[0] = '\0';	/* not ours to remove */
			efail(c, "bind");
		}
		if (listen(ls, 5) < 0)
			efail(c, "listen");
		kid = fork();
		if (kid < 0)
			efail(c, "fork");
		if (kid == 0) {
			close(ls);
			s = socket(AF_UNIX, SOCK_STREAM, 0);
			if (s < 0 || connect(s, (struct sockaddr *)&su, sizeof su) < 0)
				_exit(1);
			sendstream(s, key3(i, 1), -1);
			_exit(0);
		}
		g_nk = 1;
		s = accept_fd(c, ls);
		close(ls);
		unlink(g_path);
		g_path[0] = '\0';
		recvstream(c, s, key3(i, 1));
		close(s);
		waitkid(c, 0);
		g_nk = 0;
		st_op_end(c, 2 * MB);
	}
}

static void
now_us(unsigned long *sec, unsigned long *usec)
{
	struct timeval t;

	gettimeofday(&t, NULL);
	*sec = t.tv_sec & ST_MASK;
	*usec = t.tv_usec;
}

static unsigned long
selkey(unsigned long id, unsigned long seq)
{
	return key3(0x5e100000UL + id, seq);
}

/* select client: connects NSOCK sockets, then sends iters frames on random
 * ones at random intervals (and a 600 ms pause every 100th frame). */
static void
selclient(long iters, unsigned short nport, int ls)
{
	struct st_rng r;
	unsigned char fr[HDR + MAXPAY];
	unsigned long seq[NSOCK], id, len, sec, usec;
	int s[NSOCK], k;
	long i;

	close(ls);
	for (k = 0; k < NSOCK; k++) {
		seq[k] = 0;
		s[k] = connect_local(nport);
		if (s[k] < 0)
			_exit(1);
	}
	st_rng_init(&r, st_opt.seed, "netsel", 1);
	for (i = 0; i < iters; i++) {
		id = st_range(&r, 0, NSOCK - 1);
		len = st_range(&r, 0, MAXPAY);
		now_us(&sec, &usec);
		fr[0] = id >> 8;
		fr[1] = id;
		fr[2] = len >> 8;
		fr[3] = len;
		put32(fr + 4, seq[id]);
		put32(fr + 8, sec);
		put32(fr + 12, usec);
		st_fill(fr + HDR, len, selkey(id, seq[id]), 0);
		seq[id]++;
		if (writeall(s[id], fr, HDR + len) < 0)
			_exit(1);
		usleep(st_range(&r, 0, 3000));
		if (i % 100 == 99)
			usleep(600000);
	}
	_exit(0);
}

/* select: one process over NSOCK accepted sockets with a 2 s timeout. */
static void
t_select(struct st_ctx *c)
{
	struct {
		int fd, have;
		unsigned long seq;
		unsigned char buf[HDR + MAXPAY];
	} cn[NSOCK];
	pid_t kid;
	fd_set all, rd;
	struct timeval tv;
	unsigned char *b;
	unsigned long id, len, seq, sec, usec, nsec, nusec;
	unsigned short nport;
	long got = 0, frames, bad, gap;
	int ls, k, maxfd = 0, r, need, suspect, status;

	/* the client sends c->iters frames: -T would stop the server early and
	 * the client would fail writing to closed sockets */
	st_opt.budget = 0;
	g_kids = &kid;
	ls = listen_local(c, &nport);
	kid = fork();
	if (kid < 0)
		efail(c, "fork");
	if (kid == 0)
		selclient(c->iters, nport, ls);
	g_nk = 1;
	FD_ZERO(&all);
	for (k = 0; k < NSOCK; k++) {
		cn[k].fd = accept_fd(c, ls);
		cn[k].have = 0;
		cn[k].seq = 0;
		FD_SET(cn[k].fd, &all);
		if (cn[k].fd > maxfd)
			maxfd = cn[k].fd;
	}
	close(ls);
	while (st_more(c, got)) {
		rd = all;
		tv.tv_sec = 2;
		tv.tv_usec = 0;
		r = select(maxfd + 1, &rd, NULL, NULL, &tv);
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0)
			efail(c, "select");
		suspect = 0;
		if (r == 0) {
			/* 2 s of silence: is anything really ready? */
			rd = all;
			tv.tv_sec = tv.tv_usec = 0;
			r = select(maxfd + 1, &rd, NULL, NULL, &tv);
			if (r < 0 && errno != EINTR)
				efail(c, "select");
			if (r <= 0) {
				if (waitpid(kid, &status, WNOHANG) == kid) {
					g_kids[0] = 0;
					nfail(c, "reason=short got=%ld want=%ld status=0x%x", got, c->iters, status);
				}
				continue;
			}
			suspect = 1;
		}
		st_op_begin(c);
		frames = 0;
		for (k = 0; k < NSOCK; k++) {
			if (cn[k].fd < 0 || !FD_ISSET(cn[k].fd, &rd))
				continue;
			b = cn[k].buf;
			need = cn[k].have < HDR ? HDR - cn[k].have :
			       HDR + ((b[2] << 8) | b[3]) - cn[k].have;
			r = read(cn[k].fd, b + cn[k].have, need);
			if (r < 0 && errno == EINTR)
				continue;
			if (r < 0)
				efail(c, "read");
			if (r == 0) {
				/* the client finished and closed; frames on other sockets may remain */
				if (cn[k].have != 0)
					nfail(c, "reason=eof-partial sock=%d got=%ld", k, got);
				FD_CLR(cn[k].fd, &all);
				close(cn[k].fd);
				cn[k].fd = -1;
				continue;
			}
			cn[k].have += r;
			if (cn[k].have < HDR)
				continue;
			len = (b[2] << 8) | b[3];
			if (len > MAXPAY)
				nfail(c, "reason=badlen sock=%d len=%lu", k, len);
			if (cn[k].have < HDR + (int)len)
				continue;
			cn[k].have = 0;
			id = (b[0] << 8) | b[1];
			if (id != (unsigned long)k)
				nfail(c, "reason=crosstalk sock=%d id=%lu", k, id);
			seq = get32(b + 4);
			if (seq != cn[k].seq)
				nfail(c, "reason=seq sock=%d want=%lu got=%lu", k, cn[k].seq, seq);
			cn[k].seq++;
			bad = st_check(b + HDR, len, selkey(id, seq), 0);
			if (bad >= 0)
				dfail(c, "frame", b + HDR, len, selkey(id, seq), 0, bad);
			if (suspect) {
				/* select said nothing for 2 s, yet this frame was sent
				 * more than 500 ms ago (a clock step back reads as small) */
				now_us(&nsec, &nusec);
				sec = get32(b + 8);
				usec = get32(b + 12);
				gap = ((long)nsec - (long)sec) * 1000L + ((long)nusec - (long)usec) / 1000L;
				if (gap > 500)
					nfail(c, "reason=missed-wakeup sock=%d seq=%lu age=%ldms", k, seq, gap);
			}
			got++;
			frames++;
		}
		st_op_end(c, frames);
	}
	for (k = 0; k < NSOCK; k++)
		if (cn[k].fd >= 0)
			close(cn[k].fd);
	waitkid(c, 0);
	g_nk = 0;
}

static int
countfds(void)
{
	int fd, n = 0, max = getdtablesize();

	for (fd = 0; fd < max; fd++)
		if (fcntl(fd, F_GETFD) >= 0)
			n++;
	return n;
}

/* accept: connect, send 4 bytes, accept, close. Most clients abort with
 * SO_LINGER 0 so TIME_WAIT does not use up the ephemeral ports. */
static void
t_accept(struct st_ctx *c)
{
	struct linger lg;
	unsigned char b[4];
	unsigned short nport;
	unsigned long key;
	long i, bad;
	int before, after, ls, cl, a, r;

	before = countfds();
	ls = listen_local(c, &nport);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		cl = connect_local(nport);
		if (cl < 0)
			st_fail_errno(c, "connect");
		if (i % 16 != 15) {
			lg.l_onoff = 1;
			lg.l_linger = 0;
			setsockopt(cl, SOL_SOCKET, SO_LINGER, &lg, sizeof lg);
		}
		key = key3(c->idx, i);
		st_fill(b, 4, key, 0);
		if (writeall(cl, b, 4) < 0)
			st_fail_errno(c, "write");
		a = accept_fd(c, ls);
		r = readfull(a, b, 4);
		if (r < 0)
			st_fail_errno(c, "read");
		if (r > 0)
			st_fail(c, "reason=short conn=%ld", i);
		bad = st_check(b, 4, key, 0);
		if (bad >= 0)
			st_fail_data(c, "accept", b, 4, key, 0, bad);
		close(a);
		close(cl);
		st_op_end(c, 1);
	}
	close(ls);
	after = countfds();
	if (after != before)
		st_fail(c, "reason=fdleak before=%d after=%d", before, after);
}

#ifdef SCM_RIGHTS
struct fdmsg {
	struct cmsghdr h;
	int fd;
};

/* 0, or -1 with errno. */
static int
sendfd(int sock, int fd)
{
	struct msghdr m;
	struct iovec iov;
	struct fdmsg cm;
	char x = 'x';

	memset(&m, 0, sizeof m);
	memset(&cm, 0, sizeof cm);
	iov.iov_base = &x;
	iov.iov_len = 1;
	m.msg_iov = &iov;
	m.msg_iovlen = 1;
	cm.h.cmsg_len = sizeof cm;
	cm.h.cmsg_level = SOL_SOCKET;
	cm.h.cmsg_type = SCM_RIGHTS;
	cm.fd = fd;
	m.msg_control = (caddr_t)&cm;
	m.msg_controllen = sizeof cm;
	return sendmsg(sock, &m, 0) == 1 ? 0 : -1;
}

/* The received descriptor, or -1 with errno (EINVAL when none came). */
static int
recvfd(int sock)
{
	struct msghdr m;
	struct iovec iov;
	struct fdmsg cm;
	char x;

	memset(&m, 0, sizeof m);
	memset(&cm, 0, sizeof cm);
	iov.iov_base = &x;
	iov.iov_len = 1;
	m.msg_iov = &iov;
	m.msg_iovlen = 1;
	m.msg_control = (caddr_t)&cm;
	m.msg_controllen = sizeof cm;
	if (recvmsg(sock, &m, 0) != 1)
		return -1;
	if (m.msg_controllen < sizeof cm || cm.h.cmsg_type != SCM_RIGHTS) {
		errno = EINVAL;
		return -1;
	}
	return cm.fd;
}

static int
fdpass_probe(char *why, int len)
{
	int sv[2], f, g;
	const char *call;

	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
		sprintf(why, "socketpair: %s", st_errname(errno));
		return 1;
	}
	f = open("/dev/null", O_RDONLY);
	call = "sendmsg";
	if (f >= 0 && sendfd(sv[0], f) == 0) {
		call = "recvmsg";
		g = recvfd(sv[1]);
		if (g >= 0) {
			close(g);
			close(f);
			close(sv[0]);
			close(sv[1]);
			return 0;
		}
	}
	sprintf(why, "%s: %s", call, st_errname(errno));
	close(sv[0]);
	close(sv[1]);
	return 1;
}

/* A patterned, already unlinked file, open read-write. */
static int
mkfile(struct st_ctx *c, unsigned long key)
{
	static unsigned char buf[FDFILE];
	char path[300];
	int fd;

	st_path(c, path, sizeof path, "fd");
	unlink(path);
	fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (fd < 0)
		efail(c, "open");
	unlink(path);
	st_fill(buf, FDFILE, key, 0);
	if (writeall(fd, buf, FDFILE) < 0)
		efail(c, "write");
	return fd;
}

/* fdpass: the sender closes its descriptors (and the file is unlinked), so
 * the file lives only in the message; the received fd must read the data
 * and be the same inode. -x passes a different file. */
static void
t_fdpass(struct st_ctx *c)
{
	static unsigned char buf[FDFILE];
	struct stat want, got;
	unsigned long key, off;
	long i, badi, bad;
	int sv[2], f, wrong, nfd;

	badi = st_range(&c->rng, 0, c->iters - 1);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = key3(c->idx, i);
		f = mkfile(c, key);
		wrong = c->selfcheck && i == badi ? mkfile(c, key + 1) : f;
		if (fstat(f, &want) < 0)
			efail(c, "fstat");
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0)
			efail(c, "socketpair");
		if (sendfd(sv[0], wrong) < 0)
			efail(c, "sendmsg");
		close(f);
		if (wrong != f)
			close(wrong);
		nfd = recvfd(sv[1]);
		if (nfd < 0)
			efail(c, "recvmsg");
		close(sv[0]);
		close(sv[1]);
		off = st_range(&c->rng, 0, FDFILE - 1);
		if (lseek(nfd, off, SEEK_SET) < 0)
			efail(c, "lseek");
		if (readfull(nfd, buf, FDFILE - off) != 0)
			nfail(c, "reason=short off=0x%lx", off);
		bad = st_check(buf, FDFILE - off, key, off);
		if (bad >= 0)
			dfail(c, "fdfile", buf, FDFILE - off, key, off, bad);
		if (fstat(nfd, &got) < 0)
			efail(c, "fstat");
		if (got.st_ino != want.st_ino || got.st_dev != want.st_dev)
			nfail(c, "what=inode want=%lu got=%lu", (unsigned long)want.st_ino,
			      (unsigned long)got.st_ino);
		close(nfd);
		st_op_end(c, 1);
	}
}
#else
static int
fdpass_probe(char *why, int len)
{
	sprintf(why, "SCM_RIGHTS: not in the headers");
	return 1;
}

static void
t_fdpass(struct st_ctx *c)
{
}
#endif

/* storm: 64 connects arrive in a burst at a listener whose backlog is 5 while
 * the server is accepting. Even connections block in connect, odd ones
 * use a non-blocking connect and select. Refused, timed out and reset
 * connects are allowed; every connect that succeeded must be accepted and
 * carry a 64 byte message each way. -x corrupts one message. */
#define STORMN		64
#define STORMMSG	64
/* A SYN dropped on a full backlog is retransmitted in waves that back off
 * (a few seconds, then 12 s, 24 s ...), each admitting only about backlog
 * connects, so a burst can take tens of seconds. The connect itself gives
 * up with ETIMEDOUT after 75 s; select must report that before STORMWAIT. */
#define STORMWAIT	90

struct stormres {
	int count;	/* connections the client holds */
	int err;	/* 0, an unexpected errno, or -1: select timed out */
};

static int
storm_allowed(int e)
{
	return e == ECONNREFUSED || e == ETIMEDOUT || e == ECONNRESET;
}

static void
storm_msg(unsigned char *m, long iter, int dir, int conn)
{
	put32(m, conn);
	st_fill(m + 4, STORMMSG - 4, key3(iter * 2 + dir, conn), 0);
}

static void
stormclient(long iter, unsigned short nport, int pfd)
{
	struct stormres res;
	struct sockaddr_in sa;
	struct linger lg;
	struct timeval tv;
	fd_set wr;
	unsigned char m[STORMMSG];
	int fd[STORMN], pend[STORMN];
	int i, e, r, maxfd, npend = 0, sl;

	res.count = res.err = 0;
	local_addr(&sa, nport);
	for (i = 0; i < STORMN; i++) {
		fd[i] = -1;
		pend[i] = 0;
	}
	for (i = 1; i < STORMN; i += 2) {
		fd[i] = socket(AF_INET, SOCK_STREAM, 0);
		if (fd[i] < 0) {
			res.err = errno;
			goto report;
		}
		fcntl(fd[i], F_SETFL, O_NONBLOCK);
		if (connect(fd[i], (struct sockaddr *)&sa, sizeof sa) == 0)
			continue;
		if (errno == EINPROGRESS) {
			pend[i] = 1;
			npend++;
			continue;
		}
		e = errno;
		close(fd[i]);
		fd[i] = -1;
		if (!storm_allowed(e)) {
			res.err = e;
			goto report;
		}
	}
	for (i = 0; i < STORMN; i += 2) {
		fd[i] = socket(AF_INET, SOCK_STREAM, 0);
		if (fd[i] < 0) {
			res.err = errno;
			goto report;
		}
		if (connect(fd[i], (struct sockaddr *)&sa, sizeof sa) < 0) {
			e = errno;
			close(fd[i]);
			fd[i] = -1;
			if (!storm_allowed(e)) {
				res.err = e;
				goto report;
			}
		}
	}
	while (npend > 0) {
		FD_ZERO(&wr);
		maxfd = 0;
		for (i = 0; i < STORMN; i++)
			if (pend[i]) {
				FD_SET(fd[i], &wr);
				if (fd[i] > maxfd)
					maxfd = fd[i];
			}
		tv.tv_sec = STORMWAIT;
		tv.tv_usec = 0;
		r = select(maxfd + 1, NULL, &wr, NULL, &tv);
		if (r < 0 && errno == EINTR)
			continue;
		if (r <= 0) {
			res.err = r < 0 ? errno : -1;
			goto report;
		}
		for (i = 0; i < STORMN; i++) {
			if (!pend[i] || !FD_ISSET(fd[i], &wr))
				continue;
			pend[i] = 0;
			npend--;
			e = 0;
			sl = sizeof e;
			if (getsockopt(fd[i], SOL_SOCKET, SO_ERROR, &e, &sl) < 0)
				e = errno;
			if (e == 0)
				continue;
			close(fd[i]);
			fd[i] = -1;
			if (!storm_allowed(e)) {
				res.err = e;
				goto report;
			}
		}
	}
	lg.l_onoff = 1;
	lg.l_linger = 0;
	for (i = 0; i < STORMN; i++)
		if (fd[i] >= 0) {
			res.count++;
			fcntl(fd[i], F_SETFL, 0);
			setsockopt(fd[i], SOL_SOCKET, SO_LINGER, &lg, sizeof lg);
		}
report:
	if (write(pfd, &res, sizeof res) != sizeof res || res.err != 0)
		_exit(1);
	for (i = 0; i < STORMN; i++)
		if (fd[i] >= 0) {
			storm_msg(m, iter, 0, i);
			if (writeall(fd[i], m, STORMMSG) < 0)
				_exit(1);
		}
	for (i = 0; i < STORMN; i++)
		if (fd[i] >= 0) {
			if (readfull(fd[i], m, STORMMSG) != 0)
				_exit(1);
			if (get32(m) != (unsigned long)i ||
			    st_check(m + 4, STORMMSG - 4, key3(iter * 2 + 1, i), 0) >= 0)
				_exit(3);
		}
	_exit(0);
}

static void
t_storm(struct st_ctx *c)
{
	struct sockaddr_in sa;
	struct stormres res;
	struct timeval tv, t0, now;
	unsigned char m[STORMMSG], seen[STORMN];
	fd_set rd;
	pid_t kid;
	unsigned short nport;
	long i, badi, left, bad;
	int ls, pp[2], acc[STORMN], na, k, r, a, have, maxfd, conn, sl;

	g_kids = &kid;
	badi = st_range(&c->rng, 0, c->iters - 1);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		ls = socket(AF_INET, SOCK_STREAM, 0);
		if (ls < 0)
			efail(c, "socket");
		local_addr(&sa, 0);
		sl = sizeof sa;
		if (bind(ls, (struct sockaddr *)&sa, sizeof sa) < 0)
			efail(c, "bind");
		if (getsockname(ls, (struct sockaddr *)&sa, &sl) < 0)
			efail(c, "getsockname");
		nport = sa.sin_port;
		if (listen(ls, 5) < 0)
			efail(c, "listen");
		fcntl(ls, F_SETFL, O_NONBLOCK);
		if (pipe(pp) < 0)
			efail(c, "pipe");
		kid = fork();
		if (kid < 0)
			efail(c, "fork");
		if (kid == 0) {
			close(ls);
			close(pp[0]);
			stormclient(i, nport, pp[1]);
		}
		g_nk = 1;
		close(pp[1]);
		gettimeofday(&t0, NULL);
		na = have = 0;
		for (;;) {
			if (have && na >= res.count)
				break;
			gettimeofday(&now, NULL);
			left = STORMWAIT * 1000L + 30000L - ((now.tv_sec - t0.tv_sec) * 1000L + (now.tv_usec - t0.tv_usec) / 1000L);
			if (left <= 0)
				nfail(c, "reason=timeout accepted=%d want=%d", na, have ? res.count : -1);
			FD_ZERO(&rd);
			FD_SET(ls, &rd);
			maxfd = ls;
			if (!have) {
				FD_SET(pp[0], &rd);
				if (pp[0] > maxfd)
					maxfd = pp[0];
			}
			tv.tv_sec = left / 1000;
			tv.tv_usec = (left % 1000) * 1000;
			r = select(maxfd + 1, &rd, NULL, NULL, &tv);
			if (r < 0 && errno == EINTR)
				continue;
			if (r < 0)
				efail(c, "select");
			if (FD_ISSET(ls, &rd)) {
				a = accept(ls, NULL, NULL);
				if (a >= 0) {
					if (na >= STORMN)
						nfail(c, "reason=extra-accept");
					fcntl(a, F_SETFL, 0);
					acc[na++] = a;
				} else if (errno != EINTR && errno != EWOULDBLOCK && errno != ECONNABORTED)
					efail(c, "accept");
			}
			if (!have && FD_ISSET(pp[0], &rd)) {
				r = read(pp[0], &res, sizeof res);
				if (r < 0 && errno == EINTR)
					continue;
				if (r != sizeof res)
					nfail(c, "reason=peer-died accepted=%d", na);
				have = 1;
				if (res.err == -1)
					nfail(c, "reason=\"connect select timed out\" accepted=%d", na);
				if (res.err != 0)
					nfail(c, "reason=\"client: %s\" accepted=%d", st_errname(res.err), na);
			}
		}
		if (na != res.count)
			nfail(c, "reason=count accepted=%d connected=%d", na, res.count);
		memset(seen, 0, sizeof seen);
		for (k = 0; k < na; k++) {
			r = readfull(acc[k], m, STORMMSG);
			if (r < 0)
				efail(c, "read");
			if (r > 0)
				nfail(c, "reason=short conn=%d", k);
			conn = get32(m);
			if (conn >= STORMN || seen[conn])
				nfail(c, "reason=badconn conn=%d", conn);
			seen[conn] = 1;
			if (c->selfcheck && i == badi && k == 0)
				m[10] ^= 1;
			bad = st_check(m + 4, STORMMSG - 4, key3(i * 2, conn), 0);
			if (bad >= 0)
				dfail(c, "storm", m + 4, STORMMSG - 4, key3(i * 2, conn), 0, bad);
			storm_msg(m, i, 1, conn);
			if (writeall(acc[k], m, STORMMSG) < 0)
				efail(c, "write");
		}
		waitkid(c, 0);
		g_nk = 0;
		for (k = 0; k < na; k++)
			close(acc[k]);
		close(ls);
		close(pp[0]);
		st_op_end(c, na);
	}
}

/* flood: opt-in (STRESS_EXHAUST=1 or 2). Opens unix and TCP pairs until the
 * kernel or the process runs out, fills every writer until it would block
 * or has its share of FLOODFILL bytes, drains and checks every reader,
 * closes everything, and then a fresh TCP pair must still carry 64 KB. Only
 * the errnos of running out are allowed. The fill is budgeted because
 * sosend waits for mbufs even on a non-blocking socket: filling every
 * buffer to the brim on thousands of pairs uses up the cluster pool and
 * sleeps forever, taking the whole machine (sshd included) with it.
 * STRESS_EXHAUST=2 lifts the budget (fill every pair until EWOULDBLOCK or
 * ENOBUFS) and is expected to wedge current kernels. -x flips one byte of
 * the first drained chunk. */
#define FLOODMAX	4096
#define FLOODFILL	(1024L * 1024)
#define FLOODSMALL	100	/* per pair when there are too many for a cluster each */
#define FLOODBYTES	65536

static int fl_w[FLOODMAX], fl_r[FLOODMAX];
static unsigned long fl_n[FLOODMAX];

static int
flood_probe(char *why, int len)
{
	const char *e = getenv("STRESS_EXHAUST");

	if (e == NULL || (strcmp(e, "1") != 0 && strcmp(e, "2") != 0)) {
		sprintf(why, "needs STRESS_EXHAUST=1");
		return 1;
	}
	return 0;
}

static int
flood_out(int e)
{
	return e == EMFILE || e == ENFILE || e == ENOBUFS || e == ENOMEM ||
	       e == EADDRNOTAVAIL || e == ECONNREFUSED || e == ETIMEDOUT;
}

static int
flood_wouldblock(int e)
{
	return e == EWOULDBLOCK || e == ENOBUFS;
}

/* A TCP pair through ls: w connected, r accepted; 0, or -1 with errno. */
static int
tcp_pair(int ls, unsigned short nport, int *w, int *r)
{
	int e;

	*w = connect_local(nport);
	if (*w < 0)
		return -1;
	while ((*r = accept(ls, NULL, NULL)) < 0 && errno == EINTR)
		;
	if (*r < 0) {
		e = errno;
		close(*w);
		errno = e;
		return -1;
	}
	return 0;
}

static void
t_flood(struct st_ctx *c)
{
	static unsigned char buf[CHUNK];
	struct rlimit rl;
	struct linger lg;
	unsigned long total = 0, off, key;
	unsigned short nport;
	long bad, idle, cap;
	int ls, sv[2], np, i, w, r, e, n;

	getrlimit(RLIMIT_NOFILE, &rl);
	rl.rlim_cur = rl.rlim_max;
	setrlimit(RLIMIT_NOFILE, &rl);
	ls = listen_local(c, &nport);
	st_op_begin(c);
	for (np = 0; np < FLOODMAX; np++) {
		if (np % 2 == 0) {
			if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0)
				break;
			w = sv[0];
			r = sv[1];
		} else if (tcp_pair(ls, nport, &w, &r) < 0)
			break;
		fl_w[np] = w;
		fl_r[np] = r;
	}
	if (np < FLOODMAX && !flood_out(errno))
		efail(c, "pair");
	cap = strcmp(getenv("STRESS_EXHAUST"), "2") == 0 ? 0x7fffffffL :
	      np > 1000 ? FLOODSMALL : FLOODFILL / (np + 1);
	for (i = 0; i < np; i++) {
		key = key3(i, 0);
		fcntl(fl_w[i], F_SETFL, O_NONBLOCK);
		fcntl(fl_r[i], F_SETFL, O_NONBLOCK);
		while (fl_n[i] < cap) {
			n = cap - fl_n[i] < CHUNK ? cap - fl_n[i] : CHUNK;
			st_fill(buf, n, key, fl_n[i]);
			n = write(fl_w[i], buf, n);
			if (n > 0) {
				fl_n[i] += n;
				continue;
			}
			if (n < 0 && errno == EINTR)
				continue;
			if (n < 0 && flood_wouldblock(errno))
				break;
			efail(c, "write");
		}
		total += fl_n[i];
	}
	for (i = 0; i < np; i++) {
		key = key3(i, 0);
		idle = 0;
		for (off = 0; off < fl_n[i]; ) {
			n = read(fl_r[i], buf, fl_n[i] - off < CHUNK ? fl_n[i] - off : CHUNK);
			if (n < 0 && errno == EINTR)
				continue;
			if (n < 0 && errno == EWOULDBLOCK) {
				/* bytes still in flight or waiting for a window update */
				if (++idle > 2000)
					nfail(c, "reason=lost pair=%d got=%lu want=%lu", i, off, fl_n[i]);
				usleep(10000);
				continue;
			}
			if (n < 0)
				efail(c, "read");
			if (n == 0)
				nfail(c, "reason=short pair=%d got=%lu want=%lu", i, off, fl_n[i]);
			idle = 0;
			if (c->selfcheck && i == 0 && off == 0)
				buf[0] ^= 1;
			bad = st_check(buf, n, key, off);
			if (bad >= 0)
				dfail(c, "flood", buf, n, key, off, bad);
			off += n;
		}
	}
	lg.l_onoff = 1;
	lg.l_linger = 0;
	for (i = 0; i < np; i++) {
		if (i % 2 == 1) {
			setsockopt(fl_w[i], SOL_SOCKET, SO_LINGER, &lg, sizeof lg);
			setsockopt(fl_r[i], SOL_SOCKET, SO_LINGER, &lg, sizeof lg);
		}
		close(fl_w[i]);
		close(fl_r[i]);
	}
	st_op_end(c, np);
	fprintf(stderr, "stress: net flood pairs=%d bytes=%lu\n", np, total);

	/* recovery: a fresh TCP pair carries 64 KB, interleaved so neither side blocks */
	if (tcp_pair(ls, nport, &w, &r) < 0)
		efail(c, "connect");
	fcntl(w, F_SETFL, O_NONBLOCK);
	fcntl(r, F_SETFL, O_NONBLOCK);
	key = key3(FLOODMAX, 1);
	total = off = 0;
	idle = 0;
	while (off < FLOODBYTES) {
		n = 0;
		if (total < FLOODBYTES) {
			st_fill(buf, CHUNK, key, total);
			n = write(w, buf, FLOODBYTES - total < CHUNK ? FLOODBYTES - total : CHUNK);
			if (n > 0)
				total += n;
			else if (n < 0 && errno != EINTR && !flood_wouldblock(errno))
				efail(c, "write");
		}
		e = read(r, buf, CHUNK);
		if (e > 0) {
			bad = st_check(buf, e, key, off);
			if (bad >= 0)
				dfail(c, "recover", buf, e, key, off, bad);
			off += e;
			n = e;
		} else if (e == 0)
			nfail(c, "reason=short-recover got=%lu", off);
		else if (errno != EINTR && errno != EWOULDBLOCK)
			efail(c, "read");
		if (n > 0)
			idle = 0;
		else if (++idle > 20000)
			nfail(c, "reason=stuck-recover got=%lu sent=%lu", off, total);
		else
			usleep(1000);
	}
	close(w);
	close(r);
	close(ls);
}

static const struct st_test tests[] = {
	{ "tcp", 3, 1, NULL, t_tcp },
	{ "udp", 5000, 0, NULL, t_udp },
	{ "unix", 3, 1, NULL, t_unix },
	{ "select", 500, 1, NULL, t_select },
	{ "accept", 2000, 0, NULL, t_accept },
	{ "fdpass", 200, 0, fdpass_probe, t_fdpass },
	{ "storm", 20, 1, NULL, t_storm },
	{ "flood", 1, 1, flood_probe, t_flood, 1 },
	{ NULL, 0, 0, NULL, NULL }
};

int
main(int argc, char **argv)
{
	signal(SIGPIPE, SIG_IGN);
	return stress_main(argc, argv, "net", tests);
}
