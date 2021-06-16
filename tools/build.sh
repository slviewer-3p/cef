#!/usr/bin/env bash

# extra tracing
exec 4>&1; export BASH_XTRACEFD=4; set -x

# check command line arguments
if [ $# != 3 ]
then
    {
        echo -e "\nUsage:"
        echo -e "    $0 <CEF branch number> <commit hash> <CEF build dir>"
    } 2> /dev/null
    exit 1
fi

# The first command line parameter is the CEF branch number you want to build
# The relationship to Chrome and the versions of Chromium/CEF is complex and
# can make it difficult to find the branch number to use. This page can help:
# https://bitbucket.org/chromiumembedded/cef/wiki/BranchesAndBuilding.md#markdown-header-release-branches
# as can this one: https://www.chromium.org/developers/calendar
# E.G. Branch 4472 represents Chromium/CEF 91.x
cef_branch_number=$1

# The second command line parameter is the commit hash in the branch we want to
# check out from. One way to determine the hash to use is to look at the commits
# for the branch you are building - for example:
# https://bitbucket.org/chromiumembedded/cef/commits/branch/3987 and pick the
# commit hash the looks sensible - often something like "bumped CEF/Chromium
# to version x.xx.xx"
# E.G. for branch number 4472, cf0c26a is a valid commit hash for Chromuim v91
cef_commit_hash=$2

# The third command line parameter is the directory you want to use to build
# Chromium and CEF. It must not exist already.
cef_build_dir=$3

# we stipulate that the parent build dir must be empty
if [ -d "$cef_build_dir" ];
then
    echo "Selected CEF build directory already exists - remove it first"
    exit 1
fi

# Turn on the proprietary codec support (the main reason for building from source vs using
# the Spotify open source builds here http://opensource.spotify.com/cefbuilds/index.html)
# Turning this on for builds will allow the resulting browser to render media URLs for
# MPEG4 and H264 directly along with providing transport controls. Examples of this are
# Twitch and YouTube live streams.
use_proprietary_codecs=1

# We build both debug and release configurations normally but turning debug builds off
# can significantly shorten the time to run a build - less than half usually.
make_debug_build=1

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

# Builds take forever and when developing, not building Debug can save more than 50%
# of the time when developing or testing builds
if [ "$make_debug_build" = "0" ]; then
    debug_build_flag="--no-debug-build"
else
    debug_build_flag=""
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
# the 64bit command line parameter.
cd "$cef_build_dir/code/chromium_git"
python ../automate/automate-git.py \
    --download-dir="$cef_build_dir/code/chromium_git" \
    --depot-tools-dir="$cef_build_dir/code/depot_tools" \
    --branch="$cef_branch_number" \
    --checkout="$cef_commit_hash" \
    --client-distrib \
    --x64-build \
    --distrib-subdir="$cef_distrib_subdir" \
    "$debug_build_flag"

echo "Build finished - look in $cef_build_dir/code/chromium_git/chromium/src/cef/binary_distrib/$cef_distrib_subdir for build products and $cef_build_dir/code/chromium_git/chromium/src/cef/binary_distrib/*.tar.bz2 for packages"
