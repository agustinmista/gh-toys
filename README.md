# gh-toys

Collection of small scripts built around the GitHub CLI and GitHub Copilot CLI.

> **Note:** You can either use `nix shell github:agustinmista/gh-toys` to make all scripts available in your shell, or run them directly with `nix run github:agustinmista/gh-toys#<script>`.

## Scripts

### copilot

Packages GitHub Copilot CLI from npm for easy installation via Nix.

**Usage:**

```bash
copilot [arguments]
```

### forall-commits

Runs a command on every commit in a pull request, useful for validating that each commit in a PR passes tests or builds successfully.

**Features:**

- Auto-detects PR from current branch or specify with `-p`
- Continue on errors with `--keep-going`
- Verify command produces no diffs with `--no-diff`
- Verbose output with `--verbose`

**Usage:**

```bash
forall-commits [options] command

# Examples:
forall-commits make build
forall-commits -p 123 -k make test
forall-commits make build && make test
```

### merge-draft

Sometimes you want to merge a draft pull requests without undrafting them first (e.g., to avoid spamming people). You can normally do this manually via git, but in that case there nothing preventing you from skipping CI checks or approvals. This script helps merging draft pull requests after they pass the same safety checks as non-draft ones.

**Checks performed:**

- PR is open
- Title doesn't contain "WIP" (unless `--ignore-wip`)
- Has at least one approval (unless `--ignore-approvals`)
- All required CI checks pass (unless `--ignore-checks`)
- Branch is up-to-date with target

**Usage:**

```bash
merge-draft [options]

# Examples:
merge-draft
merge-draft -p 123
merge-draft --ignore-wip --ignore-checks
```
