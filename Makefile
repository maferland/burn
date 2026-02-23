.PHONY: build test release install clean app update-homebrew-tap

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
NEXT_VERSION ?= $(VERSION)

build:
	swift build -c release

test:
	swift test

app: test
	./scripts/package_app.sh $(NEXT_VERSION)

install: app
	cp -R Burn.app /Applications/
	@echo "Installed Burn.app to /Applications"

clean:
	rm -rf .build *.dmg Burn.app

update-homebrew-tap:
	./scripts/update_homebrew_tap.sh $(NEXT_VERSION) Burn-$(NEXT_VERSION)-macos.dmg

release: app
	@if [ "$(VERSION)" = "$(NEXT_VERSION)" ]; then \
		echo "Error: specify NEXT_VERSION=vX.Y.Z"; exit 1; \
	fi
	gh release create $(NEXT_VERSION) Burn-$(NEXT_VERSION)-macos.dmg \
		--title "Burn $(NEXT_VERSION)" \
		--generate-notes
	$(MAKE) update-homebrew-tap
	@rm Burn-$(NEXT_VERSION)-macos.dmg
