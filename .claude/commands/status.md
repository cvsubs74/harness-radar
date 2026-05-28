---
description: Summarize backlog and recent progress. Mode-aware — reads from GitHub in github mode or from harness/backlog.md in local mode.
allowed-tools: Bash, Read
---

# /status

Print a concise snapshot of the project state. Reads from whichever surface this project's mode says is authoritative.

## Mode detection

```bash
MODE=$(jq -r '.mode // "github"' .claude/harness-mode.json 2>/dev/null || echo "github")
echo "mode: $MODE"
```

## Steps

### 1. Backlog by priority

**(github mode)**

```bash
for p in P0 P1 P2; do
  open=$(gh issue list --state open  --label "priority:$p" -L 500 --json number --jq 'length')
  closed=$(gh issue list --state closed --label "priority:$p" -L 500 --json number --jq 'length')
  total=$((open + closed))
  echo "[$p] $closed/$total  (open: $open)"
done
```

**(local mode)**

```bash
for p in P0 P1 P2; do
  read total open <<<$(awk -v want_prio="$p" '
    function emit() {
      if (id != "" && prio == want_prio) {
        t++
        if (status == "open") o++
      }
    }
    /^## T-/ { emit(); id=$2; status=""; prio=""; next }
    /^- Status: / { status=$3 }
    /^- Priority: / { prio=$3 }
    END { emit(); printf "%d %d\n", t+0, o+0 }
  ' harness/backlog.md)
  echo "[$p] open: $open / total: $total"
done
```

### 2. In flight

**(github mode)** — issues assigned to me, open:

```bash
gh issue list --state open --assignee @me \
  --json number,title,labels \
  --jq '.[] | "  #\(.number) \(.title)  [\(.labels | map(.name) | join(","))]"'
```

**(local mode)** — tasks with `Status: in-progress` or `Status: in-review`:

```bash
awk '
  function emit() {
    if (id != "" && (status == "in-progress" || status == "in-review"))
      print "  " title " [" status "]"
  }
  /^## T-/ { emit(); id=$2; title=$0; status=""; next }
  /^- Status: / { status=$3 }
  END { emit() }
' harness/backlog.md
```

### 3. Open PRs (both modes)

```bash
gh pr list --state open --json number,title,headRefName,isDraft,statusCheckRollup \
  --jq '.[] | "  #\(.number) \(.title)  (\(.headRefName))  \(.isDraft|if . then "DRAFT" else "" end)"'
```

### 4. Worktrees (both modes)

```bash
git worktree list
```

### 5. Recent commits on main (both modes)

```bash
git log --oneline -10 main
```

### 6. Last progress entry (both modes)

```bash
tail -n 30 harness/progress.md
```

### 7. Next pick — what `/next` would choose

**(github mode)**

```bash
N=$(bash scripts/gh-next-issue.sh 2>/dev/null) || N=""
if [ -n "$N" ]; then
  gh issue view "$N" --json number,title,labels \
    --jq '"  #\(.number) \(.title)  [\(.labels | map(.name) | join(","))]"'
else
  echo "  (no open unassigned stories)"
fi
```

**(local mode)**

```bash
awk '
  function emit() {
    if (id != "" && open && prio != "") print prio, id, title
  }
  /^## T-/ { emit(); id=$2; title=$0; open=0; prio=""; next }
  /^- Status: open$/ { open=1 }
  /^- Priority: / { prio=$3 }
  END { emit() }
' harness/backlog.md | sort -k1,1 -k2,2 | head -1
```

### 8. Project board URL (github mode only)

```bash
OWNER=$(jq -r .owner .github/project-config.json 2>/dev/null)
PROJ=$(jq -r .project_number .github/project-config.json 2>/dev/null)
if [ -n "$OWNER" ] && [ -n "$PROJ" ] && [ "$PROJ" != "null" ]; then
  echo "Project: https://github.com/users/$OWNER/projects/$PROJ"
fi
```

Format as a short report with these section headers. No prose narration.
