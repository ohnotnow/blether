APP = build/Build/Products/Release/Blether.app

# Optional, untracked: sign every build with one certificate from your keychain, for example
#   SIGN = 0123456789ABCDEF0123456789ABCDEF01234567   # the hash `security find-identity -v -p codesigning` prints
#   TEAM = ABCDE12345                                  # the team id in brackets in the same line
# The certificate's name ("Apple Development") does not work here: xcodebuild goes looking for a
# "Mac Development" certificate and fails. The hash does. TEAM is needed by the package resource bundles.
# Every build is then signed by the same certificate, so the keychain stops asking for your
# password on each new build to hand over the stored API keys. Left unset, builds are ad-hoc.
-include local.mk
ifdef SIGN
SIGNING = CODE_SIGN_IDENTITY="$(SIGN)" CODE_SIGN_STYLE=Manual
endif
ifdef TEAM
SIGNING += DEVELOPMENT_TEAM=$(TEAM)
endif

.PHONY: build generate run test clean

build: Blether.xcodeproj
	xcodebuild -project Blether.xcodeproj -scheme Blether -configuration Release -derivedDataPath build build $(SIGNING)

SOURCES = $(shell find Sources Tests -type f)

generate Blether.xcodeproj: project.yml $(SOURCES)
	xcodegen generate

run: build
	open $(APP)

test: Blether.xcodeproj
	xcodebuild -project Blether.xcodeproj -scheme Blether -derivedDataPath build test CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf build
