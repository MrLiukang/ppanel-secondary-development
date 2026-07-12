FROM docker:27-cli
COPY --from=golang:alpine /usr/local/go/ /usr/local/go/
ENV PATH=/usr/local/go/bin:$PATH
ARG TARGETARCH=amd64
RUN apk add --no-cache curl unzip \
    && if [ "${TARGETARCH}" = "amd64" ]; then XRAY_ARCH=64; else XRAY_ARCH=arm64-v8a; fi \
    && curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip \
    && unzip -p /tmp/xray.zip xray > /usr/local/bin/xray \
    && chmod 0755 /usr/local/bin/xray \
    && rm -f /tmp/xray.zip
WORKDIR /src
COPY tools/anytls-sidecar-manager ./
RUN go mod init sidecar-manager && go mod tidy && go build -trimpath -o /usr/local/bin/anytls-sidecar-manager .
ENTRYPOINT ["/usr/local/bin/anytls-sidecar-manager"]
