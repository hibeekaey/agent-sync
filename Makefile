PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
MANDIR := $(PREFIX)/share/man/man1
BASHCOMPDIR := $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR := $(PREFIX)/share/zsh/site-functions

.PHONY: install uninstall test man

install:
	install -d "$(BINDIR)"
	install -m 0755 bin/agent "$(BINDIR)/agent"
	-install -d "$(MANDIR)" && install -m 0644 docs/agent.1 "$(MANDIR)/agent.1"
	-install -d "$(BASHCOMPDIR)" && install -m 0644 completions/agent.bash "$(BASHCOMPDIR)/agent"
	-install -d "$(ZSHCOMPDIR)" && install -m 0644 completions/_agent "$(ZSHCOMPDIR)/_agent"
	@echo "installed $(BINDIR)/agent (man page and completions best-effort)"

uninstall:
	rm -f "$(BINDIR)/agent" "$(MANDIR)/agent.1" "$(BASHCOMPDIR)/agent" "$(ZSHCOMPDIR)/_agent"
	@echo "removed $(BINDIR)/agent"

# Regenerate the committed roff from the scdoc source (contributors only).
man:
	scdoc < docs/agent.1.scd > docs/agent.1

test:
	sh -n bin/agent
	sh -n install.sh
	@for t in tests/*_test.sh; do \
		sh -n "$$t" || exit 1; \
		sh "$$t" || exit 1; \
	done
