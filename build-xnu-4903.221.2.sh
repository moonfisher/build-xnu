#! /bin/bash
#
# build-xnu-4903.221.2.sh
# Initial script by Brandon Azad (https://gist.github.com/bazad/654959120a423b226dc564073b435453)
# Updated on 12/11/18 by matteyeux
# 
# A script showing how to build XNU version 4570.1.46 on MacOS High Sierra
# 10.13 with Xcode 9.
#
# Note: This process will OVERWRITE files in Xcode's MacOSX10.13.sdk. Make a
# backup of this directory first!
#

# Set the working directory.
WORKDIR="${WORKDIR:-build-xnu-4903.221.2}"

# Set a permissive umask just in case.
umask 022

# Print commands and exit on failure.
set -ex

# Get the SDK path and toolchain path.
SDKPATH="$(xcrun --sdk macosx --show-sdk-path)"
TOOLCHAINPATH="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
[ -d "${SDKPATH}" ] && [ -d "${TOOLCHAINPATH}" ]

# Create the working directory.
mkdir "${WORKDIR}"
cd "${WORKDIR}"

# Back up the SDK if that option is given.
if [ -n "${BACKUP_SDK}" ]; then
        sudo ditto "${SDKPATH}" "$(basename "${SDKPATH}")"
fi

# Download XNU and some additional sources we will need to help build.
curl https://opensource.apple.com/tarballs/xnu/xnu-4903.221.2.tar.gz | tar -xf-
curl https://opensource.apple.com/tarballs/dtrace/dtrace-284.200.15.tar.gz | tar -xf-
curl https://opensource.apple.com/tarballs/AvailabilityVersions/AvailabilityVersions-33.200.4.tar.gz | tar -xf-
curl https://opensource.apple.com/tarballs/libplatform/libplatform-177.200.16.tar.gz | tar -xf-
curl https://opensource.apple.com/tarballs/libdispatch/libdispatch-1008.220.2.tar.gz | tar -xf-

# Build and install ctf utilities. This adds the ctf tools to
# ${TOOLCHAINPATH}/usr/local/bin.
cd dtrace-284.200.15
mkdir -p obj dst sym
xcodebuild install -target ctfconvert -target ctfdump -target ctfmerge ARCHS="x86_64" SRCROOT="${PWD}" OBJROOT="${PWD}/obj" SYMROOT="${PWD}/sym" DSTROOT="${PWD}/dst" USER_HEADER_SEARCH_PATHS="${PWD}/compat/opensolaris/sys ${PWD}/lib/libelf ${PWD}/lib/libdwarf"
# TODO: Get the XcodeDefault.toolchain path programmatically.
sudo ditto "${PWD}/dst/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain" "${TOOLCHAINPATH}"
cd ..

# Install AvailabilityVersions. This writes to ${SDKPATH}/usr/local/libexec.
cd AvailabilityVersions-33.200.4
mkdir -p dst
make install SRCROOT="${PWD}" DSTROOT="${PWD}/dst"
sudo ditto "${PWD}/dst/usr/local" "${SDKPATH}/usr/local"
cd ..

# Install the XNU headers we'll need for libdispatch. This OVERWRITES files in
# MacOSX10.13.sdk!
cd xnu-4903.221.2
mkdir -p BUILD.hdrs/obj BUILD.hdrs/sym BUILD.hdrs/dst
make installhdrs SDKROOT=macosx ARCH_CONFIGS=X86_64 SRCROOT="${PWD}" OBJROOT="${PWD}/BUILD.hdrs/obj" SYMROOT="${PWD}/BUILD.hdrs/sym" DSTROOT="${PWD}/BUILD.hdrs/dst"
# HACK: The subsequent build command fails with a missing file error. We create
# that file so that the build continues.
touch libsyscall/os/thread_self_restrict.h
xcodebuild installhdrs -project libsyscall/Libsyscall.xcodeproj -sdk macosx ARCHS="x86_64" SRCROOT="${PWD}/libsyscall" OBJROOT="${PWD}/BUILD.hdrs/obj" SYMROOT="${PWD}/BUILD.hdrs/sym" DSTROOT="${PWD}/BUILD.hdrs/dst"
# Set permissions correctly before dittoing over MacOSX10.13.sdk.
sudo chown -R root:wheel BUILD.hdrs/dst/
sudo ditto BUILD.hdrs/dst "${SDKPATH}"
cd ..

# Install libplatform headers to ${SDKPATH}/usr/local/include.
cd libplatform-177.200.16
sudo ditto "${PWD}/include" "${SDKPATH}/usr/local/include"
sudo ditto "${PWD}/private"  "${SDKPATH}/usr/local/include"
cd ..

# Build and install libdispatch's libfirehose_kernel target to
# ${SDKPATH}/usr/local.
cd libdispatch-1008.220.2
mkdir -p obj sym dst
xcodebuild install -project libdispatch.xcodeproj -target libfirehose_kernel -sdk macosx ARCHS="x86_64 i386" SRCROOT="${PWD}" OBJROOT="${PWD}/obj" SYMROOT="${PWD}/sym" DSTROOT="${PWD}/dst"
sudo ditto "${PWD}/dst/usr/local" "${SDKPATH}/usr/local"
cd ..

# Build XNU.
cd xnu-4903.221.2
make SDKROOT=macosx ARCH_CONFIGS=X86_64 KERNEL_CONFIGS="RELEASE"
