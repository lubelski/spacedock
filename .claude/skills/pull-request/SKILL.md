---
name: pull-request
description: Open or update a pull request for this repo. Use when the user asks to open, create, update, revise, or fix a PR, or when a task branch is ready for review. Covers the body template, evidence and screenshots from a profile, uploading images with gh --attach, the issue link and board card, and the attribution footer.
---

# Pull requests for Spacedock

A PR is the review point for one task branch. The body follows `.github/pull_request_template.md` exactly, the evidence comes from the actual change, and images are uploaded with the gh CLI's `--attach` flag.

## Before opening

1. Work happens on a task branch in a worktree under `.wt/`. The primary checkout stays on `main`.
2. Commit as you go and push the branch. Do not leave completed work uncommitted.
3. Build with `swift build -c release`. Fix warnings the change introduced.
4. Capture evidence from the built change on a profile (see Evidence). Keep screenshots in the scratchpad, not the repo. They travel as PR attachments, and image files do not belong in the diff.

## Body

Four sections, in this order, with these headings:

1. `## Overview`: a TL;DR of intent and the problem context. Link the issue with `Closes #N` when the PR completes it.
2. `## Visual Preview`: the evidence. Say what was verified and how, label mocks, and name any remaining verification gap in plain words.
3. `## Changes`: bullets, one per file or behavior.
4. `## Notes`: findings a reviewer or future reader needs, verification limits, follow-up work. Write "None" if there are none.

End the body with the attribution footer from the session's instructions (currently `🤖 Generated with [Claude Code](https://claude.com/claude-code)`).

Write the body to a file in the scratchpad, then pass it with `--body-file`. Reference each image by the same path you pass to `--attach`:

```markdown
![settings window, Ghostty section](/path/to/scratchpad/settings-ghostty.png)
```

## Evidence

- Evidence must come from the actual change, with enough context to interpret it. UI changes show the affected window, before and after where useful. Nonvisual changes include test output, logs, or a reproducible example. CLI changes can show the command and its output.
- Run the change on a profile (`--profile NAME`), never on the user's installed apps. Quit the profile's apps with `Spacedock quit --profile NAME` when done.
- Capture single windows. Build `scripts/wins.swift`, find the window id by owner name, then run `screencapture -x -l <windowID> FILE`. A full-screen grab of the user's desktop is not acceptable evidence.
- Label mocks and unverified behavior. Never substitute a proposed design for a screenshot of working UI.
- Exclude secrets, private conversations, terminal contents from the user's own sessions, and other windows.
- If visual capture is unavailable, say why, give the alternative evidence, and name the gap.
- A claim is verified only if you ran it. A scripted exercise of a code path (`scripts/keypost.swift`, `--binding-action`, `--settings-section`) is evidence for that path, not for the human gesture. Say which one you did.
- Dock, Cmd-Tab, and Spaces behavior must be observed. Where only the user can observe it, say so in Notes.

## Uploading images

Use `--attach` on `gh pr create`, `gh pr edit`, and `gh pr comment`. Links to `raw.githubusercontent.com` or `github.com/.../blob/...` do not render for a private repo. Up to 50 files per command. Alt text follows the path after `#`.

```sh
gh pr create --base main --title "Short title" \
  --body-file "$SCRATCH/pr-body.md" \
  --attach "$SCRATCH/before.png#Before" \
  --attach "$SCRATCH/after.png#After"
```

A body reference like `![alt](/path/to/scratchpad/after.png)` is rewritten to the uploaded asset and keeps its alt text. An attached file the body does not reference is appended at the end. If some uploads fail, the command still updates the PR and exits non-zero. Check the printed URL.

## Updating a PR

1. Fetch the current body: `gh pr view <n> --json body --jq '.body' > "$SCRATCH/pr-body.md"`.
2. Edit the file. Rewrite the Overview if the approach changed. Add to Notes rather than deleting history a reviewer may have read.
3. Replace or add images with `gh pr edit <n> --body-file "$SCRATCH/pr-body.md" --attach <file>` for each new image. Already-uploaded `user-attachments` URLs stay as they are.
4. Push the commits first, so the Changes section matches the diff.

## After opening or updating

- Comment on the issue with the PR URL. Record divergence from the issue's intent in a comment, never by editing the issue.
- Move the issue's card on the [Spacedock board](https://github.com/users/lubelski/projects/3) as AGENTS.md describes.
- Keep the session's links current with the PR and issue.
- Do not merge without the user's authorization. When authorized: `gh pr merge <n> --merge`, fast-forward the primary checkout, and move the card to Done.
