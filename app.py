from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.backends import default_backend

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
async def fips_check():
    status_code = 200
    try:
        digest = hashes.Hash(hashes.MD5(), backend=default_backend())
        digest.update(b"test")
        digest.finalize()
        status = "FIPS mode is NOT active — MD5 succeeded."
        color = "red"
    except Exception:
        status_code = 500
        status = "FIPS mode is ACTIVE — MD5 is blocked."
        color = "green"

    return f"""
    <!DOCTYPE html>
    <html>
    <head><title>FIPS Status</title></head>
    <body style="font-family: Arial; text-align: center; padding-top: 5em;">
        <h1 style="color: {color};">{status}</h1>
    </body>
    </html>
    """, status_code
