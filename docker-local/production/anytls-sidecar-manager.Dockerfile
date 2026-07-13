FROM golang:1.24-alpine@sha256:8bee1901f1e530bfb4a7850aa7a479d17ae3a18beb6e09064ed54cfd245b7191 AS anytls-builder
ARG ANYTLS_COMMIT=9666872946857b50a74fdb692896d77b53773cb2
RUN apk add --no-cache git \
    && git init /src/anytls \
    && cd /src/anytls \
    && git remote add origin https://github.com/anytls/anytls-go.git \
    && git fetch --depth 1 origin ${ANYTLS_COMMIT} \
    && git checkout --detach ${ANYTLS_COMMIT} \
    && test "$(git rev-parse HEAD)" = "${ANYTLS_COMMIT}" \
    && CGO_ENABLED=0 go build -trimpath -o /out/anytls-client ./cmd/client

FROM docker:27-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c
ARG ANYTLS_COMMIT=9666872946857b50a74fdb692896d77b53773cb2
ARG XRAY_VERSION=v26.3.27
ARG XRAY_SHA256_AMD64=23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
ARG XRAY_SHA256_ARM64=4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c
LABEL org.opencontainers.image.anytls.commit=${ANYTLS_COMMIT} \
      org.opencontainers.image.xray.version=${XRAY_VERSION}
COPY --from=anytls-builder /usr/local/go/ /usr/local/go/
COPY --from=anytls-builder /out/anytls-client /usr/local/bin/anytls-client
ENV PATH=/usr/local/go/bin:$PATH
ARG TARGETARCH=amd64
RUN apk add --no-cache curl unzip \
    && case "${TARGETARCH}" in \
         amd64) XRAY_ARCH=64; XRAY_SHA256=${XRAY_SHA256_AMD64} ;; \
         arm64) XRAY_ARCH=arm64-v8a; XRAY_SHA256=${XRAY_SHA256_ARM64} ;; \
         *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip \
    && echo "${XRAY_SHA256}  /tmp/xray.zip" | sha256sum -c - \
    && unzip -p /tmp/xray.zip xray > /usr/local/bin/xray \
    && chmod 0755 /usr/local/bin/xray \
    && rm -f /tmp/xray.zip
WORKDIR /src
COPY backend/tools/anytls-sidecar-manager ./
ARG X_NET_VERSION=v0.35.0
RUN go mod init sidecar-manager \
    && go get golang.org/x/net@${X_NET_VERSION} \
    && go build -trimpath -o /usr/local/bin/anytls-sidecar-manager .
COPY scripts/relay-sidecar-manager-entrypoint.sh /usr/local/bin/relay-sidecar-manager-entrypoint
RUN chmod 0755 /usr/local/bin/relay-sidecar-manager-entrypoint
ENTRYPOINT ["/usr/local/bin/relay-sidecar-manager-entrypoint"]
