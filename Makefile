APP := MeetRec.app
BIN := $(APP)/Contents/MacOS/MeetRec
SIGN_ID := MeetRec Local
RN_SRCS := denoise.c kiss_fft.c pitch.c celt_lpc.c rnn.c rnn_data.c
RN_OBJS := $(addprefix build/,$(RN_SRCS:.c=.o))

.PHONY: all run clean identity

all: identity $(RN_OBJS)
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -swift-version 5 -O -parse-as-library \
		-framework AppKit -framework AVFoundation -framework ScreenCaptureKit -framework CoreMedia \
		-import-objc-header Sources/RNNoiseBridge.h \
		-I vendor/rnnoise/include \
		-o $(BIN) Sources/main.swift $(RN_OBJS)
	codesign --force --sign "$(SIGN_ID)" --timestamp=none $(APP)

build/%.o: vendor/rnnoise/src/%.c
	mkdir -p build
	clang -O2 -std=c99 -I vendor/rnnoise/include -I vendor/rnnoise/src -c $< -o $@

identity:
	./scripts/ensure-sign-identity.sh

run: all
	open $(APP)

clean:
	rm -rf $(APP) build
