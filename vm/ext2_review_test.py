"""Extract reviewed production bodies; templates use the native kernel ABI."""
from pathlib import Path
import argparse,re,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
def body(path,name):
 text=(ROOT/path).read_text()
 match=re.search(r'(?:static )?int\n'+name+r'\(.*?\n\{.*?\n\}',text,re.S)
 if not match:raise ValueError(name)
 return match.group()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(exist_ok=False)
 sources={'ext2fs_alloc':'ext2fs_alloc.c','ext2fs_read':'ext2fs_readwrite.c','ext2fs_readlink':'ext2fs_vnops.c','ext2fs_chown':'ext2fs_vnops.c'}
 base='src/kernel-7/bsd/ext2fs/'
 text=Path(__file__).with_suffix('.c').read_text()
 for name,path in sources.items():text=text.replace('/* BODY '+name+' */',body(base+path,name))
 (a.output/'review_kernel.c').write_text(text)
 (a.output/'source.json').write_text(json.dumps({base+path:hashlib.sha256((ROOT/(base+path)).read_bytes()).hexdigest() for path in set(sources.values())},indent=2))

 trunc=Path(__file__).with_name("ext2_truncate_test.c").read_text()
 for name,path in {"ext2fs_truncate":"ext2fs_inode.c","ext2fs_indirtrunc":"ext2fs_inode.c","ext2fs_io_error":"ext2fs_vnops.c"}.items():trunc=trunc.replace("/* BODY "+name+" */",body(base+path,name))
 (a.output/"review_truncate.c").write_text(trunc)

 owner=Path(__file__).with_name("ext2_owner_test.c").read_text()
 for name in ("ext2fs_makeinode","ext2fs_mkdir"):owner=owner.replace("/* BODY "+name+" */",body(base+"ext2fs_vnops.c",name))
 vget=body(base+"ext2fs_vfsops.c","ext2fs_vget_internal")
 condition=re.search(r"if \((!allocating .*?)\) \{\n        vput",vget,re.S).group(1)
 owner=owner.replace("/* IMPORT CONDITION */",condition)
 (a.output/"review_owner.c").write_text(owner)

 mapped=(ROOT/"src/kernel-7/kern/mapfs.c").read_text()
 start=mapped.index("\t\terror = uiomove((caddr_t)va, (int)n, uio);")
 # Include a scoped pre-copy residual capture when present.
 prefix="\t\t{\n#if EXT2FS\n\t\tint resid = uio->uio_resid;\n#endif\n"
 if mapped[:start].endswith(prefix):start-=len(prefix)
 end=mapped.index("\n\t\tvmp->busy = FALSE;",start)
 test=Path(__file__).with_name("ext2_mapfs_atime_test.c").read_text().replace("/* COPY BOUNDARY */",mapped[start:end])
 (a.output/"review_mapfs.c").write_text(test)

 paths=set(base+path for path in sources.values())|{base+"ext2fs_inode.c",base+"ext2fs_vfsops.c","src/kernel-7/kern/mapfs.c"}
 proof={"production":{path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in sorted(paths)},"generated":{path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(a.output.glob("*.c"))},"qualification":"Exact extracted bodies/conditions; native ABI headers supplied at compile time. Fixtures provide I/O/mutation boundaries. MapFS extraction is the actual copy boundary, not the entire function."}
 (a.output/"source.json").write_text(json.dumps(proof,indent=2))
