List all available slash commands. Read the `.claude/commands/` directory to find every command file, then produce a formatted reference.

Format:

---
## Available Commands

### Project Tracking
/report                    — Full portfolio report (all projects)
/report <repo-name>        — Report for one project
/new-project <repo-name>   — Onboard a new project (team check + tracking file)

### PM Messages (rule suggestions + hire requests)
/messages                  — List pending PM messages awaiting approval
/messages new              — PM drafts a rule-suggestion or hire-request (shown to you inline)
/messages approve <file>   — Approve a message; PM implements then archives it
/messages reject <file>    — Reject a message; PM archives it, implements nothing

### Rules Management
/update-rules              — Pull latest AI-rules into this repo (no confirmation needed)

### Security + Audit
/audit                     — Scan all branches for rogue AI PM rule changes
/audit quick               — Scan only recently active branches (last 7 days)
/audit branch <name>       — Audit one specific branch
/audit delete <branch>     — Delete a confirmed rogue branch (asks for confirmation)

### Help
/help                      — This list

---

If any commands exist in `.claude/commands/` that are not in the list above, add them.
Keep descriptions to one line each.
