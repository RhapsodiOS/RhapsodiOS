/*
	Portions adapted from Berkeley stdio code by Chris Torek.

	Copyright (c) 1990, 1993
	The Regents of the University of California. All rights reserved.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are
	met:
	1. Redistributions of source code must retain the above copyright notice,
	   this list of conditions and the following disclaimer.
	2. Redistributions in binary form must reproduce the above copyright
	   notice, this list of conditions and the following disclaimer in the
	   documentation and/or other materials provided with the distribution.
	3. All advertising materials mentioning features or use of this software
	   must display the following acknowledgement:
	   This product includes software developed by the University of California,
	   Berkeley and its contributors.
	4. Neither the name of the University nor the names of its contributors may
	   be used to endorse or promote products derived from this software without
	   specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
	EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/*	NSPrintf.m
	PPC Foundation formatted-output support.
*/

#if defined(__ppc__) || defined(__POWERPC__)

#include <stddef.h>
#include <stdarg.h>
#include <string.h>

typedef struct {
	void *base;
	size_t length;
} NSPrintfIOVector;

typedef struct {
	NSPrintfIOVector *vectors;
	int vectorCount;
	int remaining;
} NSPrintfIO;

typedef struct {
	unsigned char *base;
	int size;
} NSPrintfBuffer;

/* PPC FILE fields used here: _p 0, _w 8, _flags 12, _bf 16, _cookie 28,
 * and _write 44, as recovered from the formatter and writer bodies. */
typedef struct {
	unsigned char *position;
	int readCount;
	int writeCount;
	unsigned short flags;
	short file;
	NSPrintfBuffer buffer;
	int lineBufferSize;
	void *cookie;
	int (*closeFunction)(void *);
	int (*readFunction)(void *, char *, int);
	long (*seekFunction)(void *, long, int);
	int (*writeFunction)(void *, const char *, int);
} NSPrintfFile;

enum {
	NSPrintfUnbuffered = 0x0002,
	NSPrintfString = 0x0200,
	NSPrintfError = 0x0040
};

extern int fflush(NSPrintfFile *file);
extern int _NSvfprintf(NSPrintfFile *file, const char *format,
		va_list arguments);

int
__sfvwrite(NSPrintfFile *file, NSPrintfIO *output)
{
	NSPrintfIOVector *vector;
	unsigned char *source;
	size_t length;
	size_t amount;
	int written;

	if (output->remaining == 0)
		return 0;
	vector = output->vectors;
	source = (unsigned char *)vector->base;
	length = vector->length;
	++vector;

	if (file->flags & NSPrintfUnbuffered) {
		while (output->remaining != 0) {
			while (length == 0) {
				source = (unsigned char *)vector->base;
				length = vector->length;
				++vector;
			}
			amount = length > 1024 ? 1024 : length;
			written = (*file->writeFunction)(file->cookie,
				(const char *)source, (int)amount);
			if (written <= 0)
				goto writeError;
			source += written;
			length -= written;
			output->remaining -= written;
		}
		return 0;
	}

	/* The reference line-buffered branch reports success without consuming. */
	if (file->flags & 0x0001)
		return 0;

	while (output->remaining != 0) {
		while (length == 0) {
			source = (unsigned char *)vector->base;
			length = vector->length;
			++vector;
		}
		amount = (size_t)file->writeCount;
		if (file->flags & NSPrintfString) {
			if (length < amount)
				amount = length;
			memmove(file->position, source, amount);
			file->writeCount -= (int)amount;
			file->position += amount;
			amount = length;
		} else if (file->position <= file->buffer.base
			|| length <= amount) {
			if (length < (size_t)file->buffer.size) {
				amount = length;
				memmove(file->position, source, length);
				file->writeCount -= (int)length;
				file->position += length;
			} else {
				amount = (size_t)(*file->writeFunction)(file->cookie,
					(const char *)source, file->buffer.size);
				if ((int)amount <= 0)
					goto writeError;
			}
		} else {
			memmove(file->position, source, (size_t)file->writeCount);
			file->position += amount;
			if (fflush(file) != 0)
				goto writeError;
		}
		source += amount;
		length -= amount;
		output->remaining -= (int)amount;
	}
	return 0;

writeError:
	file->flags |= NSPrintfError;
	return -1;
}

int
__sprint(NSPrintfFile *file, NSPrintfIO *output)
{
	int error;

	if (output->remaining == 0) {
		output->vectorCount = 0;
		return 0;
	}
	error = __sfvwrite(file, output);
	output->remaining = 0;
	output->vectorCount = 0;
	return error;
}

