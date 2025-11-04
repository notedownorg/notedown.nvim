# Copyright 2024 Notedown Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Use nix develop shell if nix is available
define NIX_SETTINGS
warn-dirty = false
download-buffer-size = 134217728
endef
export NIX_CONFIG := $(NIX_SETTINGS)
ifneq ($(shell command -v nix 2> /dev/null),)
SHELL := nix develop --command bash
endif

# Docker test environment versions
NVIM_VERSION ?= v0.10.2
LSP_VERSION ?= v0.1.0

check: hygiene test dirty

hygiene: format

dirty:
	git diff --exit-code

format: licenser
	stylua lua/ plugin/ tests/

test: test-docker

test-local:
	./scripts/test

test-docker-build:
	docker build -f Dockerfile.test -t notedown-nvim:test \
		--build-arg NVIM_VERSION=$(NVIM_VERSION) \
		--build-arg LSP_VERSION=$(LSP_VERSION) \
		.

test-docker: test-docker-build
	docker run --rm notedown-nvim:test

licenser:
	licenser apply -r "Notedown Authors"

.PHONY: all hygiene dirty format test test-local test-docker test-docker-build test-docker-shell licenser
