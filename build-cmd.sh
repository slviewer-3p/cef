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
stage="${top}/stage"

# this name must match the one in the autobuild.xml manifest
cef_bundle_dir="${stage}/cef"
cef_bundle_file="cef_pkg"

# URLs of the raw CEF bundle (without libcef_dll_wrapper) to download
cef_bundle_url_base="https://callum-linden.s3.amazonaws.com/cef/"
cef_bundle_url_windows32="${cef_bundle_url_base}cef_binary_81.2.17_windows32_media.tar.bz2"
cef_bundle_url_windows64="${cef_bundle_url_base}cef_binary_81.2.17_windows64_media.tar.bz2"
cef_bundle_url_darwin64="${cef_bundle_url_base}cef_binary_81.2.15_macosx64_media.tar.bz2"

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# used in VERSION.txt but common to all bit-widths and platforms
build=${AUTOBUILD_BUILD_ID:=0}

case "$AUTOBUILD_PLATFORM" in
    windows*)
        # work in our own folder to keep the CEF and the autobuild
        # files from interfering with each other
        mkdir -p "${cef_bundle_dir}"
        cd "${cef_bundle_dir}"

        # Download the raw CEF package - this will be be replaced
        # by code to build Chromium and CEF from source
        cef_bundle_url="cef_bundle_url_windows${AUTOBUILD_ADDRSIZE}"
        curl "${!cef_bundle_url}" > "${cef_bundle_file}.tar.bz2"

        # On my development machine 'tar xvjf cef_file.tar.bz' hangs
        # trying to decompress Debug/libcef.lib - workable solution 
        # is to split the process into two stages
        bzip2 -dv "${cef_bundle_file}.tar.bz2"
        
        # (we do not know the name of the folder inside the package 
        # that is version specifc to we invoke the option to 
        # strip it off and use the parent folder to contain everything)
        tar xvfj "${cef_bundle_file}.tar" --strip-components=1

        # Remove files from the raw CEF build that we do not use
        rm -rf "tests"
        rm "Debug/cef_sandbox.lib"
        rm "Release/cef_sandbox.lib"

        # licence file
        mkdir -p "${stage}/LICENSES"
        cp "${cef_bundle_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # populate version_file (after header files are extracted 
        # to a well specified place that version.cpp can access)
        cl \
            /Fo"$(cygpath -w "$stage/version.obj")" \
            /Fe"$(cygpath -w "$stage/version.exe")" \
            /I "$(cygpath -w "$cef_bundle_dir/include/")"  \
            /I "$(cygpath -w "$cef_bundle_dir/")"  \
            /D "AUTOBUILD_BUILD=${build}" \
            "$(cygpath -w "$top/version.cpp")"
        "$stage/version.exe" > "$stage/VERSION.txt"
        rm "$stage"/version.{obj,exe}
    ;;

    darwin64)
        # work in our own folder to keep the CEF and the autobuild
        # files from interfering with each other
        mkdir -p "${cef_bundle_dir}"
        cd "${cef_bundle_dir}"

        # Download the raw CEF package - this will be be replaced
        # by code to build Chromium and CEF from source
        cef_bundle_url="cef_bundle_url_darwin64"
        curl "${!cef_bundle_url}" > "${cef_bundle_file}.tar.bz2"

        # extract files into the container folder
        # (we do not know the name of the folder inside the package 
        # that is version specifc to we invoke the option to 
        # strip it off and use the parent folder to contain everything)
        tar xvfj "${cef_bundle_file}.tar.bz2" --strip-components=1

        # Remove files from the raw CEF build that we do not use
        rm -rf "tests"
        rm "Debug/cef_sandbox.a"
        rm "Release/cef_sandbox.a"

        # licence file
        mkdir -p "${stage}/LICENSES"
        cp "${cef_bundle_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # write version using original CEF package includes
        g++ \
            -I "$cef_bundle_dir/include" \
            -I "$cef_bundle_dir/" \
            -o "$stage/version" \
            "$top/version.cpp"
        "$stage/version" > "$stage/version.txt"
    ;;

    linux*)
        echo "This project is not currently supported for $AUTOBUILD_PLATFORM" 1>&2 ; exit 1
    ;;
esac
