---
name: review-push-merge
description: Review local roon-ios work, commit on a cursor/ branch, push, and fast-forward merge to main. Use when the user says review, push, merge, ship this, create-branch-and-commit, or "push and merge".
---

# Review, push, and merge (roon-ios)

This repo is `djehring/roon-ios`. Default branch is `main`. There is no `.github` PR template and no protected-branch workflow in-tree. The owner's working method is: review, commit on `cursor/<short-description>`, push that branch, fast-forward `main` to it, push `main`. Do not open a GitHub PR unless they ask for one.

The companion bridge is `/Users/david/Development/Projects/roon-web-stack`. This skill does not ship that repo. If the live change is only there, stop and say so.

## When to run

The user asked to review, ship, push, merge, or "commit ALL" of the current work. If they only asked for a branch/commit, stop after the commit (do not push). If they said "push and merge", do the full sequence after a passing review.

## 1. Review

Work from `git status`, `git diff`, and `git log -8 --oneline`. Read the actual diff, not just the file list.

**Scope**

- Commit what they asked. "Commit ALL" means every modified and untracked file in this repo except junk (`DerivedData/`, `build/`, `.DS_Store`, simulator logs).
- Do not mix in `roon-web-stack` files.
- Do not commit secrets, `.env`, API keys, or `cache/time-capsules`.

**Checks (blocking unless they override)**

1. `xcodegen generate` is not required for a merge if `project.yml` and `RoonRemote.xcodeproj` were edited together. If only `project.yml` changed, regenerate and include the xcodeproj.
2. Tests, with full Xcode (CLI tools alone fail):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project RoonRemote.xcodeproj -scheme RoonRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If that simulator is missing, pick any available iPhone 16/17 from `xcrun simctl list devices available`.

3. If `Shared/` or tvOS sources changed, also:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project RoonRemote.xcodeproj -scheme RoonRemoteTV \
  -destination 'generic/platform=tvOS'
```

4. Cinema / Time Capsule diffs: photo clock is independent of music; configured capsules can publish with three photos; `Watch pictures` must still animate. Do not "fix" that by coupling photos to `isPlaying`.
5. Do not start the web bridge from this agent to prove the native change. Agent-started `yarn dev` dies with the tool call; `launchd` cannot reach the Roon core (Local Network). Review is tests + diff.

Report findings first if anything fails. Do not push a red test run unless they explicitly say to.

## 2. Branch and commit

Current branch is often `main` with uncommitted work.

```bash
git checkout -b cursor/<short-description>
```

Reuse `cursor/` if already on one and it is not `main`. Never commit directly on `main` unless they insist.

Commit message style from this repo:

- `feat(cinema): …`
- `fix: …`
- `docs(cinema): …`

Subject line in the imperative, what changed and why, no PR number unless one exists. Use a HEREDOC. No `git add -A` if they named files; with "commit ALL", `git add -A` from the repo root is correct.

## 3. Push and merge

```bash
git push -u origin HEAD
git checkout main
git pull --ff-only origin main
git merge --ff-only <feature-branch>
git push origin main
```

- Fast-forward only. If `main` has diverged, stop and say so; do not rebase or merge-commit unless they ask.
- Never `git push --force` to `main`.
- After success: `git status -sb` should show `main...origin/main` with no ahead/behind.
- Leave the `cursor/` branch on the remote; do not delete it unless they ask.

If they asked only to push, skip the `main` merge.

## 4. Do not

- Do not use `ManagePullRequest` / `gh pr create` unless they want a PR.
- Do not hang on `yarn backend` / `yarn dev` from this workspace.
- Do not wait minutes on `xcodebuild` with `head` or `pino-pretty` pipes; write logs to `/tmp` and grep.
- Do not start a second merge if `origin/main` already contains the commit.
