#!/bin/sh

CODE=$1
if [ "$1" == "" ]; then
  CODE=package-w32
fi

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo Creating output at: $SCRIPTDIR/$CODE

pushd $SCRIPTDIR &> /dev/null
SRCDIR=..
TARGET_DIR=$CODE
BLD_DIR=$TARGET_DIR/_build.tmp

rm -rf $TARGET_DIR
mkdir  $TARGET_DIR
cp -r  $SRCDIR/win32/include   $TARGET_DIR/include
cp     $SRCDIR/include/*       $TARGET_DIR/include
mkdir  $TARGET_DIR/lib
cp     $SRCDIR/win32/lib/*.def $TARGET_DIR/lib

mkdir  $BLD_DIR
echo -e "\
#ifndef CONFIG_TCCDIR\n\
# define CONFIG_TCCDIR \".\"\n\
#endif\n\
#define GCC_MAJOR 0\n\
#define GCC_MINOR 0\n\
#define CONFIG_WIN32 1\n\
#define TCC_VERSION \"0.9.26\"\n\
" > $BLD_DIR/config.h

CFLAGS="-Wall"
PLAT_TARGET="-DTCC_TARGET_I386 -DTCC_TARGET_PE"
#TCC_FLAGS="-I$BLD_DIR -DONE_SOURCE -DCONFIG_TCC_STATIC"
TCC_FLAGS="-I$BLD_DIR -DONE_SOURCE"

# just shorter to use
TLM=win32/tools/tiny_libmaker.c
TID=win32/tools/tiny_impdef.c

# use the external $cc to create initial tmp tcc and libmaker executables.
# we leave the tmp tcc at the target dir since tcc uses it as "home" for includes
$CC $CFLAGS $PLAT_TARGET $TCC_FLAGS $SRCDIR/tcc.c -o $TARGET_DIR/tmp_tcc.exe
$CC $CFLAGS $PLAT_TARGET            $SRCDIR/$TLM  -o $BLD_DIR/tmp_tiny_libmaker.exe

# ms compiler leaves .obj
rm *.obj &> /dev/null

# from now on, we're using only our tmp tcc/libmaker. tcc uses the includes which we copied earlier to TARGET_DIR
# tmp libmaker is fully functional, but tmp tcc is missing libtcc1 - apparently can create objects but not exe
CC=$TARGET_DIR/tmp_tcc.exe
AR=$BLD_DIR/tmp_tiny_libmaker.exe

LD=$SRCDIR/lib
WLD=$SRCDIR/win32/lib

$CC $CFLAGS $PLAT_TARGET -c $LD/libtcc1.c     -o $BLD_DIR/libtcc1.o
$CC $CFLAGS $PLAT_TARGET -c $LD/alloca86.S    -o $BLD_DIR/alloca86.o
$CC $CFLAGS $PLAT_TARGET -c $LD/alloca86-bt.S -o $BLD_DIR/alloca86-bt.o
$CC $CFLAGS $PLAT_TARGET -c $LD/bcheck.c      -o $BLD_DIR/bcheck.o

$CC $CFLAGS $PLAT_TARGET -c $WLD/chkstk.S     -o $BLD_DIR/chkstk.o
$CC $CFLAGS $PLAT_TARGET -c $WLD/crt1.c       -o $BLD_DIR/crt1.o
$CC $CFLAGS $PLAT_TARGET -c $WLD/wincrt1.c    -o $BLD_DIR/wincrt1.o
$CC $CFLAGS $PLAT_TARGET -c $WLD/dllcrt1.c    -o $BLD_DIR/dllcrt1.o
$CC $CFLAGS $PLAT_TARGET -c $WLD/dllmain.c    -o $BLD_DIR/dllmain.o

# create libtcc1
$AR rcs $TARGET_DIR/lib/libtcc1.a $BLD_DIR/libtcc1.o $BLD_DIR/alloca86.o $BLD_DIR/alloca86-bt.o $BLD_DIR/bcheck.o $BLD_DIR/chkstk.o $BLD_DIR/crt1.o $BLD_DIR/wincrt1.o $BLD_DIR/dllcrt1.o $BLD_DIR/dllmain.o

# now with libtcc1 our tmp tcc is fully functional, re-build libmaker and tcc with our tcc
$CC $CFLAGS $TCC_FLAGS $PLAT_TARGET $SRCDIR/tcc.c -o $TARGET_DIR/tcc.exe
$CC $CFLAGS            $PLAT_TARGET $SRCDIR/$TLM  -o $TARGET_DIR/tiny_libmaker.exe
$CC $CFLAGS            $PLAT_TARGET $SRCDIR/$TID  -o $TARGET_DIR/tiny_impdef.exe

# build dummy libm (an empty string also works, but just looks weird)
echo "void _tcc_dummy_libm(){}" | $CC -c - -o $BLD_DIR/libm.o
$AR rcs $TARGET_DIR/lib/libm.a $BLD_DIR/libm.o

mv $TARGET_DIR/tmp* $BLD_DIR/

# remove out tmp objects. but for debugging leave it.
#rm -rf $BLD_DIR

popd &> /dev/null
