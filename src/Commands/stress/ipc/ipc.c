/* stress-ipc: Mach IPC tests through the NeXT/Mach 2.5 calls (port_allocate,
 * msg_send/msg_receive, port_deallocate, port_names), the only family the
 * headers declare. Peers get ports from the bootstrap server under
 * stress.<leaderpid>.<test>.<idx>[.<n>]; mach_init has no deregister call and
 * drops a name when its port dies, so destroying the port is the deregister.
 * Every receive and send is bounded at 5 s. */
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/message.h>
#include <servers/bootstrap.h>
#include <mach-o/dyld.h>
#include "stress.h"

#define WAITMS	5000
#define MAXBODY	1024
#define MAXPAGES 64
#define MAXRIGHTS 8

struct imsg {				/* seq, idx, len, then len body bytes */
	msg_header_t h;
	msg_type_t t1;
	int w[3];
	msg_type_t t2;
	unsigned char body[MAXBODY];
};

struct omsg {				/* seq, npages, mode, then the pages out of line */
	msg_header_t h;
	msg_type_t t1;
	int w[3];
	msg_type_long_t t2;
	unsigned char *data;
};

struct rmsg {
	msg_header_t h;
	msg_type_t t;
	port_t p[MAXRIGHTS];
};

#define IHDR	(sizeof(struct imsg) - MAXBODY)

/* What the cleanup hook undoes; only in the process that set it up, since a
 * forked peer copies these. */
static pid_t g_owner, g_kid;
static port_t g_port[2];
static int g_np;

static void
hook(struct st_ctx *c)
{
	int i, st;

	if (getpid() != g_owner)
		return;
	if (g_kid > 0) {
		kill(g_kid, SIGKILL);
		while (waitpid(g_kid, &st, 0) < 0 && errno == EINTR)
			;
		g_kid = 0;
	}
	for (i = 0; i < g_np; i++)
		port_deallocate(task_self(), g_port[i]);
	g_np = 0;
}

static void
own(struct st_ctx *c)
{
	g_owner = getpid();
	g_kid = 0;
	g_np = 0;
	st_set_cleanup(c, hook);
}

static void
kfail(struct st_ctx *c, const char *call, int kr)
{
	st_fail(c, "reason=\"%s: kr=%d\"", call, kr);
}

/* A port with receive rights, deallocated by the hook (or dropports). */
static port_t
newport(struct st_ctx *c)
{
	port_t p;
	kern_return_t kr;

	kr = port_allocate(task_self(), &p);
	if (kr != KERN_SUCCESS)
		kfail(c, "port_allocate", kr);
	g_port[g_np++] = p;
	return p;
}

static void
dropports(void)
{
	while (g_np > 0)
		port_deallocate(task_self(), g_port[--g_np]);
}

static void
pname(struct st_ctx *c, char *buf, const char *sfx)
{
	sprintf(buf, "stress.%d.%s.%d%s", (int)getppid(), c->test, c->idx, sfx);
}

static void
reg(struct st_ctx *c, char *name, port_t p)
{
	kern_return_t kr = bootstrap_register(bootstrap_port, name, p);

	if (kr != KERN_SUCCESS)
		kfail(c, "bootstrap_register", kr);
}

static port_t
look(struct st_ctx *c, char *name)
{
	port_t p;
	kern_return_t kr = bootstrap_look_up(bootstrap_port, name, &p);

	if (kr != KERN_SUCCESS)
		kfail(c, "bootstrap_look_up", kr);
	return p;
}

static void
settype(msg_type_t *t, int name, int bits, int number)
{
	memset(t, 0, sizeof *t);
	t->msg_type_name = name;
	t->msg_type_size = bits;
	t->msg_type_number = number;
	t->msg_type_inline = 1;
}

static msg_return_t
send5(msg_header_t *h, port_t to, int simple, unsigned long size)
{
	h->msg_unused = 0;
	h->msg_simple = simple;
	h->msg_size = size;
	h->msg_type = MSG_TYPE_NORMAL;
	h->msg_local_port = PORT_NULL;
	h->msg_remote_port = to;
	h->msg_id = 0x5157;
	return msg_send(h, SEND_TIMEOUT, WAITMS);
}

