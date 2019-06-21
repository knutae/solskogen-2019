
CFLAGS = -fomit-frame-pointer -fno-stack-protector -Wall -Werror -Os
CFLAGS += $(shell pkg-config --cflags gtk+-3.0)

LIBS = -lGL
LIBS += -lgtk-3 -lgdk-3 -lgobject-2.0

XZ = xz -c -9e --format=lzma --lzma1=preset=9,lc=0,lp=0,pb=0

EXE = bin/solskogen-4k

all: $(EXE)

run: $(EXE)
	./$(EXE)

clean:
	rm -rf bin/ obj/ gen/

gen/shaders.h: fshader.glsl
	@mkdir -p gen
	TERM=xterm mono ../Shader_Minifier/shader_minifier.exe --preserve-externals $^ -o $@

obj/%.o: %.c gen/shaders.h
	@mkdir -p obj
	$(CC) -c $(CFLAGS) -o $@ $<

bin/%: obj/%.o
	@mkdir -p bin
	$(CC) -o $@ $^ $(LIBS)
	../ELFkickers/bin/sstrip $@

%.xz: %
	cat $^ | $(XZ) > $@

%-4k: uncompress-header %.xz
	cat $^ > $@
	chmod a+x $@
	@stat --printf="$@: %s bytes\n" $@