int
_NSvsnprintf(char *buffer, size_t size, const char *format,
		va_list arguments)
{
	NSPrintfFile file;
	int result;

	if (size == 0)
		return -1;
	file.position = (unsigned char *)buffer;
	file.writeCount = (int)(size - 1);
	file.flags = 0x0208;
	file.buffer.base = (unsigned char *)buffer;
	file.buffer.size = (int)(size - 1);
	result = _NSvfprintf(&file, format, arguments);
	*file.position = 0;
	return result;
}

#endif /* PowerPC */

#if defined(__ppc__) || defined(__POWERPC__)

#include <limits.h>
#include <math.h>
#include <stdlib.h>

typedef unsigned long u_long;
typedef unsigned long long u_quad_t;
typedef long long quad_t;
typedef unsigned int u_int;
typedef unsigned short u_short;
#define __P(arguments) arguments
#define QUAD_MAX 0x7fffffffffffffffLL
#define FLOATING_POINT 1
#define MAXEXP 308
#define MAXFRACT 39
#define BUF (MAXEXP + MAXFRACT + 1)
#define DEFPREC 6
static char *cvt(double, int, int, char *, int *, int, int *);
static int exponent(char *, int, int);

/*
 * Macros for converting digits to letters and vice versa
 */
#define	to_digit(c)	((c) - '0')
#define is_digit(c)	((unsigned)to_digit(c) <= 9)
#define	to_char(n)	((n) + '0')

/*
 * Convert an unsigned long to ASCII for printf purposes, returning
 * a pointer to the first character of the string representation.
 * Octal numbers can be forced to have a leading zero; hex numbers
 * use the given digits.
 */
static char *
__ultoa(val, endp, base, octzero, xdigs)
	register u_long val;
	char *endp;
	int base, octzero;
	char *xdigs;
{
	register char *cp = endp;
	register long sval;

	/*
	 * Handle the three cases separately, in the hope of getting
	 * better/faster code.
	 */
	switch (base) {
	case 10:
		if (val < 10) {	/* many numbers are 1 digit */
			*--cp = to_char(val);
			return (cp);
		}
		/*
		 * On many machines, unsigned arithmetic is harder than
		 * signed arithmetic, so we do at most one unsigned mod and
		 * divide; this is sufficient to reduce the range of
		 * the incoming value to where signed arithmetic works.
		 */
		if (val > LONG_MAX) {
			*--cp = to_char(val % 10);
			sval = val / 10;
		} else
			sval = val;
		do {
			*--cp = to_char(sval % 10);
			sval /= 10;
		} while (sval != 0);
		break;

	case 8:
		do {
			*--cp = to_char(val & 7);
			val >>= 3;
		} while (val);
		if (octzero && *cp != '0')
			*--cp = '0';
		break;

	case 16:
		do {
			*--cp = xdigs[val & 15];
			val >>= 4;
		} while (val);
		break;

	default:			/* oops */
		abort();
	}
	return (cp);
}

/* Identical to __ultoa, but for quads. */
static char *
__uqtoa(val, endp, base, octzero, xdigs)
	register u_quad_t val;
	char *endp;
	int base, octzero;
	char *xdigs;
{
	register char *cp = endp;
	register quad_t sval;

	/* quick test for small values; __ultoa is typically much faster */
	/* (perhaps instead we should run until small, then call __ultoa?) */
	if (val <= ULONG_MAX)
		return (__ultoa((u_long)val, endp, base, octzero, xdigs));
	switch (base) {
	case 10:
		if (val < 10) {
			*--cp = to_char(val % 10);
			return (cp);
		}
		if (val > QUAD_MAX) {
			*--cp = to_char(val % 10);
			sval = val / 10;
		} else
			sval = val;
		do {
			*--cp = to_char(sval % 10);
			sval /= 10;
		} while (sval != 0);
		break;

	case 8:
		do {
			*--cp = to_char(val & 7);
			val >>= 3;
		} while (val);
		if (octzero && *cp != '0')
			*--cp = '0';
		break;

	case 16:
		do {
			*--cp = xdigs[val & 15];
			val >>= 4;
		} while (val);
		break;

	default:
		abort();
	}
	return (cp);
}

/*
 * Flags used during conversion.
 */
