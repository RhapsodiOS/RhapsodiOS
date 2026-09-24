/*
 * Test of HFS Plus long-name mangling: ConvertUnicodeToUTF8Mangled, and
 * GetEmbeddedFileID reading its names back (UnicodeWrappers.c).
 *
 * run-tests.sh builds this on the build box, against the real ConvertUTF.c
 * and the functions extract.py takes from UnicodeWrappers.c (extracted.c).
 */
#include <stdio.h>
#include <string.h>
#include "ConvertUTF.h"

typedef short			OSErr;
typedef unsigned long	ByteCount;
typedef unsigned long	ItemCount;
typedef unsigned char	UInt8;
typedef unsigned short	UInt16;
typedef unsigned long	UInt32;
typedef long			SInt32;
typedef unsigned char	Boolean;
typedef unsigned short	UniChar;
typedef const UniChar	*ConstUniCharArrayPtr;
typedef UInt32			HFSCatalogNodeID;

enum { noErr = 0, kTECPartialCharErr = -8753, kTECOutputBufferFullStatus = -8785 };
#define NAME_MAX	255
#define true		1
#define false		0
#define BlockMoveData(src, dst, len)	memmove((dst), (src), (len))

#include "extracted.c"

static int failures;

static void fail(const char *what, const char *why)
{
	printf("FAIL %s: %s\n", what, why);
	failures++;
}

/*
 * The comparison LocateCatalogNodeByMangledName (CatalogUtilities.c) makes,
 * which cannot be linked here because it needs the catalog: the name must
 * carry the node's ID, and the node's real name, converted into NAME_MAX + 1
 * bytes, must start with the mangled name's prefix.
 */
static int matcherAccepts(const UniChar *name, ItemCount n, const unsigned char *mangled,
						  HFSCatalogNodeID cnid)
{
	unsigned char	nodeName[NAME_MAX + 1];
	ByteCount		actualDstLen;
	UInt32			prefixlen;

	if (GetEmbeddedFileID(mangled, &prefixlen) != cnid)
		return 0;
	(void) ConvertUnicodeToUTF8(n * sizeof(UniChar), name, sizeof nodeName, &actualDstLen, nodeName);
	return actualDstLen >= prefixlen && memcmp(nodeName, mangled, prefixlen) == 0;
}

/*
 * Mangle name[0..n) with cnid and check that the result is wantPrefix bytes
 * of the name followed by wantSuffix, then that it reads back.
 */
static void check(const char *what, const UniChar *name, ItemCount n, HFSCatalogNodeID cnid,
				  ByteCount wantPrefix, const char *wantSuffix)
{
	unsigned char	out[NAME_MAX + 1 + 16];
	unsigned char	plain[3 * 255 + 1];
	ByteCount		len, plainLen;
	UInt32			prefixlen;

	memset(out, 0xAA, sizeof out);
	if (ConvertUnicodeToUTF8Mangled(n * sizeof(UniChar), name, NAME_MAX + 1, &len, out, cnid) != noErr)
		{ fail(what, "returned an error"); return; }
	if (memchr(out, 0, NAME_MAX + 1) == NULL)
		{ fail(what, "no NUL in the first NAME_MAX + 1 bytes"); return; }
	if (out[NAME_MAX + 1] != 0xAA)
		{ fail(what, "wrote past NAME_MAX + 1 bytes"); return; }
	if (strlen((char *) out) != len)
		{ fail(what, "actualDstLen is not the length"); return; }
	if (len != wantPrefix + strlen(wantSuffix)) {
		printf("     got %lu bytes, ending \"%s\"\n", len, (char *) out + (len > 24 ? len - 24 : 0));
		fail(what, "wrong length");
		return;
	}
	if (strcmp((char *) out + wantPrefix, wantSuffix) != 0)
		{ fail(what, "wrong file ID or extension"); return; }

	(void) ConvertUnicodeToUTF8(n * sizeof(UniChar), name, sizeof plain, &plainLen, plain);
	if (memcmp(out, plain, wantPrefix) != 0)
		{ fail(what, "the prefix is not the start of the name"); return; }
	if ((plain[wantPrefix] & 0xC0) == 0x80)
		{ fail(what, "the prefix ends inside a character"); return; }

	if (GetEmbeddedFileID(out, &prefixlen) != cnid)
		{ fail(what, "GetEmbeddedFileID read the wrong file ID"); return; }
	if (prefixlen != wantPrefix)
		{ fail(what, "GetEmbeddedFileID read the wrong prefix length"); return; }
	if (!matcherAccepts(name, n, out, cnid))
		{ fail(what, "LocateCatalogNodeByMangledName's comparison rejects it"); return; }
	printf("ok   %s\n", what);
}