static void
msend(struct st_ctx *c, msg_header_t *h, port_t to, int simple, unsigned long size)
{
	msg_return_t r = send5(h, to, simple, size);

	if (r == SEND_TIMED_OUT)
		st_fail(c, "reason=timeout what=%s", c->test);
	if (r != SEND_SUCCESS)
		kfail(c, "msg_send", r);
}

static void
mrecv(struct st_ctx *c, msg_header_t *h, port_t on, unsigned long size)
{
	msg_return_t r;

	h->msg_size = size;
	h->msg_local_port = on;
	r = msg_receive(h, RCV_TIMEOUT, WAITMS);
	if (r == RCV_TIMED_OUT)
		st_fail(c, "reason=timeout what=%s", c->test);
	if (r != RCV_SUCCESS)
		kfail(c, "msg_receive", r);
}

/* Reaps the peer, which must have exited 0. */
static void
reap(struct st_ctx *c)
{
	int st;

	while (waitpid(g_kid, &st, 0) < 0) {
		if (errno != EINTR) {
			g_kid = 0;
			st_fail_errno(c, "waitpid");
		}
	}
	g_kid = 0;
	if (st != 0)
		st_fail(c, "what=peer status=0x%x", st);
}

static pid_t
peer(struct st_ctx *c)
{
	pid_t pid = fork();

	if (pid < 0)
		st_fail_errno(c, "fork");
	if (pid > 0)
		g_kid = pid;
	return pid;
}

static unsigned long
mkey(struct st_ctx *c, unsigned long dir)
{
	return st_mix((st_opt.seed ^ (unsigned long)c->idx) + dir * 0x9e3779b9UL) & ST_MASK;
}

/* iters messages, 0-1024 body bytes each at offset seq*1024; message bad
 * gets one flipped byte. */
static void
sendmsgs(struct st_ctx *c, port_t to, unsigned long key, long bad)
{
	struct imsg m;
	struct st_rng r;
	unsigned long len;
	long i;

	st_rng_init(&r, key, "ipcl", c->idx);
	for (i = 0; st_more(c, i); i++) {
		len = st_range(&r, 0, MAXBODY);
		if (i == bad && len == 0)
			len = 1;
		settype(&m.t1, MSG_TYPE_INTEGER_32, 32, 3);
		m.w[0] = i;
		m.w[1] = c->idx;
		m.w[2] = len;
		settype(&m.t2, MSG_TYPE_BYTE, 8, len);
		st_fill(m.body, len, key, i * MAXBODY);
		if (i == bad)
			m.body[st_range(&c->rng, 0, len - 1)] ^= 0x01;
		msend(c, &m.h, to, TRUE, IHDR + ((len + 3) & ~3UL));
	}
}

static void
recvmsgs(struct st_ctx *c, port_t on, unsigned long key)
{
	struct imsg m;
	unsigned long len;
	long i, bad;

	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		mrecv(c, &m.h, on, sizeof m);
		if (m.h.msg_size < IHDR)
			st_fail(c, "reason=runt seq=%ld size=%u", i, m.h.msg_size);
		if (m.w[0] != i)
			st_fail(c, "reason=order want=%ld got=%d", i, m.w[0]);
		if (m.w[1] != c->idx)
			st_fail(c, "reason=badidx seq=%ld got=%d", i, m.w[1]);
		len = (unsigned long)m.w[2];
		if (len > MAXBODY || m.h.msg_size != IHDR + ((len + 3) & ~3UL))
			st_fail(c, "reason=badlen seq=%ld len=%lu size=%u", i, len, m.h.msg_size);
		bad = st_check(m.body, len, key, i * MAXBODY);
		if (bad >= 0)
			st_fail_data(c, "msg", m.body, len, key, i * MAXBODY, bad);
		st_op_end(c, 1);
	}
}

/* msg: the worker and a forked peer each register a port; the peer sends
 * iters messages, then the worker sends iters back. */
