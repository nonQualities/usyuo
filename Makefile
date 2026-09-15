# ==============================================================================
# usyuo Makefile
# ==============================================================================

# Variables & Configuration
C3C       ?= c3c
C3C_LIB   ?= $(CURDIR)/c3lib
BUILD_DIR ?= build
BIN       := $(BUILD_DIR)/usyuo

# Phony targets do not represent physical files on disk
.PHONY: all build run test test_arena test_parser test_sort stress clean help

# Default target executed when typing 'make'
all: build

SRC_FILES := $(wildcard src/*.c3 src/**/*.c3)

# Build the main usyuo binary
build: $(BIN)

$(BIN): $(SRC_FILES)
	@mkdir -p $(@D)
	C3C_LIB=$(C3C_LIB) $(C3C) compile "src/**" -o $@

# Run interactive REPL
run: build
	./$(BIN)

# Run all unit tests and verify CLI flags
test: test_arena test_parser test_sort build
	./$(BIN) --version
	./$(BIN) --help

test_arena:
	@mkdir -p $(BUILD_DIR)
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/backend/arena.c3" test/test_arena.c3 -o $(BUILD_DIR)/test_arena

test_parser:
	@mkdir -p $(BUILD_DIR)
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/backend/ast.c3" "src/backend/parser.c3" test/test_parser.c3 -o $(BUILD_DIR)/test_parser

test_sort:
	@mkdir -p $(BUILD_DIR)
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/backend/ast.c3" "src/backend/arena.c3" "src/backend/parser.c3" "src/backend/index.c3" "src/backend/storage.c3" test/test_sort.c3 -o $(BUILD_DIR)/test_sort

# Generate 200k stress test tasks and launch usyuo
stress: build
	@scripts/generate_stress_test.sh 200000 resources/stress_200k.txt
	./$(BIN) resources/stress_200k.txt

# Clean up all compiled binaries and temporary artifacts
clean:
	rm -rf $(BUILD_DIR) resources/stress_200k.txt

# Help target describing available commands
help:
	@echo "Available targets:"
	@echo "  make build       - Compile usyuo executable into $(BUILD_DIR)/"
	@echo "  make run         - Build and launch interactive REPL"
	@echo "  make test        - Run all unit tests and verify CLI flags"
	@echo "  make test_arena  - Run memory arena allocator unit tests"
	@echo "  make test_parser - Run todo.txt parser unit tests"
	@echo "  make test_sort   - Run task date sorting unit tests"
	@echo "  make stress      - Generate 200k task file and launch REPL"
	@echo "  make clean       - Remove $(BUILD_DIR)/ and all compiled artifacts"
	@echo "  make help        - Show this reference menu"
