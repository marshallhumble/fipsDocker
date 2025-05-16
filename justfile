# Justfile for building and testing FIPS-compliant Python Docker image

# Set variables
set dotenv-load := true
IMAGE_NAME := "fips-python"
TAG := "3.11.12" # tag with python version
PLATFORM := "linux/arm64"
DOCKERFILE := "Dockerfile"
BUILD_ARCH := "linux-x86_64"

build:
    docker buildx build \
      --platform linux/amd64 \
      --build-arg TARGETARCH=amd64 \
      --build-arg BUILD_ARCH={{BUILD_ARCH}} \
      -t fips-python:latest .

build-mac:
    docker buildx build \
      --platform linux/arm64 \
      --build-arg TARGETARCH=arm64 \
      --build-arg BUILD_ARCH=linux-aarch64 \
      -t fips-python:mac .


# Build and load to local docker daemon
build-load:
	docker buildx build --platform {{PLATFORM}} -t {{IMAGE_NAME}}:{{TAG}} --load -f {{DOCKERFILE}} .

# Build and push to remote registry
build-push:
	docker buildx build --platform {{PLATFORM}} -t {{IMAGE_NAME}}:{{TAG}} --push -f {{DOCKERFILE}} .

# Run the image
run:
	docker run --rm -e OPENSSL_FIPS=1 {{IMAGE_NAME}}:{{TAG}}

# Launch a shell in the container
shell:
	docker run --rm -it {{IMAGE_NAME}}:{{TAG}} sh

# Clean up the image
clean:
	docker image rm {{IMAGE_NAME}}:{{TAG}} || true

# Scan image for vulnerabilities
trivy-scan:
	trivy image --severity CRITICAL,HIGH,MEDIUM {{IMAGE_NAME}}:{{TAG}}

# Generate SBOM in SPDX format
trivy-sbom:
	trivy image --format spdx-json --output sbom.spdx.json {{IMAGE_NAME}}:{{TAG}}

# Run full build + scan + sbom
build-all:
	just build-load && just trivy-scan && just trivy-sbom