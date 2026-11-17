SCRIPTS := $(wildcard scripts/*.sh scripts/lib/*.sh)

.PHONY: all lint test

all: lint test

lint:
	shellcheck -x $(SCRIPTS)

test:
	bats tests/
