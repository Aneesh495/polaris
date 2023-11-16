# Polaris HTTP/1.1 REST Daemon API Specification

## 1. Overview

Polaris includes an embedded zero-dependency HTTP/1.1 REST server built directly on base R socket primitives (`R/server/http_server.R`). The server enables client applications, desktop visualizers, and web map interfaces to interact with the Polaris routing engine over TCP port 8080.

All responses include standard CORS headers allowing direct access from modern browser frontends:
```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

---

## 2. API Endpoints

### 2.1 Engine Health & Status
- Method: `GET`
- Path: `/health`
- Description: Returns engine status, node and edge counts, and native acceleration status.

Example Response:
```json
{
  "status": "HEALTHY",
  "nodes": 100,
  "edges": 360,
  "native_acceleration": true,
  "timestamp": "2023-11-18T10:00:00Z"
}
```

---

### 2.2 Shortest Path Routing
- Method: `GET`
- Path: `/route`
- Query Parameters:
  - `origin`: Origin node ID (string, required).
  - `destination`: Destination node ID (string, required).
  - `algo`: Routing algorithm: `dijkstra`, `bidirectional`, `astar`, `ch` (default `dijkstra`).
  - `metric`: Minimization metric: `distance` (meters) or `time` (seconds) (default `distance`).

Example Request:
```http
GET /route?origin=N_0_0&destination=N_9_9&algo=ch HTTP/1.1
Host: localhost:8080
```

Example Response:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-122.45, 37.70],
          [-122.44, 37.70],
          [-122.36, 37.79]
        ]
      },
      "properties": {
        "status": "OK",
        "algorithm": "contraction_hierarchies",
        "total_distance_m": 18000.0,
        "total_time_s": 1080.0,
        "edge_count": 18
      }
    }
  ]
}
```

---

### 2.3 GPS Trace Map Matching
- Method: `POST`
- Path: `/match`
- Header: `Content-Type: application/json`
- Request Body: JSON array of GPS coordinates with optional timestamps:
```json
[
  {"lat": 37.7001, "lon": -122.4501, "timestamp": 1729245600},
  {"lat": 37.7102, "lon": -122.4503, "timestamp": 1729245660}
]
```

Example Response:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-122.45, 37.70],
          [-122.45, 37.71]
        ]
      },
      "properties": {
        "status": "MATCHED",
        "snapped_points": 2,
        "log_likelihood": -12.452
      }
    }
  ]
}
```

---

### 2.4 Reachability Isochrones
- Method: `GET`
- Path: `/isochrone`
- Query Parameters:
  - `origin`: Origin node ID (required).
  - `cutoff_time`: Travel time threshold in seconds (default 900.0s).

Example Response:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [[-122.46, 37.71], [-122.44, 37.71], [-122.45, 37.72], [-122.46, 37.71]]
        ]
      },
      "properties": {
        "origin": "N_0_0",
        "cutoff_seconds": 900.0,
        "reachable_nodes": 45
      }
    }
  ]
}
```
