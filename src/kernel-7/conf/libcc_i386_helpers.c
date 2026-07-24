/*
 * i386 soft 64-bit helpers for RELEASE_I386 mach_kernel link.
 * Symbol names use a single leading underscore in C so Mach-O exports
 * match ppc libcc.a (__muldi3, not ___muldi3).
 */
typedef unsigned long long UDItype;
typedef long long DItype;

DItype
_muldi3(DItype u, DItype v)
{
	unsigned int u0 = (unsigned int)u;
	unsigned int u1 = (unsigned int)((UDItype)u >> 32);
	unsigned int v0 = (unsigned int)v;
	unsigned int v1 = (unsigned int)((UDItype)v >> 32);
	UDItype p0 = (UDItype)u0 * (UDItype)v0;
	UDItype p1 = (UDItype)u1 * (UDItype)v0;
	UDItype p2 = (UDItype)u0 * (UDItype)v1;

	return (DItype)(p0 + ((p1 + p2) << 32));
}

static UDItype
udivmoddi4(UDItype num, UDItype den, UDItype *rem_p)
{
	UDItype q = 0;
	UDItype r = 0;
	int i;

	if (den == 0)
		return 0;
	for (i = 63; i >= 0; i--) {
		r = (r << 1) | ((num >> i) & 1);
		if (r >= den) {
			r -= den;
			q |= (UDItype)1 << i;
		}
	}
	if (rem_p)
		*rem_p = r;
	return q;
}

DItype
_divdi3(DItype u, DItype v)
{
	int neg = 0;
	UDItype uu, vv, q;

	if (u < 0) {
		uu = (UDItype)(-u);
		neg = !neg;
	} else
		uu = (UDItype)u;
	if (v < 0) {
		vv = (UDItype)(-v);
		neg = !neg;
	} else
		vv = (UDItype)v;
	q = udivmoddi4(uu, vv, 0);
	return neg ? -(DItype)q : (DItype)q;
}

DItype
_moddi3(DItype u, DItype v)
{
	int neg = 0;
	UDItype uu, vv, r;

	if (u < 0) {
		uu = (UDItype)(-u);
		neg = 1;
	} else
		uu = (UDItype)u;
	if (v < 0)
		vv = (UDItype)(-v);
	else
		vv = (UDItype)v;
	(void)udivmoddi4(uu, vv, &r);
	return neg ? -(DItype)r : (DItype)r;
}

UDItype
_udivdi3(UDItype u, UDItype v)
{
	return udivmoddi4(u, v, 0);
}

UDItype
_umoddi3(UDItype u, UDItype v)
{
	UDItype r;

	(void)udivmoddi4(u, v, &r);
	return r;
}
