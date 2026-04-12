# Branch Protection Setup Guide

This guide explains how to configure branch protection rules on GitHub to enforce the CI/CD workflow.

## Setup Instructions

### Step 1: Go to Repository Settings

1. Go to `https://github.com/Crashcart/Zerotierone-moon`
2. Click **Settings** → **Branches**

### Step 2: Configure "main" Branch Protection

1. Click **Add rule**, enter `main`
2. Configure:
   - ✅ Require pull request before merging (1 approval)
   - ✅ Require status checks: Tests, Lint & Format, Docker Build
   - ✅ Require branches to be up to date before merging
   - ✅ Allow auto-merge (squash strategy)

### Step 3: Configure "test" Branch Protection

Same as main, with 1 required approval.

## Testing the Setup

1. Create a test branch and push changes
2. Confirm all status checks run
3. Approve the PR and verify auto-merge works

## Quick Reference

| Aspect | main | test |
|--------|------|------|
| PR Required | ✅ Yes | ✅ Yes |
| Approvals | 1+ | 1+ |
| Status Checks | All | All |
| Auto-merge | ✅ Yes | ✅ Yes |
| Merge Strategy | Squash | Squash |
