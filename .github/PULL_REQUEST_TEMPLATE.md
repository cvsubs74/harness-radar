<!--
Title format: <type>(<area>): <subject> (#<n>)
  e.g. feat(auth): add OAuth login flow (#42)
       fix(api): handle expired tokens gracefully (#88)
-->

## Summary

<!-- One paragraph: what changed and why. -->

Closes #

## Evidence

<!--
The tester's evidence for each acceptance criterion: command output,
screenshots, links, curl responses. Reproducible if possible.

Example:
- Acceptance: "Users can sign in with GitHub"
  Evidence: `curl -sf http://localhost:3000/auth/github | head` → 302 to github.com/login/oauth/authorize ✓
-->

## Checklist

- [ ] All acceptance criteria on the linked issue are ticked
- [ ] `harness/verify.sh` exits 0 locally
- [ ] CI is green
- [ ] No `--no-verify` or other gate bypasses
- [ ] Commit message references the issue: `(#<n>)`
