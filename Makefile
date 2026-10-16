.PHONY: lint test all
all: lint test
lint:
	shellcheck bin/*.sh lib/*.sh
test:
	bats tests/
