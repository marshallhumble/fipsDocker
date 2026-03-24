from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.backends import default_backend

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
async def fips_check():
    try:
        digest = hashes.Hash(hashes.MD5(), backend=default_backend())
        digest.update(b"test")
        digest.finalize()
        # MD5 succeeded — FIPS is NOT enforcing algorithm restrictions
        status = "FIPS mode is NOT active — MD5 succeeded."
        color = "red"
        status_code = 500
    except Exception:
        # MD5 blocked — FIPS provider is active and working
        status = "FIPS mode is ACTIVE — MD5 is blocked."
        color = "green"
        status_code = 200

    content = f"""
    <!DOCTYPE html>
    <html>
    <head><title>FIPS Status</title></head>
    <body style="font-family: Arial; text-align: center; padding-top: 5em;">
        <h1 style="color: {color};">{status}</h1>
    </body>
    </html>
    """
    return HTMLResponse(content=content, status_code=status_code)