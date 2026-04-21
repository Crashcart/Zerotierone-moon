# Branch-Aware Files

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

These files contain content that **must match the current branch name**. When code is promoted between branches, an agent must update every entry below so install URLs and references point to the correct branch and the correct branch-specific installer filename.

---

## How to use this file

When promoting a branch (e.g. merging alpha into beta):

1. Replace every occurrence of the **old** branch name and installer filename with the **new** ones in the files listed below.
2. Limit the replacement to the lines/patterns listed — do not rename unrelated branch references.
3. Commit the update as part of the promotion commit (or a separate `chore(docs): update branch refs for <branch>` commit).
4. Verify with: `grep -rE "/(alpha|beta|test|main)/install" README.md install*.sh` — all results should reference the target branch.

---

## Branch installer naming convention

| Branch | Installer filename | Header URL pattern |
|--------|-------------------|--------------------|
| `alpha` | `install-alpha.sh` | `.../alpha/install-alpha.sh` |
| `beta`  | `install-beta.sh`  | `.../beta/install-beta.sh`  |
| `test`  | `install-test.sh`  | `.../test/install-test.sh`  |
| `main`  | `install.sh`       | `.../main/install.sh`        |

`main` is the only branch without a `-<branch>` suffix. All other branches have a dedicated named installer.

---

## Manifest

### `README.md`
All 6 install one-liners reference the branch-specific installer URL.

| Line | Pattern (on alpha) | Notes |
|------|--------------------|-------|
| 19 | `.../alpha/install-alpha.sh` | Basic install one-liner |
| 35 | `.../alpha/install-alpha.sh` | Fully automatic install |
| 41 | `.../alpha/install-alpha.sh` | Auto install with explicit IP |
| 62 | `.../alpha/install-alpha.sh` | Update one-liner |
| 72 | `.../alpha/install-alpha.sh` | Uninstall one-liner |
| 78 | `.../alpha/install-alpha.sh` | Uninstall --purge one-liner |

**Replacement rule on promotion**: `raw.githubusercontent.com/Crashcart/Zerotierone-moon/<old>/<old-installer>` → `raw.githubusercontent.com/Crashcart/Zerotierone-moon/<new>/<new-installer>`

---

### `install-alpha.sh`
| Line | Pattern | Notes |
|------|---------|-------|
| 8 | `#   curl -fsSL .../alpha/install-alpha.sh` | Header comment |

**Replacement rule**: update both the branch name and filename on promotion to the next stage.

---

### `install-beta.sh`
| Line | Pattern | Notes |
|------|---------|-------|
| 8 | `#   curl -fsSL .../beta/install-beta.sh` | Header comment |

---

### `install-test.sh`
| Line | Pattern | Notes |
|------|---------|-------|
| 8 | `#   curl -fsSL .../test/install-test.sh` | Header comment |

---

### `install.sh` (main)
| Line | Pattern | Notes |
|------|---------|-------|
| 8 | `#   curl -fsSL .../main/install.sh` | Header comment — stable/production installer |

---

## Branch promotion checklist

Copy this checklist into your PR description when promoting branches:

```
## Branch-aware file updates
- [ ] README.md — all 6 install URLs updated from `/<old>/<old-installer>` to `/<new>/<new-installer>`
- [ ] `install-<new>.sh` line 8 — header comment URL verified correct
- [ ] grep confirms no stale `/<old>/` install references remain in README.md
```

---

## Branch hierarchy

```
feature/* → alpha → beta → test → main
```

| Branch | Purpose | Installer |
|--------|---------|-----------|
| `alpha` | Active development / staging | `install-alpha.sh` |
| `beta`  | Integration / pre-release    | `install-beta.sh`  |
| `test`  | QA / user acceptance testing | `install-test.sh`  |
| `main`  | Stable production            | `install.sh`        |
