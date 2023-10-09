/*
 * Polaris Native Acceleration Kernel
 * SIMD and cache-aligned C routines for Dijkstra CSR relaxation, geodesics, and ray-casting
 */

#ifndef POLARIS_ACCEL_H
#define POLARIS_ACCEL_H

#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>

#define WGS84_A 6378137.0
#define WGS84_F (1.0 / 298.257223563)
#define WGS84_B (6378137.0 * (1.0 - (1.0 / 298.257223563)))
#define DEG_TO_RAD (3.14159265358979323846 / 180.0)

/* Binary min-heap node */
typedef struct {
    int node;
    double priority;
} HeapEntry;

typedef struct {
    HeapEntry *data;
    int size;
    int capacity;
} MinHeap;

MinHeap *heap_create(int capacity);
void heap_free(MinHeap *heap);
void heap_push(MinHeap *heap, int node, double priority);
bool heap_pop(MinHeap *heap, int *out_node, double *out_prio);

/* Exported R Callables */
SEXP c_dijkstra_csr(SEXP s_idx_s, SEXP t_idx_s, SEXP offsets_s, SEXP targets_s, SEXP weights_s, SEXP n_nodes_s);
SEXP c_vincenty_distance(SEXP lat1_s, SEXP lon1_s, SEXP lat2_s, SEXP lon2_s);
SEXP c_haversine_matrix(SEXP lats1_s, SEXP lons1_s, SEXP lats2_s, SEXP lons2_s);
SEXP c_point_in_polygon(SEXP lat_s, SEXP lon_s, SEXP poly_lats_s, SEXP poly_lons_s);

#endif /* POLARIS_ACCEL_H */
