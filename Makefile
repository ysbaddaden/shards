.POSIX:

# Recipes for this Makefile

## Build shards
##   $ make
## Build shards in release mode
##   $ make release=1
## Run tests
##   $ make test
## Run tests without fossil tests
##   $ make test skip_fossil=1
## Generate docs
##   $ make docs
## Install shards
##   $ make install
## Uninstall shards
##   $ make uninstall
## Build and install shards
##   $ make build && sudo make install

release ?=      ## Compile in release mode
debug ?=        ## Add symbolic debug info
static ?=       ## Enable static linking
skip_fossil ?=  ## Skip fossil tests
skip_git ?=     ## Skip git tests
skip_hg ?=      ## Skip hg tests

DESTDIR ?=          ## Install destination dir
PREFIX ?= /usr/local## Install path prefix

CRYSTAL ?= crystal
SHARDS ?= shards
override FLAGS += $(if $(release),--release )$(if $(debug),-d )$(if $(static),--static )

SHARDS_SOURCES = $(shell find src -name '*.cr')
MOLINILLO_SOURCES = $(shell find lib/molinillo -name '*.cr' 2> /dev/null)
SOURCES = $(SHARDS_SOURCES) $(MOLINILLO_SOURCES)
TEMPLATES = src/templates/*.ecr

SHARDS_CONFIG_BUILD_COMMIT := $(shell git rev-parse --short HEAD 2> /dev/null)
SHARDS_VERSION := $(shell cat VERSION)
SOURCE_DATE_EPOCH := $(shell (git show -s --format=%ct HEAD || stat -c "%Y" Makefile || stat -f "%m" Makefile) 2> /dev/null)
EXPORTS := SHARDS_CONFIG_BUILD_COMMIT="$(SHARDS_CONFIG_BUILD_COMMIT)" SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)"
BINDIR ?= $(DESTDIR)$(PREFIX)/bin
MANDIR ?= $(DESTDIR)$(PREFIX)/share/man
INSTALL ?= /usr/bin/install

MOLINILLO_VERSION = $(shell $(CRYSTAL) eval 'require "yaml"; puts YAML.parse(File.read("shard.lock"))["shards"]["molinillo"]["version"]')
MOLINILLO_URL = "https://github.com/crystal-lang/crystal-molinillo/archive/v$(MOLINILLO_VERSION).tar.gz"

# MSYS2 support (native Windows should use `Makefile.win` instead)
ifeq ($(OS),Windows_NT)
  EXE := .exe
  WINDOWS := 1
else
  EXE :=
  WINDOWS :=
endif

.PHONY: all
all: build

include docs.mk

.PHONY: build
build: bin/shards$(EXE)

.PHONY: clean
clean: ## Remove build artifacts
clean: clean_docs
	rm -f bin/shards$(EXE)

bin/shards$(EXE): $(SOURCES) $(TEMPLATES) lib
	@mkdir -p bin
	$(EXPORTS) $(CRYSTAL) build $(FLAGS) src/shards.cr -o "$@"

.PHONY: install
install: ## Install shards
install: bin/shards$(EXE) man/shards.1.gz man/shard.yml.5.gz
	$(INSTALL) -m 0755 -d "$(BINDIR)" "$(MANDIR)/man1" "$(MANDIR)/man5"
	$(INSTALL) -m 0755 bin/shards$(EXE) "$(BINDIR)"
	$(INSTALL) -m 0644 man/shards.1.gz "$(MANDIR)/man1"
	$(INSTALL) -m 0644 man/shard.yml.5.gz "$(MANDIR)/man5"

.PHONY: uninstall
uninstall: ## Uninstall shards
uninstall:
	rm -f "$(BINDIR)/shards"
	rm -f "$(MANDIR)/man1/shards.1.gz"
	rm -f "$(MANDIR)/man5/shard.yml.5.gz"

.PHONY: test
test: ## Run all tests
test: test_unit test_integration

.PHONY: test_unit
test_unit: ## Run unit tests
test_unit: lib
	$(CRYSTAL) spec ./spec/unit/ $(if $(skip_fossil),--tag ~fossil) $(if $(skip_git),--tag ~git) $(if $(skip_hg),--tag ~hg)

.PHONY: test_integration
test_integration: ## Run integration tests
test_integration: bin/shards$(EXE)
	$(CRYSTAL) spec ./spec/integration/

lib: shard.lock
	mkdir -p lib/molinillo
	$(SHARDS) install || (curl -L $(MOLINILLO_URL) | tar -xzf - -C lib/molinillo --strip-components=1)

shard.lock: shard.yml
	([ $(SHARDS) = false ] && touch $@) || $(SHARDS) update

man/%.gz: man/%
	gzip -c -9 $< > $@

.PHONY: help
help: ## Show this help
	@echo
	@printf '\033[34mtargets:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34moptional variables:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+ \?=.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = " \\?=.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34mrecipes:\033[0m\n'
	@grep -hE '^##.*$$' $(MAKEFILE_LIST) |\
		awk 'BEGIN {FS = "## "}; /^## [a-zA-Z_-]/ {printf "  \033[36m%s\033[0m\n", $$2}; /^##  / {printf "  %s\n", $$2}'
