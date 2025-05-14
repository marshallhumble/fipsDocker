import hashlib
from flask import Flask
from waitress import serve

app = Flask(__name__)

@app.route("/")
def hello():
    try:
        hashlib.md5()
        return "MD5 is available (FIPS compliance check failed)"
    except ValueError as e:
        return "MD5 is not available (FIPS compliance check passed): {e}"

if __name__ == "__main__":
    serve(app, host="0.0.0.0", port=8080)