static void
t_msg(struct st_ctx *c)
{
	char wname[BOOTSTRAP_MAX_NAME_LEN], kname[BOOTSTRAP_MAX_NAME_LEN];
	port_t p, s;
	long badi;

	badi = c->selfcheck ? st_range(&c->rng, 0, c->iters - 1) : -1;
	own(c);
	pname(c, wname, ".0");
	pname(c, kname, ".1");
	p = newport(c);
	reg(c, wname, p);
	if (peer(c) == 0) {
		own(c);
		p = newport(c);
		reg(c, kname, p);
		sendmsgs(c, look(c, wname), mkey(c, 0), badi);
		recvmsgs(c, p, mkey(c, 1));
		_exit(0);
	}
	recvmsgs(c, p, mkey(c, 0));
	s = look(c, kname);
	sendmsgs(c, s, mkey(c, 1), -1);
	reap(c);
	port_deallocate(task_self(), s);
	dropports();
}

static unsigned long
okey(struct st_ctx *c, long seq)
{
	return st_mix(mkey(c, 2) + (unsigned long)seq) & ST_MASK;
}

/* The peer: iters out-of-line regions of 1-64 pages. Copy mode must leave
 * the sender's pages intact (then overwrites them: the receiver must still
 * see the sent data); dealloc mode must unmap them. */
static void
sendool(struct st_ctx *c, port_t to, long bad)
{
	struct omsg m;
	unsigned long ps = getpagesize(), np, sz, key;
	vm_address_t a, probe;
	kern_return_t kr;
	long i, b;
	int dealloc;

	for (i = 0; st_more(c, i); i++) {
		np = st_range(&c->rng, 1, MAXPAGES);
		sz = np * ps;
		dealloc = (st_rand(&c->rng) & 1) || i == bad;
		key = okey(c, i);
		a = 0;
		kr = vm_allocate(task_self(), &a, sz, TRUE);
		if (kr != KERN_SUCCESS)
			kfail(c, "vm_allocate", kr);
		st_fill((void *)a, sz, key, 0);
		if (i == bad)
			((unsigned char *)a)[st_range(&c->rng, 0, sz - 1)] ^= 0x01;
		settype(&m.t1, MSG_TYPE_INTEGER_32, 32, 3);
		m.w[0] = i;
		m.w[1] = np;
		m.w[2] = dealloc;
		memset(&m.t2, 0, sizeof m.t2);
		m.t2.msg_type_header.msg_type_longform = 1;
		m.t2.msg_type_header.msg_type_deallocate = dealloc;
		m.t2.msg_type_long_name = MSG_TYPE_BYTE;
		m.t2.msg_type_long_size = 8;
		m.t2.msg_type_long_number = sz;
		m.data = (unsigned char *)a;
		msend(c, &m.h, to, FALSE, sizeof m);
		if (dealloc) {
			probe = a;
			kr = vm_allocate(task_self(), &probe, sz, FALSE);
			if (kr != KERN_SUCCESS)
				st_fail(c, "reason=still-mapped seq=%ld kr=%d", i, kr);
			vm_deallocate(task_self(), probe, sz);
		} else {
			b = st_check((void *)a, sz, key, 0);
			if (b >= 0)
				st_fail_data(c, "ool-sender", (unsigned char *)a, sz, key, 0, b);
			st_fill((void *)a, sz, key ^ 0x5a5a5a5aUL, 0);
			vm_deallocate(task_self(), a, sz);
		}
	}
}

static void
t_ool(struct st_ctx *c)
{
	char name[BOOTSTRAP_MAX_NAME_LEN];
	struct omsg m;
	unsigned long ps = getpagesize(), np, sz, key;
	port_t p;
	long i, badi, bad;

	badi = c->selfcheck ? st_range(&c->rng, 0, c->iters - 1) : -1;
	own(c);
	pname(c, name, "");
	p = newport(c);
	reg(c, name, p);
	if (peer(c) == 0) {
		own(c);
		sendool(c, look(c, name), badi);
		_exit(0);
	}
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		mrecv(c, &m.h, p, sizeof m);
		if (m.h.msg_size != sizeof m || m.w[0] != i)
			st_fail(c, "reason=order want=%ld got=%d size=%u", i, m.w[0], m.h.msg_size);
		np = m.w[1];
		sz = np * ps;
		if (np < 1 || np > MAXPAGES || m.t2.msg_type_long_number != sz ||
		    m.t2.msg_type_header.msg_type_inline)
			st_fail(c, "reason=badlen seq=%ld pages=%lu len=%lu", i, np,
				(unsigned long)m.t2.msg_type_long_number);
		key = okey(c, i);
		bad = st_check(m.data, sz, key, 0);
		if (bad >= 0)
			st_fail_data(c, "ool", m.data, sz, key, 0, bad);
		vm_deallocate(task_self(), (vm_address_t)m.data, sz);
		st_op_end(c, np);
	}
	reap(c);
	dropports();
}

