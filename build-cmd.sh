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
#cef_commit_hash=e07275d
cef_commit_hash=b9282cc

# Turn on the proprietary codec support (the main reason for building from source vs using
# the Spotify open source builds here http://opensource.spotify.com/cefbuilds/index.html)
# Turning this on for builds will allow the resulting browser to render media URLs for
# MPEG4 and H264 directly along with providing transport controls. Examples of this are
# Twitch and YouTube live streams.
use_proprietary_codecs=1

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# used in VERSION.txt but common to all bit-widths and platforms
build=${AUTOBUILD_BUILD_ID:=0}

case "$AUTOBUILD_PLATFORM" in
    windows*)
        load_vsvars
        # This is a windows path to the directory where Chromium/CEF will be built. The
        # official build process has some rules about this name - the most important of which
        # is that it cannot have spaces and must be "less than 35 chars" - using a sub-directory
        # of the $stage directory like we usually do with autobuild does not work - a typical 
        # TeamCity path that would be used is D:\work\ac945f566d69d0ee\latest\stage\cef3809_64\ 
        # and parts of the Chromium build scripts fail with "Filename too long". Moreover, we place
        # the builds in a single cef folder in the root since the branch number will change overtime and the
        # TeamCity task to clean up that folder after a build does not know the branch number. This
        # way the TeamCity cleanup task can delete the whole \cef folder.
        cef_build_dir="\\cef\\$cef_branch_number"_"$AUTOBUILD_ADDRSIZE"

        # The location of the distributable files is based on the version but that makes it
        # difficult to find so we set the sub-dir directly and pass to automate-git.py
        # in the batch file
        cef_distrib_subdir="cef_binary_windows$AUTOBUILD_ADDRSIZE"

        # mysteriously, builds in TeamCity started failing to execute the main batch file
        # in the following line because "Permission denied" - investigating why and am
        # going to try explicitly setting the execute permissions using Cygwin chmod
        chmod a+x "$top/tools/build.bat"

        # This invokes the batch file that builds Chromium/CEF. Replacing batch file commands
        # with bash equivalents and moving the code into this file did not work - the Chromium
        # build scripts are much too complex to debug or change - plus the batch file is
        # useful by itself to make builds without using autobuild
        $top/tools/build.bat \
                    $cef_build_dir \
                    $AUTOBUILD_ADDRSIZE \
                    $use_proprietary_codecs \
                    $cef_branch_number \
                    $cef_commit_hash \
                    $cef_distrib_subdir

        # copy over the bits of the build we need to package
        cp -R "$cef_build_dir/code/chromium_git/chromium/src/cef/binary_distrib/$cef_distrib_subdir/" "$cef_stage_dir/"

        # return to the directory above where we built CEF
        cd "${cef_stage_dir}"

        # Remove files from the raw CEF build that we do not use
        rm -rf "tests"
        rm "Debug/cef_sandbox.lib"
        rm "Release/cef_sandbox.lib"

        # licence file
        mkdir -p "${stage}/LICENSES"
        cp "${cef_stage_dir}/LICENSE.txt" "$stage/LICENSES/cef.txt"

        # populate version_file (after header files are extracted
        # to a well specified place that version.cpp can access)
        # /EHsc is for 'warning C4530: C++ exception handler used,
        # but unwind semantics are not enabled. Specify /EHsc'
        cl \
            /EHsc \
            /Fo"$(cygpath -w "$stage/version.obj")" \
            /Fe"$(cygpath -w "$stage/version.exe")" \
            /I "$(cygpath -w "$cef_stage_dir/include/")" \
            /I "$(cygpath -w "$cef_stage_dir/")" \
            "$(cygpath -w "$top/version.cpp")"
        "$stage/version.exe" > "$stage/VERSION.txt"
        rm "$stage"/version.{obj,exe}
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

        # Clone the Git repo with the Chromium/CEF build tools
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
