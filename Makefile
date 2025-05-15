# Makefile for building and testing FIPS-compliant Python Docker image

IMAGE_NAME := fips-python
TAG := 3.11.12 # tag with python version
PLATFORM := linux/arm64
DOCKERFILE := Dockerfile

build:
	docker buildx build --platform $(PLATFORM) -t $(IMAGE_NAME):$(TAG) -f $(DOCKERFILE) .

build-load:
	docker buildx build --platform $(PLATFORM) -t $(IMAGE_NAME):$(TAG) --load -f $(DOCKERFILE) .

build-push:
	docker buildx build --platform $(PLATFORM) -t $(IMAGE_NAME):$(TAG) --push -f $(DOCKERFILE) .

run:
	docker run --rm -e OPENSSL_FIPS=1 $(IMAGE_NAME):$(TAG)

shell:
	docker run --rm -it $(IMAGE_NAME):$(TAG) sh

clean:
	docker image rm $(IMAGE_NAME):$(TAG) || true

trivy-scan:
	trivy image --severity CRITICAL,HIGH $(IMAGE_NAME):$(TAG)

trivy-sbom:
	trivy image --format spdx-json --output sbom.spdx.json $(IMAGE_NAME):$(TAG)

build-all:
	$(MAKE) build-load && \
	$(MAKE) trivy-scan && \
	$(MAKE) trivy-sbom