# AGENTS.md
## Overview

This repository contains a containerized [ClamAV](https://docs.clamav.net/) antivirus scanner designed for use in Konflux CI/CD pipelines. It builds a Docker image that includes ClamAV daemon (`clamd`) with optimized configuration for scanning container images and artifacts in CI/CD environments.

## Technology Stack

- **Language**: bash, Dockerfile
- **Pipeline engine**: Tekton PipelineRuns
- **Testing**: Tekton pipelines, GitHub actions
- **Build**: Dockerfile, Tekton build pipelines

## Repository Structure

```
integration-tests/     # Tekton pipeline and task definitions for running integration and e2e tests
test/                  # Testing scripts that are used in the CI/CD pipelines
rpms.*                 # Contain packages that are built hermetically with their corresponding location
Dockerfile             # Container image definition
```

## Architecture

### ClamAV Antivirus Engine

The image is meant to be used as part of the [clamav-scan](https://github.com/konflux-ci/konflux-test-tasks/tree/main/task/clamav-scan) Konflux CI Tekton task.
It is meant to provide the latest available version of the ClamAV utility with updated virus definitions database contained within it.
The image's `Dockerfile` contains pre-tuned `clamd` settings for CI/CD scanning workflows - see more details in `README.md`.

### Automated updates

Automated virus definition updates are done via `freshclam` utility as part of the Konflux build pipeline defined in `.tekton/` directory.
A new build of the image is triggered daily.

## Development Guidelines

- See `CONTRIBUTING.md` for overall guidelines for making contributions to this repository.
- **Git**: conventional commits with Jira ticket as scope — `type(issue-id): description` (e.g. `feat(STONEINTG-1519): create PR group snapshots from ComponentGroups`)
    - The `main` branch is read only, never push there directly, a new feature branch must be created instead
    - Pull requests are used to propose changes to the `main` branch
- Don't change whitespaces or newlines in the existing unrelated code and never add whitespaces or tabs to empty lines
- Don't remove unrelated code and don't change files when/where modifications are not needed
- Don't add trailing newlines at the end of file, last newline character is at the end of code
- Never make changes that includes sensitive information like API keys, secrets, passwords, etc.
- Comment changes, but only for logic that is not obvious.
- Make sure that the Dockerfile is well-formatted and does not include unnecessary layers