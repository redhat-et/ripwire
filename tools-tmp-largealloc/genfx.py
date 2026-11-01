#!/usr/bin/env python3
import os,sys
root,files,calls=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
os.makedirs(root,exist_ok=True)
for f in range(files):
    d=f"{root}/m{f%40}"; os.makedirs(d,exist_ok=True)
    L=[f"int leaf_{f}_{k}(int x);" for k in range(8)]
    for k in range(8):
        L.append(f"int caller_{f}_{k}(int x) {{")
        for c in range(calls//8):
            L.append(f"    x += leaf_{(f+c)%files}_{c%8}(x) + helper_{c%97}(x);")
        L.append("    return x;\n}")
    open(f"{d}/f{f}.c","w").write("\n".join(L)+"\n")
