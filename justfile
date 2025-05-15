# Justfile for building and testing FIPS-compliant Python Docker image

# Set variables
set dotenv-load := true
IMAGE_NAME := "fips-python"
TAG := "3.11.12" #Tag with python version
PLATFORM := "linux/amd64"
DOCKERFILE := "Dockerfile"

# Build image
build:
	docker buildx build --platform {{PLATFORM}} -t {{IMAGE_NAME}}:{{TAG}} -f {{DOCKERFILE}} .

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
	trivy image --severity CRITICAL,HIGH {{IMAGE_NAME}}:{{TAG}}

# Generate SBOM in SPDX format
trivy-sbom:
	trivy image --format spdx-json --output sbom.spdx.json {{IMAGE_NAME}}:{{TAG}}

# Run full build + scan + sbom
build-all:
	just build-load && just trivy-scan && just trivy-sbom
