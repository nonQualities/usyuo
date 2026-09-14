C3C = c3c
C3C_LIB ?= $(CURDIR)/c3lib

.PHONY: all build run test test_arena test_parser clean help

all: build

build:
	C3C_LIB=$(C3C_LIB) $(C3C) compile "src/**" -o usyuo

run: build
	./usyuo

test:
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/**" -- --help

test_arena:
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/backend/arena.c3" test/test_arena.c3

test_parser:
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/backend/ast.c3" "src/backend/parser.c3" test/test_parser.c3

clean:
	rm -rf build usyuo c3todo test_arena test_parser

help:
	@echo "Available targets:"
	@echo "  make build  - Compile usyuo executable from src/**"
	@echo "  make run    - Build and launch interactive REPL"
	@echo "  make test   - Test compilation and display help"
	@echo "  make clean  - Remove build artifacts and binary"
