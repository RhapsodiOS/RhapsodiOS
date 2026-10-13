"""Extract actual patched helper and caller bodies into no-I/O native controls."""
from pathlib import Path
import re,argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument('vendor',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
a.output.mkdir(exist_ok=False)
s=(a.vendor/'lib/ext2fs/ismounted.c').read_text()
start=s.index('/* Match ordinary aliases') if '/* Match ordinary aliases' in s else s.index('/* Mounted-target identity')
helper=s[start:s.index('#endif /* HAVE_GETMNTINFO */',start)]
def body(path):
 s=(a.vendor/path).read_text();return re.search(r'(?:static )?void check_mount\(.*?\n\}',s,re.S).group().replace('check_mount(',('checker_decision(' if path.startswith('e2fsck') else 'formatter_decision('),1)
s=Path(__file__).with_suffix('.c').read_text().replace('/* HELPER */',helper).replace('/* CHECKER */',body('e2fsck/unix.c')).replace('/* FORMATTER */',body('misc/util.c'))
(a.output/'review_vendor_mount.c').write_text(s)
(a.output/'source.json').write_text(json.dumps({f:hashlib.sha256((a.vendor/f).read_bytes()).hexdigest() for f in ('lib/ext2fs/ismounted.c','e2fsck/unix.c','misc/util.c')},indent=2))
