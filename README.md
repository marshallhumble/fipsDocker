# FIPS-Compliant Python Docker Image

[![Build Status](https://github.com/marshallhumble/fips-python-docker/actions/workflows/build-and-scan.yml/badge.svg)](https://github.com/your-org/fips-python-docker/actions)
[![SBOM](https://img.shields.io/badge/SBOM-SPDX-blue)](./sbom.spdx.json)
[![License](https://img.shields.io/github/license/marshallhumble/fips-python-docker)](./LICENSE)

A FIPS 140-2 compliant Python 3.11 container image with OpenSSL and `cryptography` built from source.

Built for secure workloads in regulated environments like that need to be FIPS *compliant*


---

## Key Features

- OpenSSL 3.1.2 ([FIPS 140-3](https://openssl-library.org/post/2025-03-11-fips-140-3/)) compiled with FIPS support
- Python 3.11.12 compiled against FIPS OpenSSL
- `cryptography` built from source with FIPS compliance
- Final image is ~350MB and stripped of unneeded files
- SBOM + CVE scan via [Trivy](https://github.com/aquasecurity/trivy)

---

## Usage

###  Build the image

```bash
  just build-all
```
Or:

```bazaar
  make build-all
```
Repo Structure:

* Dockerfile             # Multi-stage build
* Makefile               # Build, run, scan
* justfile               # Just-style developer commands
* fipsCheck.py           # Runtime FIPS test
* sbom.spdx.json         # Generated SBOM

License:
MIT 

## Actions 

This repo includes a GitHub Actions workflow to:

* Build on each PR
* Scan for CVEs
* Generate SBOM
* Post results as a comment to the PR

Pull requests welcome! Open issues for bugs or feature suggestions.