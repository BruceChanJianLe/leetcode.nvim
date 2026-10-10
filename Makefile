TESTS_INIT := tests/minimal_init.lua
TESTS_DIR := tests

.PHONY: test lint fmt

test:
	nvim --headless -u $(TESTS_INIT) -c "PlenaryBustedDirectory $(TESTS_DIR) { minimal_init = '$(TESTS_INIT)', sequential = true }"

lint:
	stylua --check lua tests

fmt:
	stylua lua tests
