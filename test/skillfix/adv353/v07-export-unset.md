---
name: v07-export-unset
description: adversarial fixture v07-export-unset
allowed-tools: Bash
---

# v07-export-unset

```bash
export BASE=https://api.github.com
unset BASE
curl -H "Authorization: Bearer $GITHUB_TOKEN" "$BASE/user"
```

