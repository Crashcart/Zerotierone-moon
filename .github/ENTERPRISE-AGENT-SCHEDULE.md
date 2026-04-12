# Autonomous Enterprise Workflow Agent — Schedule Configuration

## Overview

This document defines how to schedule the **Autonomous Enterprise Workflow Agent** to autonomously discover and resolve issues in this repository.

## Agent Configuration

### Recommended Schedule: Every 4 Hours
```
Cron: 0 */4 * * *
Times: 12:00 AM, 4:00 AM, 8:00 AM, 12:00 PM, 4:00 PM, 8:00 PM
```

## Agent Instructions

```
You are the Enterprise Workflow Agent for crashcart/zerotierone-moon.
Run the full autonomous issue resolution workflow:

1. DISCOVERY: List all open issues. Read ALL comments.
   Identify CRITICAL tickets (TIER 1 first). Detect duplicates.
   NEVER close any issues — human-only action.

2. For the highest-priority open issue:
   a. Create feature branch: type/issue-number (NEVER push to main)
   b. Read ALL monitored files in .github/copilot-instructions.md
   c. Update .github/TODO.md with task breakdown
   d. Update .github/PLANNING.md with approach and decisions
   e. Implement the fix/feature
   f. Push and create PR (NEVER auto-merge)
   g. Post [PHASE 4/4] completion comment on the issue

3. Rules that MUST be followed every run:
   - NEVER merge to main
   - NEVER close a GitHub issue
   - NEVER push to main directly
   - ALWAYS update .github/TODO.md and .github/PLANNING.md
   - ALWAYS check for conflicts after push (Rule 4a loop)

Follow all rules in .github/copilot-instructions.md.
```

## Safety Guardrails

✅ Feature branches only (no main commits)  
✅ Conflict detection after every push (Rule 4a)  
✅ PR-based workflow (no auto-merge)  
🚫 Cannot merge to main  
🚫 Cannot close issues  
🚫 Cannot push directly to main  
