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
included [`app.py`](./app.py) smoke endpoint, which serves a status page indicating
whether MD5 is blocked by the active FIPS provider.

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

If your cluster uses a read-only root filesystem (recommended), the entrypoint still
needs to write two files at startup: `/etc/ssl/openssl.cnf` and
`/usr/local/ssl/fipsmodule.cnf`. The image pre-creates both as empty files owned by
uid 1000 — overlay them with a writable `emptyDir` via `subPath` so the rest of
`/etc/ssl` (including the CA trust store at `/etc/ssl/certs`) stays read-only:

```yaml
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: app
      securityContext:
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: openssl-config
          mountPath: /etc/ssl/openssl.cnf
          subPath: openssl.cnf
        - name: openssl-config
          mountPath: /usr/local/ssl/fipsmodule.cnf
          subPath: fipsmodule.cnf
  volumes:
    - name: openssl-config
      emptyDir: {}
```

If you prefer to relocate the writable config out of `/etc/ssl` entirely, set
`OPENSSL_CONF` and `FIPSMODULE_CNF` to paths inside your writable volume and edit
`docker-entrypoint.sh` accordingly.

---

## Supported Versions

| Image Tag | Python | OpenSSL | FIPS Certificate | Supported |
|-----------|--------|---------|-----------------|-----------|
| `3.11.12` | 3.11.12 | 3.1.2 | [Active](https://openssl-library.org/post/2025-03-11-fips-140-3/) | Yes |

Only the latest published tag receives security updates. Users should pin to a specific
digest rather than a tag for production deployments:

```bash
docker pull marshallhumble/fips-python@sha256:<digest>
```

### OpenSSL 3.1.2 pin (accepted tradeoff)

OpenSSL is deliberately pinned to **3.1.2** because that is the source-code version
covered by the [OpenSSL FIPS 140-3 validation](https://openssl-library.org/post/2025-03-11-fips-140-3/).
Upgrading the OpenSSL source invalidates the CMVP cert link and defeats the purpose
of this image.

Upstream's 3.1.x line has reached end-of-life, which means any libssl/libcrypto CVE
published after 2023-08 is **not patched** in this image. This is an intentional
tradeoff between FIPS compliance and routine security patching. Specific findings
that surface from scanners against this OpenSSL version are tracked in the *Known
Vulnerabilities* table below with a `will_not_fix` rationale.

Operators who can accept a non-FIPS-validated runtime should use a current OpenSSL
LTS release (3.0.x or 3.5.x) instead.

---

## Known Vulnerabilities

The following findings from automated scans are acknowledged and accepted:

| CVE | Package | Severity | Reason |
|-----|---------|----------|--------|
| CVE-2023-45853 | zlib1g | CRITICAL | Affects `minizip` API only, not reachable via Python or this image. Debian `will_not_fix`. |
| CVE-2024-10041 | libpam | MEDIUM | PAM is present as a `useradd` dependency only. No PAM authentication is performed in this image. Debian `will_not_fix`. |
| Post-2023-08 libssl/libcrypto CVEs | openssl 3.1.2 | varies | OpenSSL is pinned to the FIPS 140-3 validated source version (see *Supported Versions* above). Upstream 3.1.x is EOL; cherry-picking patches would invalidate the FIPS cert link. Accepted tradeoff. |

The `rustls-webpki` finding (GHSA-pwjx-qhcg-rvj4) flagged against older `cryptography`
releases should be re-scanned against the bundled `cryptography==48.0.0` and removed
from this table or re-listed depending on the scan result.

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
  against the SHA256 published at `openssl-3.1.2.tar.gz.sha256`, pinned in the Dockerfile
  as `OPENSSL_SHA256`
- Python source is downloaded from `https://www.python.org/ftp/python/` and verified
  against a SHA256 pinned in the Dockerfile as `PYTHON_SHA256` (python.org only publishes
  MD5 + GPG signatures for source tarballs; the SHA was computed from the official
  upstream tarball and pinned at build time)
- The `cryptography` package is built from source via PyPI sdist, not a pre-built wheel,
  ensuring it links against this image's OpenSSL and not a bundled non-FIPS build
- All Python dependencies pinned in `requirements.txt` ship full SHA256 hashes; the test
  image installs them with `uv pip install --require-hashes`
- The uv binary is pulled from a pinned `sha256:` digest at `ghcr.io/astral-sh/uv`
- The `debian:bookworm-slim` base image is pinned to a `sha256:` digest in all three
  build stages
- `rustup-init.sh` itself is not verified by the Dockerfile (it is fetched over TLS only);
  rustup then verifies the toolchains it downloads via GPG. If this is unacceptable for
  your threat model, replace the rustup install with a pinned `rustup-init` binary
  download verified against the SHA256 published at
  `https://static.rust-lang.org/rustup/dist/<target>/rustup-init.sha256`

---

## License

MIT. See [LICENSE](./LICENSE).