#define	ALT		0x001		/* alternate form */
#define	HEXPREFIX	0x002		/* add 0x or 0X prefix */
#define	LADJUST		0x004		/* left adjustment */
#define	LONGDBL		0x008		/* target accepts L but reads a double */
#define	LONGINT		0x010		/* long integer */
#define	QUADINT		0x020		/* quad integer */
#define	SHORTINT	0x040		/* short integer */
#define	ZEROPAD		0x080		/* zero (as opposed to blank) pad */
#define FPT		0x100		/* Floating point number */

int
_NSvfprintf(fp, fmt0, ap)
	NSPrintfFile *fp;
	const char *fmt0;
	va_list ap;
{
	register char *fmt;	/* format string */
	register int ch;	/* character from fmt */
	register int n;		/* handy integer (short term usage) */
	register char *cp;	/* handy char pointer (short term usage) */
	register NSPrintfIOVector *iovp;/* for PRINT macro */
	register int flags;	/* flags as above */
	int ret;		/* return value accumulator */
	int width;		/* width from format (%8d), or 0 */
	int prec;		/* precision from format (%.3d), or -1 */
	char sign;		/* sign prefix (' ', '+', '-', or \0) */
#ifdef FLOATING_POINT
	char softsign;		/* temporary negative sign for floats */
	double _double = 0;	/* double precision arguments %[eEfgG] */
	int expt;		/* integer value of exponent */
	int expsize = 0;	/* character count for expstr */
	int ndig;		/* actual number of digits returned by cvt */
	char expstr[7];		/* buffer for exponent string */
#endif
	u_long ulval = 0;	/* integer arguments %[diouxX] */
	u_quad_t uqval = 0;	/* %q integers */
	int base;		/* base for [diouxX] conversion */
	int dprec;		/* a copy of prec if [diouxX], 0 otherwise */
	int fieldsz;		/* field size expanded by sign, etc */
	int realsz;		/* field size expanded by dprec */
	int size;		/* size of converted field or string */
	char *xdigs = NULL;	/* digits for [xX] conversion */
#define NIOV 8
	NSPrintfIO uio;	/* output information: summary */
	NSPrintfIOVector iov[NIOV];/* ... and individual io vectors */
	char buf[BUF];		/* space for %c, %[diouxX], %[eEfgG] */
	char ox[2];		/* space for 0x hex-prefix */

	/*
	 * Choose PADSIZE to trade efficiency vs. size.  If larger printf
	 * fields occur frequently, increase PADSIZE and make the initialisers
	 * below longer.
	 */
#define	PADSIZE	16		/* pad chunk size */
	static char blanks[PADSIZE] =
	 {' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' '};
	static char zeroes[PADSIZE] =
	 {'0','0','0','0','0','0','0','0','0','0','0','0','0','0','0','0'};

	/*
	 * BEWARE, these `goto error' on error, and PAD uses `n'.
	 */
#define	PRINT(ptr, len) { \
	iovp->base = (ptr); \
	iovp->length = (len); \
	uio.remaining += (len); \
	iovp++; \
	if (++uio.vectorCount >= NIOV) { \
		if (__sprint(fp, &uio)) \
			goto error; \
		iovp = iov; \
	} \
}
#define	PAD(howmany, with) { \
	if ((n = (howmany)) > 0) { \
		while (n > PADSIZE) { \
			PRINT(with, PADSIZE); \
			n -= PADSIZE; \
		} \
		PRINT(with, n); \
	} \
}
#define	FLUSH() { \
	if (uio.remaining && __sprint(fp, &uio)) \
		goto error; \
	uio.vectorCount = 0; \
	iovp = iov; \
}

	/*
	 * To extend shorts properly, we need both signed and unsigned
	 * argument extraction methods.
	 */
#define	SARG() \
	(flags&LONGINT ? va_arg(ap, long) : \
	    flags&SHORTINT ? (long)(short)va_arg(ap, int) : \
	    (long)va_arg(ap, int))
