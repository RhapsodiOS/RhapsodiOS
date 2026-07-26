import sys, re, capstone
sys.path.insert(0,'tools/binrecon')
from binrecon import macho
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc'
OUR='out/i386/drvPortServer/PortServer.config/PortServer_reloc'
def load(p):
    m=macho.read_macho(p); raw=open(p,'rb').read()
    t=[s for s in m['sections'] if s['name'].endswith('__text')][0]
    syms={}
    for s in m['symbols']:
        if s.get('section')=='__TEXT,__text':
            n=s['name'].split(':')[0]
            if n not in syms or s['address']<syms[n]: syms[n]=s['address']
    return raw,t,syms
rr,rt,rs = load(REF); orr,ot,os_ = load(OUR)
common=sorted(set(rs)&set(os_))
# boundaries: only addresses belonging to functions we know about
rb=sorted({rs[n] for n in rs}); ob=sorted({os_[n] for n in common})
def end(addr,bounds,t):
    for b in bounds:
        if b>addr: return b
    return t['address']+t['size']
def norm(raw,t,start,stop):
    md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_32)
    off=t['offset']+(start-t['address'])
    out=[]
    for i in md.disasm(raw[off:off+(stop-start)],start):
        op=re.sub(r'\b0x[0-9a-f]{4,}\b','IMM',i.op_str)
        op=re.sub(r'\b\d{4,}\b','IMM',op)
        out.append(f'{i.mnemonic} {op}'.strip())
    while out and out[-1]=='nop': out.pop()
    return out
same=[];diff=[]
for n in common:
    a=norm(rr,rt,rs[n],end(rs[n],rb,rt))
    b=norm(orr,ot,os_[n],end(os_[n],ob,ot))
    (same if a==b else diff).append((n,a,b))
print(f'compared {len(common)}  identical {len(same)}  differing {len(diff)}')
for n,a,b in diff: print(f'  {n:<58} ref {len(a):>4} / ours {len(b):>4}')

import difflib
if len(sys.argv)>1:
    for n,a,b in diff:
        if sys.argv[1] in n:
            print('\n==== '+n)
            for l in difflib.unified_diff(a,b,'ref','ours',lineterm='',n=2): print(l)
            break
