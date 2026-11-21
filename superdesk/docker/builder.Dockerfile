# Linux build environment for super远程桌面:
#   - flutter_rust_bridge codegen (bridge files are also used by the Windows build)
#   - Android APK build
# Versions are pinned to RustDesk 1.5.3 CI (.github/workflows/flutter-build.yml, bridge.yml).
# Build context is staged by superdesk/scripts/build-android.ps1.
#
# Every download is wrapped in `retry` and split into its own layer: the build host's network
# drops connections under sustained load, and a finished layer is never downloaded again.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
# Prefer IPv4 everywhere (glibc getaddrinfo): the build host's DNS can hand out unroutable
# IPv6 addresses, and every tool would first wait for those to time out.
RUN echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf \
    && printf '#!/bin/sh\nn=0\nuntil "$@"; do n=$((n+1)); [ $n -ge 8 ] && exit 1; echo "retry $n/7: $*" >&2; sleep 20; done\n' \
        > /usr/local/bin/retry && chmod +x /usr/local/bin/retry \
    && printf 'Acquire::Retries "10";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::ForceIPv4 "true";\n' \
        > /etc/apt/apt.conf.d/80-retries
ENV CARGO_NET_RETRY=10 CARGO_HTTP_TIMEOUT=60

# Ubuntu apt mirror (empty = official archive.ubuntu.com)
ARG APT_MIRROR=mirrors.aliyun.com
RUN if [ -n "$APT_MIRROR" ]; then \
        sed -i "s@//archive.ubuntu.com@//$APT_MIRROR@g; s@//security.ubuntu.com@//$APT_MIRROR@g" /etc/apt/sources.list; \
    fi \
    && retry apt-get update \
    && retry apt-get install -y --no-install-recommends \
        ca-certificates curl wget git unzip zip xz-utils file rsync python3 \
        clang cmake gcc g++ gcc-multilib g++-multilib libclang-dev llvm-dev \
        nasm ninja-build pkg-config make autoconf automake libtool \
        libgtk-3-dev libayatana-appindicator3-dev libasound2-dev libc6-dev libunwind-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libpulse-dev libva-dev \
        libxcb-randr0-dev libxcb-shape0-dev libxcb-xfixes0-dev libxdo-dev libxfixes-dev \
        openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'

# --- Rust 1.75 + codegen tools --------------------------------------------
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN retry sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.75 -c rustfmt" \
    && retry rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
RUN retry cargo install cargo-expand --version 1.0.95 --locked \
    && retry cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked \
    && retry cargo install cargo-ndk --version 3.1.2 --locked \
    && rm -rf /opt/cargo/registry /opt/cargo/git

# --- Flutter: 3.22.3 for bridge codegen, 3.24.5 (+RustDesk patch) for APK --
RUN retry sh -c 'rm -rf /opt/flutter-3.22.3 && git clone --depth 1 -b 3.22.3 https://github.com/flutter/flutter.git /opt/flutter-3.22.3' \
    && /opt/flutter-3.22.3/bin/flutter config --no-analytics \
    && retry /opt/flutter-3.22.3/bin/flutter --version
COPY flutter_3.24.4_dropdown_menu_enableFilter.diff /tmp/dropdown.diff
RUN retry sh -c 'rm -rf /opt/flutter-3.24.5 && git clone --depth 1 -b 3.24.5 https://github.com/flutter/flutter.git /opt/flutter-3.24.5' \
    && git -C /opt/flutter-3.24.5 apply /tmp/dropdown.diff \
    && retry /opt/flutter-3.24.5/bin/flutter --version \
    && retry /opt/flutter-3.24.5/bin/flutter precache --android

# --- Android SDK + NDK r28c ----------------------------------------------
ENV ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-ndk-r28c ANDROID_NDK_ROOT=/opt/android-ndk-r28c \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
RUN mkdir -p $ANDROID_HOME/cmdline-tools && cd /tmp \
    && retry wget -q -c https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q commandlinetools-linux-11076708_latest.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm commandlinetools-linux-11076708_latest.zip \
    && (yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null) \
    && retry $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --install \
        "platform-tools" "platforms;android-36" "platforms;android-35" "build-tools;35.0.0"
RUN cd /tmp && retry wget -q -c https://dl.google.com/android/repository/android-ndk-r28c-linux.zip \
    && unzip -q android-ndk-r28c-linux.zip -d /opt && rm android-ndk-r28c-linux.zip

# --- vcpkg + prebuilt Android native deps (ffmpeg, libvpx, opus, aom, ...) ---
ENV VCPKG_ROOT=/opt/vcpkg
RUN retry sh -c "rm -rf $VCPKG_ROOT && git clone https://github.com/microsoft/vcpkg.git $VCPKG_ROOT" \
    && git -C $VCPKG_ROOT checkout 9e593bb18ea69cc5095e012465dcd675a822ed0d \
    && retry $VCPKG_ROOT/bootstrap-vcpkg.sh -disableMetrics
COPY vcpkg-manifest/ /opt/vcpkg-manifest/
# Space-separated vcpkg triplets: arm64-android (most phones), arm-neon-android (old 32-bit), x64-android (emulators)
ARG VCPKG_TRIPLETS="arm64-android"
RUN cd /opt/vcpkg-manifest \
    && for t in $VCPKG_TRIPLETS; do \
         retry $VCPKG_ROOT/vcpkg install --triplet $t --x-install-root=$VCPKG_ROOT/installed || exit 1; \
         if [ "$t" = arm-neon-android ]; then ln -sf $VCPKG_ROOT/installed/arm-neon-android $VCPKG_ROOT/installed/arm-android; fi; \
       done \
    && rm -rf $VCPKG_ROOT/buildtrees $VCPKG_ROOT/packages $VCPKG_ROOT/downloads

# Host-side OpenSSL for build-time crates (GitHub's CI runners ship it preinstalled). Kept as a
# late layer so the expensive SDK/NDK/vcpkg layers above stay cached.
RUN retry apt-get update && retry apt-get install -y --no-install-recommends libssl-dev \
    && rm -rf /var/lib/apt/lists/*
# Flutter plugins compile against android-33; Gradle would otherwise fetch it into every
# (throwaway) container.
RUN retry $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --install "platforms;android-33"

COPY build-in-container.sh /usr/local/bin/build-in-container.sh
RUN sed -i 's/\r$//' /usr/local/bin/build-in-container.sh && chmod +x /usr/local/bin/build-in-container.sh
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/build-in-container.sh"]
