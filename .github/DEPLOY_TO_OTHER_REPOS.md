# Deploying the Enterprise AI Governance Framework to Other Repos

> **Source**: This governance framework originates from `crashcart/Kali-AI-term`.  
> **Last Updated**: 2026-04-12

---

## What Gets Copied

### Universal files (copy as-is):
- `.github/copilot-instructions.md` — master ruleset
- `.github/pull_request_template.md` — PR template
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`

### Files that need per-repo customization:
- `.github/REPO_CONFIG.md` — **must be customized** per project
- `.github/TODO.md` — start fresh for each repo
- `.github/PLANNING.md` — start fresh for each repo

---

## Step-by-Step: Deploy to a New Repo

```bash
TARGET_REPO="/path/to/target-repo"

mkdir -p "$TARGET_REPO/.github/ISSUE_TEMPLATE"

cp .github/copilot-instructions.md "$TARGET_REPO/.github/"
cp .github/pull_request_template.md "$TARGET_REPO/.github/"
cp .github/ISSUE_TEMPLATE/bug_report.md "$TARGET_REPO/.github/ISSUE_TEMPLATE/"
cp .github/ISSUE_TEMPLATE/feature_request.md "$TARGET_REPO/.github/ISSUE_TEMPLATE/"
```

Then create a repo-specific `REPO_CONFIG.md`, fresh `TODO.md` and `PLANNING.md`.

---

## Current Status

| File | kali-ai-term | ollama-intelgpu | rpg-bot | discord-chromecast | zerotierone-moon |
|------|:---:|:---:|:---:|:---:|:---:|
| `copilot-instructions.md` | ✅ | ⚠️ needs update | ❌ | ❌ | ✅ |
| `REPO_CONFIG.md` | ✅ | ❌ | ❌ | ❌ | ✅ |
| `TODO.md` | ✅ | ❌ | ❌ | ❌ | ✅ |
| `PLANNING.md` | ✅ | ❌ | ❌ | ❌ | ✅ |
| `pull_request_template.md` | ✅ | ❌ | ❌ | ❌ | ✅ |
| `ISSUE_TEMPLATE/*` | ✅ | ❌ | ❌ | ❌ | ✅ |
