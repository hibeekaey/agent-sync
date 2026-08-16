PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: install uninstall test

install:
	install -d "$(BINDIR)"
	install -m 0755 bin/agent "$(BINDIR)/agent"
	@echo "installed $(BINDIR)/agent"

uninstall:
	rm -f "$(BINDIR)/agent"
	@echo "removed $(BINDIR)/agent"

test:
	sh -n bin/agent
	sh tests/agent_test.sh
