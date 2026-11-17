# Build sem Xcode nem SwiftPM: só precisa das Command Line Tools (xcode-select --install).
APP := build/Kizami.app
SRC := $(wildcard Sources/Kizami/*.swift)
TEXTOS := $(wildcard Resources/*.lproj/*.strings)
SWIFTC := swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0
# O mesmo certificado local do Kanji (scripts/dev-certificate.sh lá): as permissões do macOS (Calendários,
# Automação) ficam presas à assinatura, e com a ad-hoc o macOS perguntaria tudo de novo a cada build.
IDENTIDADE := $(shell security find-certificate -c "Kanji Dev" >/dev/null 2>&1 && echo "Kanji Dev" || echo -)

app: $(APP)

$(APP): $(SRC) $(TEXTOS) Resources/Info.plist
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp -R Resources/en.lproj Resources/pt-BR.lproj "$(APP)/Contents/Resources/"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	$(SWIFTC) -O $(SRC) -o "$(APP)/Contents/MacOS/Kizami"
	codesign --force --sign "$(IDENTIDADE)" "$(APP)"

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
	$(SWIFTC) Tests/*.swift Sources/Kizami/Geometria.swift Sources/Kizami/Atividades.swift Sources/Kizami/Correio.swift Sources/Kizami/Bandeja.swift Sources/Kizami/Som.swift Sources/Kizami/Player.swift \
		Sources/Kizami/Agenda.swift Sources/Kizami/Tempo.swift Sources/Kizami/Claude.swift Sources/Kizami/Mac.swift \
		Sources/Kizami/Interesses.swift Sources/Kizami/Kanji.swift Sources/Kizami/Placar.swift Sources/Kizami/Cronometro.swift Sources/Kizami/Copiados.swift Sources/Kizami/Espelho.swift Sources/Kizami/Downloads.swift Sources/Kizami/GitHub.swift Sources/Kizami/Personalizacao.swift Sources/Kizami/AtalhosApple.swift -o build/teste
	./build/teste

clean:
	rm -rf build

.PHONY: app run install teste clean
