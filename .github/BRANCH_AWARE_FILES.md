# Branch-Aware Files

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

These files contain content that **must match the current branch name**. When code is promoted between branches (`alpha → test`, `test → main`), an agent must update every entry below so install URLs and references point to the correct branch.

---

## How to use this file

When promoting a branch (e.g. merging alpha into test):

1. Replace every occurrence of the **old** branch name with the **new** branch name in the files listed below.
2. Limit the replacement to the lines/patterns listed — do not rename unrelated branch references.
3. Commit the update as part of the promotion commit (or a separate `chore(docs): update branch refs for <branch>` commit).
4. Verify with: `grep -r "/<old-branch>/" README.md install.sh` — should return nothing.

---

## Manifest

### `README.md`
Lines containing `raw.githubusercontent.com/Crashcart/Zerotierone-moon/<branch>/install.sh`

| Line | Pattern | Notes |
|------|---------|-------|
| 21 | `.../alpha/install.sh` | Basic install one-liner |
| 37 | `.../alpha/install.sh` | Fully automatic install |
| 43 | `.../alpha/install.sh` | Auto install with explicit IP |
| 64 | `.../alpha/install.sh` | Update one-liner |
| 74 | `.../alpha/install.sh` | Uninstall one-liner |
| 80 | `.../alpha/install.sh` | Uninstall --purge one-liner |

**Replacement rule**: `raw.githubusercontent.com/Crashcart/Zerotierone-moon/alpha/` → `raw.githubusercontent.com/Crashcart/Zerotierone-moon/<target-branch>/`

---

### `install.sh`
Lines containing a URL comment pointing users to the raw script.

| Line | Pattern | Notes |
|------|---------|-------|
| 8 | `#   curl -fsSL .../alpha/install.sh` | Header comment — shown in usage output |

**Replacement rule**: same as README.md above.

---

## Branch promotion checklist

Copy this checklist into your PR description when promoting branches:

```
## Branch-aware file updates
- [ ] README.md — all 6 install URLs updated from `/<old>/` to `/<new>/`
- [ ] install.sh line 8 — header comment URL updated
- [ ] grep confirms no stale `/<old>/install.sh` references remain
```

---

## Branch hierarchy

```
feature/* → alpha → test → main
```

| Branch | Purpose | Install URL suffix |
|--------|---------|-------------------|
| `alpha` | Active development / staging | `/alpha/install.sh` |
| `test` | Pre-release testing | `/test/install.sh` |
| `main` | Stable production | `/main/install.sh` |
