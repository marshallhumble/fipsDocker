# Security Policy

## Overview

This image provides a FIPS 140-2/140-3 *compliant* Python runtime built from source against
OpenSSL 3.1.2, which holds an active CMVP certificate. It is intended for use in regulated
environments such as FedRAMP, CMMC, HIPAA, and PCI-DSS where FIPS-approved cryptography
is required.

**FIPS compliant** means this image is built and configured to use only FIPS-approved
algorithms through the OpenSSL FIPS provider. It does not mean the image itself holds a
CMVP certificate — only the OpenSSL 3.1.2 FIPS provider does.

---

## What Is and Is Not in the FIPS Boundary

### Inside the boundary

- OpenSSL 3.1.2 FIPS provider (`fips.so`), built from the validated source and installed
  via `make install_fips`
- All cryptographic operations performed by the `cryptography` Python package, which is
  compiled from source against this OpenSSL and linked exclusively against it
- TLS connections made via Python's `ssl` module, which uses the same OpenSSL build

### Outside the boundary

- The Python interpreter itself
- The Debian bookworm-slim base OS and its system libraries
- uv (used as a package manager, not for cryptographic operations)
- Any third-party Python packages installed by the image consumer

The FIPS provider enforces algorithm restrictions at runtime. Non-approved algorithms
(MD5, RC4, DES, etc.) will raise exceptions when attempted. This is verified by the
included `/app/fipsCheck.py` smoke test, which confirms MD5 is blocked on startup.

---

## FIPS Configuration

### `fipsmodule.cnf` generation

Per the [OpenSSL 3.1.2 README-FIPS](https://github.com/openssl/openssl/blob/master/README-FIPS.md),
the `fipsmodule.cnf` file **must not be copied between machines**. It contains an
integrity checksum of `fips.so` computed on the specific host where it was generated.
If copied, the FIPS self-tests are skipped on the target machine, which is non-compliant.

This image addresses this by running `openssl fipsinstall` at container startup via
`docker-entrypoint.sh`. The `fipsmodule.cnf` is generated fresh on each host the
container runs on, ensuring the self-tests execute and the integrity check passes.

### Kubernetes deployments

If your cluster uses a read-only root filesystem (recommended), mount a writable volume
at `/etc/ssl` so the entrypoint can write `fipsmodule.cnf` and `openssl.cnf`:

```yaml
volumes:
  - name: openssl-config
    emptyDir: {}
volumeMounts:
  - name: openssl-config
    mountPath: /etc/ssl
```

Set `OPENSSL_CONF` to point into that volume if you change the mount path.

---

## Supported Versions

| Image Tag | Python | OpenSSL | FIPS Certificate | Supported |
|-----------|--------|---------|-----------------|-----------|
| `3.11.12` | 3.11.12 | 3.1.2 | [Active](https://www.openssl.org/source/) | Yes |

Only the latest published tag receives security updates. Users should pin to a specific
digest rather than a tag for production deployments:

```bash
docker pull marshallhumble/fips-python@sha256:<digest>
```

---

## Known Vulnerabilities

The following findings from automated scans are acknowledged and accepted:

| CVE | Package | Severity | Reason |
|-----|---------|----------|--------|
| CVE-2023-45853 | zlib1g | CRITICAL | Affects `minizip` API only, not reachable via Python or this image. Debian `will_not_fix`. |
| CVE-2024-10041 | libpam | MEDIUM | PAM is present as a `useradd` dependency only. No PAM authentication is performed in this image. Debian `will_not_fix`. |

All other findings are remediated in the current tag or tracked in open issues.

---

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Report vulnerabilities by opening a [GitHub Security Advisory](https://github.com/marshallhumble/fipsDocker/security/advisories/new)
on this repository. You will receive a response within 72 hours.

Please include:

- A description of the vulnerability and its potential impact
- Steps to reproduce or proof-of-concept code
- The image tag and digest you tested against (`docker inspect --format='{{index .RepoDigests 0}}'`)
- Whether the vulnerability affects the FIPS boundary components (OpenSSL, cryptography)
  or the base OS packages

---

## Vulnerability Scanning

This image is scanned with [Trivy](https://github.com/aquasecurity/trivy) on every build.
The SBOM is published in SPDX format alongside each release and is available at
`sbom.spdx.json` in the repository root.

To scan the current image yourself:

```bash
trivy image marshallhumble/fips-python:3.11.12
```

---

## Supply Chain

- OpenSSL source is downloaded directly from `https://www.openssl.org/source/` and verified
  against the published SHA256 checksum
- Python source is downloaded from `https://www.python.org/ftp/python/`
- The `cryptography` package is built from source via PyPI sdist, not a pre-built wheel,
  ensuring it links against this image's OpenSSL and not a bundled non-FIPS build
- The uv binary is pulled from a pinned digest at `ghcr.io/astral-sh/uv`
- The base image is pinned to a specific `debian:bookworm-slim` digest in CI

---

## License

MIT. See [LICENSE](./LICENSE).