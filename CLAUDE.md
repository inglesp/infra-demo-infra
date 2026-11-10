This is the infra half of a demo of infrastructure and configuration as code. It deploys apps such as inglesp/infra-demo-app. Both are usually worked on from the inglesp/infra-demo workspace, which holds them as subdirectories, and whose CLAUDE.md has the working rules.

For now, commits are pushed straight to `main`, without branches or PRs. Droplets apply `main` within a minute, so each commit must be safe to apply on its own.

When you prepare a commit, leave it uncommitted for the user to review, and write two files in `tmp/` (gitignored), replacing any from the previous commit:

- `tmp/commit-message.txt`: the commit message, for `git commit -F tmp/commit-message.txt`. A short imperative subject line, a blank line, then a body saying what changed and why, and whether it changes anything on existing droplets.
- `tmp/verification-instructions.txt`: the exact `git add` command for the commit's files, and the checks to run, with what each should show. Split them into those to run before committing (such as `just check`, `just plan`, `just apply`), and those to run after pushing (on the droplets, and in the browser).
