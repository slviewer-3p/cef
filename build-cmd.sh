#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x

# make errors fatal
set -e

# bleat on references to undefined shell variables
set -u

# Check autobuild is around or fail
if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi
if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# URLs of the raw CEF bundle (without libcef_dll_wrapper) to download
CEF_BUNDLE_URL_WINDOWS32="https://callum-linden.s3.amazonaws.com/cef/cef_binary_81.2.17_windows32_media.tar.bz2"
CEF_BUNDLE_URL_WINDOWS64="https://callum-linden.s3.amazonaws.com/cef/cef_binary_81.2.17_windows64_media.tar.bz2"
CEF_BUNDLE_URL_DARWIN64="https://callum-linden.s3.amazonaws.com/cef/cef_binary_81.2.15_macosx64_media.tar.bz2"

# file where the CEF bundle will be downloaded to before unpacking etc.
CEF_BUNDLE_DOWNLOAD_FILE_WINDOWS="${top}/stage/windows${AUTOBUILD_ADDRSIZE}.bz2"
CEF_BUNDLE_DOWNLOAD_FILE_DARWIN64="${top}/stage/darwin64.bz2"

# directories where the downloaded, unpacked, modified and ready to build CEF
# bundle will end up and where it will be built by Cmake
CEF_BUNDLE_SRC_DIR_WINDOWS="${top}/stage/windows${AUTOBUILD_ADDRSIZE}"
CEF_BUNDLE_SRC_DIR_DARWIN64="${top}/stage/darwin64"

# used in VERSION.txt but common to all bit-widths and platforms
build=${AUTOBUILD_BUILD_ID:=0}

