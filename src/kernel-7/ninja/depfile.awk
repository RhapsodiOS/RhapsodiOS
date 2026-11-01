function path(p, n,a,i,result,depth,stack) {
    if (p !~ /^\//) p = base "/" p
    n = split(p,a,"/")
    depth=0
    for (i=1;i<=n;i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == ".." && depth > 0 && stack[depth] != "..") depth--
        else stack[++depth]=a[i]
    }
    result = p ~ /^\// ? "/" : ""
    for (i=1;i<=depth;i++) result=result stack[i] (i<depth ? "/" : "")
    return result
}
BEGIN { printf "%s:", target }
{
    if ($0 ~ /:/) {
        sub(/^[^:]*:/,"")
        found=1
    }
    for (i=1;i<=NF;i++) {
        if ($i == "\\") continue
        if ($i ~ /[$:]/) { bad=1; exit 1 }
        p=path($i)
        if (!seen[p]++) printf " %s", p
    }
}
END { print ""; if (!found || bad) exit 1 }
