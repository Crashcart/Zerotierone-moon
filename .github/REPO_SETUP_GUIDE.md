# Branch + Installer Governance Setup Guide

> Copy-paste guide to replicate the alpha/beta/test/main branch structure used in `crashcart/zerotierone-moon`.

---

## What This Sets Up

- 4-tier branch hierarchy: `feature/* → alpha → beta → test → main`
- Branch-specific install scripts: each branch has its own `install-<branch>.sh` (except `main` → `install.sh`)
- Governance files: `copilot-instructions.md`, `BRANCH_AWARE_FILES.md`, `TODO.md`, `PLANNING.md`, `REPO_CONFIG.md`
- CI enforcement: PRs validated against correct branch + installer filename
- Protected branches: `alpha`, `beta`, `test`, `main` (rules set via GitHub UI)

---

## Step 1 — Create the Branch Structure

Run these commands in your local repo clone.

```bash
# Start from main
git checkout main
git pull origin main

# Create alpha
git checkout -b alpha
git push -u origin alpha

# Create beta from alpha
git checkout alpha
git checkout -b beta
git push -u origin beta

# Create test from beta (or main, depending on your flow)
git checkout main
git checkout -b test
git push -u origin test
```

---

## Step 2 — Protect Branches in GitHub UI

For **each** of `alpha`, `beta`, `test`, `main`:

1. Go to **Settings → Branches → Add rule**
2. Branch name pattern: `alpha` (repeat for each branch)
3. Check:
   - ✅ Require a pull request before merging
   - ✅ Require approvals: **1**
   - ✅ Require status checks to pass before merging
   - ✅ Require branches to be up to date before merging
   - ✅ Do not allow bypassing the above settings
4. Click **Create**

---

## Step 3 — Create the Governance Files

### `.github/copilot-instructions.md`

Copy the file from this repo verbatim. Update:
- Line 1 `**Scope**` — change repo name
- Line 3 `**Applies to**` — change org/repo name
- Update the `REPO_CONFIG.md` reference section for your tech stack

### `.github/REPO_CONFIG.md`

Create this file with your project's specifics:

```markdown
# Repo Config — <your-repo-name>

## Tech Stack
- Runtime: <e.g. Node 20, Python 3.12, bash>
- Package manager: <e.g. npm, pip, none>

## Test Commands
- Lint:   <e.g. npm run lint>
- Test:   <e.g. npm test>
- Build:  <e.g. npm run build>

## Monitored Files (conflict-prone)
- <list files agents must be careful editing>

## Branch-Aware Files
See `.github/BRANCH_AWARE_FILES.md`
```

### `.github/TODO.md`

```markdown
# 📋 <Repo Name> Active Task List

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`.

**Last Updated**: YYYY-MM-DD
**Current Session**: <session-name>
**Repository**: <repo-name>

---

## Active Tasks

| ID | Task | Status | Priority | Notes |
|:--:|------|--------|----------|-------|
| 1 | Initial governance setup | ✅ completed | 🟠 HIGH | |

---

## Status / Priority Legend

| Symbol | Status | | Symbol | Priority |
|--------|--------|-|--------|----------|
| ✅ | completed | | 🔴 | CRITICAL |
| 🟠 | in-progress | | 🟠 | HIGH |
| 🔵 | not-started | | 🟡 | MEDIUM |

---

Rules:
- Max 1 task `in-progress` per agent
- Update immediately on state change — no batching
- 3 statuses only: not-started, in-progress, completed
```

### `.github/PLANNING.md`

```markdown
# 🗺️ <Repo Name> Planning & Coordination

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`.

**Last Updated**: YYYY-MM-DD
**Document Purpose**: Centralized planning for multi-agent coordination, architectural decisions, and project context

---

## 🎯 Active Initiatives

### Initial Governance Setup

**Status**: ✅ Complete
**Branch**: `claude/initial-governance-setup`

**Approach**: Copied governance framework from `crashcart/zerotierone-moon`. Applied branch hierarchy (feature/* → alpha → beta → test → main) and branch-specific installer pattern.

**Decisions Log**:
- [YYYY-MM-DD] Governance framework adopted from zerotierone-moon
- [YYYY-MM-DD] Branch hierarchy: feature/* → alpha → beta → test → main
- [YYYY-MM-DD] Branch-specific install scripts created for alpha, beta, test

---

## 🏗️ Architecture Decisions

_(add as needed)_

---

## 🤝 Handoff Notes

**For next agent**:
- Read copilot-instructions.md before touching anything
- All PRs target `alpha`, never `main` directly (Rule 11)
```

### `.github/BRANCH_AWARE_FILES.md`

```markdown
# Branch-Aware Files Manifest

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`.

This file lists every file whose content must change when the branch changes.
When promoting `alpha → beta`, `beta → test`, or `test → main`, update every
file listed here before merging.

---

## Branch Hierarchy

```
feature/* ──▶ alpha ──▶ beta ──▶ test ──▶ main
```

