FRIDA ?= ../frida

all: app

build/build.ninja:
	rm -rf build
	( \
		. $(FRIDA)/build/frida_thin-meson-env-macos-x86_64.rc \
		&& $(FRIDA)/releng/meson/meson.py \
			build \
	)

app: build/build.ninja server/server.vala server/server-glue-darwin.m server/cobalt/cobalt-darwin.vala server/cobalt/cobalt-glue-darwin.m
	( \
		. $(FRIDA)/build/frida_thin-meson-env-macos-x86_64.rc \
		&& ninja -C build \
	)

test: app
	./build/server/wonder-playground-server

clean:
	rm -rf build/

.PHONY: all app test clean
.SECONDARY:
