#!/usr/bin/env bash
# Cloud Agent bootstrap for the Roon Remote repository.
#
# Roon Remote is an iOS + watchOS SwiftUI app. Building and running the app
# itself requires macOS + Xcode (SwiftUI, UIKit, WatchKit, AVFoundation,
# PhotosUI and the Security framework are Apple-only and are not available on
# Linux), so this cannot happen on a Linux Cloud Agent.
#
# What this script CAN provide on Linux is the open-source Swift toolchain,
# which compiles and runs the platform-independent core of the app (the
# Foundation-based data models in RoonRemote/Models.swift +
# RoonRemote/API/RoonAPIModels.swift and the URLSession networking layer in
# RoonRemote/API/RoonAPIClient.swift). That lets an agent type-check and
# exercise that code without a Mac.
#
# The script is idempotent: re-running it is a no-op once the toolchain is in
# place.
set -euo pipefail

SWIFT_VERSION="6.3.3"
SWIFT_PLATFORM="ubuntu24.04"
SWIFT_DIR="/opt/swift"
SWIFT_BIN="${SWIFT_DIR}/usr/bin"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM}.tar.gz"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

log "Installing Swift build/runtime dependencies (apt)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
  libz3-dev pkg-config tzdata zip unzip zlib1g-dev

if [ -x "${SWIFT_BIN}/swift" ]; then
  log "Swift already present at ${SWIFT_BIN} ($(${SWIFT_BIN}/swift --version | head -1))"
else
  log "Downloading Swift ${SWIFT_VERSION} for ${SWIFT_PLATFORM}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/swift.tar.gz" "${SWIFT_URL}"
  log "Extracting to ${SWIFT_DIR}"
  sudo mkdir -p "${SWIFT_DIR}"
  sudo tar xzf "${tmp}/swift.tar.gz" -C "${SWIFT_DIR}" --strip-components=1
  rm -rf "${tmp}"
fi

log "Exposing the toolchain on PATH for interactive and non-interactive shells"
sudo tee /etc/profile.d/swift.sh >/dev/null <<EOF
export PATH="${SWIFT_BIN}:\$PATH"
EOF
# Symlinks make swift* resolvable from non-login shells (e.g. bash -c) too.
for bin in "${SWIFT_BIN}"/swift "${SWIFT_BIN}"/swiftc "${SWIFT_BIN}"/swift-*; do
  [ -e "$bin" ] && sudo ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
done

log "Swift toolchain ready"
"${SWIFT_BIN}/swift" --version
