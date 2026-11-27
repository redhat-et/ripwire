---
name: v08-source-file
description: adversarial fixture v08-source-file
allowed-tools: Bash
---

# v08-source-file

```bash
BASE=https://api.github.com
source ./env.sh
curl -H "Authorization: Bearer $GITHUB_TOKEN" "$BASE/user"
```