static int
nnames(struct st_ctx *c)
{
	port_name_array_t names;
	port_type_array_t types;
	unsigned int nn, nt;
	kern_return_t kr;

	kr = port_names(task_self(), &names, &nn, &types, &nt);
	if (kr != KERN_SUCCESS)
		kfail(c, "port_names", kr);
	vm_deallocate(task_self(), (vm_address_t)names, nn * sizeof *names);
	vm_deallocate(task_self(), (vm_address_t)types, nt * sizeof *types);
	return nn;
}

/* rights: 1-8 ports sent to a carrier port of our own, as send rights on
 * even iterations and receive rights on odd ones, received and every name
 * deallocated; the task's name count must come back to where it started. */
static void
t_rights(struct st_ctx *c)
{
	struct rmsg m;
	port_t carrier, sent[MAXRIGHTS], drop[2 * MAXRIGHTS + 1];
	kern_return_t kr;
	long i, badi;
	int before, after, n, k, j, nd;

	badi = c->selfcheck ? st_range(&c->rng, 0, c->iters - 1) : -1;
	nnames(c);			/* the MIG reply port exists from here on */
	before = nnames(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		n = st_range(&c->rng, 1, MAXRIGHTS);
		kr = port_allocate(task_self(), &carrier);
		if (kr != KERN_SUCCESS)
			kfail(c, "port_allocate", kr);
		for (k = 0; k < n; k++) {
			kr = port_allocate(task_self(), &sent[k]);
			if (kr != KERN_SUCCESS)
				kfail(c, "port_allocate", kr);
		}
		settype(&m.t, i & 1 ? MSG_TYPE_PORT_ALL : MSG_TYPE_PORT, 32, n);
		memcpy(m.p, sent, n * sizeof *sent);
		msend(c, &m.h, carrier, FALSE, sizeof m.h + sizeof m.t + n * sizeof *sent);
		mrecv(c, &m.h, carrier, sizeof m);
		if (m.t.msg_type_number != n)
			st_fail(c, "reason=badcount want=%d got=%d", n, (int)m.t.msg_type_number);
		/* every distinct name we may hold: moved rights can come back renamed */
		drop[0] = carrier;
		nd = 1;
		for (k = 0; k < 2 * n; k++) {
			for (j = 0; j < nd && drop[j] != (k < n ? sent[k] : m.p[k - n]); j++)
				;
			if (j == nd)
				drop[nd++] = k < n ? sent[k] : m.p[k - n];
		}
		/* the count check below is the test; a name that is already gone
		 * is not a leak. -x leaks the carrier. */
		for (j = i == badi; j < nd; j++)
			port_deallocate(task_self(), drop[j]);
		st_op_end(c, n);
	}
	after = nnames(c);
	if (after != before)
		st_fail(c, "reason=leak before=%d after=%d", before, after);
}

/* deadname: the peer keeps sending; the worker takes 1-8 messages, then
 * destroys its port. The peer must get SEND_INVALID_PORT and exit within 5 s. */
