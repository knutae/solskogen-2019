
CFLAGS = -fomit-frame-pointer -fno-stack-protector -Wall -Werror -Os
CFLAGS += $(shell pkg-config --cflags gtk+-3.0)

LIBS = -lGL
LIBS += -lgtk-3 -lgdk-3 -lgobject-2.0

XZ = xz -c -9e --format=lzma --lzma1=preset=9,lc=0,lp=0,pb=0

EXE = bin/solskogen-4k
DEBUG_EXE = bin/solskogen-debug

all: $(EXE)

run: $(EXE)
	./$(EXE)

debug: $(DEBUG_EXE)
	./$(DEBUG_EXE)

clean:
	rm -rf bin/ obj/ gen/

gen/shaders.h: fshader.glsl
	@mkdir -p gen
	TERM=xterm mono ../Shader_Minifier/shader_minifier.exe --preserve-externals $^ -o $@

gen/shaders-debug.h: fshader.glsl embed-shader.py
	@mkdir -p gen
	python3 embed-shader.py > $@

obj/%.o: %.c gen/shaders.h
	@mkdir -p obj
	$(CC) -c $(CFLAGS) -o $@ $<

obj/%-debug.o: %.c gen/shaders-debug.h
	@mkdir -p obj
	$(CC) -c $(CFLAGS) -DDEBUG -o $@ $<

bin/%: obj/%.o
	@mkdir -p bin
	$(CC) -o $@ $^ $(LIBS)
	../ELFkickers/bin/sstrip $@

bin/%-debug: obj/%-debug.o
	@mkdir -p bin
	$(CC) -o $@ $^ $(LIBS)

%.xz: %
	cat $^ | $(XZ) > $@

%-4k: uncompress-header %.xz
	cat $^ > $@
	chmod a+x $@
	@stat --printf="$@: %s bytes\n" $@
