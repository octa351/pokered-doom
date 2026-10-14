ROM ?= ../pokered.gbc
SYM ?= ../pokered.sym
CFLAGS = -O1 -w $(shell sdl2-config --cflags)
# usage: make -j10
all: pokered-mac
gen/table.c: gen.py $(ROM) $(SYM)
	python3 gen.py $(ROM) $(SYM) gen
BANKS = $(addprefix gen/bank,$(addsuffix .o,$(shell seq -f %02g 0 63)))
OBJS = $(BANKS) gen/table.o rt.o apu.o
gen/%.o: gen/%.c rt.h
	clang $(CFLAGS) -c $< -o $@
%.o: %.c rt.h
	clang $(CFLAGS) -c $< -o $@
$(BANKS:.o=.c): gen/table.c ;   # gen.py rewrites only the banks whose code changed
pokered-mac: $(OBJS)
	clang $^ $(shell sdl2-config --libs) -o $@

app: pokered-mac
	rm -rf "Pokemon Red.app" && mkdir -p "Pokemon Red.app/Contents/MacOS" "Pokemon Red.app/Contents/Resources"
	cp pokered-mac "Pokemon Red.app/Contents/Resources/" && cp $(ROM) "Pokemon Red.app/Contents/Resources/pokered.gbc"
	printf '#!/bin/sh\nd="$$HOME/Library/Application Support/PokemonRed"; mkdir -p "$$d"; cd "$$d"\nexec "$$(dirname "$$0")/../Resources/pokered-mac" "$$(dirname "$$0")/../Resources/pokered.gbc"\n' > "Pokemon Red.app/Contents/MacOS/run" && chmod +x "Pokemon Red.app/Contents/MacOS/run"
	printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>run</string><key>CFBundleName</key><string>Pokemon Red</string><key>CFBundleIdentifier</key><string>local.pokered</string><key>NSHighResolutionCapable</key><true/></dict></plist>' > "Pokemon Red.app/Contents/Info.plist"
