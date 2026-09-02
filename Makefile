CC := gcc
LUAJIT := luajit
CFLAGS := -O2 -Wall -Wextra -Igenerated $(shell pkg-config --cflags luajit 2>/dev/null)

# LuaJIT is linked in statically (no runtime dependency on libluajit-5.1.so /
# a system luajit install); glibc/libm/libdl stay dynamic on purpose: LuaJIT's
# FFI resolves ffi.C.* symbols via dlsym-style lookup, which does not work
# against a fully statically linked glibc (verified: -static breaks it with
# "undefined symbol" at runtime for every ffi.C call). glibc/libm are present
# on every Linux system, so this is still a self-contained, dependency-free
# executable in the sense that matters: no Lua/LuaJIT install required.
LUAJIT_STATIC_LIB := $(shell gcc -print-file-name=libluajit-5.1.a)
LDLIBS := $(LUAJIT_STATIC_LIB) -lm -ldl

BIN := resmon
GEN_HEADERS := generated/core_bc.h generated/sextant_chars_bc.h generated/block_fonts_bc.h \
               generated/big_font_bc.h generated/med_font_bc.h generated/fake_fetcher_bc.h \
               generated/fetch_cpu_average_bc.h generated/fetch_mem_bc.h generated/fetch_top_bc.h \
               generated/mod_cpu_bc.h generated/mod_mem_bc.h generated/mod_top_bc.h

HOME_CONFIG := $(HOME)/.config/resmon

VERSION := $(shell sed -n 's/^local VERSION = "\(.*\)"/\1/p' src/core.lua)
DIST_ARCH := linux-x86_64
DIST_NAME := resmon-v$(VERSION)-$(DIST_ARCH)
DIST_DIR := build/$(DIST_NAME)

.PHONY: all clean install-config dist

all: $(BIN)

$(BIN): host.o
	$(CC) host.o -o $(BIN) $(LDLIBS)

host.o: host.c $(GEN_HEADERS)
	$(CC) $(CFLAGS) -c host.c -o host.o

generated/core_bc.h: src/core.lua
	@mkdir -p generated
	$(LUAJIT) -b -n core -t h src/core.lua generated/core_bc.h

generated/sextant_chars_bc.h: src/sextant_chars.lua
	@mkdir -p generated
	$(LUAJIT) -b -n sextant_chars -t h src/sextant_chars.lua generated/sextant_chars_bc.h

generated/block_fonts_bc.h: src/block_fonts.lua
	@mkdir -p generated
	$(LUAJIT) -b -n block_fonts -t h src/block_fonts.lua generated/block_fonts_bc.h

generated/big_font_bc.h: src/big_font.lua
	@mkdir -p generated
	$(LUAJIT) -b -n big_font -t h src/big_font.lua generated/big_font_bc.h

generated/med_font_bc.h: src/med_font.lua
	@mkdir -p generated
	$(LUAJIT) -b -n med_font -t h src/med_font.lua generated/med_font_bc.h

generated/fake_fetcher_bc.h: src/fake_fetcher.lua
	@mkdir -p generated
	$(LUAJIT) -b -n fake_fetcher -t h src/fake_fetcher.lua generated/fake_fetcher_bc.h

generated/fetch_cpu_average_bc.h: src/fetch_cpu_average.lua
	@mkdir -p generated
	$(LUAJIT) -b -n fetch_cpu_average -t h src/fetch_cpu_average.lua generated/fetch_cpu_average_bc.h

generated/fetch_mem_bc.h: src/fetch_mem.lua
	@mkdir -p generated
	$(LUAJIT) -b -n fetch_mem -t h src/fetch_mem.lua generated/fetch_mem_bc.h

generated/fetch_top_bc.h: src/fetch_top.lua
	@mkdir -p generated
	$(LUAJIT) -b -n fetch_top -t h src/fetch_top.lua generated/fetch_top_bc.h

generated/mod_cpu_bc.h: src/mod_cpu.lua
	@mkdir -p generated
	$(LUAJIT) -b -n mod_cpu -t h src/mod_cpu.lua generated/mod_cpu_bc.h

generated/mod_mem_bc.h: src/mod_mem.lua
	@mkdir -p generated
	$(LUAJIT) -b -n mod_mem -t h src/mod_mem.lua generated/mod_mem_bc.h

generated/mod_top_bc.h: src/mod_top.lua
	@mkdir -p generated
	$(LUAJIT) -b -n mod_top -t h src/mod_top.lua generated/mod_top_bc.h

install-config:
	mkdir -p $(HOME_CONFIG)/addons/fetchers $(HOME_CONFIG)/addons/mods
	test -f $(HOME_CONFIG)/config.lua || cp config/config.lua.example $(HOME_CONFIG)/config.lua
	cp fetchers/*.lua $(HOME_CONFIG)/addons/fetchers/
	cp mods/*.lua $(HOME_CONFIG)/addons/mods/

dist: $(BIN)
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)/images $(DIST_DIR)/config/addons/fetchers $(DIST_DIR)/config/addons/mods
	cp $(BIN) $(DIST_DIR)/resmon
	cp dist/install.sh $(DIST_DIR)/install.sh
	chmod +x $(DIST_DIR)/install.sh
	cp dist/README.md $(DIST_DIR)/README.md
	cp images/desktop1.png images/desktop2.png images/desktop3.png images/desktop4.png $(DIST_DIR)/images/
	cp config/config.lua.example config/config-full.lua.example config/config-horiz.lua.example $(DIST_DIR)/config/
	cp config/config-full.lua.example $(DIST_DIR)/config/config.lua
	cp fetchers/*.lua $(DIST_DIR)/config/addons/fetchers/
	cp mods/*.lua $(DIST_DIR)/config/addons/mods/
	tar -C build -czf build/$(DIST_NAME).tar.gz $(DIST_NAME)
	@echo "built build/$(DIST_NAME).tar.gz"

clean:
	rm -f host.o $(BIN) $(GEN_HEADERS)
	rmdir generated 2>/dev/null || true

# vim: filetype=make foldmethod=marker foldmarker=>{,>}
