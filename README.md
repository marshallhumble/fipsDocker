# FIPS-Compliant Python Docker Image

[![SBOM](https://img.shields.io/badge/SBOM-SPDX-blue)](./sbom.spdx.json)
[![License](https://img.shields.io/github/license/marshallhumble/fipsDocker)](./LICENSE)

A FIPS 140-2 compliant Python 3.11 container image with OpenSSL and `cryptography` built from source.

Built for secure workloads in regulated environments like that need to be FIPS *compliant*


---

## Key Features

- OpenSSL 3.1.2 ([FIPS 140-3](https://openssl-library.org/post/2025-03-11-fips-140-3/)) compiled with FIPS support
- Python 3.11.12 compiled against FIPS OpenSSL
- `cryptography` built from source with FIPS compliance
- Final image is ~166MB and stripped of unneeded files

https://hub.docker.com/repository/docker/marshallhumble/fips-python/general

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

## Issues

For any issues of improvements please either open an issue or PR
