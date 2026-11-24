# Convenience targets over scripts/*.sh (the scripts are the source of truth).
TREE ?= .work/tree

all: build

check:
	sh scripts/check-prereqs.sh

build:
	sh scripts/build.sh

verify:
	sh scripts/verify.sh $(TREE)

regen:
	sh scripts/regen.sh $(TREE)

clean:
	rm -rf .work
