APP = build/Build/Products/Release/Blether.app

.PHONY: build generate run test clean

build: Blether.xcodeproj
	xcodebuild -project Blether.xcodeproj -scheme Blether -configuration Release -derivedDataPath build build

SOURCES = $(shell find Sources Tests -type f)

generate Blether.xcodeproj: project.yml $(SOURCES)
	xcodegen generate

run: build
	open $(APP)

test: Blether.xcodeproj
	xcodebuild -project Blether.xcodeproj -scheme Blether -derivedDataPath build test CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf build
