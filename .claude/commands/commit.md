# Navigator Git Commit and PR Workflow

## Important Notes

**Always confirm with user before:**
- Adding unstaged/untracked files
- Creating a pull request
- Pushing to remote repository

**Generate content automatically:**
- Commit messages based on diff analysis
- PR titles and descriptions based on actual changes
- No test plans, no mentions of Claude in commit messages or PRs.

**Branch Handling:**
- Only create new branches when committing from main
- Use existing feature branches when already on one
- New branch format: `feature/YYYYMMDD-HHMMSS-brief-description`
- Keep descriptions short and use hyphens instead of spaces

**Quality Requirements:**
- All commits must pass `make check` (formatting, linting, tests)
- Never commit without running quality checks first
- Ensure proper commit message formatting without Claude attribution

## Claude Code Commit Instructions

When the user asks you to commit changes or use the `/commit` command, follow these steps:

### 1. Check for Unstaged and Untracked Changes

First, check the current git status to identify any changes:

```bash
git status
```

**If there are unstaged or untracked changes:**
- Ask the user: "I found unstaged/untracked changes. Would you like me to add them to the commit?"
- If yes, add them with `git add .` or selectively with `git add <files>`
- If no, proceed with only the currently staged changes

### 2. Analyze Staged Changes

Examine what will be committed to understand the changes:

```bash
git diff --cached
```

**Analyze the diff to:**
- Understand what functionality was added, modified, or removed
- Identify the scope and purpose of the changes
- Generate appropriate commit message and PR content based on the actual changes

### 3. Check CLAUDE.md Updates

Check if CLAUDE.md needs to be updated based on the changes:

**If changes include:**
- New directories or components
- Modified build commands or development workflows
- Technology stack changes (new dependencies, frameworks)
- Architectural changes or new patterns
- New development tools or CI/CD changes

**Then:**
- Ask the user: "I notice changes that may require CLAUDE.md updates. Would you like me to analyze and update the documentation?"
- If yes, analyze the changes and update CLAUDE.md accordingly
- If no, proceed to quality checks

### 4. Run Quality Checks

Always run quality checks before committing:

```bash
make check
```

**If quality checks fail:**
- Attempt to fix the issues automatically (formatting, linting, etc.)
- Re-run `make check` to verify fixes
- If issues persist after fixes, show the remaining errors to the user and ask for guidance

### 5. Create Commit

**Generate commit message based on the diff analysis:**
- Use conventional commit format: `type(scope): description`
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- If unsure about the commit type, ask the user to clarify
- Keep the first line under 50 characters
- Add detailed description if needed
- Base the message on what actually changed in the diff

```bash
git commit -m "[commit message here]"
```

### 6. Ask About Pull Request

**Ask the user:** "Would you like me to create a pull request for this commit?"

**If no:** Stop here - the commit is complete.

**If yes:** Continue to PR creation steps.

### 7. Handle Branch for PR Creation

**Check current branch:**

```bash
git branch --show-current
```

**If on main branch:**
- Create and switch to a new feature branch with timestamp
- Format: `feature/YYYYMMDD-HHMMSS-brief-description`

```bash
# Only if on main - create new feature branch
BRANCH_NAME="feature/$(date +%Y%m%d-%H%M%S)-$(echo '[brief-description]' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
git checkout -b "$BRANCH_NAME"
```

**If on existing feature branch:**
- Use the current branch for the PR
- No need to create a new branch

**Push the branch:**

```bash
git push -u origin "$(git branch --show-current)"
```

### 8. Create Pull Request

Use GitHub CLI to create the pull request:

```bash
gh pr create --title "[PR title]" --body "$(cat <<'EOF'
## Summary
[Bullet points describing the changes]

EOF
)"
```

**Generate PR content based on the diff analysis:**
- PR title based on the commit message and changes
- Summary with bullet points describing what was modified
- Test plan based on the areas of code that were changed

### 9. Provide PR URL

After successful PR creation, provide the user with:
- The PR URL for easy access
- Brief summary of what was accomplished

### 10. Update Existing PR (Alternative Workflow)

**If there's already an open PR for the current branch and you have new changes:**

**Check for existing PR:**
```bash
gh pr view --json url,title 2>/dev/null || echo "No PR found"
```

**If PR exists and there are unstaged/untracked changes:**

1. **Run quality checks first**:
   ```bash
   make check
   ```
   - Attempt to fix issues automatically
   - Re-run if fixes were applied

2. **Handle unstaged/untracked changes** (after quality checks):
   - Ask: "I found unstaged/untracked changes. Would you like me to add them to update the existing PR?"
   - If yes, add them with `git add .` or selectively

3. **Analyze the new changes**:
   ```bash
   git diff --cached
   ```
   - Understand what functionality was added/modified
   - Generate appropriate commit message for these additional changes

4. **Create additional commit**:
   - Generate commit message based on the new changes
   - Use conventional commit format for the incremental changes

   ```bash
   git commit -m "[commit message for additional changes]"
   ```

5. **Push to update PR**:
   ```bash
   git push
   ```

6. **Confirm completion**:
   - Show the updated PR URL
   - Summarize what changes were added to the existing PR