| Branch | Install script    | README URL pattern                  |
|--------|-------------------|-------------------------------------|
| alpha  | install-alpha.sh  | .../alpha/install-alpha.sh          |
| beta   | install-beta.sh   | .../beta/install-beta.sh            |
| test   | install-test.sh   | .../test/install-test.sh            |
| main   | install.sh        | .../main/install.sh                 |

---

## File Manifest

### install-alpha.sh (alpha branch only)

Header comment must reference:
```
raw.githubusercontent.com/<ORG>/<REPO>/alpha/install-alpha.sh
```

### install-beta.sh (beta branch only)

Header comment must reference:
```
raw.githubusercontent.com/<ORG>/<REPO>/beta/install-beta.sh
```

### install-test.sh (test branch only)

Header comment must reference:
```
raw.githubusercontent.com/<ORG>/<REPO>/test/install-test.sh
```

### install.sh (main branch only)

Header comment must reference:
```
raw.githubusercontent.com/<ORG>/<REPO>/main/install.sh
```

### README.md

All install one-liner URLs must reference the correct branch + filename.
On alpha: all URLs → `.../alpha/install-alpha.sh`
On main: all URLs → `.../main/install.sh`

---

## Promotion Checklist

When merging alpha → beta:
- [ ] Update all URLs in README.md: `alpha/install-alpha.sh` → `beta/install-beta.sh`
- [ ] Remove install-alpha.sh, add install-beta.sh with correct header URL
- [ ] Update this manifest if needed

When merging beta → test:
- [ ] Update all URLs in README.md: `beta/install-beta.sh` → `test/install-test.sh`
- [ ] Remove install-beta.sh, add install-test.sh with correct header URL

When merging test → main:
- [ ] Update all URLs in README.md: `test/install-test.sh` → `main/install.sh`
- [ ] Remove install-test.sh, rename to install.sh (no suffix on main)
```

---

## Step 4 — Create the Install Scripts

### Base `install.sh`

Your installer must support these actions: `install`, `update`, `uninstall`, `reinstall`.

Key patterns to use (copy from `zerotierone-moon/install.sh`):

```bash
#!/bin/bash
# <Repo Name> — <description>
#
# branch-aware: the URL below must match the branch this file lives on.
# See .github/BRANCH_AWARE_FILES.md for the full list and promotion checklist.
#
#   curl -fsSL https://raw.githubusercontent.com/<ORG>/<REPO>/main/install.sh \
#     -o /tmp/zt-install.sh && bash /tmp/zt-install.sh

# ShellCheck-safe docker compose invocation:
if docker compose version >/dev/null 2>&1; then
    DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    DC=(docker-compose)
else
    error "docker compose not found"
fi

# Always guard cd:
cd "$COMPOSE_DIR" || error "Cannot cd to $COMPOSE_DIR"

# Use "${DC[@]}" not $DC:
"${DC[@]}" pull
"${DC[@]}" up -d

# do_reinstall() — complete wipe + fresh install:
do_reinstall() {
    # Warn user
    # Prompt for 'yes' confirmation (unless --auto)
    PURGE=true
    do_uninstall
    docker rmi "$IMAGE" 2>/dev/null || true   # force fresh pull
    do_install
}

# Case statement must include all 4 actions:
case "$ACTION" in
    install)   do_install   ;;
    update)    do_update    ;;
    uninstall) do_uninstall ;;
    reinstall) do_reinstall ;;
esac
```

### Generate Branch Scripts

After finalizing `install.sh`, generate the branch-specific scripts with `sed`:

```bash
# From repo root
sed 's|/main/install.sh|/alpha/install-alpha.sh|g' install.sh > install-alpha.sh
sed 's|/main/install.sh|/beta/install-beta.sh|g'   install.sh > install-beta.sh
sed 's|/main/install.sh|/test/install-test.sh|g'   install.sh > install-test.sh

# Verify syntax
bash -n install.sh        && echo "✓ install.sh"
bash -n install-alpha.sh  && echo "✓ install-alpha.sh"
bash -n install-beta.sh   && echo "✓ install-beta.sh"
bash -n install-test.sh   && echo "✓ install-test.sh"

# Confirm each URL is correct
grep "raw.githubusercontent" install.sh        | head -1
grep "raw.githubusercontent" install-alpha.sh  | head -1
grep "raw.githubusercontent" install-beta.sh   | head -1
grep "raw.githubusercontent" install-test.sh   | head -1
```

---

## Step 5 — Add CI Enforcement

Create `.github/workflows/test.yml`:

```yaml
name: Tests

