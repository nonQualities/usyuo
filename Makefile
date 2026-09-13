C3C = c3c
C3C_LIB ?= $(CURDIR)/c3lib

.PHONY: all build run test clean help

all: build

build:
	C3C_LIB=$(C3C_LIB) $(C3C) compile "src/**" -o c3todo

run: build
	./c3todo

test:
	C3C_LIB=$(C3C_LIB) $(C3C) compile-run "src/**" -- --help

clean:
	rm -rf build c3todo

help:
	@echo "Available targets:"
	@echo "  make build  - Compile c3todo executable from src/**"
	@echo "  make run    - Build and launch interactive REPL"
	@echo "  make test   - Test compilation and display help"
	@echo "  make clean  - Remove build artifacts and binary"
