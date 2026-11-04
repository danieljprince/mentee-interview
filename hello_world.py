import json
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from types import FrameType


def get_version() -> str:
    return os.environ.get("APP_VERSION", "0.1.0-dev")


class VersionHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        version = get_version()
        if self.path in ("/", "/version", "/health"):
            payload = {
                "service": "mentee-interview",
                "version": version,
                "message": f"App version: {version}",
                "status": "healthy",
            }
            body = (json.dumps(payload, indent=2) + "\n").encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404, "Not Found")

    def log_message(self, format: str, *args: object) -> None:
        sys.stdout.write(f"[HTTP] {self.address_string()} - {format % args}\n")
        sys.stdout.flush()


def main() -> None:
    version = get_version()
    print(f"App version: {version}", flush=True)

    if "--version" in sys.argv or "--once" in sys.argv:
        return

    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), VersionHandler)

    def handle_signal(signum: int, _frame: FrameType | None) -> None:
        print(f"Received signal {signum}, shutting down...", flush=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    print(f"Listening on http://0.0.0.0:{port} (version {version})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