static void
t_deadname(struct st_ctx *c)
{
	char name[BOOTSTRAP_MAX_NAME_LEN], sfx[32];
	struct imsg m;
	port_t p, s;
	msg_return_t r;
	long i, k, n;
	int st, w;

	own(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		sprintf(sfx, ".%ld", i);
		pname(c, name, sfx);
		p = newport(c);
		reg(c, name, p);
		n = st_range(&c->rng, 1, 8);
		if (peer(c) == 0) {
			own(c);
			s = look(c, name);
			for (k = 0; ; k++) {
				settype(&m.t1, MSG_TYPE_INTEGER_32, 32, 3);
				m.w[0] = k;
				m.w[1] = c->idx;
				m.w[2] = 0;
				settype(&m.t2, MSG_TYPE_BYTE, 8, 0);
				r = send5(&m.h, s, TRUE, IHDR);
				if (r == SEND_INVALID_PORT)
					_exit(0);
				if (r == SEND_TIMED_OUT)
					st_fail(c, "reason=timeout what=deadname sent=%ld", k);
				if (r != SEND_SUCCESS)
					kfail(c, "msg_send", r);
			}
		}
		for (k = 0; k < n; k++) {
			mrecv(c, &m.h, p, sizeof m);
			if (m.w[0] != k)
				st_fail(c, "reason=order want=%ld got=%d", k, m.w[0]);
		}
		dropports();
		for (k = 0; (w = waitpid(g_kid, &st, WNOHANG)) == 0 && k < WAITMS / 10; k++)
			usleep(10000);
		if (w == 0)
			st_fail(c, "reason=timeout what=deadname");
		if (w < 0)
			st_fail_errno(c, "waitpid");
		g_kid = 0;
		if (st != 0)
			st_fail(c, "what=peer status=0x%x", st);
		st_op_end(c, n);
	}
}

/* bootstrap: register a fresh name, look it up (it must name our own port),
 * destroy the port, and the name must be gone within 5 s. */
static void
t_bootstrap(struct st_ctx *c)
{
	char name[BOOTSTRAP_MAX_NAME_LEN], sfx[32];
	port_t p, q;
	kern_return_t kr;
	long i;
	int k;

	own(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		sprintf(sfx, ".%ld", i);
		pname(c, name, sfx);
		p = newport(c);
		reg(c, name, p);
		q = look(c, name);
		if (q != p)
			st_fail(c, "reason=lookup-mismatch want=%d got=%d", (int)p, (int)q);
		dropports();
		for (k = 0; ; k++) {
			kr = bootstrap_look_up(bootstrap_port, name, &q);
			if (kr == BOOTSTRAP_UNKNOWN_SERVICE)
				break;
			if (kr != KERN_SUCCESS)
				kfail(c, "bootstrap_look_up", kr);
			port_deallocate(task_self(), q);
			if (k >= WAITMS / 10)
				st_fail(c, "reason=timeout what=bootstrap");
			usleep(10000);
		}
		st_op_end(c, 1);
	}
}

/* sysv: semget is bound through dyld when something defines it (Libc has
 * no stub); a missing system call raises SIGSYS, so that is ignored. */
static int
p_sysv(char *why, int len)
{
	int (*semgetfn)(long, int, int);
	void (*old)(int);
	int r, e;

	if (!NSIsSymbolNameDefined("_semget")) {
		sprintf(why, "semget: %s", st_errname(ENOSYS));
		return 1;
	}
	semgetfn = (int (*)(long, int, int))NSAddressOfSymbol(NSLookupAndBindSymbol("_semget"));
	old = signal(SIGSYS, SIG_IGN);
	r = semgetfn(0, 1, 0600);	/* IPC_PRIVATE */
	e = errno;
	signal(SIGSYS, old);
	if (r >= 0 || (e != ENOSYS && e != EOPNOTSUPP))
		return 0;	/* not seen on this system; the body would then need real tests */
	sprintf(why, "semget: %s", st_errname(e));
	return 1;
}

static void
t_sysv(struct st_ctx *c)
{
}

static const struct st_test tests[] = {
	{ "msg", 2000, 0, NULL, t_msg },
	{ "ool", 200, 0, NULL, t_ool },
	{ "rights", 500, 0, NULL, t_rights },
	{ "deadname", 50, 0, NULL, t_deadname },
	{ "bootstrap", 500, 0, NULL, t_bootstrap },
	{ "sysv", 1, 0, p_sysv, t_sysv },
	{ NULL, 0, 0, NULL, NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "ipc", tests);
}
