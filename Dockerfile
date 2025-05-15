### --- Stage 1: FIPS Core (OpenSSL, wget, curl) ---
FROM alpine:latest AS fipscore

ARG OPENSSL_VERSION=3.1.2
ARG WGET2_VERSION=latest
ARG CURL_VERSION=8.7.1

ARG BUILD_ARCH=linux-aarch64

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Install base build deps
RUN apk add --no-cache \
    build-base linux-headers perl coreutils \
    bzip2-dev zlib-dev autoconf automake libtool cmake curl-dev libintl ca-certificates

# Download sources
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && wget https://ftp.gnu.org/gnu/wget/wget2-${WGET2_VERSION}.tar.gz \
    && wget https://curl.se/download/curl-${CURL_VERSION}.tar.gz

# Build and install OpenSSL with FIPS
RUN tar -xf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure ${BUILD_ARCH} enable-fips shared enable-ec_nistp_64_gcc_128 --prefix=/usr/local \
    && make -j1 \
    && make install \
    && make install_fips

# Configure OpenSSL FIPS
RUN printf '%s\n' \
  'openssl_conf = openssl_init' \
  '.include /usr/local/ssl/fipsmodule.cnf' \
  '' \
  '[openssl_init]' \
  'providers = provider_sect' \
  'alg_section = algorithm_sect' \
  'system_default = system_default_sect' \
  '' \
  '[provider_sect]' \
  'fips = fips_sect' \
  'base = base_sect' \
  '' \
  '[base_sect]' \
  'activate = 1' \
  '' \
  '[algorithm_sect]' \
  'default_properties = fips=yes' \
  '' \
  '[system_default_sect]' \
  'ssl_cert_file = /etc/ssl/certs/ca-certificates.crt' \
  > /etc/ssl/openssl.cnf

# Rebuild wget against FIPS OpenSSL
RUN mkdir wget_build \
    && tar -xzf wget2-${WGET2_VERSION}.tar.gz -C wget_build --strip-components=1 \
    && cd wget_build \
    && ./configure --with-ssl=openssl --with-libssl-prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf wget_build*

# Rebuild curl against FIPS OpenSSL
RUN mkdir curl_build \
    && tar -xzf curl-${CURL_VERSION}.tar.gz -C curl_build --strip-components=1 \
    && cd curl_build \
    && ./configure --with-ssl=/usr/local --disable-shared --enable-static \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf curl_build*

### --- Stage 2: Python & Cryptography ---
FROM alpine:latest AS pythoncrypto

ARG PYTHON_VERSION=3.11.12

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

RUN apk add --no-cache \
    build-base linux-headers perl coreutils pkgconfig libffi-dev \
    zlib-dev bzip2-dev sqlite-dev libxml2-dev libxslt-dev libintl \
    ca-certificates curl libgcc

COPY --from=fipscore /usr/local /usr/local
COPY --from=fipscore /etc/ssl /etc/ssl

ENV OPENSSL_FIPS=1
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV LDFLAGS="-L/usr/local/lib"
ENV CPPFLAGS="-I/usr/local/include"
ENV CFLAGS="-I/usr/local/include"

# Install Rust with rustup (before enabling FIPS networking restrictions)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable && \
    ln -s /root/.cargo/bin/* /usr/local/bin/

# Download and build Python
RUN wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz \
    && tar -xf Python-${PYTHON_VERSION}.tgz \
    && cd Python-${PYTHON_VERSION} \
    && ./configure --enable-optimizations --enable-shared --with-ensurepip=no --with-openssl=/usr/local \
    && make -j1 \
    && make install

# Install pip and cryptography
RUN wget -q https://bootstrap.pypa.io/get-pip.py \
    && python3 get-pip.py \
    && rm get-pip.py \
    && pip install --no-binary cryptography cryptography

### --- Stage 3: Minimal Runtime ---
FROM alpine:latest

ENV PATH=/usr/local/bin:$PATH
ENV OPENSSL_FIPS=1
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY --from=fipscore /usr/local /usr/local
COPY --from=fipscore /etc/ssl /etc/ssl
COPY --from=pythoncrypto /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=pythoncrypto /usr/local/bin/pip /usr/local/bin/pip
COPY --from=pythoncrypto /usr/local/lib /usr/local/lib
COPY --from=pythoncrypto /usr/lib/libgcc* /usr/lib/

COPY app.py /app/app.py
COPY fipsCheck.py fipsCheck.py
COPY requirements.txt /app/requirements.txt
RUN pip install --no-binary cryptography -r /app/requirements.txt

# Clean up unnecessary files to reduce image size
RUN strip --strip-unneeded /usr/local/bin/python3 || true \
    && strip --strip-unneeded /usr/local/lib/libpython3* || true \
    && strip --strip-unneeded /usr/local/lib/libssl.so* || true \
    && strip --strip-unneeded /usr/local/lib/libcrypto.so* || true \
    && find /usr/local -name '*.a' -delete \
    && find /usr/local -name '*.la' -delete \
    && rm -rf /usr/local/lib/python3.11/test

# Smoke test
RUN python3 fipsCheck.py
RUN openssl list -providers


CMD ["python3", "/app/app.py"]
