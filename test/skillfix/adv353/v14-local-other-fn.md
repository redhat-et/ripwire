---
name: v14-local-other-fn
description: adversarial fixture v14-local-other-fn
allowed-tools: Bash
---

# v14-local-other-fn

```bash
BASE=https://api.github.com
go() { curl -H "Authorization: Bearer $GITHUB_TOKEN" "$BASE/user"; }
```

Then:

```bash
BASE2=x
go
```

