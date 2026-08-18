GM2 ?= gm2
PKG_CONFIG ?= pkg-config
TARGET = ionlancer

.PHONY: all release portable aggressive debug run clean check deps

all: release

release: deps
	GM2="$(GM2)" PKG_CONFIG="$(PKG_CONFIG)" ./scripts/build-unix.sh release "$(TARGET)"

portable: release
	GM2="$(GM2)" PKG_CONFIG="$(PKG_CONFIG)" ./scripts/build-portable-linux.sh "$(TARGET)"

aggressive: deps
	GM2="$(GM2)" PKG_CONFIG="$(PKG_CONFIG)" ./scripts/build-unix.sh aggressive "$(TARGET)"

debug: deps
	GM2="$(GM2)" PKG_CONFIG="$(PKG_CONFIG)" ./scripts/build-unix.sh debug "$(TARGET)"

run: release
	./scripts/run.sh --auto

check:
	@command -v $(GM2) >/dev/null || { echo "gm2 not found"; exit 1; }
	@$(GM2) --version | head -n 1
	@command -v $(PKG_CONFIG) >/dev/null || { echo "pkg-config not found"; exit 1; }
	@echo "SDL2: $$($(PKG_CONFIG) --modversion sdl2 2>/dev/null || echo missing)"
	@echo "SDL2 libdir: $$($(PKG_CONFIG) --variable=libdir sdl2 2>/dev/null || echo unknown)"
	@libdir="$$($(PKG_CONFIG) --variable=libdir sdl2 2>/dev/null || true)"; \
	  if [ -n "$$libdir" ]; then ls -1 "$$libdir"/libSDL2* 2>/dev/null || true; fi

deps:
	@command -v $(GM2) >/dev/null || { echo "error: gm2 not found"; exit 1; }
	@command -v $(PKG_CONFIG) >/dev/null || { echo "error: pkg-config not found"; exit 1; }
	@$(PKG_CONFIG) --exists sdl2 || { echo "error: SDL2 development files not found (pkg-config sdl2)"; exit 1; }

clean:
	rm -rf build dist
	rm -f $(TARGET) $(TARGET)-debug *.o *.s *.lst
