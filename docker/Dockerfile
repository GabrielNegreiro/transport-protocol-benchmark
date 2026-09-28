# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04 AS quic-build

ARG DEBIAN_FRONTEND=noninteractive
ARG OPENSSL_VERSION=3.5.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf automake build-essential ca-certificates cmake curl libnghttp2-dev libpcre2-dev libtool ninja-build perl pkg-config \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --show-error --silent \
        "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
        -o /tmp/openssl.tar.gz \
    && mkdir -p /src/openssl \
    && tar -xzf /tmp/openssl.tar.gz --strip-components=1 -C /src/openssl \
    && cd /src/openssl \
    && ./Configure linux-x86_64 --prefix=/opt/quic-openssl --libdir=lib shared \
    && make -j"$(nproc)" \
    && make install_sw

FROM quic-build AS nginx-build

ARG NGINX_VERSION=1.27.5
RUN curl --fail --location --show-error --silent \
        "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
        -o /tmp/nginx.tar.gz \
    && mkdir /src/nginx \
    && tar -xzf /tmp/nginx.tar.gz --strip-components=1 -C /src/nginx \
    && cd /src/nginx \
    && ./configure \
        --prefix=/opt/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --error-log-path=/dev/stderr \
        --http-log-path=/dev/stdout \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-cc-opt='-I/opt/quic-openssl/include' \
        --with-ld-opt='-L/opt/quic-openssl/lib -Wl,-rpath,/opt/quic-openssl/lib' \
    && make -j"$(nproc)" \
    && make install \
    && nginx -V 2>&1 | grep -q -- '--with-http_v3_module'

FROM quic-build AS client-build

ARG NGHTTP3_VERSION=1.8.0
ARG NGTCP2_VERSION=1.12.0
ARG CURL_VERSION=8.22.0
ENV PKG_CONFIG_PATH=/opt/quic-openssl/lib/pkgconfig

RUN curl --fail --location --show-error --silent \
        "https://github.com/ngtcp2/nghttp3/releases/download/v${NGHTTP3_VERSION}/nghttp3-${NGHTTP3_VERSION}.tar.xz" \
        -o /tmp/nghttp3.tar.xz \
    && mkdir /src/nghttp3 \
    && tar -xJf /tmp/nghttp3.tar.xz --strip-components=1 -C /src/nghttp3 \
    && cd /src/nghttp3 \
    && ./configure --prefix=/usr/local --enable-lib-only \
    && make -j"$(nproc)" \
    && make install

RUN curl --fail --location --show-error --silent \
        "https://github.com/ngtcp2/ngtcp2/releases/download/v${NGTCP2_VERSION}/ngtcp2-${NGTCP2_VERSION}.tar.xz" \
        -o /tmp/ngtcp2.tar.xz \
    && mkdir /src/ngtcp2 \
    && tar -xJf /tmp/ngtcp2.tar.xz --strip-components=1 -C /src/ngtcp2 \
    && cd /src/ngtcp2 \
    && PKG_CONFIG_PATH=/opt/quic-openssl/lib/pkgconfig:/usr/local/lib/pkgconfig \
        LDFLAGS='-Wl,-rpath,/opt/quic-openssl/lib' \
        ./configure --prefix=/usr/local --enable-lib-only --with-openssl \
    && make -j"$(nproc)" \
    && make install

RUN curl --fail --location --show-error --silent \
        "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" \
        -o /tmp/curl.tar.xz \
    && mkdir /src/curl \
    && tar -xJf /tmp/curl.tar.xz --strip-components=1 -C /src/curl \
    && cd /src/curl \
    && PKG_CONFIG_PATH=/opt/quic-openssl/lib/pkgconfig:/usr/local/lib/pkgconfig \
        LDFLAGS='-Wl,-rpath,/opt/quic-openssl/lib' ./configure \
        --prefix=/usr/local \
        --with-openssl=/opt/quic-openssl \
        --with-nghttp3=/usr/local \
        --with-ngtcp2=/usr/local \
        --without-libpsl \
        --disable-shared \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && /usr/local/bin/curl --version | grep -q 'HTTP2' \
    && /usr/local/bin/curl --version | grep -q 'HTTP3'

FROM ubuntu:24.04 AS server

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates iperf3 openssl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/www/html /etc/nginx/tls /run
COPY --from=quic-build /opt/quic-openssl /opt/quic-openssl
COPY --from=nginx-build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx-build /opt/nginx /opt/nginx
COPY --from=nginx-build /src/nginx/conf/mime.types /etc/nginx/mime.types
COPY server/nginx.conf /etc/nginx/nginx.conf
COPY server/entrypoint.sh /usr/local/bin/server-entrypoint
COPY server/index.html /var/www/html/index.html
RUN chmod 0755 /usr/local/bin/server-entrypoint \
    && nginx -V 2>&1 | grep -q -- '--with-http_v3_module'
EXPOSE 8443/tcp 8443/udp 5201/tcp 5201/udp
ENTRYPOINT ["/usr/local/bin/server-entrypoint"]

FROM ubuntu:24.04 AS client

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates iperf3 iproute2 iputils-ping python3 tshark \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /artifacts
COPY --from=quic-build /opt/quic-openssl /opt/quic-openssl
COPY --from=client-build /usr/local /usr/local
RUN printf '%s\n%s\n' '/opt/quic-openssl/lib' '/usr/local/lib' > /etc/ld.so.conf.d/quic-client.conf \
    && ldconfig \
    && /usr/local/bin/curl --version | grep -q 'HTTP2' \
    && /usr/local/bin/curl --version | grep -q 'HTTP3'
ENV PATH=/usr/local/bin:${PATH}
EXPOSE 5201/tcp 5201/udp
