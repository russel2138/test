#!/usr/bin/env python3
import cgi
import html
import os
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
DEST = "/data/game.jar"
PASSWORD = os.environ.get("UPLOAD_PASSWORD", "")
MAX_SIZE = 10 * 1024 * 1024

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NRO first setup</title>
<style>body{font-family:system-ui,sans-serif;max-width:620px;margin:50px auto;padding:0 18px;background:#111;color:#eee}form{display:grid;gap:14px;padding:22px;border:1px solid #333;border-radius:14px;background:#181818}input,button{font:inherit;padding:10px;border-radius:8px;border:1px solid #444}button{cursor:pointer}code{background:#222;padding:2px 5px;border-radius:5px}.muted{color:#aaa}</style></head>
<body><h1>NRO first setup</h1><p>Upload your J2ME <code>.jar</code> once. It will be stored in the persistent <code>/data</code> volume.</p>
<form method="post" enctype="multipart/form-data"><label>Xpra / upload password<input name="password" type="password" required></label><label>Game JAR<input name="game" type="file" accept=".jar,application/java-archive" required></label><button type="submit">Upload and start game</button></form>
<p class="muted">After upload, wait about 10-20 seconds and refresh this page. The Xpra HTML5 client should appear.</p></body></html>"""

class Handler(BaseHTTPRequestHandler):
    server_version = "NROUploader/1.0"

    def _send(self, code, body, content_type="text/html; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, "waiting-for-game", "text/plain; charset=utf-8")
        self._send(200, PAGE)

    def do_POST(self):
        ctype, params = cgi.parse_header(self.headers.get("Content-Type", ""))
        if ctype != "multipart/form-data":
            return self._send(400, "<h1>Expected multipart form upload</h1>")
        try:
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={"REQUEST_METHOD": "POST", "CONTENT_TYPE": self.headers.get("Content-Type", "")},
                keep_blank_values=True,
            )
            supplied = form.getfirst("password", "")
            if not PASSWORD or supplied != PASSWORD:
                return self._send(403, "<h1>Wrong password</h1><p>Go back and use the Xpra password from the app logs.</p>")
            item = form["game"] if "game" in form else None
            if item is None or not getattr(item, "file", None):
                return self._send(400, "<h1>No game JAR received</h1>")

            os.makedirs("/data", exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix="game-", suffix=".jar", dir="/data")
            size = 0
            try:
                with os.fdopen(fd, "wb") as out:
                    while True:
                        chunk = item.file.read(64 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > MAX_SIZE:
                            raise ValueError("file-too-large")
                        out.write(chunk)
                with open(tmp, "rb") as f:
                    if f.read(4)[:2] != b"PK":
                        raise ValueError("not-a-jar")
                os.replace(tmp, DEST)
            except Exception:
                try:
                    os.unlink(tmp)
                except FileNotFoundError:
                    pass
                raise

            body = f"<h1>Uploaded {html.escape(str(size))} bytes</h1><p>Game saved. Xpra is starting now. Wait 10-20 seconds, then refresh this URL.</p>"
            self._send(200, body)
            self.server.upload_complete = True
        except ValueError as e:
            msg = "File is too large (10 MB max)." if str(e) == "file-too-large" else "The upload does not look like a JAR/ZIP file."
            self._send(400, f"<h1>Upload rejected</h1><p>{html.escape(msg)}</p>")
        except Exception as e:
            self._send(500, f"<h1>Upload failed</h1><pre>{html.escape(str(e))}</pre>")

    def log_message(self, fmt, *args):
        print("[upload] " + (fmt % args), flush=True)

class Server(ThreadingHTTPServer):
    upload_complete = False

def main():
    server = Server(("0.0.0.0", PORT), Handler)
    print(f"[upload] waiting for game JAR on 0.0.0.0:{PORT}", flush=True)
    while not server.upload_complete:
        server.handle_request()
    print("[upload] upload complete; handing port to Xpra", flush=True)

if __name__ == "__main__":
    main()
