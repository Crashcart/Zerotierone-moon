# GitHub Actions CI/CD Workflows

Automated CI/CD pipeline for the Zerotierone-moon repository.

## Workflow Overview

```
Feature Branch (claude/**)
    ↓
    └─→ [Lint] [Docker Validate] [Tests] ✓ or ✗
         All must pass for PR to alpha

alpha Branch
    ↓
    └─→ Auto-merge from claude/** on approval + passing checks
         (then promoted alpha → beta → main by humans)
```

## Workflows

### 1. Tests (`test.yml`)
**Trigger:** Push to `main`, `alpha`, or `claude/**`; PR to `main` or `alpha`

**What it does:**
- Checks `install.sh` bash syntax (`bash -n`)
- Validates `docker-compose.yml` is parseable
- Verifies README contains the install one-liner
- Confirms governance files are present

### 2. Lint (`lint.yml`)
**Trigger:** Push to `main`, `alpha`, or `claude/**`; PR to `main` or `alpha`

**What it does:**
- Validates all YAML files for syntax errors
- Runs shellcheck on `install.sh` (falls back to `bash -n` if unavailable)
- Checks for hardcoded secrets in shell and YAML files

### 3. Docker Validate (`build.yml`)
**Trigger:** Push to `main`, `alpha`, or `claude/**`; PR to `main` or `alpha`

**What it does:**
- Validates `docker-compose.yml` syntax via `docker compose config`
- Confirms `zyclonite/zerotier` image is referenced
- Confirms `network_mode: host` is set (required for UDP 9993)
- Confirms `/dev/net/tun` device is mounted

### 4. Code Review Gate (`code-review-gate.yml`)
**Trigger:** PR to `main`, `alpha`, or `test`

**What it does:**
- Conflict detection between PR branch and target branch
- Posts a review summary comment with changed files
- Checks that `TODO.md` and `PLANNING.md` were updated

### 5. Auto-merge claude/**→alpha (`merge-test-to-main.yml`)
**Trigger:** PR opened/updated from any `claude/**` branch to `alpha`

**Requirements:**
- At least 1 approval
- No "Changes requested" reviews
- All status checks passing

### 6. Copilot Setup (`copilot-setup-steps.yml`)
**Trigger:** Changes to the workflow file itself, or manual dispatch

**What it does:**
- Validates Docker is available in the CI environment

## Development Workflow

```bash
# 1. Create a feature branch
git checkout -b claude/my-feature

# 2. Make changes and commit
git add install.sh README.md
git commit -m "fix(install): description"

# 3. Push — triggers CI
git push -u origin claude/my-feature

# 4. Create PR to alpha, get review, merge
```

## Troubleshooting

### YAML Validation Failing
```bash
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))"
```

### install.sh Syntax Error
```bash
bash -n install.sh
```

### Conflict Check Failing
```bash
git fetch origin alpha
git merge --no-commit origin/alpha
git merge --abort
# Resolve conflicts, then push
```
