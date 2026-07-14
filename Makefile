# Makefile for the minimal self-hosted GitHub Actions runner image.

IMAGE        ?= runner-images-minimal:latest
RUNNER_VERSION ?= 2.317.0
DOCKERFILE   := images/ubuntu/Dockerfile
CONTEXT      := images/ubuntu
SH_FILES     := $(shell find . -name '*.sh' -not -path './*/_work/*')

.DEFAULT_GOAL := help

.PHONY: help build lint test validate run

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the runner image (override RUNNER_VERSION=x.y.z)
	docker build \
		--build-arg RUNNER_VERSION=$(RUNNER_VERSION) \
		-t $(IMAGE) \
		-f $(DOCKERFILE) \
		$(CONTEXT)

lint: ## Run shellcheck on all shell scripts
	shellcheck -x -P SCRIPTDIR -S style $(SH_FILES)

test: ## Run the bats test suite
	bats tests/

validate: ## Validate a built image (requires `make build` first; override IMAGE=)
	tests/validate-image.sh $(IMAGE)

run: ## Run the image (needs RUNNER_REPO_URL and RUNNER_TOKEN)
	docker run --rm -it \
		-e RUNNER_REPO_URL=$(RUNNER_REPO_URL) \
		-e RUNNER_TOKEN=$(RUNNER_TOKEN) \
		-e RUNNER_LABELS=$(RUNNER_LABELS) \
		$(IMAGE)