int main(void)
{
	UniChar		s[400];
	ItemCount	n, i;

	/* 120 kanji (3 bytes each) + ".txt" = 364 bytes, ID 0x1A2B.  "#1A2B" and
	   ".txt" leave 247 bytes with the NUL: 82 kanji (246) fit.  246 + 9 = 255. */
	n = 0;
	for (i = 0; i < 120; i++) s[n++] = 0x65E5;
	s[n++] = '.'; s[n++] = 't'; s[n++] = 'x'; s[n++] = 't';
	check("kanji name with .txt", s, n, 0x1A2B, 246, "#1A2B.txt");

	/* 100 hiragana, no extension, ID 0x10.  "#10" leaves 253: 84 (252) fit. */
	n = 0;
	for (i = 0; i < 100; i++) s[n++] = 0x3042;
	check("hiragana, no extension, ID 0x10", s, n, 0x10, 252, "#10");

	/* 90 hiragana + ".abcdef": 6 letters is too many for an extension.
	   ID 0x103, which xnu-124 writes "#13".  "#103" leaves 252: 83 (249) fit. */
	n = 0;
	for (i = 0; i < 90; i++) s[n++] = 0x3042;
	s[n++] = '.';
	for (i = 0; i < 6; i++) s[n++] = 'a' + i;
	check("6-letter tail is no extension, ID 0x103", s, n, 0x103, 249, "#103");

	/* 90 hiragana + ".": a trailing dot is no extension.  ID 0x1000:
	   "#1000" leaves 251: 83 (249) fit. */
	n = 0;
	for (i = 0; i < 90; i++) s[n++] = 0x3042;
	s[n++] = '.';
	check("trailing dot is no extension, ID 0x1000", s, n, 0x1000, 249, "#1000");

	/* "aa" + 64 surrogate pairs (4 bytes each) = 258 bytes, ID 0x10.  "#10"
	   leaves 253: "aa" + 62 pairs (250) fit, and a 63rd would end at 254. */
	n = 0;
	s[n++] = 'a'; s[n++] = 'a';
	for (i = 0; i < 64; i++) { s[n++] = 0xD83D; s[n++] = 0xDE00; }
	check("surrogate pair at the cut", s, n, 0x10, 250, "#10");

	/* 300 'z' + ".abcde" (5 letters: the longest extension), ID 0xFFFFFFFF.
	   "#FFFFFFFF" and ".abcde" leave 241: 240 fit, 240 + 15 = 255. */
	n = 0;
	for (i = 0; i < 300; i++) s[n++] = 'z';
	s[n++] = '.';
	for (i = 0; i < 5; i++) s[n++] = 'a' + i;
	check("ASCII name with 5-letter extension, ID 0xFFFFFFFF", s, n, 0xFFFFFFFF, 240, "#FFFFFFFF.abcde");

	/* 249 'x' + ".ab" + 20 'y' (no extension: 22 letters follow the dot), ID
	   0x1A.  "#1A" leaves 253: the prefix is 249 'x' + ".ab" (252), so the name
	   ends ".ab#1A".  A parser that counts any printable ASCII as an extension
	   character takes "ab#1A" for one and never finds the file ID. */
	n = 0;
	for (i = 0; i < 249; i++) s[n++] = 'x';
	s[n++] = '.'; s[n++] = 'a'; s[n++] = 'b';
	for (i = 0; i < 20; i++) s[n++] = 'y';
	check("dot just before the file ID", s, n, 0x1A, 252, "#1A");

	printf("%d failure(s)\n", failures);
	return failures != 0;
}
