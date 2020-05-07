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

# this name must match the one in the autobuild.xml manifest since that is
# what 'autobuild package' looks for when it create a package
cef_stage_dir="${stage}/cef"

# The CEF branch number you want to build
# The relationship to Chrome and the versions of Chromium/CEF is complex and
# can make it difficult to find the branch number to use. This page can help:
# https://bitbucket.org/chromiumembedded/cef/wiki/BranchesAndBuilding.md#markdown-header-release-branches
# as can this one: https://www.chromium.org/developers/calendar
# E.G. Branch 4044 represents Chromium/CEF 81.x
cef_branch_number=4044

# The commit hash in the branch we want to
# check out from. One way to determine the hash to use is to look at the commits
# for the branch you are building - for example:
# https://bitbucket.org/chromiumembedded/cef/commits/branch/3987 and pick the
# commit hash the looks sensible - often something like "bumped CEF/Chromium
# to version x.xx.xx"
# E.G. for branch number 4044, e07275d is a valid commit hash
cef_commit_hash=e07275d



# deprecate:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# this name must match the one in the autobuild.xml manifest
cef_bundle_dir="${stage}/cef"
cef_bundle_file="cef_pkg"
# deprecate:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Turn on the proprietary codec support (the main reason for building from source vs using
# the Spotify open source builds here http://opensource.spotify.com/cefbuilds/index.html)
# Turning this on for builds will allow the resulting browser to render media URLs for
# MPEG4 and H264 directly along with providing transport controls. Examples of this are
# Twitch and YouTube live streams.
use_proprietary_codecs=1

# deprecate:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# URLs of the raw CEF bundle (without libcef_dll_wrapper) to download
cef_bundle_url_base="https://callum-linden.s3.amazonaws.com/cef/"
cef_bundle_url_windows32="${cef_bundle_url_base}cef_binary_81.2.17_windows32_media.tar.bz2"
cef_bundle_url_windows64="${cef_bundle_url_base}cef_binary_81.2.17_windows64_media.tar.bz2"
########cef_bundle_url_darwin64="${cef_bundle_url_base}cef_binary_81.2.15_macosx64_media.tar.bz2"
# deprecate:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# used in VERSION.txt but common to all bit-widths and platforms
build=${AUTOBUILD_BUILD_ID:=0}

case "$AUTOBUILD_PLATFORM" in
    windows*)
        # the directory where CEF is built. The documentation suggests that on
        # Windows at least, this shouldn't be in a subdirectory since the
        # complex build process generates enormous path names. This means we
        # have a different location per build platform type