#define	UARG() \
	(flags&LONGINT ? va_arg(ap, u_long) : \
	    flags&SHORTINT ? (u_long)(u_short)va_arg(ap, int) : \
	    (u_long)va_arg(ap, u_int))

	fmt = (char *)fmt0;
	uio.vectors = iovp = iov;
	uio.remaining = 0;
	uio.vectorCount = 0;
	ret = 0;

	/*
	 * Scan the format for conversions (`%' character).
	 */
	for (;;) {
		for (cp = fmt; (ch = *fmt) != '\0' && ch != '%'; fmt++)
			/* void */;
		if ((n = fmt - cp) != 0) {
			PRINT(cp, n);
			ret += n;
		}
		if (ch == '\0')
			goto done;
		fmt++;		/* skip over '%' */

		flags = 0;
		dprec = 0;
		width = 0;
		prec = -1;
		sign = '\0';

rflag:		ch = *fmt++;
reswitch:	switch (ch) {
		case ' ':
			/*
			 * ``If the space and + flags both appear, the space
			 * flag will be ignored.''
			 *	-- ANSI X3J11
			 */
			if (!sign)
				sign = ' ';
			goto rflag;
		case '#':
			flags |= ALT;
			goto rflag;
		case '*':
			/*
			 * ``A negative field width argument is taken as a
			 * - flag followed by a positive field width.''
			 *	-- ANSI X3J11
			 * They don't exclude field widths read from args.
			 */
			if ((width = va_arg(ap, int)) >= 0)
				goto rflag;
			width = -width;
			/* FALLTHROUGH */
		case '-':
			flags |= LADJUST;
			goto rflag;
		case '+':
			sign = '+';
			goto rflag;
		case '.':
			if ((ch = *fmt++) == '*') {
				n = va_arg(ap, int);
				prec = n < 0 ? -1 : n;
				goto rflag;
			}
			n = 0;
			while (is_digit(ch)) {
				n = 10 * n + to_digit(ch);
				ch = *fmt++;
			}
			prec = n < 0 ? -1 : n;
			goto reswitch;
		case '0':
			/*
			 * ``Note that 0 is taken as a flag, not as the
			 * beginning of a field width.''
			 *	-- ANSI X3J11
			 */
			flags |= ZEROPAD;
			goto rflag;
		case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
			n = 0;
			do {
				n = 10 * n + to_digit(ch);
				ch = *fmt++;
			} while (is_digit(ch));
			width = n;
			goto reswitch;
#ifdef FLOATING_POINT
		case 'L':
			flags |= LONGDBL;
			goto rflag;
#endif
		case 'h':
			flags |= SHORTINT;
			goto rflag;
		case 'l':
			flags |= LONGINT;
			goto rflag;
		case 'q':
			flags |= QUADINT;
			goto rflag;
		case 'c':
			*(cp = buf) = va_arg(ap, int);
			size = 1;
			sign = '\0';
			break;
		case 'D':
			flags |= LONGINT;
			/*FALLTHROUGH*/
		case 'd':
		case 'i':
			if (flags & QUADINT) {
				uqval = va_arg(ap, quad_t);
				if ((quad_t)uqval < 0) {
					uqval = -uqval;
					sign = '-';
				}
			} else {
				ulval = SARG();
				if ((long)ulval < 0) {
					ulval = -ulval;
					sign = '-';
				}
			}
			base = 10;
			goto number;
#ifdef FLOATING_POINT
		case 'e':		/* anomalous precision */
		case 'E':
			prec = (prec == -1) ?
				DEFPREC + 1 : prec + 1;
			/* FALLTHROUGH */
			goto fp_begin;
		case 'f':		/* always print trailing zeroes */
			if (prec != 0)
				flags |= ALT;
		case 'g':
		case 'G':
			if (prec == -1)
				prec = DEFPREC;
fp_begin:		_double = va_arg(ap, double);
			/* do this before tricky precision changes */
			if (isinf(_double)) {
				if (_double < 0)
					sign = '-';
				cp = "Inf";
				size = 3;
				break;
			}
			/* The PPC dtoa path handles NaN and supplies decpt = 9999. */
			flags |= FPT;
			cp = cvt(_double, prec, flags, &softsign,
				&expt, ch, &ndig);
			if (ch == 'g' || ch == 'G') {
				if (expt <= -4 || expt > prec)
					ch = (ch == 'g') ? 'e' : 'E';
				else
					ch = 'g';
			}
			if (ch <= 'e') {	/* 'e' or 'E' fmt */
				--expt;
				expsize = exponent(expstr, expt, ch);
				size = expsize + ndig;
				if (ndig > 1 || flags & ALT)
					++size;
			} else if (ch == 'f') {		/* f fmt */
				if (expt > 0) {
					size = expt;
					if (prec || flags & ALT)
						size += prec + 1;
				} else	/* "0.X" */
					size = prec + 2;
			} else if (expt >= ndig) {	/* fixed g fmt */
				size = expt;
				if (flags & ALT)
					++size;
			} else
				size = ndig + (expt > 0 ?
					1 : 2 - expt);

			if (softsign)
				sign = '-';
			break;
#endif /* FLOATING_POINT */

#endif /* PowerPC */
		case 'n':
			if (flags & QUADINT)
				*va_arg(ap, quad_t *) = ret;
			else if (flags & LONGINT)
				*va_arg(ap, long *) = ret;
			else if (flags & SHORTINT)
				*va_arg(ap, short *) = ret;
			else
				*va_arg(ap, int *) = ret;
			continue;	/* no output */
		case 'O':
			flags |= LONGINT;
			/*FALLTHROUGH*/
		case 'o':
			if (flags & QUADINT)
				uqval = va_arg(ap, u_quad_t);
			else
				ulval = UARG();
			base = 8;
			goto nosign;
		case 'p':
			/*
			 * ``The argument shall be a pointer to void.  The
			 * value of the pointer is converted to a sequence
			 * of printable characters, in an implementation-
			 * defined manner.''
			 *	-- ANSI X3J11
			 */
			ulval = (u_long)va_arg(ap, void *);
			base = 16;
			xdigs = "0123456789abcdef";
			flags = (flags & ~QUADINT) | HEXPREFIX;
			ch = 'x';
			goto nosign;
		case 's':
			if ((cp = va_arg(ap, char *)) == NULL)
				cp = "(null)";
			if (prec >= 0) {
				/*
				 * can't use strlen; can only look for the
				 * NUL in the first `prec' characters, and
				 * strlen() will go further.
				 */
				char *p = memchr(cp, 0, prec);

				if (p != NULL) {
					size = p - cp;
					if (size > prec)
						size = prec;
				} else
					size = prec;
			} else
				size = strlen(cp);
			sign = '\0';
			break;
		case 'U':
			flags |= LONGINT;
			/*FALLTHROUGH*/
		case 'u':
			if (flags & QUADINT)
				uqval = va_arg(ap, u_quad_t);
			else
				ulval = UARG();
			base = 10;
			goto nosign;
		case 'X':
			xdigs = "0123456789ABCDEF";
			goto hex;
		case 'x':
			xdigs = "0123456789abcdef";
hex:			if (flags & QUADINT)
				uqval = va_arg(ap, u_quad_t);
			else
				ulval = UARG();
			base = 16;
			/* leading 0x/X only if non-zero */
			if (flags & ALT &&
			    (flags & QUADINT ? uqval != 0 : ulval != 0))
				flags |= HEXPREFIX;

			/* unsigned conversions */
nosign:			sign = '\0';
			/*
			 * ``... diouXx conversions ... if a precision is
			 * specified, the 0 flag will be ignored.''
			 *	-- ANSI X3J11
			 */
number:			if ((dprec = prec) >= 0)
				flags &= ~ZEROPAD;

			/*
			 * ``The result of converting a zero value with an
			 * explicit precision of zero is no characters.''
			 *	-- ANSI X3J11
			 */
			cp = buf + BUF;
			if (flags & QUADINT) {
				if (uqval != 0 || prec != 0)
					cp = __uqtoa(uqval, cp, base,
					    flags & ALT, xdigs);
			} else {
				if (ulval != 0 || prec != 0)
					cp = __ultoa(ulval, cp, base,
					    flags & ALT, xdigs);
			}
			size = buf + BUF - cp;
			break;
		default:	/* "%?" prints ?, unless ? is NUL */
			if (ch == '\0')
				goto done;
			/* pretend it was %c with argument ch */
			cp = buf;
			*cp = ch;
			size = 1;
			sign = '\0';
			break;
		}

		/*
		 * All reasonable formats wind up here.  At this point, `cp'
		 * points to a string which (if not flags&LADJUST) should be
		 * padded out to `width' places.  If flags&ZEROPAD, it should
		 * first be prefixed by any sign or other prefix; otherwise,
		 * it should be blank padded before the prefix is emitted.
		 * After any left-hand padding and prefixing, emit zeroes
		 * required by a decimal [diouxX] precision, then print the
		 * string proper, then emit zeroes required by any leftover
		 * floating precision; finally, if LADJUST, pad with blanks.
		 *
		 * Compute actual size, so we know how much to pad.
		 * fieldsz excludes decimal prec; realsz includes it.
		 */
		fieldsz = size;
		if (sign)
			fieldsz++;
		else if (flags & HEXPREFIX)
			fieldsz += 2;
		realsz = dprec > fieldsz ? dprec : fieldsz;

		/* right-adjusting blank padding */
		if ((flags & (LADJUST|ZEROPAD)) == 0)
			PAD(width - realsz, blanks);

		/* prefix */
		if (sign) {
			PRINT(&sign, 1);
		} else if (flags & HEXPREFIX) {
			ox[0] = '0';
			ox[1] = ch;
			PRINT(ox, 2);
		}

		/* right-adjusting zero padding */
		if ((flags & (LADJUST|ZEROPAD)) == ZEROPAD)
			PAD(width - realsz, zeroes);

		/* leading zeroes from decimal precision */
		PAD(dprec - fieldsz, zeroes);

		/* the string or number proper */
#ifdef FLOATING_POINT
		if ((flags & FPT) == 0) {
			PRINT(cp, size);
		} else {	/* glue together f_p fragments */
			if (ch >= 'f') {	/* 'f' or 'g' */
				if (_double == 0) {
				/* kludge for __dtoa irregularity */
					if (prec == 0 ||
					    (flags & ALT) == 0) {
						PRINT("0", 1);
					} else {
						PRINT("0.", 2);
						PAD(ndig - 1, zeroes);
					}
				} else if (expt <= 0) {
					PRINT("0.", 2);
					PAD(-expt, zeroes);
					PRINT(cp, ndig);
				} else if (expt >= ndig) {
					PRINT(cp, ndig);
					PAD(expt - ndig, zeroes);
					if (flags & ALT)
						PRINT(".", 1);
				} else {
					PRINT(cp, expt);
					cp += expt;
					PRINT(".", 1);
					PRINT(cp, ndig-expt);
				}
			} else {	/* 'e' or 'E' */
				if (ndig > 1 || flags & ALT) {
					ox[0] = *cp++;
					ox[1] = '.';
					PRINT(ox, 2);
					if (_double != 0) {
						PRINT(cp, ndig-1);
					} else	/* 0.[0..] */
						/* __dtoa irregularity */
						PAD(ndig - 1, zeroes);
				} else	/* XeYYY */
					PRINT(cp, 1);
				PRINT(expstr, expsize);
			}
		}
#else
		PRINT(cp, size);
#endif
		/* left-adjusting padding (always blank) */
		if (flags & LADJUST)
			PAD(width - realsz, blanks);

		/* finally, adjust ret */
		ret += width > realsz ? width : realsz;

		FLUSH();	/* copy out the I/O vectors */
	}
