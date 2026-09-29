# IONLANCER build.
#
# GM2 and PKG_CONFIG default to empty, which means "figure it out". The real
# detection lives in scripts/tools.sh, which searches $PATH, Homebrew,
# MacPorts, /usr/local, /opt and the Nix/Guix stores, and validates each
# candidate by running it. That is what makes `make release` work on a machine
# where the compiler is only installed as something like gm2-mp-15.
# Override explicitly when you need to: make GM2=/path/to/gm2 release
GM2 ?=
PKG_CONFIG ?=
export GM2
export PKG_CONFIG

TARGET = ionlancer
TOOLS = ./scripts/tools.sh

.PHONY: all release portable portable-macos aggressive debug run clean check deps test-lan

all: release

release: deps
	./scripts/build-unix.sh release "$(TARGET)"

portable: release
	./scripts/build-portable-linux.sh "$(TARGET)"

portable-macos: release
	./scripts/build-portable-macos.sh "$(TARGET)"

aggressive: deps
	./scripts/build-unix.sh aggressive "$(TARGET)"

debug: deps
	./scripts/build-unix.sh debug "$(TARGET)"

run: release
	./scripts/run.sh --auto

check:
	@$(TOOLS) check
	@$(TOOLS) probe && echo "toolchain ok"

test-lan: release
	./tests/test-lan.sh

deps:
	@$(TOOLS) deps

clean:
	rm -rf build dist
	rm -f $(TARGET) $(TARGET)-debug *.o *.s *.lst
