# Branch Protection Setup Guide

How to configure branch protection on GitHub to enforce the CI/CD workflow.

## Setup Instructions

### Step 1: Go to Repository Settings

1. Go to `https://github.com/Crashcart/Zerotierone-moon`
2. Click **Settings** → **Branches**

### Step 2: Configure "main" Branch Protection

1. Click **Add rule**, enter `main`
2. Configure:
   - ✅ Require pull request before merging (1 approval)
   - ✅ Require status checks: `Tests`, `Lint`, `Docker Validate`
   - ✅ Require branches to be up to date before merging
   - ✅ Allow auto-merge (squash strategy)

## Testing the Setup

1. Create a `claude/test-branch` and push changes
2. Open a PR to `main`
3. Confirm all three status checks run
4. Approve the PR and verify auto-merge triggers

## Quick Reference

| Aspect | main |
|--------|------|
| PR Required | ✅ Yes |
| Approvals | 1+ |
| Status Checks | Tests, Lint, Docker Validate |
| Auto-merge | ✅ Yes (claude/** branches) |
| Merge Strategy | Squash |
