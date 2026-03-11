.PHONY: build release run app dmg clean

build:
	cd VoiceNative && swift build

release:
	cd VoiceNative && swift build -c release

run: build
	cd VoiceNative && .build/debug/VoiceNative

app:
	./scripts/package-app.sh

dmg: app
	./scripts/create-dmg.sh

clean:
	cd VoiceNative && swift package clean
	rm -rf dist
