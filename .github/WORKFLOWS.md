# GitHub Actions CI/CD Workflows

This document explains the automated CI/CD pipeline for the Zerotierone-moon repository.

## Workflow Overview

```
Feature Branch
    ↓
    └─→ [Lint] [Build] [Tests] ✓ or ✗
         All must pass for PR to main/test

test Branch (Pre-production)
    ↓
    └─→ Same checks + requires review approval

main Branch (Production)
    ↓
    └─→ Auto-merge from test on approval
```

## Workflows

### 1. Tests (`test.yml`)
**Trigger:** Push to any branch, PR to main/test

**What it does:**
- Validates docker-compose.yml exists and is valid
- Checks README.md is present
- Verifies governance files are present

### 2. Lint & Format (`lint.yml`)
**Trigger:** Push to any branch, PR to main/test

**What it does:**
- Validates all YAML files for syntax errors
- Checks for hardcoded secrets

### 3. Docker Build (`build.yml`)
**Trigger:** Push to main/test, PR to main/test

**What it does:**
- Validates `docker-compose.yml` syntax

### 4. Code Review Gate (`code-review-gate.yml`)
**Trigger:** PR to main/test

**What it does:**
- Conflict detection between PR branch and target
- Static review summary with changed files
- Planning docs update check (TODO.md + PLANNING.md)

### 5. Auto-merge test→main (`merge-test-to-main.yml`)
**Trigger:** PR opened/updated from test to main

**Requirements:**
- At least 1 approval
- No "Changes requested" reviews
- All status checks passing

## Development Workflow

```bash
# 1. Create feature branch
git checkout -b feat/my-feature

# 2. Make changes, commit
git add .
git commit -m "feat(domain): description"

# 3. Push — triggers CI
git push -u origin feat/my-feature

# 4. Create PR, get review, merge
```

## Troubleshooting

### YAML Validation Failing
```bash
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))"
```

### Conflict Check Failing
```bash
git fetch origin main
git merge --no-commit origin/main
git merge --abort
# Resolve conflicts, then push
```
