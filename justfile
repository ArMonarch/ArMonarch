uname := "ArMonarch <praffulthapa12@gmail.com>"
name := "armonarch"
src := "src"

# build on file change
watch:
  watchexec --exts odin,glsl -- just build

# start an server with python
serve: build-debug
  python -m http.server 4000

# build debug binary (no optimization)
build-debug:
  [ -d target/debug ] || mkdir -p target/debug
  odin build {{src}} -target:js_wasm32 -out:target/debug/{{name}} -o:none -debug

# build minimal binary (minimal optimization)
build-minimal:
  [ -d target/minimal ] || mkdir -p target/minimal
  odin build {{src}} -target:js_wasm32 -out:target/minimal/{{name}} -o:minimal

# build size binary (size optimization)
build-size:
  [ -d target/size ] || mkdir -p target/size
  odin build {{src}} -target:js_wasm32 -out:target/size/{{name}} -o:size

# build speed binary (speed optimization)
build-speed:
  [ -d target/speed ] || mkdir -p target/speed
  odin build {{src}} -target:js_wasm32 -out:target/speed/{{name}} -o:speed

# build aggressive binary (aggressive optimization)
build-aggressive:
  [ -d target/aggressive ] || mkdir -p target/aggressive
  odin build {{src}} -target:js_wasm32 -out:target/aggressive/{{name}} -o:aggressive

alias build := build-debug
