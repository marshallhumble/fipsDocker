# Makefile for building and testing FIPS-compliant Python Docker image

IMAGE_NAME := fips-python
TAG := 3.11.12 #Tag with python version
PLATFORM := linux/amd64
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
