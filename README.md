# FIPS-Compliant Python Docker Image

[![SBOM](https://img.shields.io/badge/SBOM-SPDX-blue)](./sbom.spdx.json)
[![License](https://img.shields.io/github/license/marshallhumble/fipsDocker)](./LICENSE)

A FIPS 140-2 / 140-3 *compliant* Python 3.11 container image, built from source against
the FIPS-validated OpenSSL 3.1.2 provider with the `cryptography` package linked against
the same OpenSSL.

Intended for regulated workloads (FedRAMP, CMMC, HIPAA, PCI-DSS) that need to ship a
Python runtime using only FIPS-approved cryptography.

See [`security.md`](./security.md) for the full FIPS boundary, supply-chain posture,
Kubernetes recipe, and the list of accepted-but-not-fixed CVEs.

---

## Key Features

- OpenSSL 3.1.2 ([FIPS 140-3 validated](https://openssl-library.org/post/2025-03-11-fips-140-3/))
  compiled from source with `enable-fips` and `no-legacy`
- Python 3.11.12 compiled against the FIPS OpenSSL
- `cryptography` built from source (no pre-built wheels) so it links against this image's
  OpenSSL and not a bundled non-FIPS build
- Pinned digests for the Debian base and the uv installer; SHA256-verified source
  tarballs for OpenSSL and Python
- Runs as a non-root user (uid 1000); FIPS provider self-tests run fresh on every
  container start via the entrypoint
- Final image is ~390 MB on `linux/amd64`

Published at <https://hub.docker.com/r/marshallhumble/fips-python>.

---

## Usage

### Build

With [just](https://github.com/casey/just):

```bash
just build-all   # build for native arch + Trivy scan + SPDX SBOM
```

Or with make:

```bash
make build-all
```

### Run

```bash
docker run --rm -p 8080:8080 marshallhumble/fips-python:3.11.12
# open http://localhost:8080 — the smoke endpoint reports whether MD5 is blocked
```

### Pin by digest in production

```bash
docker pull marshallhumble/fips-python@sha256:<digest>
```

---

## Repo layout

| File | Purpose |
|---|---|
| [`Dockerfile`](./Dockerfile) | Multi-stage build: OpenSSL → Python + cryptography → minimal runtime |
| [`Dockerfile.test`](./Dockerfile.test) | Layers `app.py` + test deps onto the base for a runnable FIPS demo |
| [`app.py`](./app.py) | FastAPI smoke endpoint that returns whether MD5 is blocked under the active FIPS provider |
| [`docker-entrypoint.sh`](./docker-entrypoint.sh) | Runs `openssl fipsinstall` fresh on each container start so the FIPS self-tests execute on the target host |
| [`requirements.txt`](./requirements.txt) | uv-exported, fully hash-pinned dependency lock for the test image |
| [`justfile`](./justfile) / [`Makefile`](./Makefile) | Build, scan, SBOM, run, sign |
| [`security.md`](./security.md) | Security policy, FIPS boundary, supply chain, accepted CVEs |

---

## Issues

For bugs or improvements please open an issue or PR. For security reports, follow the
process in [`security.md`](./security.md#reporting-a-vulnerability) — *not* a public issue.

---

## License

MIT — see [`LICENSE`](./LICENSE).
