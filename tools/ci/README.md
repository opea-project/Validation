# Scripts and guidances for CI/CD

This folder includes scripts and guidances for seting up CI/CD servers and jobs.

## Scripts

| Script            | Description                                                           |
| ----------------- | --------------------------------------------------------------------- |
| registry.sh       | to manage a local [image registry](https://hub.docker.com/_/registry) |
| registry.yaml     | configuration file for local image registry                           |
| read_only.yaml    | enable local image registry with read-only mode                       |
| cleanup.sh        | a cron job every day to clean up unused images                        |
| clean_registry.py | aims to keep ONLY images with the 'latest' tag in each repository     |
