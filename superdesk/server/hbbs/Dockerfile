# hbbs (RustDesk ID server) 1.1.16 + super远程桌面 patch: devices can register over TCP/WebSocket,
# so a single public port (WebSocket gateway) is enough -- upstream OSS hbbs only accepts UDP
# registration. Built static (musl) and dropped into the official scratch image.
# Build context: rustdesk-server 1.1.16 source + tcp-register.patch + `cargo vendor`ed
# dependencies (prepared by superdesk/scripts/deploy-server.py), so the build is fully offline
# (the server cannot reach GitHub, where some dependencies live).
FROM rust:1.90-alpine AS build
ARG APK_MIRROR=mirrors.aliyun.com
RUN if [ -n "$APK_MIRROR" ]; then sed -i "s#dl-cdn.alpinelinux.org#$APK_MIRROR#g" /etc/apk/repositories; fi \
    && apk add --no-cache musl-dev gcc g++ make perl linux-headers
WORKDIR /src
COPY . .
RUN sed 's#directory = "vendor"#directory = "/src/vendor"#' vendor-config.toml > "$CARGO_HOME/config.toml" \
    && cargo build --release --offline --bin hbbs && strip target/release/hbbs

FROM rustdesk/rustdesk-server:1.1.16
COPY --from=build /src/target/release/hbbs /usr/bin/hbbs