done:
	FLUSH();
error:
	return ((fp->flags & NSPrintfError) ? -1 : ret);
	/* NOTREACHED */
}

#ifdef FLOATING_POINT

extern char *__dtoa __P((double, int, int, int *, int *, char **));

static char *
cvt(value, ndigits, flags, sign, decpt, ch, length)
	double value;
	int ndigits, flags, *decpt, ch, *length;
	char *sign;
{
	int mode, dsgn;
	char *digits, *bp, *rve;

	if (ch == 'f')
		mode = 3;
	else {
		mode = 2;
	}
	if (!(value >= 0)) {
		value = -value;
		*sign = '-';
	} else
		*sign = '\000';
	digits = __dtoa(value, mode, ndigits, decpt, &dsgn, &rve);
	if (flags & ALT) {	/* Print trailing zeros */
		bp = digits + ndigits;
		if (ch == 'f') {
			if (*digits == '0' && value)
				*decpt = -ndigits + 1;
			bp += *decpt;
		}
		if (value == 0)	/* kludge for __dtoa irregularity */
			rve = bp;
		while (rve < bp)
			*rve++ = '0';
	}
	*length = rve - digits;
	return (digits);
}

static int
exponent(p0, exp, fmtch)
	char *p0;
	int exp, fmtch;
{
	register char *p, *t;
	char expbuf[MAXEXP];

	p = p0;
	*p++ = fmtch;
	if (exp < 0) {
		exp = -exp;
		*p++ = '-';
	}
	else
		*p++ = '+';
	t = expbuf + MAXEXP;
	if (exp > 9) {
		do {
			*--t = to_char(exp % 10);
		} while ((exp /= 10) > 9);
		*--t = to_char(exp);
		for (; t < expbuf + MAXEXP; *p++ = *t++);
	}
	else {
		*p++ = '0';
		*p++ = to_char(exp);
	}
	return (p - p0);
}
#endif /* FLOATING_POINT */
