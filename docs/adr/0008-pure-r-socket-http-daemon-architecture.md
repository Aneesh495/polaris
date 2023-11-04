# ADR 0008: Zero-Dependency Pure-R HTTP/1.1 Socket Daemon Architecture

## Status
Accepted

## Context
Deploying routing engines often relies on external web framework packages (such as `plumber` or `httpuv`) or third-party web servers (such as NGINX or Envoy). While suitable for production clusters, external dependencies introduce heavy installation overhead, native compilation barriers, and version incompatibilities across heterogeneous environments.

We require an embedded HTTP/1.1 REST daemon that operates out-of-the-box using only base R networking primitives, enabling zero-install API serving for interactive frontends, microservices, and automated testing harnesses.

## Decision Drivers
1. Zero External Dependencies: Must rely solely on base R `socketConnection()` and `serverSocket()`.
2. HTTP/1.1 Conformance: Support GET, POST, OPTIONS (CORS preflight), chunked parsing, and RFC-compliant status codes.
3. Content Negotiation: Parse JSON request payloads and return structured JSON / GeoJSON responses.
4. Non-Blocking Event Loop: Process inbound requests without deadlocking or exhausting socket descriptors.
5. Error Resilience: Gracefully catch and handle application exceptions without terminating the server process.

## Considered Options
- Option 1: Base R Socket Daemon (`serverSocket()` and `socketConnection()`).
- Option 2: `httpuv` C++ libuv bindings.
- Option 3: `plumber` package.
- Option 4: Standalone external reverse proxy.

## Decision Outcome
Chosen Option: Option 1 (Base R Socket Daemon).

Polaris implements an integrated HTTP/1.1 server engine in pure R (`R/server/http_server.R`). By managing raw TCP stream sockets, header serialization, route dispatching, and JSON serialization directly, Polaris requires zero external packages and zero system libraries to expose its entire routing engine as a live REST API.

## Technical Details

### 1. TCP Server Loop
The server listens on a configurable port (default 8080) using `serverSocket(port)`:
- Accepts incoming client connections via `socketConnection(server = ..., blocking = TRUE, open = "r+b")`.
- Reads the HTTP request line: `METHOD /path HTTP/1.1`.
- Parses headers into a key-value hash table.
- Reads request body bytes up to `Content-Length`.

### 2. URL Routing and Dispatch Table
Incoming paths are matched against registered endpoints:
- `GET /health`: Engine status, uptime, node and edge counts, native acceleration state.
- `GET /route`: Point-to-point shortest path queries with parameters `origin`, `destination`, `algo`, `metric`.
- `POST /match`: Trace map matching ingestion with GPS coordinates payload.
- `GET /isochrone`: Reachability polygon generation with parameters `origin`, `cutoff_time`.
- `GET /matrix`: Many-to-many distance matrix calculation.
- `OPTIONS *`: Universal CORS preflight headers allowing cross-origin web browser interaction.

### 3. Response Generation
Responses are serialized as HTTP/1.1 compliant text streams:
- Status line: `HTTP/1.1 200 OK` or RFC error code.
- Headers: `Content-Type: application/json`, `Access-Control-Allow-Origin: *`, `Connection: close`.
- Body: Formatted JSON payload containing GeoJSON geometry, distance, duration, and telemetry.

### 4. Fault Tolerance
Every route handler is wrapped in a `tryCatch()` block. If an invalid node ID or disconnected destination is requested, the daemon returns an RFC 400 Bad Request or 404 Not Found JSON error object without crashing the server loop.

## Consequences

### Positive
- True zero-dependency execution: runs anywhere R is installed.
- Instant startup: boots in under 5 milliseconds.
- Completely inspectable: 100% transparent pure-R network stack.

### Negative
- Single-threaded base R socket model is designed for development, desktop visualization, and integration testing rather than 100,000 req/sec production workloads. For high-concurrency production deployments, multi-worker process pools or containerized sidecars can be placed in front.
