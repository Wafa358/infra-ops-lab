#!/usr/bin/env python3
"""Tiny demo service for the lab: answers with the name of the VM that served the request,
so the load balancing is visible from outside. Listens on localhost; Nginx sits in front."""

import datetime
import json
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOSTNAME = socket.gethostname()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body, content_type = b"ok\n", "text/plain"
        else:
            payload = {
                "served_by": HOSTNAME,
                "path": self.path,
                "time": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            }
            body, content_type = (json.dumps(payload) + "\n").encode(), "application/json"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):  # Nginx keeps the access log
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
