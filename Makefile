# Build sem Xcode nem SwiftPM: só precisa das Command Line Tools (xcode-select --install).
APP := build/Kizami.app
SRC := $(wildcard Sources/Kizami/*.swift)
TEXTOS := $(wildcard Resources/*.lproj/*.strings)
SWIFTC := swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0

app: $(APP)

# Assinatura ad-hoc: o Kizami não pede nenhuma permissão, então não há o que perder entre builds.
$(APP): $(SRC) $(TEXTOS) Resources/Info.plist
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp -R Resources/en.lproj Resources/pt-BR.lproj "$(APP)/Contents/Resources/"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	$(SWIFTC) -O $(SRC) -o "$(APP)/Contents/MacOS/Kizami"
	codesign --force --sign - "$(APP)"

run: app
	-pkill -x Kizami
	open "$(APP)"

install: app
	-pkill -x Kizami
	rm -rf /Applications/Kizami.app
	cp -R "$(APP)" /Applications/
	open /Applications/Kizami.app

teste:
	mkdir -p build
	$(SWIFTC) Tests/*.swift Sources/Kizami/Geometria.swift Sources/Kizami/Atividades.swift Sources/Kizami/Correio.swift -o build/teste
	./build/teste

clean:
	rm -rf build

.PHONY: app run install teste clean
