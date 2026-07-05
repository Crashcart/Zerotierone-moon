Onboard a new project into the portfolio tracking system.

Argument: <repo-name> (required). GitHub URL is inferred as https://github.com/Crashcart/<repo-name>.

Steps:
1. **Team check** — read `.ai-rules/agents/registry.json`; identify which roles are needed for this tech stack.
   Use GitHub MCP tools to read the repo: get its language, description, open issue count, and
   recent activity. If MCP unavailable, ask the user for a brief description.

2. **Assess team fit**:
   - Map the tech stack to required roles (e.g. Python repo → BACKEND DEVELOPER, QA ENGINEER;
     Discord bot → BACKEND DEVELOPER, QA ENGINEER; TypeScript → FRONTEND/FULLSTACK DEVELOPER)
   - Check each required role against `.ai-rules/agents/registry.json`
   - Note any gaps (roles needed but not approved)

3. **Create tracking file** — copy `.ai-rules/projects/template.md` to `.ai-rules/projects/{repo-name}.md`;
   fill in: repo URL, stack, current date, team assessment from step 2.

4. **Register the project** — add entry to `.ai-rules/projects/_registry.json`:
   ```json
   {
     "name": "{repo-name}",
     "repo": "https://github.com/Crashcart/{repo-name}",
     "status": "active",
     "phase": "new",
     "last_updated": "{today}"
   }
   ```

5. **Create context note** — create `notes/context/{repo-name}-context.md` with:
   - One paragraph: what this project is and who uses it
   - Stack summary
   - Any constraints noted from the repo

6. **Report findings**:
   - Team fit: ✓ covered | ⚑ gap: {role missing}
   - Infrastructure created: .ai-rules/projects/{repo-name}.md + notes/context/{repo-name}-context.md
   - If hire gaps found: list them but DO NOT generate hire requests yet — wait for at least
     one session of observed work before flagging (RULE 16: no hire without evidence of gap)

Do NOT commit changes — leave files staged for user review.