# TODO: this likely still has to live in the root dir
# TODO: we should delete it on startup - it's huge - 120GB - and consumes most of the build host disk space
        cef_build_dir="${stage}/cef_build"
        cef_build_dir="/cef/$cef_branch_number"_"$AUTOBUILD_ADDRSIZE"

        # base directory structure
        mkdir -p "$cef_build_dir/code"
        mkdir -p "$cef_build_dir/code/automate"
        mkdir -p "$cef_build_dir/code/chromium_git"

        # Clone the GIT repo with the Chromium/CEF build tools
        cd "$cef_build_dir/code"
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

        # Update the CEF build tools 
        cd "$cef_build_dir/code/depot_tools"
        chmod u+x update_depot_tools.bat 
        ./update_depot_tools.bat

        cd "$cef_build_dir/code"

        export PATH="$(cygpath --unix "$cef_build_dir/code/depot_tools")":$PATH

        tmp_cef=tmp_cef_git
        git clone --depth 1 https://bitbucket.org/chromiumembedded/cef "$tmp_cef"
        cp "$tmp_cef/tools/automate/automate-git.py" "$cef_build_dir/code/automate/automate-git.py"
        rm -rf "$tmp_cef"

        cd "$cef_build_dir/code/chromium_git"

        export GN_ARGUMENTS="--ide=vs2017 --sln=cef --filters=//cef/*"
        export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome"
        export CEF_ARCHIVE_FORMAT=tar.bz2

        cef_distrib_subdir="cef_binary_windows"

        python ../automate/automate-git.py \
            --download-dir=$cef_build_dir/code/chromium_git \
            --depot-tools-dir=$cef_build_dir/code/depot_tools \
            --no-build \
            --branch=$cef_branch_number \
            --checkout=$cef_commit_hash \
            --distrib-subdir=$cef_distrib_subdir \
            --client-distrib \
            --force-clean \
            --x64-build

        # copy over the bits of the build we need to package
        cp -R "$cef_build_dir/code/chromium_git/chromium/src/cef/binary_distrib/$cef_distrib_subdir/" "$cef_stage_dir/"

        # return to the directory above where we built CEF
        cd "${cef_stage_dir}"

        # Remove files from the raw CEF build that we do not use
        rm -rf "tests"
        rm "Debug/cef_sandbox.a"
        rm "Release/cef_sandbox.a"

        # licence file
        mkdir -p "${stage}/LICENSES"
        cp "${cef_stage_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # write version using original CEF package includes
        g++ \
            -I "$cef_stage_dir/include" \
            -I "$cef_stage_dir/" \
            -o "$stage/version" \
            "$top/version.cpp"
        "$stage/version" > "$stage/version.txt"


        # # work in our own folder to keep the CEF and the autobuild
        # # files from interfering with each other
        # mkdir -p "${cef_bundle_dir}"
        # cd "${cef_bundle_dir}"

        # # Download the raw CEF package - this will be be replaced
        # # by code to build Chromium and CEF from source
        # cef_bundle_url="cef_bundle_url_windows${AUTOBUILD_ADDRSIZE}"
        # curl "${!cef_bundle_url}" -o "${cef_bundle_file}.tar.bz2"

        # # Need a different way to swtich code paths based on if
        # # we are running locally because TeamCity also runs Cygwin
        # # so we cannot use the built in $OSTYPE - it's completely
        # # miserable to have to do this all over the place...
        # if [[ -z "$TEAMCITY_PROJECT_NAME" ]]; then
        #     # On my development machine 'tar xvjf cef_file.tar.bz' hangs
        #     # trying to decompress Debug/libcef.lib - workable solution
        #     # is to split the process into two stages
        #     bzip2 -dv "${cef_bundle_file}.tar.bz2"

        #     # (we do not know the name of the folder inside the package
        #     # that is version specifc to we invoke the option to
        #     # strip it off and use the parent folder to contain everything)
        #     tar xvfj "${cef_bundle_file}.tar" --strip-components=1
        # else
        #     # unsurprisingly the same code doesn't work in TeamCity and
        #     # it fails with a bzip2 error so we have to resort to two
        #     # a separate codepath for each.
        #     tar xvfj "${cef_bundle_file}.tar.bz2" --strip-components=1
        # # fi

        # # Remove files from the raw CEF build that we do not use
        # rm -rf "tests"
        # rm "Debug/cef_sandbox.lib"
        # rm "Release/cef_sandbox.lib"

        # # licence file
        # mkdir -p "${stage}/LICENSES"
        # cp "${cef_bundle_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # # populate version_file (after header files are extracted
        # # to a well specified place that version.cpp can access)
        # # /EHsc is for 'warning C4530: C++ exception handler used,
        # # but unwind semantics are not enabled. Specify /EHsc'
        # cl \
        #     /EHsc \
        #     /Fo"$(cygpath -w "$stage/version.obj")" \
        #     /Fe"$(cygpath -w "$stage/version.exe")" \
        #     /I "$(cygpath -w "$cef_bundle_dir/include/")"  \
        #     /I "$(cygpath -w "$cef_bundle_dir/")"  \
        #     /D "AUTOBUILD_BUILD=${build}" \
        #     "$(cygpath -w "$top/version.cpp")"
        # "$stage/version.exe" > "$stage/VERSION.txt"
        # rm "$stage"/version.{obj,exe}
    ;;

    darwin64)
        # the directory where CEF is built. The documentation suggests that on
        # Windows at least, this shouldn't be in a subdirectory since the
        # complex build process generates enormous path names. This means we
        # have a different location per build platform type
        cef_build_dir="${stage}/cef_build"

        # base directory structure
        mkdir -p "$cef_build_dir/code"
        mkdir -p "$cef_build_dir/code/automate"
        mkdir -p "$cef_build_dir/code/chromium_git"

        # Clone the GIT repo with the Chromium/CEF build tools
        cd "$cef_build_dir/code"
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

        # Grab the main build script (-k or --insecure to bypass curl failing on team city host)
        # Note: using curl here to grab the file directly fails in TeamCity so we must use git
        tmp_cef=tmp_cef_git
        git clone --depth 1 https://bitbucket.org/chromiumembedded/cef "$tmp_cef"
        cp "$tmp_cef/tools/automate/automate-git.py" "$cef_build_dir/code/automate/automate-git.py"
        rm -rf "$tmp_cef"

        # PATH needs to include the depot tools folder we cloned
        export PATH=$cef_build_dir/code/depot_tools:$PATH

        # Generally want media codecs enabled but switch them off above if that's not the case
        # Note: we use quotation marks around the GN_DEFINES variable otherwise the build scripts
        # ignore anything after the first space - maybe a bash limitation?
        if [ $use_proprietary_codecs = "1" ]; then
            export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome"
        else
            export GN_DEFINES="is_official_build=true"
        fi

        # create .tar.bz2 format package archives
        export CEF_ARCHIVE_FORMAT=tar.bz2

        # the location of the distributable files is based on the long, complex CEF/Chromium
        # version numbers and that makes it difficult to deduce and find so we invoke the
        # automate-git.py option to set the sub-dir ourselves
        cef_distrib_subdir="cef_binary_macosx"

        # The main build script that does everything and based on command line parameter
        # (--client-distrib) also generates the distributable packages just like we used
        # to take from Spotify. Note too that unlike the Windows version, we always invoke
        # the 64bit command line parameter. Moreover, note that we never invoke the option
        # to turn off debug builds since doing so produces a build result that is not
        # compatible with autobuild and packages that consume it downstream.
        cd "$cef_build_dir/code/chromium_git"
        python ../automate/automate-git.py \
            --download-dir="$cef_build_dir/code/chromium_git" \
            --depot-tools-dir="$cef_build_dir/code/depot_tools" \
            --branch="$cef_branch_number" \
            --checkout="$cef_commit_hash" \
            --client-distrib \
            --x64-build \
            --distrib-subdir="$cef_distrib_subdir"

        # copy over the bits of the build we need to package
        cp -R "$cef_build_dir/code/chromium_git/chromium/src/cef/binary_distrib/$cef_distrib_subdir/" "$cef_stage_dir/"

        # return to the directory above where we built CEF
        cd "${cef_stage_dir}"

        # Remove files from the raw CEF build that we do not use
        rm -rf "tests"
        rm "Debug/cef_sandbox.a"
        rm "Release/cef_sandbox.a"

        # licence file
        mkdir -p "${stage}/LICENSES"
        cp "${cef_stage_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # write version using original CEF package includes
        g++ \
            -I "$cef_stage_dir/include" \
            -I "$cef_stage_dir/" \
            -o "$stage/version" \
            "$top/version.cpp"
        "$stage/version" > "$stage/version.txt"
    ;;

    linux*)
        echo "This project is not currently supported for $AUTOBUILD_PLATFORM" 1>&2 ; exit 1
    ;;
esac
