"""lelint.py FIELDS SOURCE...: on-disk fields passed unwrapped to varargs.

Every multi-byte on-disk field is a little-endian wrapper struct
(hammer_port.h), so any arithmetic, compare or assignment on one is a
compile error.  The one hole is a varargs call: printf() and friends accept
the struct by value without complaint and print garbage on big-endian
CPUs.  This reports each '->field' / '.field' access, whose name is an
on-disk field (FIELDS: 'name width signed' lines), that sits in the
argument list of a varargs function and is not inside hgetN().

Same-named fields of host structures are recognised by HOST, the access
paths known to be host structs (hammer_inode, hammer_io, hammer_node
members); any other host field still needs a trailing '/* lelint: host */'
comment on its line.  Exit status 1 when anything is reported.

Run on the host: python lelint.py fields.txt ../../kernel-7/bsd/hammer/*.c
"""
import re
import sys

VARARGS = ('printf', 'kprintf', 'ksnprintf', 'krateprintf', 'hkprintf',
           'hdkprintf', 'hvkprintf', 'hmkprintf', 'hkrateprintf',
           'hvkrateprintf', 'hmkrateprintf', 'hpanic', 'panic', 'log',
           'hammer_kprintf', 'hammer_ksnprintf', 'hammer_krateprintf',
           'fprintf', 'snprintf', 'sprintf', 'err', 'errx', 'warn', 'warnx',
           'hwarn', 'hwarnx')
# Host-structure access paths that share a name with an on-disk field.
HOST = re.compile(r'(\bip|\bdip|\bnip|->ip)->(obj_id|obj_asof)$|'
                  r'\bio->offset$|->node_offset$|\bcursor->parent$|'
                  r'\bvolume->vol_no$|\bstats->count$')
CALL_RE = re.compile(r'\b(%s)\s*\(' % '|'.join(VARARGS))


def strip_comments(text):
    """Blank out comments (keeping newlines and 'lelint: host' marks)."""
    def blank(m):
        keep = 'lelint: host' in m.group(0)
        return re.sub(r'[^\n]', ' ', m.group(0)) if not keep else \
            ' ' * (len(m.group(0)) - 14) + 'LELINT_HOST__'
    return re.sub(r'/\*.*?\*/', blank, text, flags=re.S)


def drop_if0(text):
    """Blank out #if 0 ... #endif regions (nesting aware)."""
    out = []
    depth = 0
    for line in text.split('\n'):
        s = line.strip()
        if depth == 0 and re.match(r'#\s*if\s+0\b', s):
            depth = 1
        elif depth and re.match(r'#\s*if', s):
            depth += 1
        elif depth and re.match(r'#\s*endif', s):
            depth -= 1
            out.append('')
            continue
        out.append('' if depth else line)
    return '\n'.join(out)


def call_spans(text):
    """(start, end) of the argument text of every varargs call."""
    spans = []
    for m in CALL_RE.finditer(text):
        depth = 0
        i = m.end() - 1
        while i < len(text):
            c = text[i]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            elif c == '"':
                i += 1
                while i < len(text) and text[i] != '"':
                    i += 2 if text[i] == '\\' else 1
            i += 1
        spans.append((m.end(), i))
    return spans


def lint(fields, path):
    text = open(path, encoding='latin-1').read()
    text = drop_if0(strip_comments(text))
    field_re = re.compile(r'(->|\.)(%s)\b' % '|'.join(sorted(fields, key=len, reverse=True)))
    hits = []
    lines = text.split('\n')
    starts = [0]
    for line in lines:
        starts.append(starts[-1] + len(line) + 1)
    for a, b in call_spans(text):
        for m in field_re.finditer(text, a, b):
            pre = text[a:m.start()]
            post = text[m.end():b]
            # a member of the field (wrapper.v, uuid parts) or deeper
            if re.match(r'\s*(\.|->|\[)', post):
                continue
            # inside hgetN( ... ) on the same expression
            if re.search(r'hget(16|32|64)\(\s*[\w.>\-\[\]()* +]*$', pre):
                continue
            if re.search(r'(?<![&\w)\]])&\s*[\w.>\-\[\]()*]*$', pre):
                continue
            if re.search(r'(sizeof|offsetof)\s*\(\s*[\w.>\-\[\]()*]*$', pre):
                continue
            k = m.start()
            while k > a and (text[k - 1].isalnum() or text[k - 1] in '_.->'):
                k -= 1
            if HOST.search(text[k:m.end()]):
                continue
            n = next(i for i in range(len(starts)) if starts[i + 1] > m.start())
            if 'LELINT_HOST__' in lines[n]:
                continue
            hits.append('%s:%d: %s' % (path, n + 1, lines[n].strip()))
    return hits


def main(argv):
    fields = {}
    for line in open(argv[1]):
        name, width, signed = line.split()
        fields[name] = int(width)
    hits = []
    for path in argv[2:]:
        hits += lint(fields, path)
    for h in hits:
        print(h)
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
