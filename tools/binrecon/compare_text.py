import sys,re,capstone,difflib
sys.path.insert(0,'tools/binrecon')
from binrecon import macho
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc'
OUR='out/i386/drvPortServer/PortServer.config/PortServer_reloc'
BR=re.compile(r'^(j\w+|call|loop\w*)$')
def load(p):
    m=macho.read_macho(p); raw=open(p,'rb').read()
    t=[s for s in m['sections'] if s['name'].endswith('__text')][0]
    syms={}
    for s in m['symbols']:
        if s.get('section')=='__TEXT,__text':
            n=s['name'].split(':')[0]
            if n not in syms or s['address']<syms[n]: syms[n]=s['address']
    return raw,t,syms
rr,rt,rs=load(REF); orr,ot,os_=load(OUR)
common=sorted(set(rs)&set(os_))
rb=sorted(set(rs.values())); ob=sorted({os_[n] for n in common})
def end(a,bs,t):
    for x in bs:
        if x>a: return x
    return t['address']+t['size']
def norm(raw,t,s,e):
    md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_32)
    off=t['offset']+(s-t['address']); out=[]
    for i in md.disasm(raw[off:off+(e-s)],s):
        op=i.op_str
        if BR.match(i.mnemonic):
            m2=re.fullmatch(r'0x[0-9a-f]+',op)
            if m2:
                tgt=int(op,16)
                # branch inside this function -> express relative to entry
                op=f'+{tgt-s}' if s<=tgt<e else 'EXT'
        else:
            op=re.sub(r'\b0x[0-9a-f]{4,}\b','IMM',op)
            op=re.sub(r'\b\d{4,}\b','IMM',op)
        out.append(f'{i.mnemonic} {op}'.strip())
    while out and out[-1]=='nop': out.pop()
    return out
res={}
for n in common:
    a=norm(rr,rt,rs[n],end(rs[n],rb,rt)); b=norm(orr,ot,os_[n],end(os_[n],ob,ot))
    if a!=b: res[n]=(a,b)
if len(sys.argv)>1 and sys.argv[1]!='list':
    for n,(a,b) in res.items():
        if sys.argv[1] in n:
            print('==== '+n)
            for l in difflib.unified_diff(a,b,'ref','ours',lineterm='',n=1): print(l)
            break
else:
    print(f'compared {len(common)}  identical {len(common)-len(res)}  differing {len(res)}')
    for n,(a,b) in sorted(res.items(),key=lambda x:(abs(len(x[1][0])-len(x[1][1])), sum(1 for p,q in zip(*x[1]) if p!=q))):
        d=sum(1 for p,q in zip(a,b) if p!=q)
        print(f'  len {len(a):>4}/{len(b):<4} first-order diffs {d:>4}   {n}')
