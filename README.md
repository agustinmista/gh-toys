# gh-toys

A collection of small scripts built around the GitHub CLI.

## Scripts

### copilot

Wraps the [@github/copilot](https://www.npmjs.com/package/@github/copilot) npm package to run GitHub Copilot via Node.js.

```sh
nix run github:agustinmista/gh-toys#copilot
```

### forall-commits

Runs a command on each commit in a pull request. Useful for validating that each commit in a PR builds and passes tests independently.

**Options:**
- `-p, --pr <number>` — Specify PR number (defaults to detecting from current branch)
- `-k, --keep-going` — Continue on errors instead of stopping at the first failure
- `-d, --no-diff` — Check that the command does not produce any diff
- `-v, --verbose` — Print command output while running

```sh
nix run github:agustinmista/gh-toys#forall-commits -- [options] <command>
```

### merge-draft

Safely merge draft pull requests after verifying:
- The PR is open
- The title does not contain "WIP"
- At least one approval exists
- All required CI checks have passed
- The branch is up-to-date with the target branch

**Options:**
- `-p, --pr <number>` — Specify PR number (defaults to detecting from current branch)
- `-w, --ignore-wip` — Ignore WIP status in PR title
- `-c, --ignore-checks` — Ignore CI checks status
- `-a, --ignore-approvals` — Ignore PR approvals

```sh
nix run github:agustinmista/gh-toys#merge-draft -- [options]
```
