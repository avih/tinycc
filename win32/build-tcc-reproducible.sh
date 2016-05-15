#!/bin/sh

TMP_SUFFIX="_tcc_reprobuild.tmp"
BOOTSTRAP_SUFFIX="_bootstrap.tmp"

is_dir_empty() {
  [ -z "$(ls -1qA "$1")" ]
}

# dir must already exist or be create-able
real_dir() {
  local NEEDS_RM=""
  if ! [ -e "$1" ]; then
    mkdir "$1" || return 1
    NEEDS_RM="yes"
  elif ! [ -d "$1" ]; then
    return 1
  fi
  echo "$(cd "$1" && pwd)"
  [ -z "$NEEDS_RM" ] || rmdir "$1"
}

# args: $CC, $TARGET_DIR (absolute). Expects to be already at $top_srcdir
# Doesn't touch anything outside of $TARGET_DIR - which must already exist.
# Does not clean $TARGET_DIR before build.
one_build() {
  # TODO: actually return error on failure
  local CC="$1"
  local TARGET_DIR="$2"

  echo "Creating package at '$TARGET_DIR'"

  cp -r win32/include     "$TARGET_DIR/include"
  cp    include/*         "$TARGET_DIR/include"
  mkdir "$TARGET_DIR/lib"
  cp    win32/lib/*.def   "$TARGET_DIR/lib"

  local BLD_DIR="$TARGET_DIR/$TMP_SUFFIX"
  mkdir "$BLD_DIR" &>/dev/null

  echo '
#ifndef CONFIG_TCCDIR
# define CONFIG_TCCDIR "."
#endif
#define GCC_MAJOR 0
#define GCC_MINOR 0
#define CONFIG_WIN32 1
#define TCC_VERSION "0.9.26"
' > "$BLD_DIR/config.h"

  local CFLAGS="-Wall"
  local PLAT_TARGET="-DTCC_TARGET_I386 -DTCC_TARGET_PE"
  #TCC_FLAGS="-I$BLD_DIR -DONE_SOURCE -DCONFIG_TCC_STATIC"
  local TCC_FLAGS="-I$BLD_DIR -DONE_SOURCE"  # $BLD_DIR should be quoted but tcc does not like it quoted

  # just shorter to use
  local TLM=win32/tools/tiny_libmaker.c
  local TID=win32/tools/tiny_impdef.c

  # use the external $cc to create initial tmp tcc and libmaker executables.
  # we leave the tmp tcc at the target dir since tcc uses it as "home" for includes
  $CC $CFLAGS $PLAT_TARGET $TCC_FLAGS tcc.c -o "$TARGET_DIR/tmp_tcc.exe"
  $CC $CFLAGS $PLAT_TARGET            $TLM  -o "$BLD_DIR/tmp_tiny_libmaker.exe"

  # ms compiler leaves .obj
  rm *.obj &> /dev/null


  # from now on, we're using only our tmp tcc/libmaker. tcc uses the includes which we copied earlier to TARGET_DIR
  # tmp libmaker is fully functional, but tmp tcc is missing libtcc1 - apparently can create objects but not exe
  CC="$TARGET_DIR/tmp_tcc.exe"
  AR="$BLD_DIR/tmp_tiny_libmaker.exe"

  LD=lib
  WLD=win32/lib

  $CC $CFLAGS $PLAT_TARGET -c $LD/libtcc1.c     -o "$BLD_DIR/libtcc1.o"
  $CC $CFLAGS $PLAT_TARGET -c $LD/alloca86.S    -o "$BLD_DIR/alloca86.o"
  $CC $CFLAGS $PLAT_TARGET -c $LD/alloca86-bt.S -o "$BLD_DIR/alloca86-bt.o"
  $CC $CFLAGS $PLAT_TARGET -c $LD/bcheck.c      -o "$BLD_DIR/bcheck.o"

  $CC $CFLAGS $PLAT_TARGET -c $WLD/chkstk.S     -o "$BLD_DIR/chkstk.o"
  $CC $CFLAGS $PLAT_TARGET -c $WLD/crt1.c       -o "$BLD_DIR/crt1.o"
  $CC $CFLAGS $PLAT_TARGET -c $WLD/wincrt1.c    -o "$BLD_DIR/wincrt1.o"
  $CC $CFLAGS $PLAT_TARGET -c $WLD/dllcrt1.c    -o "$BLD_DIR/dllcrt1.o"
  $CC $CFLAGS $PLAT_TARGET -c $WLD/dllmain.c    -o "$BLD_DIR/dllmain.o"

  # create libtcc1
  $AR rcs "$TARGET_DIR/lib/libtcc1.a" \
    "$BLD_DIR/libtcc1.o" "$BLD_DIR/alloca86.o" "$BLD_DIR/alloca86-bt.o" "$BLD_DIR/bcheck.o" \
    "$BLD_DIR/chkstk.o" "$BLD_DIR/crt1.o" "$BLD_DIR/wincrt1.o" "$BLD_DIR/dllcrt1.o" "$BLD_DIR/dllmain.o"

  # now with libtcc1 our tmp tcc is fully functional, re-build libmaker and tcc with our tcc
  $CC $CFLAGS $TCC_FLAGS $PLAT_TARGET tcc.c -o "$TARGET_DIR/tcc.exe"
  $CC $CFLAGS            $PLAT_TARGET $TLM  -o "$TARGET_DIR/tiny_libmaker.exe"
  $CC $CFLAGS            $PLAT_TARGET $TID  -o "$TARGET_DIR/tiny_impdef.exe"

  # build dummy libm (an empty string also works, but just looks weird)
  echo "void _tcc_dummy_libm(){}" | $CC -c - -o "$BLD_DIR/libm.o"
  $AR rcs "$TARGET_DIR/lib/libm.a" "$BLD_DIR/libm.o"

  mv "$TARGET_DIR"/tmp* "$BLD_DIR/"

  # remove out tmp objects. but for debugging leave it.
  #rm -rf $BLD_DIR

  return 0
}

# args: initial $cc, target dir (absolute). Expects to be already at $TOP_SRCDIR
full_build() {
  local CC="$1"
  local TARGET_DIR="$2"
  if ! [ -e "./tcc.c" ] || ! [ -e "./configure" ]; then
    echo "'$(pwd)' does not seem like tcc top source dir. Aborting"
    return 1
  fi

  # sanity before cleanup of target dir:
  # either target doesn't exist, or exists and (empty or has tmp build dir)
  if [ -e "$TARGET_DIR" ]; then
    if ! [ -d "$TARGET_DIR" ] || ! is_dir_empty "$TARGET_DIR" && ! [ -d "$TARGET_DIR/$TMP_SUFFIX" ]; then
      echo "'$TARGET_DIR' is a file, or does not look like target dir from earlier builds. Aborting"
      return 1
    fi

    echo "Removing '$TARGET_DIR'"
    rm -rf "$TARGET_DIR" || echo "Cannot remove '$TARGET_DIR'. Aborting." && return 1
  fi

  echo "Creating '$TARGET_DIR'"
  local BOOTSTRAP="$TARGET_DIR/$TMP_SUFFIX/$BOOTSTRAP_SUFFIX"
  mkdir -p "$BOOTSTRAP"
  one_build "$CC" "$BOOTSTRAP" && \
    one_build "$BOOTSTRAP/tcc.exe" "$TARGET_DIR" && \
    echo "Done OK at '$TARGET_DIR'" || echo "Oops. Something happened..."
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  echo "Usage: CC=<initial-compiler> $(basename "$0") [<target-dir>]"
  echo "Builds tcc for windows twice, second time using tcc from the first build - to"
  echo "hopefully end up with bit-identical dist package regardless of the initial"
  echo "compiler."
else
  _TOP_SRCDIR="$(real_dir "$(dirname "$0")")/.."
  ! [ -z "$1" ] && _TARGET_DIR="$(real_dir "$1")" || _TARGET_DIR="$(real_dir "$_TOP_SRCDIR/win32/dist-reproducible")"
  if pushd "$_TOP_SRCDIR" >/dev/null; then
    full_build  "$CC" "$_TARGET_DIR"
    popd >/dev/null
  else
    echo "Cannot cd to '$_TOP_SRCDIR'. Aborting."
  fi
fi
