### --- Stage 1: OpenSSL Build ---
FROM alpine:latest AS opensslbuild

ARG OPENSSL_VERSION=3.1.2
ARG TARGETARCH
ARG BUILD_ARCH=linux-${TARGETARCH}

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Install base build deps
RUN apk add --no-cache \
    build-base linux-headers perl coreutils \
    bzip2-dev zlib-dev autoconf automake libtool cmake curl-dev libintl ca-certificates

# Build and install OpenSSL with FIPS
# Build and install OpenSSL with FIPS (no docs)
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar -xf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure ${BUILD_ARCH} enable-fips shared enable-ec_nistp_64_gcc_128 --prefix=/usr/local \
    && make build_sw \
    && make install_sw \
    && make install_fips \
    && cd .. && rm -rf openssl-${OPENSSL_VERSION}*


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


### --- Stage 2: Python & Cryptography ---
FROM alpine:latest AS pythoncrypto

ARG PYTHON_VERSION=3.11.12

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

RUN apk add --no-cache \
    build-base linux-headers perl coreutils pkgconfig libffi-dev \
    zlib-dev bzip2-dev sqlite-dev libxml2-dev libxslt-dev libintl \
    ca-certificates curl libgcc wget

# Need to download before we turn on fips mode
RUN wget -q https://bootstrap.pypa.io/get-pip.py \
    && wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable && \
           ln -s /root/.cargo/bin/* /usr/local/bin/

RUN python3 get-pip.py \
    && rm get-pip.py

COPY --from=opensslbuild /usr/local /usr/local
COPY --from=opensslbuild /etc/ssl /etc/ssl

ENV OPENSSL_FIPS=1
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV LDFLAGS="-L/usr/local/lib"
ENV CPPFLAGS="-I/usr/local/include"
ENV CFLAGS="-I/usr/local/include"

# Build Python
RUN tar -xf Python-${PYTHON_VERSION}.tgz \
    && cd Python-${PYTHON_VERSION} \
    && ./configure --enable-optimizations --enable-shared --with-ensurepip=no --with-openssl=/usr/local \
    && make \
    && make install \
    && cd .. && rm -rf Python-${PYTHON_VERSION}*


# Install pip and cryptography
RUN pip install --no-binary cryptography cryptography

# Clean up unnecessary files to reduce image size
RUN strip --strip-unneeded /usr/local/bin/python3 || true \
    && strip --strip-unneeded /usr/local/lib/libpython3* || true \
    && strip --strip-unneeded /usr/local/lib/libssl.so* || true \
    && strip --strip-unneeded /usr/local/lib/libcrypto.so* || true \
    && find /usr/local -name '*.a' -delete \
    && find /usr/local -name '*.la' -delete \
    && rm -rf /usr/local/lib/python3.11/test

### --- Stage 3: Minimal Runtime ---
FROM alpine:latest

ENV PATH=/usr/local/bin:$PATH
ENV OPENSSL_FIPS=1
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Copy all runtime dependencies from build stages
COPY --from=opensslbuild /usr/local /usr/local
COPY --from=opensslbuild  /etc/ssl /etc/ssl

COPY --from=pythoncrypto /usr/local/bin/python3 /usr/local/bin
COPY --from=pythoncrypto  /usr/local/bin/pip /usr/local/bin
COPY --from=pythoncrypto  /usr/local/lib /usr/local/lib
COPY --from=pythoncrypto /usr/lib/libgcc* /usr/lib/

COPY --from=pythoncrypto \
  /usr/local/lib/python3.11/site-packages/cryptography \
  /usr/local/lib/python3.11/site-packages/cryptography-*.dist-info \
  /usr/local/lib/python3.11/site-packages/