case "$AUTOBUILD_PLATFORM" in
    windows*)
        # download bundle
        CEF_BUNDLE_URL="CEF_BUNDLE_URL_WINDOWS${AUTOBUILD_ADDRSIZE}"

        curl "${!CEF_BUNDLE_URL}" -o "${CEF_BUNDLE_DOWNLOAD_FILE_WINDOWS}"

        # Create directory for it and untar, stripping off the complex CEF name
        mkdir -p "${CEF_BUNDLE_SRC_DIR_WINDOWS}"
        tar xvfj "${CEF_BUNDLE_DOWNLOAD_FILE_WINDOWS}" -C "${CEF_BUNDLE_SRC_DIR_WINDOWS}" --strip-components=1

        # create solution file cef.sln in build folder
        cd "${CEF_BUNDLE_SRC_DIR_WINDOWS}"
        rm -rf build
        mkdir -p build
        cd build
        cmake -G "$AUTOBUILD_WIN_CMAKE_GEN"  -DCEF_RUNTIME_LIBRARY_FLAG=/MD ..

        # build release version of wrapper only
        build_sln cef.sln "Debug|$AUTOBUILD_WIN_VSPLATFORM" "libcef_dll_wrapper"
        build_sln cef.sln "Release|$AUTOBUILD_WIN_VSPLATFORM" "libcef_dll_wrapper"

        # create folders to stage files in
        mkdir -p "$stage/bin/debug"
        mkdir -p "$stage/bin/release"
        mkdir -p "$stage/include/cef/include"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"
        mkdir -p "$stage/resources"
        mkdir -p "$stage/LICENSES"

        # binary files
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/chrome_elf.dll" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/d3dcompiler_47.dll" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/libcef.dll" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/libEGL.dll" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/libGLESv2.dll" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/snapshot_blob.bin" "$stage/bin/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/v8_context_snapshot.bin" "$stage/bin/debug/"

        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/chrome_elf.dll" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/d3dcompiler_47.dll" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/libcef.dll" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/libEGL.dll" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/libGLESv2.dll" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/snapshot_blob.bin" "$stage/bin/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/v8_context_snapshot.bin" "$stage/bin/release/"

        # include files
        cp -r "${CEF_BUNDLE_SRC_DIR_WINDOWS}/include/." "$stage/include/cef/include/"

        # resource files
        cp -r "${CEF_BUNDLE_SRC_DIR_WINDOWS}/Resources/" "$stage/"

        # library files
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/debug/libcef.lib" "$stage/lib/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/build/libcef_dll_wrapper/debug/libcef_dll_wrapper.lib" "$stage/lib/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/release/libcef.lib" "$stage/lib/release/"
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/build/libcef_dll_wrapper/Release/libcef_dll_wrapper.lib" "$stage/lib/release/"

        # license file
        cp "${CEF_BUNDLE_SRC_DIR_WINDOWS}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # populate version_file (after header files are copied to a well specified place that version.cpp can access)
        cl \
            /Fo"$(cygpath -w "$stage/version.obj")" \
            /Fe"$(cygpath -w "$stage/version.exe")" \
            /I "$(cygpath -w "$stage/include/cef/include")"  \
            /I "$(cygpath -w "$stage/include/cef")"  \
            /D "AUTOBUILD_BUILD=${build}" \
            "$(cygpath -w "$top/version.cpp")"
        "$stage/version.exe" > "$stage/version.txt"
        rm "$stage"/version.{obj,exe}
    ;;

    darwin64)
        # download bundle
        CEF_BUNDLE_URL="CEF_BUNDLE_URL_DARWIN64"
        curl "${!CEF_BUNDLE_URL}" -o "${CEF_BUNDLE_DOWNLOAD_FILE_DARWIN64}"

        # Create directory for it and untar, stripping off the complex CEF name
        mkdir -p "${CEF_BUNDLE_SRC_DIR_DARWIN64}"
        tar xvfj "${CEF_BUNDLE_DOWNLOAD_FILE_DARWIN64}" -C "${CEF_BUNDLE_SRC_DIR_DARWIN64}" --strip-components=1

        BUILD_FOLDER="build"
        cd "${CEF_BUNDLE_SRC_DIR_DARWIN64}"
        rm -rf "${BUILD_FOLDER}"
        mkdir -p "${BUILD_FOLDER}"
        cd "${BUILD_FOLDER}"

        cmake -G "Xcode" -DPROJECT_ARCH="x86_64" ..

        xcodebuild -project cef.xcodeproj -target libcef_dll_wrapper -configuration Release
        xcodebuild -project cef.xcodeproj -target libcef_dll_wrapper -configuration Debug

        # write version using original CEF package includes
        g++ \
            -I "$CEF_BUNDLE_SRC_DIR_DARWIN64/include" \
            -I "$CEF_BUNDLE_SRC_DIR_DARWIN64/" \
            -o "$stage/version" \
            "$top/version.cpp"
        "$stage/version" > "$stage/version.txt"

        # create folders to stage files in
        mkdir -p "$stage/bin/debug"
        mkdir -p "$stage/bin/release"
        mkdir -p "$stage/include/cef/include"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"
        mkdir -p "$stage/LICENSES"

        # include files
        cp -r "${CEF_BUNDLE_SRC_DIR_DARWIN64}/include/." "$stage/include/cef/include/"

        # library file
        cp "${CEF_BUNDLE_SRC_DIR_DARWIN64}/${BUILD_FOLDER}/libcef_dll_wrapper/Debug/libcef_dll_wrapper.a" "$stage/lib/debug/"
        cp "${CEF_BUNDLE_SRC_DIR_DARWIN64}/${BUILD_FOLDER}/libcef_dll_wrapper/Release/libcef_dll_wrapper.a" "$stage/lib/release/"

        # framework
        cp -r "${CEF_BUNDLE_SRC_DIR_DARWIN64}/Debug/Chromium Embedded Framework.framework" "$stage/bin/debug/"
        cp -r "${CEF_BUNDLE_SRC_DIR_DARWIN64}/Release/Chromium Embedded Framework.framework" "$stage/bin/release/"

        # include files
        cp -r "${CEF_BUNDLE_SRC_DIR_DARWIN64}/include/." "$stage/include/cef/include/"

        # license file
        cp "${CEF_BUNDLE_SRC_DIR_DARWIN64}/LICENSE.txt" "$stage/LICENSES/cef.txt"
    ;;

    linux*)
        echo "This project is not currently supported for $AUTOBUILD_PLATFORM" 1>&2 ; exit 1
    ;;
esac
