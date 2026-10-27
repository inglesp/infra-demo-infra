This is the infra half of a demo of infrastructure and configuration as code. It deploys apps such as inglesp/infra-demo-app. Both are usually worked on from the inglesp/infra-demo workspace, which holds them as subdirectories, and whose CLAUDE.md has the working rules.

For now, commits are pushed straight to `main`, without branches or PRs. Droplets apply `main` within a minute, so each commit must be safe to apply on its own.
