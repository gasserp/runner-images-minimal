# Makefile for the minimal self-hosted GitHub Actions runner images.

# DISTRO selects which image under images/<distro>/ to build (ubuntu | ubi9).
DISTRO       ?= ubuntu
IMAGE        ?= runner-images-minimal:$(DISTRO)
RUNNER_VERSION ?= 2.317.0
# TERRAFORM_VERSION must match the ARG default in the terraform flavor Dockerfile.
TERRAFORM_VERSION ?= 1.9.8
# Tag applied to the built terraform flavor image.
FLAVOR_IMAGE ?= runner-images-minimal:terraform
# The build context is images/ so Dockerfiles can COPY shared files from
# images/common/; each distro's Dockerfile is selected with -f.
DOCKERFILE   := images/$(DISTRO)/Dockerfile
CONTEXT      := images
SH_FILES     := $(shell find . -name '*.sh' -not -path './*/_work/*')

.DEFAULT_GOAL := help

.PHONY: help build build-all build-flavor lint test validate validate-flavor run

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the runner image (override DISTRO=ubuntu|ubi9, RUNNER_VERSION=x.y.z)
	docker build \
		--build-arg RUNNER_VERSION=$(RUNNER_VERSION) \
		-t $(IMAGE) \
		-f $(DOCKERFILE) \
		$(CONTEXT)

build-all: ## Build every distro image (ubuntu and ubi9)
	$(MAKE) build DISTRO=ubuntu
	$(MAKE) build DISTRO=ubi9

build-flavor: ## Build the terraform flavor on top of IMAGE (override BASE via IMAGE=, TERRAFORM_VERSION=)
	docker build \
		--build-arg BASE_IMAGE=$(IMAGE) \
		--build-arg TERRAFORM_VERSION=$(TERRAFORM_VERSION) \
		-t $(FLAVOR_IMAGE) \
		-f images/flavors/terraform/Dockerfile \
		$(CONTEXT)

lint: ## Run shellcheck on all shell scripts
	shellcheck -x -P SCRIPTDIR -S style $(SH_FILES)

test: ## Run the bats test suite
	bats tests/

validate: ## Validate a built image (requires `make build` first; override IMAGE=)
	tests/validate-image.sh $(IMAGE)

validate-flavor: ## Validate the built terraform flavor (requires `make build-flavor` first)
	tests/validate-flavor-terraform.sh $(FLAVOR_IMAGE)

run: ## Run the image (needs RUNNER_REPO_URL and RUNNER_TOKEN)
	docker run --rm -it \
		-e RUNNER_REPO_URL=$(RUNNER_REPO_URL) \
		-e RUNNER_TOKEN=$(RUNNER_TOKEN) \
		-e RUNNER_LABELS=$(RUNNER_LABELS) \
		$(IMAGE)
