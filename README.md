# Konflux ClamAV Scanner

This repository contains a containerized ClamAV antivirus scanner designed for use in Konflux CI/CD pipelines. It builds a Docker image that includes ClamAV daemon (clamd) with optimized configuration for scanning container images and artifacts in CI/CD environments.

## What This Container Provides

- **ClamAV Antivirus Engine**: Latest ClamAV with updated virus definitions
- **Optimized Configuration**: Pre-tuned clamd settings for CI/CD scanning workflows
- **Konflux Integration**: Built on konflux-test base with policy utilities
- **Container Security**: Dedicated scanning for container images and build artifacts

## Key Features

- Automated virus definition updates via `freshclam`
- Configurable thread limits (default: 8 threads, configurable via `MAX_THREADS`)
- Custom whitelist support for known false positives
- Socket-based communication for efficient scanning
- Enhanced scanning limits for large files and archives
- Alert configuration for encrypted files and macros

## Container Components

- **Base Image**: UBI9 minimal with ClamAV packages
- **ClamAV Server**: Configured daemon for socket-based scanning
- **Utilities**: Includes jq, skopeo, tar, findutils for CI/CD operations
- **OpenShift CLI**: Pre-installed oc client for cluster operations
- **Konflux Policies**: Inherited policy framework from konflux-test

## Usage

### Basic Container Run
```bash
docker run --rm -v /path/to/scan:/scan quay.io/your-registry/konflux-clamav
```

### With Custom Thread Limit
```bash
docker run --rm -e MAX_THREADS=4 -v /path/to/scan:/scan quay.io/your-registry/konflux-clamav
```

### In Konflux Pipeline
This container is designed to be used as part of Konflux build and security scanning pipelines, typically in the security scanning phase of the build process.

## Configuration Files

- `start-clamd.sh`: Entry point script that configures and starts the ClamAV daemon
- `whitelist.ign2`: Custom whitelist for known false positive virus signatures
- `/etc/clamd.d/scan.conf`: ClamAV daemon configuration with optimized settings

## Build Requirements

The container automatically handles:
- ClamAV installation and configuration
- Virus definition updates
- User and permission setup
- Socket and logging directory creation

## Development and Contribution

This project uses GitHub Actions for CI/CD with workflows for:
- Container builds (`build_reusable.yaml`)
- ClamAV database updates (`clam-db.yaml`)
- Version checking (`clam-ver-check.yaml`)
- Pull request validation (`pr-checks.yaml`)

## License

See [LICENSE](LICENSE) file for details.
