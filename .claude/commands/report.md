Generate a project portfolio report.

If an argument was provided (e.g. `/report rpg-bot`), report on that single project only.
If no argument, report on all projects in `.ai-rules/projects/_registry.json`.

Steps:
1. Read `.ai-rules/projects/_registry.json`
2. For each project in scope, read `.ai-rules/projects/{repo-name}.md`
3. Pull live data if possible: use GitHub MCP tools to get current open issue count and
   recent merged PRs for each repo (Crashcart/{repo-name}). If MCP unavailable, use the
   last recorded data in the project file.
4. Compute or verify the current score using the formula in `.ai-rules/projects/README.md`
5. Update `.ai-rules/projects/{repo-name}.md` with a new score card row and session note
6. Update `last_updated` in `.ai-rules/projects/_registry.json`

Report format:

---
## Portfolio Report — {date}

**{N} projects tracked** · {N} 🟢 healthy · {N} 🟡 needs attention · {N} 🟠 at risk · {N} 🔴 critical

### Projects

#### {repo-name} — {score} {emoji}
Phase: {phase} | Stack: {stack}
Bugs open: {N} | Fixed this period: {N} | Fix rate: {N}%
{One-sentence observation}
{If hire flag exists: "⚑ Hire flag: {role}" }

[repeat for each project]

### Hire Requests
{If any hire flags exist, print the full copy-paste block from the project file.}
{If none: "No hire requests pending."}
---

Only include data you have actually read or fetched. Never fabricate metrics.
If a project has no score yet, say "Not yet assessed."
