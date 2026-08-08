ODIN ?= odin
BIN  := bin/wcu.exe

build:
	$(ODIN) build cmd/wcu -out:$(BIN)

run:
	$(ODIN) run cmd/wcu -- $(ARGS)

test:
	$(ODIN) test internal/version

vet:
	$(ODIN) check cmd/wcu

clean:
	rm -rf bin

.PHONY: build run test vet clean
