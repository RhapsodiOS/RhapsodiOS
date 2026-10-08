"""Read hfs.util's on-disk fields in big-endian order (HFS is big-endian).

Usage: python patch_hfsutil.py PATH/TO/hfsutil_main.c [--dry-run]

Follows hfs-226.1.1 hfs_util/hfsutil_main.c, which swaps each field where it
is read.  Substitutions apply to code only, never inside string literals;
each keeps the file's own whitespace and must match exactly the number of
times given, or nothing is written.
"""
import re
import sys

NAME_OLD = r"""(\n(\t+))ConvertUnicodeToUTF8\(k->nodeName\.length, k->nodeName\.unicode, NAME_MAX, name_o\);"""
NAME_NEW = r"""\1{
\2	/* the name is big-endian on disk: swap a copy (as hfs-226's hfs.util does) */
\2	UniChar	name[255];
\2	int		i, n = SWAP_BE16(k->nodeName.length);

\2	if (n > 255) {
\2		result = FSUR_IO_FAIL;
\2		printf("hfs.util: ERROR: k->nodeName.length is a bad size (%d)\\n", n);
\2		goto Return;
\2	}
\2	for (i = 0; i < n; i++)
\2		name[i] = SWAP_BE16(k->nodeName.unicode[i]);
\2	ConvertUnicodeToUTF8(n, name, NAME_MAX, name_o);
\2}"""

# (pattern, replacement, exact match count)
IMPORT = (r'(#import "HFSBtreesPriv\.h"\n)', r'\1#import "hfs_endian.h"\n')

SUBS = [
    # signatures, wherever they are compared or printed
    (r'\b((?:mdbPtr|hfsMasterDirectoryBlockPtr)->(?:drSigWord|drEmbedSigWord)|volHdrPtr->signature)\b',
     r'SWAP_BE16(\1)', 10),
    # the embedded (wrapped) volume's position
    (r'(hfsMasterDirectoryBlockPtr->drAlBlkSiz)\b', r'SWAP_BE32(\1)', 1),
    (r'(hfsMasterDirectoryBlockPtr->drAlBlSt)\b', r'SWAP_BE16(\1)', 1),
    (r'(hfsMasterDirectoryBlockPtr->drEmbedExtent\.(?:startBlock|blockCount))\b', r'SWAP_BE16(\1)', 2),
    # the volume header and its fork extents
    (r'(volHdrPtr->blockSize)\b', r'SWAP_BE32(\1)', 3),
    (r'(catalogExtents\[(?:0|7)\]\.(?:startBlock|blockCount))\b', r'SWAP_BE32(\1)', 2),
    (r'(volHdrPtr->extentsFile\.extents\[0\]\.startBlock)\b', r'SWAP_BE32(\1)', 1),
    (r'(extentList\s*\[i\]\.(?:startBlock|blockCount))\b', r'SWAP_BE32(\1)', 5),
    # B-tree header and node descriptors
    (r'(bTreeHeaderPtr->(?:leafRecords|firstLeafNode))\b', r'SWAP_BE32(\1)', 2),
    (r'(bTreeHeaderPtr->nodeSize)\b', r'SWAP_BE16(\1)', 1),
    (r'(bTreeNodeDescriptorPtr->numRecords)\b', r'SWAP_BE16(\1)', 3),
    (r'(bTreeNodeDescriptorPtr->(?:fLink|bLink))\b', r'SWAP_BE32(\1)', 2),
    # record offsets and keys
    (r'(p = bufPtr \+ )\*v;', r'\1SWAP_BE16(*v);', 2),
    (r'(k->parentID)\b', r'SWAP_BE32(\1)', 1),
    (r'(k->fileID)\b', r'SWAP_BE32(\1)', 1),
    (r'(p \+ )(k->keyLength)( \+ sizeof\(UInt16\))', r'\1SWAP_BE16(\2)\3', 1),
    # the HFS Plus root name
    (NAME_OLD, NAME_NEW, 1),
]


STRING = re.compile(r'"(?:\\.|[^"\\\n])*"')


def sub_code(pat, rep, text):
    """re.sub on the code only: string literals (messages) are left alone.
    Returns (text, number of matches in code)."""
    out, n, pos = [], 0, 0
    for m in STRING.finditer(text):
        code = text[pos:m.start()]
        n += len(re.findall(pat, code))
        out.append(re.sub(pat, rep, code))
        out.append(m.group(0))
        pos = m.end()
    code = text[pos:]
    n += len(re.findall(pat, code))
    out.append(re.sub(pat, rep, code))
    return "".join(out), n


def main(argv):
    path = argv[1]
    with open(path, encoding="latin-1", newline="") as f:
        text = f.read()
    # the header goes after an #import, whose file name is itself a string
    got = len(re.findall(IMPORT[0], text))
    if got != 1:
        raise SystemExit("%s: the HFSBtreesPriv.h import matched %d times" % (path, got))
    text = re.sub(IMPORT[0], IMPORT[1], text)
    for pat, rep, want in SUBS:
        new, got = sub_code(pat, rep, text)
        if got != want:
            raise SystemExit("%s: %r matched %d times, expected %d" % (path, pat, got, want))
        text = new
    if "--dry-run" in argv:
        print("all %d substitutions match" % len(SUBS))
        return 0
    with open(path, "w", encoding="latin-1", newline="") as f:
        f.write(text)
    print("patched %s" % path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
