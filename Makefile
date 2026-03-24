.PHONY: build test fmt check clean

ZIG ?= zig

build:
	$(ZIG) build

test:
	$(ZIG) build test --summary all

fmt:
	$(ZIG) fmt src/ tests/ examples/ build.zig

check:
	$(ZIG) fmt --check src/ tests/ examples/ build.zig

clean:
	rm -rf zig-out zig-cache .zig-cache

.DEFAULT_GOAL := build
