# Type.OH Auto-Dev Routine

On-demand remote Claude Code agent that picks up the next TODO.md task.

## Trigger

Run from Claude Code CLI: `/schedule run "Type.OH auto-dev"`

## What it does

1. Reads TODO.md, picks first uncompleted task
2. Implements the code changes
3. Opens a PR on a `auto/<N>-<slug>` branch

## After it runs

1. Pull the branch locally
2. Add any new files to Xcode target (listed in PR)
3. Build & test in Xcode
4. If green → merge & checkmark TODO.md
5. If issues → comment on PR or trigger another run
