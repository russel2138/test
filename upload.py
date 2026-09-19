#!/usr/bin/env python3
import cgi
import html
import os
import tempfile
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("NOVNC_PORT", "8080"))
DEST = "/data/game.jar"
PASSFILE = "/data/vnc-password.txt"
MAX_SIZE = 10 * 1024 * 1024

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NRO setup</title>
<style>
body{font-family:system-ui,sans-serif;max-width:620px;margin:50px auto;padding:0 18px;background:#111;color:#eee}
form{display:grid;gap:14px;padding:22px;border:1px solid #333;border-radius:14px;background:#181818}
input,button{font:inherit;padding:10px;border-radius:8px;border:1px solid #444}
button{cursor:pointer}
code{background:#222;padding:2px 5px;border-radius:5px}
</style></head>
<body>
<h1>NRO first setup</h1>
<p>Upload the J2ME game JAR once. It will be saved as <code>/data/game.jar</code>.</p>
<form method="post" enctype="multipart/form-data">
<label>VNC password<input name="password" type="password" required></label>
<label>Game JAR<input name="game" type="file" accept=".jar,application/java-archive" required></label>
<button type="submit">Upload game.jar</button>
</form>
</body></html>"""

def expected_password():
    value = os.environ.get("VNC_PASSWORD", "").strip()
    if value:
        return value
    try:
        with open(PASSFILE, "r", encoding="utf-8") as f:
            return f.readline().strip()
    except OSError:
        return ""

class Handler(BaseHTTPRequestHandler):
    server_version = "NROUploader/2"

    def send_text(self, code, body, content_type="text/html; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            return self.send_text(200, "waiting-for-game", "text/plain; charset=utf-8")
        self.send_text(200, PAGE)

    def do_POST(self):
        password = expected_password()
        if not password:
            return self.send_text(503, "<h1>VNC password is not ready yet. Refresh in a few seconds.</h1>")

        ctype, _ = cgi.parse_header(self.headers.get("Content-Type", ""))
        if ctype != "multipart/form-data":
            return self.send_text(400, "<h1>Expected a multipart upload.</h1>")

        try:
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={
                    "REQUEST_METHOD": "POST",
                    "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                },
                keep_blank_values=True,
            )
            if form.getfirst("password", "") != password:
                return self.send_text(403, "<h1>Wrong password.</h1>")

            item = form["game"] if "game" in form else None
            if item is None or not getattr(item, "file", None):
                return self.send_text(400, "<h1>No JAR received.</h1>")

            os.makedirs("/data", exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=".game-", suffix=".jar", dir="/data")
            size = 0
            try:
                with os.fdopen(fd, "wb") as out:
                    while True:
                        chunk = item.file.read(64 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > MAX_SIZE:
                            raise ValueError("too-large")
                        out.write(chunk)

                if not zipfile.is_zipfile(tmp):
                    raise ValueError("not-jar")

                with zipfile.ZipFile(tmp) as zf:
                    try:
                        manifest = zf.read("META-INF/MANIFEST.MF")
                    except KeyError:
                        raise ValueError("no-manifest")
                    if b"MIDlet-1:" not in manifest:
                        raise ValueError("no-midlet")

                os.replace(tmp, DEST)
            except Exception:
                try:
                    os.unlink(tmp)
                except FileNotFoundError:
                    pass
                raise

            self.send_text(
                200,
                "<h1>Uploaded.</h1>"
                "<p>Saved as <code>/data/game.jar</code>. "
                "The game will start automatically. Wait about 5 seconds, then refresh this page for noVNC.</p>",
            )
            self.server.upload_complete = True
        except ValueError as e:
            messages = {
                "too-large": "File is larger than 10 MB.",
                "not-jar": "The uploaded file is not a valid JAR/ZIP.",
                "no-manifest": "META-INF/MANIFEST.MF is missing.",
                "no-midlet": "The JAR has no MIDlet-1 entry.",
            }
            self.send_text(400, f"<h1>Upload rejected</h1><p>{html.escape(messages.get(str(e), str(e)))}</p>")
        except Exception as e:
            self.send_text(500, f"<h1>Upload failed</h1><pre>{html.escape(str(e))}</pre>")

    def log_message(self, fmt, *args):
        print("[upload] " + (fmt % args), flush=True)

class Server(ThreadingHTTPServer):
    upload_complete = False

def main():
    server = Server(("0.0.0.0", PORT), Handler)
    print(f"[upload] /data/game.jar missing; upload page listening on 0.0.0.0:{PORT}", flush=True)
    while not server.upload_complete:
        server.handle_request()
    print("[upload] game.jar saved; switching this port to noVNC", flush=True)

if __name__ == "__main__":
    main()
