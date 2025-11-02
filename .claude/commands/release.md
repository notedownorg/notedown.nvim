# Navigator Release Management

## Claude Code Release Instructions

When the user asks you to create a release, follow these steps:

### 1. Ask for Version Information
First, ask the user which version they want to release. Understand the format:
- **Major release**: `v1.0.0`, `v2.0.0` (breaking changes)
- **Minor release**: `v1.1.0`, `v1.2.0` (new features, backward compatible)
- **Patch release**: `v1.0.1`, `v1.0.2` (bug fixes only)

### 2. Determine Release Strategy

**For Major/Minor Releases (v1.1.0, v2.0.0):**
- Create from current main/master branch
- Push a new branch for future backports: `release/v1.1.x` or `release/v2.0.x`
- Create and push the tag from main

**For Patch Releases (v1.0.1, v1.0.2):**
- Find the existing minor release branch (e.g., `release/v1.0.x`)
- Create the tag from that branch, NOT from main
- If the release branch doesn't exist, ask the user to clarify

### 3. Branch and Tag Commands

**Before making ANY changes, ALWAYS confirm with the user first.**

**For Major/Minor releases:**
```bash
# Confirm current branch is main and up to date
git checkout main
git pull origin main

# Create release branch for future backports
git checkout -b release/v1.1.x
git push origin release/v1.1.x

# Create and push tag from main
git checkout main
git tag v1.1.0
git push origin v1.1.0
```

**For Patch releases:**
```bash
# Checkout the minor release branch
git checkout release/v1.0.x
git pull origin release/v1.0.x

# Create and push tag from release branch
git tag v1.0.1
git push origin v1.0.1
```

### 4. What Happens After Tag Push

GoReleaser GitHub Action (`.github/workflows/release.yml`) automatically:
- Builds cross-platform binaries (Linux, Windows, macOS for amd64/arm64)
- Builds and embeds UI (`cd ui && npm ci && npm run build`)
- Injects version info (tag, commit, date) via ldflags
- Creates GitHub release with changelog and installation instructions
- Uploads binary archives and checksums

### 5. Verification Steps

After releasing:
1. Check GitHub Actions workflow completed successfully
2. Verify GitHub release was created with all artifacts
3. Test one of the binaries can be downloaded and run

### 6. Key Files Reference

- **GoReleaser Config**: `.goreleaser.*.yaml` - defines build matrix and release settings
- **Release Workflow**: `.github/workflows/release.yml` - GitHub Actions automation
- **Test Workflow**: `.github/workflows/test.yml` - includes release validation via snapshot builds
- **Version Package**: `pkg/version/version.go` - version info injection

### 7. Branch Naming Convention

- **Release branches**: `release/v{major}.{minor}.x` (e.g., `release/v1.0.x`, `release/v1.1.x`)
- **Tags**: `v{major}.{minor}.{patch}` (e.g., `v1.0.0`, `v1.0.1`, `v1.1.0`)

### 8. Important Notes

- The project uses Nix for reproducible builds
- UI is built and embedded during GoReleaser process
- Release validation runs in CI via `goreleaser release --snapshot --clean`
- ALWAYS confirm with user before creating branches or tags
- Ask user to clarify if patch release branch doesn't exist
