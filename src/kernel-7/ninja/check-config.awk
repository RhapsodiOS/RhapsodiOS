function fail(message) {
    print config ": " message
    failed=1
    exit 1
}
function expand(s,depth, start,width,expr,colon,equal,key,from,to,value,n,a,i,part) {
    if (depth>40) fail("recursive configuration variable")
    while (match(s,/\$\([^()]*\)|\$\{[^{}]*\}/)) {
        start=RSTART; width=RLENGTH
        expr=substr(s,start+2,width-3)
        colon=index(expr,":")
        key=colon ? substr(expr,1,colon-1) : expr
        if (!(key in raw) && key !~ /^(NEXT_ROOT|MACHINE_DEFINES|SCONFIGFLAGS|VOLATILE|MACHINE_GENASSYM_FLAGS|FVMFILE_LDFLAGS|LDFLAGS2)$/)
            fail("unsupported configuration variable " key)
        if (key in expanded) value=expanded[key]
        else value=expanded[key]=expand(raw[key],depth+1)
        if (colon) {
            part=substr(expr,colon+1)
            equal=index(part,"=")
            if (!equal) fail("unsupported suffix substitution " expr)
            from=substr(part,1,equal-1); to=substr(part,equal+1)
            n=split(value,a,/[ \t]+/); value=""
            for (i=1;i<=n;i++) {
                part=a[i]
                if (substr(part,length(part)-length(from)+1)==from)
                    part=substr(part,1,length(part)-length(from)) to
                value=value (i>1 ? " " : "") part
            }
        }
        s=substr(s,1,start-1) value substr(s,start+width)
    }
    return s
}
function canon(p) {
    if (p==raw["SOURCE_DIR"] || p==srcdir || p=="../..") return "@SRC@"
    if (index(p,raw["SOURCE_DIR"] "/")==1) return "@SRC@/" substr(p,length(raw["SOURCE_DIR"])+2)
    if (index(p,srcdir "/")==1) return "@SRC@/" substr(p,length(srcdir)+2)
    if (index(p,"../../")==1) return "@SRC@/" substr(p,7)
    if (index(p,outdir "/")==1) p=substr(p,length(outdir)+2)
    while (index(p,"./")==1) p=substr(p,3)
    if (p==".") return "@OUT@"
    if (p !~ /^\//) return "@OUT@/" p
    return p
}
function cccommand(command,key, n,a,i,t,flags,source,stem,started) {
    sub(/ && awk .*/,"",command)
    command=expand(command,0)
    stem=key; sub(/\.[^.]+$/,"",stem)
    gsub(/\$\*/,stem,command)
    n=split(command,a,/[ \t]+/)
    source=""; flags=""; started=0
    for (i=1;i<=n;i++) {
        t=a[i]
        if (t=="") continue
        if (!started) { if (t ~ /(^|\/)cc$/) started=1; continue }
        if (t=="&&" || t==";") break
        if (t=="-c") continue
        if (t=="-o") { i++; continue }
        if (t ~ /\.(c|m|s)$/ && t !~ /^-/) { source=canon(t); continue }
        if (t ~ /^-I/) t="-I" canon(substr(t,3))
        flags=flags (flags!="" ? " " : "") t
    }
    if (!started || source=="") fail("unsupported compiler recipe for " key)
    return source " | " flags
}
function expected_object(key,recipe) {
    if (recipe=="") fail("missing historical compiler recipe for " key)
    expected[key]=cccommand(recipe,key)
}
function linkcommand(command, n,a,i,t,result,started) {
    command=expand(command,0)
    n=split(command,a,/[ \t]+/); result=""; started=0
    for (i=1;i<=n;i++) {
        t=a[i]
        if (t=="") continue
        if (!started) { if (t ~ /(^|\/)ld$/) started=1; continue }
        if (t=="&&" || t==";") break
        if (t=="-o") { i++; continue }
        if (t ~ /\.(o|a)$/) t=canon(t)
        result=result (result!="" ? " " : "") t
    }
    return result
}
function initialize( n,a,i,key) {
    n=split(expand(raw["OBJS"],0),a,/[ \t]+/)
    for (i=1;i<=n;i++) if (a[i]!="") expected_object(a[i],recipes[a[i]])
    n=split(expand(raw["LIBC_OBJ"],0),a,/[ \t]+/)
    for (i=1;i<=n;i++) if (a[i]!="") expected_object(a[i],recipes["$(LIBC_OBJ)"])
    n=split(expand(raw["LIBC_UNROLL_OBJ"],0),a,/[ \t]+/)
    for (i=1;i<=n;i++) if (a[i]!="") expected_object(a[i],recipes["$(LIBC_UNROLL_OBJ)"])
    n=split(expand(raw["MACH_OFILES"],0),a,/[ \t]+/)
    for (i=1;i<=n;i++) if (a[i]!="") expected_object(a[i],recipes["$(MACH_OFILES)"])
    expected_object("subr_prof.o",recipes["subr_prof.o"])
    expected_object("ioconf.o",recipes["ioconf.o"])
    expected_object("genassym.s",recipes["genassym.s"])
    expected_object("vers.o","${KCC} ${INCLUDES} ${MACHINE_CFLAGS} -c vers.c")
    expected_link=linkcommand("ld -static ${LDFLAGS} ${FVMFILE_LDFLAGS} ${LDOBJS} ${MACH_OFILES} vers.o ${LDFLAGS2} ${LIBS}")
}
FNR==NR {
    line=$0
    while (line ~ /\\$/) {
        sub(/\\$/,"",line)
        if ((getline more)<=0) fail("incomplete historical recipe")
        line=line " " more
    }
    if (line ~ /^[A-Za-z_][A-Za-z_0-9]*[ \t]*[+:?!]=/)
        fail("unsupported configuration assignment: " line)
    if (line ~ /^[A-Za-z_][A-Za-z_0-9]*[ \t]*=/) {
        at=index(line,"="); name=substr(line,1,at-1); sub(/[ \t]+$/,"",name)
        raw[name]=substr(line,at+1); sub(/^[ \t]+/,"",raw[name])
        current=""
    } else if (line ~ /^[^ \t#].*:/) {
        current=substr(line,1,index(line,":")-1)
        sub(/[ \t]+$/,"",current)
        recipes[current]=""
    } else if (line ~ /^\t/ && current!="") {
        recipes[current]=recipes[current] " " line
    }
    next
}
{
    if (!initialized) { initialize(); initialized=1 }
    if ($0 ~ /(^|[ \t])([^ \t]*\/)?cc[ \t]/) {
        n=split($0,a,/[ \t]+/); key=""
        for (i=1;i<n;i++) if (a[i]=="-o") { key=a[i+1]; break }
        sub(/^.*\//,"",key)
        if (!(key in expected)) fail("unexpected or duplicate compile output " key)
        actual=cccommand($0,key)
        if (actual!=expected[key]) fail("compiler/source mismatch for " key "\nexpected: " expected[key] "\nactual:   " actual)
        delete expected[key]
        compiles++
    } else if ($0 ~ /^ld[ \t]/) {
        if (++links>1) fail("multiple kernel links")
        actual=linkcommand($0)
        if (actual!=expected_link) fail("ordered link inputs or flags differ\nexpected: " expected_link "\nactual:   " actual)
    } else if ($0 !~ /^(\/bin\/sh ninja\/(configure|check-config|mig)\.sh |cd .*newvers|strip -x |mkdir -p .* && cp )/) {
        fail("unsupported build command: " $0)
    }
}
END {
    if (failed) exit 1
    if (!initialized || !compiles || links!=1) fail("missing compiler or linker commands")
    for (key in expected) fail("missing compile command for " key)
    print config ": configuration parity verified (" compiles " compiler commands)"
}
