# Justfile for building and testing FIPS-compliant Python Docker image

set dotenv-load := true

IMAGE_NAME := "fips-python"
TAG := "3.11.12"
DOCKERFILE := "Dockerfile"

# Detect native arch for local builds so --load works with buildx
NATIVE_ARCH := `uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'`
NATIVE_BUILD_ARCH := `uname -m | sed 's/x86_64/linux-x86_64/;s/aarch64/linux-aarch64/'`

# Build for native arch and load into local Docker daemon
build-local:
    docker buildx build \
      --platform linux/{{NATIVE_ARCH}} \
      --build-arg TARGETARCH={{NATIVE_ARCH}} \
      --load \
      -t {{IMAGE_NAME}}:{{TAG}} \
      -f {{DOCKERFILE}} .

# Build for amd64 only (CI / x86 cloud targets)
build:
    docker buildx build \
      --platform linux/amd64 \
      --build-arg TARGETARCH=amd64 \
      --load \
      -t {{IMAGE_NAME}}:{{TAG}} \
      -f {{DOCKERFILE}} .

# Build for arm64 only (Apple Silicon / ARM cloud targets)
build-mac:
    docker buildx build \
      --platform linux/arm64 \
      --build-arg TARGETARCH=arm64 \
      --load \
      -t {{IMAGE_NAME}}:{{TAG}} \
      -f {{DOCKERFILE}} .

# Build and push multi-platform image to registry
build-push:
    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t ${IMAGE_NAME}:${IMAGE_TAG} \
      -f {{DOCKERFILE}} \
      --push .

# Sign the image with cosign
sign-image:
    cosign sign --yes ${IMAGE_NAME}:${IMAGE_TAG}

# Build, push, and sign
publish: build-push sign-image

# Run the image
run:
    docker run --rm -e OPENSSL_FIPS=1 {{IMAGE_NAME}}:{{TAG}}

# Build for native arch and run the test container
test: build-local
    @echo "Building test container..."
    docker build -f Dockerfile.test -t {{IMAGE_NAME}}:test .
    @echo "Running test container on http://localhost:8080"
    docker run --rm -p 8080:8080 {{IMAGE_NAME}}:test

# Launch a shell in the container
shell:
    docker run --rm -it {{IMAGE_NAME}}:{{TAG}} sh

# Remove local images
clean:
    docker image rm {{IMAGE_NAME}}:{{TAG}} || true
    docker image rm {{IMAGE_NAME}}:test || true

# Scan image for vulnerabilities
trivy-scan:
    trivy image --severity CRITICAL,HIGH,MEDIUM {{IMAGE_NAME}}:{{TAG}}

# Generate SBOM in SPDX format
trivy-sbom:
    trivy image --format spdx-json --output sbom.spdx.json {{IMAGE_NAME}}:{{TAG}}

# Inspect image layers
dive:
    dive {{IMAGE_NAME}}:{{TAG}}

# Build for native arch, scan, and generate SBOM
build-all: build-local trivy-scan trivy-sbom
