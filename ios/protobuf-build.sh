#!/bin/bash
#
#===============================================================================
# Filename:  protobuf-build.sh
# Author:    Viktor Pogrebniak
# Copyright: (c) 2016 Viktor Pogrebniak
# License:   BSD 3-clause license
#===============================================================================
#
# Builds a protobuf library for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using protobuf in Xcode
# less painful.
#
#===============================================================================

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=protobuf
VERSION_STRING=v3.0.0-beta-2
REPO_URL=https://github.com/google/protobuf

BUILD_DIR=$COMMON_BUILD_DIR/build/$LIB_NAME-$VERSION_STRING

# paths
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING
LOG_DIR=$BUILD_DIR/logs
PLATFORM_DIR=$BUILD_DIR/platform

CFLAGS="-O3 -pipe -fPIC -fcxx-exceptions"
CXXFLAGS="$CFLAGS -std=$CPPSTD -stdlib=$STDLIB $BITCODE"
LIBS="-lc++ -lc++abi"

PROTOC=$COMMON_BUILD_DIR/bin/protoc

function create_paths
{
    mkdir -p $LOG_DIR
}

function cleanup
{
	echo 'Cleaning everything after the build...'
	rm -rf $BUILD_DIR
	rm -rf $LOG_DIR
	done_section "cleanup"
}

function automake_run
{
	rm -rf $BUILD_DIR
	cp -r $GIT_REPO_DIR $BUILD_DIR
	create_paths
	cd $BUILD_DIR
	./autogen.sh
	cd $COMMON_BUILD_DIR
}

function build_protoc
{
	if [ -f $PROTOC ]; then
		return
	fi

	cd $BUILD_DIR
	LOG="$LOG_DIR/build-macos.log"
	[ -f Makefile ] && make distclean
	./configure --disable-shared --prefix=${PLATFORM_DIR}/x86_64-mac "CC=${CC}" "CFLAGS=${CFLAGS} -arch x86_64" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} -arch x86_64" "LDFLAGS=${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
		tail -n 100 "${LOG}"
		echo "Problem while building protoc - Please check ${LOG}"
		exit 1
	fi
	make install
    
	mkdir -p $COMMON_BUILD_DIR/bin
	cp -r $PLATFORM_DIR/x86_64-mac/bin/protoc $COMMON_BUILD_DIR/bin
	mkdir -p $COMMON_BUILD_DIR/include
	cp -r $PLATFORM_DIR/x86_64-mac/include/* $COMMON_BUILD_DIR/include
}

# example:
# build_inphone armv7|armv7s|arm64
function build_iphone
{
	local MIN_VERSION_FLAG="-miphoneos-version-min=${IOS_MIN_VERSION}"
	local ARCH_FLAGS="-arch $1 -isysroot ${IPHONEOS_SYSROOT} $MIN_VERSION_FLAG"
	cd $BUILD_DIR
	LOG="$LOG_DIR/build-$1.log"
	[ -f Makefile ] && make distclean
	HOST=$1
	if [ $1 == "arm64" ]; then
		HOST=arm
	else
		HOST=$1-apple-${ARCH_POSTFIX}
	fi
	./configure --build=x86_64-apple-${ARCH_POSTFIX} --host=$HOST --with-protoc=${PROTOC} --disable-shared --prefix=${PLATFORM_DIR}/$1 "CC=${CC}" "CFLAGS=${CFLAGS} ${ARCH_FLAGS}" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} ${ARCH_FLAGS}" LDFLAGS="-arch $1 $MIN_VERSION_FLAG ${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    make install
	done_section "building $1"
}

function build_simulator
{
	local MIN_VERSION_FLAG="-mios-simulator-version-min=${IOS_MIN_VERSION}"
	local ARCH_FLAGS="-arch $1 -isysroot ${IPHONESIMULATOR_SYSROOT} ${MIN_VERSION_FLAG}"
	cd $BUILD_DIR
	LOG="$LOG_DIR/build-$1.log"
	[ -f Makefile ] && make distclean
	./configure --build=x86_64-apple-${ARCH_POSTFIX} --host=$1-apple-${ARCH_POSTFIX} --with-protoc=${PROTOC} --disable-shared --prefix=${PLATFORM_DIR}/$1 "CC=${CC}" "CFLAGS=${CFLAGS} ${ARCH_FLAGS}" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} ${ARCH_FLAGS}" LDFLAGS="-arch $1 $MIN_VERSION_FLAG ${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    make install
	done_section "building simulator"
}

function package_libraries
{
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local TOOL_LIBS=('libprotobuf.a' 'libprotobuf-lite.a' 'libprotoc.a')
	local ALL_LIBS=""

	mkdir -p $COMMON_BUILD_DIR/lib/universal
	cd $PLATFORM_DIR
	for ll in ${TOOL_LIBS[@]}; do
		ALL_LIBS=""
		for a in ${ARCHS[@]}; do
			if [ -d $a ]; then
				mkdir -p $COMMON_BUILD_DIR/lib/$a
				cp $a/lib/$ll $COMMON_BUILD_DIR/lib/$a
				ALL_LIBS="$ALL_LIBS $a/lib/$ll"
			fi
		done
		lipo $ALL_LIBS -create -output $COMMON_BUILD_DIR/lib/universal/$ll
		lipo -info $COMMON_BUILD_DIR/lib/universal/$ll
	done
    done_section "packaging fat libs"
}

if [ -f $COMMON_BUILD_DIR/lib/universal/libprotobuf.a ]; then
	echo "Assuming $LIB_NAME exists"
	exit 0
fi

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Repository dir:     $GIT_REPO_DIR"
echo "Build dir:          $BUILD_DIR"
echo "iPhone SDK version: $IPHONE_SDKVERSION"
echo "XCode root:         $XCODE_ROOT"
echo "C compiler:         $CC"
echo "C++ compiler:       $CXX"
if [ -z ${BITCODE} ]; then
    echo "BITCODE EMBEDDED: NO $BITCODE"
else 
    echo "BITCODE EMBEDDED: YES with: $BITCODE"
fi

download_from_git $REPO_URL $GIT_REPO_DIR $VERSION_STRING
# invent_missing_headers
automake_run
build_protoc
build_iphone armv7
build_iphone armv7s
build_iphone arm64
build_simulator x86_64
package_libraries
cleanup
echo "Completed successfully"

