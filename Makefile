ODIN ?= odin
BIN  := bin/wcu.exe
CMD  := cmd/wcu

build:
	mkdir -p bin
	$(ODIN) build $(CMD) -out:$(BIN)

run:
	$(ODIN) run $(CMD) -- $(ARGS)

check:
	$(ODIN) check $(CMD)

test:
	for d in internal/*/; do $(ODIN) test $$d || exit 1; done

clean:
	rm -rf bin

.PHONY: build run check test clean
