"""Loopback-only WebDAV fixture for Windows startup regression tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_PROPFIND(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        body = b'''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>
<d:propstat><d:prop><d:displayname>Startup fixture</d:displayname>
<d:resourcetype><d:collection/></d:resourcetype>
<d:quota-used-bytes>0</d:quota-used-bytes>
<d:quota-available-bytes>1048576</d:quota-available-bytes>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>'''
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"code":0,"data":{}}')


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18087), Handler).serve_forever()