on:
  push:
    branches: [ main, alpha, beta, test, 'claude/**' ]
  pull_request:
    branches: [ main, alpha, beta, test ]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Check install.sh bash syntax
      run: bash -n install.sh && echo "✓ install.sh syntax OK"

    - name: Check governance files present
      run: |
        for f in ".github/copilot-instructions.md" ".github/REPO_CONFIG.md" \
                 ".github/TODO.md" ".github/PLANNING.md" ".github/BRANCH_AWARE_FILES.md"; do
          [ -f "$f" ] && echo "✓ $f" || { echo "❌ Missing: $f"; exit 1; }
        done

    - name: Check branch-aware URLs match PR target branch
      if: github.event_name == 'pull_request'
      run: |
        TARGET="${{ github.base_ref }}"

        case "$TARGET" in
          alpha) EXPECTED_INSTALLER="install-alpha.sh" ;;
          beta)  EXPECTED_INSTALLER="install-beta.sh"  ;;
          test)  EXPECTED_INSTALLER="install-test.sh"  ;;
          main)  EXPECTED_INSTALLER="install.sh"        ;;
          *)     echo "⚠️ Unknown target branch '$TARGET' — skipping"; exit 0 ;;
        esac

        ERRORS=0

        # Check README.md URLs
        while IFS= read -r line; do
          if echo "$line" | grep -q "raw.githubusercontent.com/<ORG>/<REPO>/"; then
            if ! echo "$line" | grep -q "/$TARGET/$EXPECTED_INSTALLER"; then
              echo "❌ README.md URL should reference '$TARGET/$EXPECTED_INSTALLER': $line"
              ERRORS=$((ERRORS + 1))
            fi
          fi
        done < README.md

        # Check installer header URL
        if [ -f "$EXPECTED_INSTALLER" ]; then
          if grep -q "raw.githubusercontent.com/<ORG>/<REPO>/" "$EXPECTED_INSTALLER"; then
            if ! grep "raw.githubusercontent.com/<ORG>/<REPO>/" "$EXPECTED_INSTALLER" \
                 | grep -q "/$TARGET/$EXPECTED_INSTALLER"; then
              echo "❌ $EXPECTED_INSTALLER header URL should reference '$TARGET/$EXPECTED_INSTALLER'"
              ERRORS=$((ERRORS + 1))
            fi
          fi
        else
          echo "❌ Expected installer '$EXPECTED_INSTALLER' not found"
          ERRORS=$((ERRORS + 1))
        fi

        [ "$ERRORS" -gt 0 ] && exit 1
        echo "✓ All branch-aware URLs correctly reference '$TARGET/$EXPECTED_INSTALLER'"
```

> Replace `<ORG>/<REPO>` with your actual GitHub org and repo name (e.g. `Crashcart/my-repo`).

---

## Step 6 — Add PR Template

Create `.github/pull_request_template.md`:

```markdown
## Summary
- [what changed]

## Issue
Closes #N

## Test Plan
- [ ] All tests pass
- [ ] No regressions

## Checklist
- [ ] TODO.md updated
- [ ] PLANNING.md updated
- [ ] Targeting `alpha` branch (not `main`)
- [ ] Branch-aware URLs in README.md and install script point to the **PR target branch**
- [ ] If promoting between branches: all files in BRANCH_AWARE_FILES.md updated
```

---

## Step 7 — Initial Commit on Feature Branch

```bash
# Always work on a feature branch, never directly on main/alpha/beta/test
git checkout -b feat/initial-governance-setup

git add .github/ install.sh install-alpha.sh install-beta.sh install-test.sh README.md
git commit -m "chore(governance): initial branch + installer governance framework

- Copied enterprise agent rules from crashcart/zerotierone-moon
- Branch hierarchy: feature/* → alpha → beta → test → main
- Branch-specific install scripts: install-alpha/beta/test.sh
- CI enforces branch-aware URL correctness on every PR
- do_reinstall() added: full container/image/data wipe + fresh install"

git push -u origin feat/initial-governance-setup
# Then open a PR targeting: alpha
```

---

## Maintenance — Promoting a Branch

When merging `alpha → beta`:

```bash
git checkout beta
git merge --no-ff alpha

# Update branch-aware files:
# 1. Update all install URLs in README.md: alpha/install-alpha.sh → beta/install-beta.sh
# 2. Replace install-alpha.sh with install-beta.sh (or regenerate from install.sh via sed)
# 3. Update BRANCH_AWARE_FILES.md manifest if needed

sed 's|/alpha/install-alpha.sh|/beta/install-beta.sh|g' install-alpha.sh > install-beta.sh
rm install-alpha.sh  # beta branch does not carry alpha's script

git add -A
git commit -m "chore(promotion): promote alpha → beta, update branch-aware URLs"
git push origin beta
```

Repeat the pattern for `beta → test` and `test → main`.

---

## Quick Reference — Actions Available in Every Branch

| Command | Effect |
|---------|--------|
| `bash install-<branch>.sh` | Interactive install |
| `bash install-<branch>.sh --auto --network <id>` | Fully unattended install |
| `bash install-<branch>.sh update` | Pull latest image, keep moon config |
| `bash install-<branch>.sh uninstall` | Stop and remove container |
| `bash install-<branch>.sh uninstall --purge` | Remove container + all data |
| `bash install-<branch>.sh reinstall` | **Complete wipe + fresh install** |
| `bash install-<branch>.sh reinstall --auto` | Complete wipe, no prompts |
