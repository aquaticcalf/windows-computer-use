ODIN ?= odin
BIN  := bin/wcu.exe
CMD  := cmd/wcu
STRICT := -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors

build:
	mkdir -p bin
	$(ODIN) build $(CMD) $(STRICT) -out:$(BIN)

run:
	$(ODIN) run $(CMD) -- $(ARGS)

check:
	$(ODIN) check $(CMD) $(STRICT)

test:
	for d in $$(find internal -type d); do $(ODIN) test $$d $(STRICT) || exit 1; done

clean:
	rm -rf bin

.PHONY: build run check test clean
