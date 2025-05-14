import ssl, sys
from cryptography.hazmat.primitives import (hashes)

print(ssl.OPENSSL_VERSION)

try:
    hashes.Hash(hashes.SHA256())
    print('cryptography hash test passed')
except Exception as e:
    print(f'WARNING: cryptography hash test failed: {e}', file=sys.stderr)