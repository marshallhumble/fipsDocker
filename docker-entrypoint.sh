#!/bin/sh
set -e

# Run openssl fipsinstall on this machine to generate a fresh fipsmodule.cnf.
#
# Per the OpenSSL 3.1.2 README-FIPS, the fipsmodule.cnf must not be copied
# between machines because it contains an install-status entry that, if copied,
# causes self-tests to be skipped on the target machine. This would be
# non-compliant. Running fipsinstall here ensures the self-tests execute and
# the integrity checksum is computed against the fips.so on this specific host.
#
# In Kubernetes or similar environments, consider mounting /etc/ssl as a
# writable emptyDir or tmpfs volume so this write does not touch a read-only
# root filesystem. The OPENSSL_CONF env var can then point into that volume.

FIPS_MODULE=/usr/local/lib/ossl-modules/fips.so
FIPSMODULE_CNF=/usr/local/ssl/fipsmodule.cnf
OPENSSL_CNF=/etc/ssl/openssl.cnf
OPENSSL_CNF_TMPL=/etc/ssl/openssl.cnf.tmpl

echo "Running openssl fipsinstall on $(hostname)..."
openssl fipsinstall \
    -out "${FIPSMODULE_CNF}" \
    -module "${FIPS_MODULE}"

# Write the final openssl.cnf with the .include pointing at the freshly
# generated fipsmodule.cnf. The template does not contain this line because
# the file did not exist at image build time.
{
  echo "config_diagnostics = 1"
  echo "openssl_conf = openssl_init"
  echo ".include ${FIPSMODULE_CNF}"
  echo ""
  tail -n +3 "${OPENSSL_CNF_TMPL}"
} > "${OPENSSL_CNF}"

echo "FIPS provider initialised. Verifying..."
openssl list -providers | grep -q "OpenSSL FIPS Provider" || {
    echo "ERROR: FIPS provider not active after fipsinstall" >&2
    exit 1
}

exec "$@"