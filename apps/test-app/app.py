#!/usr/bin/env python3
"""LAB test application — integrations use Kubernetes DNS names only."""
from __future__ import annotations

import os
from http.server import BaseHTTPRequestHandler, HTTPServer


def env_flag(name: str, default: str = "false") -> bool:
    return os.environ.get(name, default).lower() in {"1", "true", "yes"}


CONFIG = {
    "postgres_host": os.environ.get("POSTGRES_HOST", "postgres.database.svc.cluster.local"),
    "kafka_bootstrap": os.environ.get("KAFKA_BOOTSTRAP", "kafka.messaging.svc.cluster.local:9092"),
    "opensearch_url": os.environ.get("OPENSEARCH_URL", "http://opensearch.logging.svc.cluster.local:9200"),
    "mqtt_host": os.environ.get("MQTT_HOST", "emqx.messaging.svc.cluster.local"),
    "otel_endpoint": os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.observability.svc.cluster.local:4317"),
    "enable_postgres": env_flag("ENABLE_POSTGRES"),
    "enable_kafka": env_flag("ENABLE_KAFKA"),
    "enable_opensearch": env_flag("ENABLE_OPENSEARCH"),
    "enable_mqtt": env_flag("ENABLE_MQTT"),
    "enable_otel": env_flag("ENABLE_OTEL"),
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path in ("/", "/healthz"):
            body = "ok\n"
            self.send_response(200)
        elif self.path == "/config":
            # Never print secrets; show DNS endpoints only
            lines = [f"{k}={v}" for k, v in CONFIG.items()]
            body = "\n".join(lines) + "\n"
            self.send_response(200)
        elif self.path == "/metrics":
            body = "# HELP lab_app_up 1 if process is up\nlab_app_up 1\n"
            self.send_response(200)
        else:
            body = "not found\n"
            self.send_response(404)
        data = body.encode()
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        return


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"lab-test-app listening on 0.0.0.0:{port}", flush=True)
    print(f"postgres_host={CONFIG['postgres_host']}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
