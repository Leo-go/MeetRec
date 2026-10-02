APP := MeetRec.app
BIN := $(APP)/Contents/MacOS/MeetRec
SIGN_ID := MeetRec Local

.PHONY: all run clean identity

all: identity
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -swift-version 5 -O -parse-as-library \
		-framework AppKit -framework AVFoundation -framework ScreenCaptureKit -framework CoreMedia \
		-o $(BIN) Sources/main.swift
	codesign --force --sign "$(SIGN_ID)" --timestamp=none $(APP)

identity:
	./scripts/ensure-sign-identity.sh

run: all
	open $(APP)

clean:
	rm -rf $(APP)
