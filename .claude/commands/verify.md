---
description: Run init.sh + verify.sh and report the result
allowed-tools: Bash, Read
---

# /verify

Sanity-check the current working tree. Use this any time you suspect baseline drift.

## Steps

```bash
pwd
git status
bash harness/init.sh
bash harness/verify.sh
echo "verify.sh exit: $?"
```

Report:
- Working dir clean? (yes/no)
- init.sh exit code
- verify.sh exit code
- If either failed, the last 30 lines of output and a one-line diagnosis.

Do not try to fix anything — `/verify` is read-only diagnostics. If something is broken, the user decides whether to fix the baseline or revert.
