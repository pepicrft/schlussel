# 🚀 Release Process

Schlussel uses automated releases with git-cliff and GitHub Actions.

## How It Works

1. **Conventional Commits** - Use conventional commit format for all commits
2. **Automatic Detection** - CI detects releasable changes on every push to main
3. **Version Bumping** - git-cliff calculates the next version (semver)
4. **Changelog Generation** - Automatic changelog from commit messages
5. **Cargo.toml Update** - Version updated automatically
6. **XCFramework Build** - Built for all Apple platforms
7. **GitHub Release** - Created with release notes and XCFramework
8. **Crates.io Publish** - Published automatically

## Conventional Commits

Use these commit prefixes:

- `feat: ...` - New feature (bumps minor version)
- `fix: ...` - Bug fix (bumps patch version)
- `docs: ...` - Documentation only
- `chore: ...` - Maintenance tasks
- `refactor: ...` - Code refactoring
- `perf: ...` - Performance improvement
- `test: ...` - Adding tests
- `ci: ...` - CI/CD changes

**Breaking changes:** Add `!` or `BREAKING CHANGE:` in commit body (bumps major version)

Example:
```bash
git commit -m "feat: add support for OAuth 2.1"
git commit -m "fix: resolve token refresh race condition"
git commit -m "feat!: change TokenRefresher API"
```

## Required Secrets

Set these in GitHub repository settings (Settings → Secrets and variables → Actions):

### `CARGO_REGISTRY_TOKEN`

**Required for:** Publishing to crates.io

**How to get:**
1. Go to https://crates.io/settings/tokens
2. Click "New Token"
3. Name: "GitHub Actions - schlussel"
4. Scopes: Select "publish-update"
5. Generate token
6. Copy the token

**Add to GitHub:**
1. Go to https://github.com/tuist/schlussel/settings/secrets/actions
2. Click "New repository secret"
3. Name: `CARGO_REGISTRY_TOKEN`
4. Value: Paste your token
5. Click "Add secret"

### `GITHUB_TOKEN`

**Required for:** Creating GitHub releases

**Status:** ✅ Automatically provided by GitHub Actions (no setup needed)

## Release Workflow

### Automatic (Recommended)

1. Merge PRs to main with conventional commits
2. CI automatically detects if changes are releasable
3. If yes:
   - Updates CHANGELOG.md
   - Bumps version in Cargo.toml
   - Builds XCFramework
   - Creates GitHub release with XCFramework artifact
   - Publishes to crates.io
4. If no releasable changes, workflow skips

### Manual Release

Trigger manually with workflow_dispatch:

1. Go to Actions → Release workflow
2. Click "Run workflow"
3. Optionally specify version
4. Click "Run workflow"

## What Gets Released

Each release includes:

1. **GitHub Release**
   - Tag: `v{version}` (e.g., v0.1.0)
   - Release notes from CHANGELOG
   - XCFramework artifact (`Schlussel.xcframework.zip`)

2. **Crates.io Package**
   - Published as `schlussel`
   - Version matches GitHub release
   - Install with: `cargo add schlussel`

3. **Updated Files**
   - `CHANGELOG.md` - Full changelog
   - `Cargo.toml` - Version bumped
   - `Cargo.lock` - Dependencies updated

## Version Scheme

Schlussel follows [Semantic Versioning](https://semver.org/):

- **Major (X.0.0)**: Breaking changes
- **Minor (0.X.0)**: New features (backward compatible)
- **Patch (0.0.X)**: Bug fixes

Examples:
- `feat: add token encryption` → 0.1.0 → 0.2.0
- `fix: resolve memory leak` → 0.1.0 → 0.1.1
- `feat!: change storage API` → 0.1.0 → 1.0.0

## Troubleshooting

### Release not triggering

Check:
1. Are you using conventional commits?
2. Are there actually releasable changes (feat/fix)?
3. Check workflow logs in Actions tab

### Crates.io publish fails

Check:
1. Is `CARGO_REGISTRY_TOKEN` set correctly?
2. Is the package name available on crates.io?
3. Are all required fields in Cargo.toml filled?

### XCFramework build fails

Check:
1. Are all Rust targets installed?
2. Is the runner on macOS?
3. Check build script logs

## First Release Checklist

Before the first release (v0.1.0):

- [ ] Set `CARGO_REGISTRY_TOKEN` secret
- [ ] Ensure Cargo.toml has all required metadata
- [ ] Verify package name "schlussel" is available on crates.io
- [ ] Test XCFramework build locally
- [ ] Review CHANGELOG.md
- [ ] Verify all examples work
- [ ] Update README with crates.io install instructions
