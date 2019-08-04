#!/bin/sh

# Config
DEFAULT_DEST="win32/reprobuild"  # relative to top source dir
TMP_DIR="_tmp"  # dir for intermediate files inside each output dir

# Builds one tcc which targets windows
# args: TARGET_DIR, CC, {I386|X86_64}, [TCC_FOR_LIBS]
# Doesn't touch anything outside of $TARGET_DIR - which must not exist on entry.
# libtcc1.a objects are compiled and linked using either TCC_FOR_LIBS, if
# provided, or otherwise using the newly built tcc - the latter requires that
# CC must be host-native (bootstrap mode and unknown host/CC).
build_one() {
  local TARGET_DIR="$1"; local CC="$2"; local CPU="$3"; local TCC4LIBS="$4"
  local BOOTSTRAP=; [ -z "$4" ] && BOOTSTRAP=1

  $run_dbg mkdir -p "$TARGET_DIR" || return 1
  echo "Creating package at '<src-dir>/$TARGET_DIR'"

  # Create the dist except the binaries (tcc, libtcc1.a)
  $run_dbg mkdir "$TARGET_DIR/lib"
  $run_dbg mkdir "$TARGET_DIR/include"
  $run_dbg cp    include/*         "$TARGET_DIR/include/"
  $run_dbg cp -r win32/include/*   "$TARGET_DIR/include/"
  $run_dbg cp    tcclib.h          "$TARGET_DIR/include/"
  $run_dbg cp    win32/lib/*.def   "$TARGET_DIR/lib/"

  # When tcc is built as windows binary, CONFIG_TCCDIR is ignored (the runtime
  # exe dir is used instead). But the bootstrap tcc's do need it on non-windows.
  # If in the future it's not ignored for windows, the verification will fail
  # because it uses a different dir, and we'd need to modify this script.
  echo "#define TCC_VERSION \"$(cat VERSION)\"" > "$TARGET_DIR/config.h"
  echo "#define CONFIG_TCCDIR \"$TARGET_DIR\"" >> "$TARGET_DIR/config.h"

  # Compile the binaries. We're using ONE_SOURCE since it's simpler to build - no shared libtcc.
  local CFLAGS="-Wall"
  local PLAT_TARGET="-DTCC_TARGET_PE -DTCC_TARGET_${CPU}"
  local TCC_FLAGS="-I$TARGET_DIR -DONE_SOURCE"  # $TARGET_DIR should be quoted but tcc does not like it quoted

  # Use the provided $CC to create tcc.exe . Despite the exe suffix,
  # depending on $CC and the host, tcc.exe might not be windows executable.
  $run_dbg "$CC" $CFLAGS $PLAT_TARGET $TCC_FLAGS -o "$TARGET_DIR/tcc.exe" tcc.c || return 1

  # ms compiler leaves .obj
  rm *.obj 2> /dev/null

  # Our tcc can now compile to object files, and tcc -ar works, but we still
  # need libtcc1.a to make tcc fully functional for linking executables.
  [ -n "$BOOTSTRAP" ] && TCC4LIBS="$TARGET_DIR/tcc.exe"

  local LD=lib; local WLD=win32/lib
  local LIBTCC1_SRCS="$LD/libtcc1.c $WLD/chkstk.S $WLD/crt1.c $WLD/wincrt1.c $WLD/dllcrt1.c $WLD/dllmain.c $WLD/crt1w.c $WLD/wincrt1w.c"
  [ "$CPU" = "I386" ] &&
    LIBTCC1_SRCS="$LIBTCC1_SRCS $LD/alloca86.S    $LD/alloca86-bt.S" ||
    LIBTCC1_SRCS="$LIBTCC1_SRCS $LD/alloca86_64.S $LD/alloca86_64-bt.S"

  make_libtcc1() {  # args: libtcc1.a source files. Creates .o files at target.
    local objs; local o;
    for f in "$@"; do
      o="$TARGET_DIR/$(basename "$f.o")"
      $run_dbg "$TCC4LIBS" $CFLAGS $PLAT_TARGET -o "$o" -c "$f" || return 1
      objs="$objs $o"  # we'd like to quote $o, but tiny_libmaker doesn't like it
    done

    $run_dbg "$TCC4LIBS" -ar rcs "$TARGET_DIR/lib/libtcc1.a" $objs || return 1
  }

  make_libtcc1 $LIBTCC1_SRCS || return 1

  # build dummy libm (an empty string also works, but just looks weird)
  echo "void _tcc_dummy_libm(){}" | $run_dbg "$TCC4LIBS" -o "$TARGET_DIR/libm.o" -c - || return 1
  $run_dbg "$TCC4LIBS" -ar rcs "$TARGET_DIR/lib/libm.a" "$TARGET_DIR/libm.o" || return 1

  # remove temps
  [ -n "$TCCREPRO_KEEPTMP" ] || (cd "$TARGET_DIR" && rm config.h *.o)
}

# args: target dir, initial $cc to create bootstraps, or tcc32 and tcc64 dirs as bootstraps
# Expects to be already at $TOP_SRCDIR and that target dir doesn't exist
build_dists() {
  local TARGET_DIR="$1"; local BOOT=; local BOOT32=; local BOOT64=

  if [ -n "$3" ]; then  # use the provided bootstrap tcc's
    BOOT32="$2"; BOOT64="$3"

  else  # Build temp host-native [cross] tcc targeting win32/64 as bootstraps
    local CC="$2"; BOOT="$TARGET_DIR/_boot"
    if "$CC" -v 2> /dev/null | grep -iq "tcc version 0.9.26 (i386 win"; then
        # not cross platform, only needed with tcc 0.9.26 official win32 release
        echo "Detected old tcc 0.9.26. Using extra boot step ..."
        build_one "$BOOT/with-0.9.26" "$CC" I386 2> /dev/null; echo ''
        CC="$BOOT/with-0.9.26/tcc.exe"
    fi
    echo "Building bootstrap tcc's..."
    build_one "$BOOT/win32" "$CC" I386   &&
    build_one "$BOOT/win64" "$CC" X86_64 ||
      return 1
    BOOT32="$BOOT/win32"; BOOT64="$BOOT/win64"; echo ''
  fi

  echo "Building native Windows tcc distributions..."
  local TCC32="$BOOT32/tcc.exe"
  local TCC64="$BOOT64/tcc.exe"

  # Build the 4 distributions: native 32 and 64, and cross 32->64 and 64->32
  build_one "$TARGET_DIR/tcc32"  "$TCC32" I386   "$TCC32" &&
  build_one "$TARGET_DIR/tcc64"  "$TCC64" X86_64 "$TCC64" &&
  build_one "$TARGET_DIR/xtcc64" "$TCC32" X86_64 "$TCC64" &&
  build_one "$TARGET_DIR/xtcc32" "$TCC64" I386   "$TCC32" ||
    return 1

  [ -z "$TCCREPRO_KEEPTMP" ] && [ -n "$BOOT" ] && rm -rf "$BOOT"

  echo "Done OK at '$(real_dir "$TARGET_DIR")'"
  [ -n "$TCCREPRO_KEEPTMP" ] && echo "Warning: signature includes temp and non-deterministic host files."
  echo "Signature: $(signature_dir "$TARGET_DIR")";
}

# uses the output tcc's to rebuild the dist and compare the results
# args: target dir, mode ("32" -> host can run only 32, otherwise can run 32 and 64)
verify_dist() {
  local DIST="$1"; local MODE="$2"
  local expected="$(signature_dir "$DIST")"

  echo ''; echo "Verifying reproducibility with the resulting 32 bit binaries..."
  build_dists "$DIST/verify_32" "$DIST/tcc32" "$DIST/xtcc64" &&
  [ "$expected" = "$(signature_dir "$DIST/verify_32")" ]  ||
    (echo "--> Verification 32: ERROR"; false) || return 1
  echo "--> Verification 32: OK"
  [ -z "$TCCREPRO_KEEPTMP" ] && rm -rf "$DIST/verify_32"

  [ "$MODE" = "32" ] && return

  echo ''; echo "Verifying reproducibility with the resulting 64 bit binaries..."
  build_dists "$DIST/verify_64" "$DIST/xtcc32" "$DIST/tcc64" &&
  [ "$expected" = "$(signature_dir "$DIST/verify_64")" ]  ||
    (echo "--> Verification 64: ERROR"; false) || return 1
  echo "--> Verification 64: OK"
  [ -z "$TCCREPRO_KEEPTMP" ] && rm -rf "$DIST/verify_64"
}


# args: target dist dir (with the 4 sub dists) and mode (32 or anything else for 32+64)
test_dist() {
    [ -e "$_TOP_SRCDIR/config.mak" ] &&
        echo "WARNING: overwriting $_TOP_SRCDIR/config.mak"
    echo ''
    local err32=; local err64=
    local tests="hello-exe hello-run asm-c-connect-test vla_test-run tests2-dir pp-dir"

    (
        $run_dbg cd "$_TOP_SRCDIR/tests" &&
        echo "#define TCC_VERSION \"$(cat ../VERSION)\"" > ../config.h &&

        printf "ARCH=i386\nTARGETOS=Windows\nCONFIG_WIN32=yes\nTOPSRC=\$(TOP)\n" > "../config.mak" &&
        $run_dbg make -k TCC="\$(TOP)/$1/tcc32/tcc.exe" clean $tests &&
        printf "\n--> tcc 32 tests: PASS\n\n" || err32=1
        [ -z "$err32" ] || printf "\n--> tcc 32 tests: see some failures above\n\n"

        [ "$2" = "32" ] && exit $([ -n "$err32" ] && echo 1 || echo 0)

        printf "ARCH=x86_64\nTARGETOS=Windows\nCONFIG_WIN32=yes\nTOPSRC=\$(TOP)\n" > "../config.mak" &&
        $run_dbg make -k TCC="\$(TOP)/$1/tcc64/tcc.exe" clean $tests &&
        printf "\n--> tcc 64 tests: PASS\n\n" || err64=1
        [ -z "$err64" ] || printf "\n--> tcc 64 tests: see some failures above\n\n"

        [ -z "$err32" ] && [ -z "$err64" ]

    ) && printf "%s\n" "  --> Overall tcc tests: PASS" ||
         printf "%s\n" "  --> Overall tcc tests: see some failures above"

    rm "$_TOP_SRCDIR/config.mak" "$_TOP_SRCDIR/config.h"
}

#  Utilities
signature_dir() {  # list all files recursively -> sort -> md5 of each -> md5
  local sum="$( (echo 1 | md5sum)>/dev/null 2>&1 && echo "md5sum" || echo "md5 -r")"  # bsd/osx: "md5 -r"
  (cd "$1" && find . -type f | LC_ALL=C sort | xargs $sum | tr -d '*' | tr -s ' ' | $sum | cut -f 1 -d ' ')
}

real_dir() { echo "$(cd "$1" && pwd)"; }  # mandatory arg: dir which must already exist

run_dbg=_run_dbg  # set to empty to completely bypasss run_dbg
_run_dbg() { [ -n "$TCCREPRO_V" ] && echo "$@"; "$@"; }  # echo if dbg, run args

maybe_relative() {  # arg: absolute/relative dir, output: relative to pwd or unmodified input
  local bn="$(basename "$(real_dir "$1")")"
  [ "$(pwd)/win32/$bn" = "$(real_dir "$1")" ] && echo "win32/$bn" || echo "$1"
}

has_cmd() { which "$1" 2>&1 > /dev/null; }

# main
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: [CC=<host-native-compiler>] $(basename "$0") [<target-dir>]"
  echo "Build tcc for windows, hopefully deterministically regardless of the OS/CC."
  echo "Requires a host-native compiler (possibly tcc, even 0.9.26), and a posix shell."
  echo "Builds windows-native tcc32/64, and cross 32-to-64, 64-to-32 (4 distributions)."
  echo "Environment variables for some extras:"
  echo " TCCREPRO_VERIFY: empty -> none. 32 -> test reproducible 32 bins, else also 64."
  echo " TCCREPRO_TEST: empty -> none. 32 -> test suit on tcc 32, else also tcc 64."
  echo " TCCREPRO_KEEPTMP: non-empty -> keep temporary build files (at the output dir)."
  echo " TCCREPRO_V: non-empty -> verbose output (not 100% reliable on windows)."
  echo " Note: TCCREPRO_VERIFY requires windows/wine, TCCREPRO_TEST also gnu make."

else
  [ -z "$1" ] && echo "(use -h for help)"

  if [ -z "$CC" ]; then
    if   has_cmd gcc; then CC=gcc
    elif has_cmd cc;  then CC=cc
    elif has_cmd cl;  then CC=cl
    elif has_cmd tcc; then CC=tcc
    fi

    [ -z "$CC" ] &&
      CC=gcc && echo "CC not set and not found. Trying CC='$CC'" ||
      echo "CC not set. Found and using CC=$CC ( $(which "$CC") )"
  else
    echo "CC: '$CC'"
  fi

  _TOP_SRCDIR="$(real_dir "$(dirname "$0")/..")"
  _TOP_SRCDIR="$(pwd)"
  if ([ -e "$_TOP_SRCDIR/config.h" ] || [ -e "$_TOP_SRCDIR/config.mak" ]) &&
     [ -z "$TCCREPRO_ALLOW_DIRTY" ]; then
    echo "Source tree seems dirty, which may interfere. Aborting."
    echo "  Force anyway with env TCCREPRO_ALLOW_DIRTY=1"
    echo "  or delete untracked files: git clean -xfd $_TOP_SRCDIR"
    echo "  In the future, consider out-of-tree builds (or in-tree build-dir)."
    exit 1
  fi
  [ -n "$1" ] && _TARGET_DIR="$1" || _TARGET_DIR="$_TOP_SRCDIR/$DEFAULT_DEST"
  if [ -e "$_TARGET_DIR" ]; then
    printf "Target dir must not exist. Aborting.\n  try: rm -rf $_TARGET_DIR\n"

  else
    mkdir -p "$_TARGET_DIR" &&
    _TARGET_DIR=$(real_dir "$_TARGET_DIR") &&
    printf "Target dir: $_TARGET_DIR\n"
    $run_dbg cd "$_TOP_SRCDIR" &&
    _TMP_TARGET="tmp_repro" && ( ! [ -e "$_TMP_TARGET" ] || rm -rf "$_TMP_TARGET" ) &&
    mkdir -p "$_TMP_TARGET" &&
    printf "Temp dir:   $(real_dir "$_TMP_TARGET")\n\n" &&
    build_dists "$_TMP_TARGET" "$CC" &&
    ( [ -z "$TCCREPRO_VERIFY" ] || verify_dist "$_TMP_TARGET" "$TCCREPRO_VERIFY" ) &&
    ( [ -z "$TCCREPRO_TEST" ] || test_dist "$_TMP_TARGET" "$TCCREPRO_TEST" ) &&
    mv $_TMP_TARGET/* "$_TARGET_DIR/" && rm -r $_TMP_TARGET
  fi
fi
