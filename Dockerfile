### --- Stage 1: OpenSSL Build ---
FROM debian:bookworm-slim AS opensslbuild

ARG OPENSSL_VERSION=3.1.2
ARG TARGETARCH

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    perl \
    coreutils \
    libbz2-dev \
    zlib1g-dev \
    autoconf \
    automake \
    libtool \
    cmake \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Build and install OpenSSL with FIPS. BUILD_ARCH is derived from TARGETARCH
# so this works correctly for both single-platform --load builds and
# multi-platform --push builds where buildx injects TARGETARCH per platform.
# no-legacy removes IDEA, RC2, single-DES and other non-FIPS algorithms.
# install_sw and install_fips must remain single-threaded.
RUN case "${TARGETARCH}" in \
      amd64) BUILD_ARCH="linux-x86_64"; EC_FLAG="enable-ec_nistp_64_gcc_128" ;; \
      arm64) BUILD_ARCH="linux-aarch64"; EC_FLAG="" ;; \
      *)     BUILD_ARCH="linux-${TARGETARCH}"; EC_FLAG="" ;; \
    esac \
    && wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar -xf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure ${BUILD_ARCH} enable-fips no-legacy shared ${EC_FLAG} --prefix=/usr/local \
    && make -j"$(nproc)" build_sw \
    && make install_sw \
    && make install_fips \
    && cd .. && rm -rf openssl-${OPENSSL_VERSION}* \
    && echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl.conf \
    && ldconfig

# Template only — no .include for fipsmodule.cnf because that file must be
# generated fresh on each machine at container startup, not baked into the
# image. See docker-entrypoint.sh and README-FIPS.md for OpenSSL 3.1.2.
RUN printf '%s\n' \
  'config_diagnostics = 1' \
  'openssl_conf = openssl_init' \
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
  > /etc/ssl/openssl.cnf.tmpl


### --- Stage 2: Python & Cryptography ---
FROM debian:bookworm-slim AS pythoncrypto

ARG PYTHON_VERSION=3.11.12
ARG TARGETARCH

ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libsqlite3-dev \
    libxml2-dev \
    libxslt1-dev \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.11.0 /uv /usr/local/bin/uv

# Downloads happen while Debian's libssl3 is present for wget HTTPS.
# ln -sf force-overwrites any symlinks left by a previous cached layer.
RUN wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz \
    && wget -qO- https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
    && ln -sf /root/.cargo/bin/* /usr/local/bin/

# Copy our FIPS OpenSSL and register it in the linker cache.
COPY --from=opensslbuild /usr/local /usr/local
COPY --from=opensslbuild /etc/ssl /etc/ssl

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl.conf && ldconfig

# Create unversioned symlinks so openssl-sys can find the libraries.
RUN ln -sf /usr/local/lib/libssl.so.3 /usr/local/lib/libssl.so \
    && ln -sf /usr/local/lib/libcrypto.so.3 /usr/local/lib/libcrypto.so

# Do NOT set OPENSSL_CONF or OPENSSL_FIPS here. OPENSSL_CONF points to a
# file that does not exist until the entrypoint generates it at runtime.
# Setting it during the build causes Python's configure test to fail to
# initialise OpenSSL and silently skip building _ssl.
# Debian's libssl3 is intentionally left in place so Python's post-build
# import test can resolve libssl.so.3 at make time. Stage 3 only contains
# our OpenSSL so Debian's libssl is absent at runtime.
ENV OPENSSL_DIR="/usr/local"
ENV OPENSSL_LIB_DIR="/usr/local/lib"
ENV OPENSSL_INCLUDE_DIR="/usr/local/include"
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
ENV LDFLAGS="-L/usr/local/lib"
ENV CPPFLAGS="-I/usr/local/include"
ENV CFLAGS="-I/usr/local/include"

RUN tar -xf Python-${PYTHON_VERSION}.tgz \
    && cd Python-${PYTHON_VERSION} \
    && ./configure \
        --enable-shared \
        --with-ensurepip=no \
        --with-openssl=/usr/local \
        --with-openssl-rpath=/usr/local/lib \
    && make -j"$(nproc)" \
    && make install \
    && cd .. && rm -rf Python-${PYTHON_VERSION}*

RUN python3 -c "import ssl; print(ssl.OPENSSL_VERSION)"

# Configure cargo to use gcc as the linker instead of rust-lld.
# rust-lld does not search ldconfig paths so it cannot find our libssl/libcrypto
# in /usr/local/lib. gcc invokes the system linker which reads ldconfig and
# finds them correctly. Both targets are listed so this works for amd64 and
# arm64 multi-platform builds.
# --no-build-isolation disables PEP 517 subprocess isolation so uv inherits
# our OPENSSL_* environment variables. maturin, cffi, and setuptools must be
# pre-installed since they would normally be fetched by the isolated build.
RUN mkdir -p /root/.cargo && printf \
  '[target.x86_64-unknown-linux-gnu]\nlinker = "gcc"\nrustflags = ["-L", "/usr/local/lib", "-C", "link-arg=-Wl,-rpath,/usr/local/lib"]\n\n[target.aarch64-unknown-linux-gnu]\nlinker = "gcc"\nrustflags = ["-L", "/usr/local/lib", "-C", "link-arg=-Wl,-rpath,/usr/local/lib"]\n' \
  > /root/.cargo/config.toml

RUN uv pip install --system maturin cffi setuptools

RUN uv pip install --system --no-build-isolation --no-binary cryptography

RUN find /usr/local -name '*.a' -delete \
    && find /usr/local -name '*.la' -delete

RUN strip --strip-unneeded /usr/local/bin/python3 || true \
    && strip --strip-unneeded /usr/local/lib/libpython3* || true \
    && strip --strip-unneeded /usr/local/lib/libssl.so* || true \
    && strip --strip-unneeded /usr/local/lib/libcrypto.so* || true \
    && rm -rf /usr/local/lib/python3.11/test


### --- Stage 3: Minimal Runtime ---
FROM debian:bookworm-slim

ENV PATH=/usr/local/bin:$PATH
ENV OPENSSL_FIPS=1
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV DEBIAN_FRONTEND=noninteractive

# libgcc-s1 is needed by the cryptography Rust extension. Installing via apt
# handles the arch-dependent path (/usr/lib/x86_64-linux-gnu vs aarch64).
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    libgcc-s1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=opensslbuild /usr/local /usr/local
COPY --from=opensslbuild /etc/ssl/openssl.cnf.tmpl /etc/ssl/openssl.cnf.tmpl
COPY --from=opensslbuild /etc/ssl/certs /etc/ssl/certs

COPY --from=pythoncrypto /usr/local/bin/python3 /usr/local/bin/
COPY --from=pythoncrypto /usr/local/bin/uv /usr/local/bin/
COPY --from=pythoncrypto /usr/local/lib /usr/local/lib

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl.conf && ldconfig

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN useradd -U -u 1000 appuser && \
    chown -R 1000:1000 \
      /usr/local/lib/python3.11/site-packages/cryptography \
      /usr/local/lib/python3.11/site-packages/ && \
    chown -R 1000:1000 /etc/ssl && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

USER 1000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]