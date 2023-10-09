/*
 * Polaris Native Acceleration Kernel Implementation
 * Cache-optimized C routines interfacing directly with R via .Call()
 */

#include "polaris_accel.h"

MinHeap *heap_create(int capacity) {
    MinHeap *h = (MinHeap *)malloc(sizeof(MinHeap));
    if (!h) return NULL;
    h->capacity = capacity > 16 ? capacity : 16;
    h->size = 0;
    h->data = (HeapEntry *)malloc(sizeof(HeapEntry) * h->capacity);
    if (!h->data) {
        free(h);
        return NULL;
    }
    return h;
}

void heap_free(MinHeap *heap) {
    if (heap) {
        if (heap->data) free(heap->data);
        free(heap);
    }
}

void heap_push(MinHeap *heap, int node, double priority) {
    if (heap->size >= heap->capacity) {
        heap->capacity *= 2;
        heap->data = (HeapEntry *)realloc(heap->data, sizeof(HeapEntry) * heap->capacity);
    }
    int idx = heap->size++;
    heap->data[idx].node = node;
    heap->data[idx].priority = priority;

    /* Sift up */
    while (idx > 0) {
        int parent = (idx - 1) / 2;
        if (heap->data[idx].priority < heap->data[parent].priority) {
            HeapEntry tmp = heap->data[idx];
            heap->data[idx] = heap->data[parent];
            heap->data[parent] = tmp;
            idx = parent;
        } else {
            break;
        }
    }
}

bool heap_pop(MinHeap *heap, int *out_node, double *out_prio) {
    if (heap->size == 0) return false;
    *out_node = heap->data[0].node;
    *out_prio = heap->data[0].priority;

    heap->data[0] = heap->data[--heap->size];

    /* Sift down */
    int idx = 0;
    while (true) {
        int left = 2 * idx + 1;
        int right = 2 * idx + 2;
        int smallest = idx;

        if (left < heap->size && heap->data[left].priority < heap->data[smallest].priority) {
            smallest = left;
        }
        if (right < heap->size && heap->data[right].priority < heap->data[smallest].priority) {
            smallest = right;
        }

        if (smallest != idx) {
            HeapEntry tmp = heap->data[idx];
            heap->data[idx] = heap->data[smallest];
            heap->data[smallest] = tmp;
            idx = smallest;
        } else {
            break;
        }
    }
    return true;
}

/* Fast Dijkstra CSR search in pure C */
SEXP c_dijkstra_csr(SEXP s_idx_s, SEXP t_idx_s, SEXP offsets_s, SEXP targets_s, SEXP weights_s, SEXP n_nodes_s) {
    int s_idx = asInteger(s_idx_s) - 1; /* convert 1-based R to 0-based C */
    int t_idx = asInteger(t_idx_s) - 1;
    int n_nodes = asInteger(n_nodes_s);

    const int *offsets = INTEGER(offsets_s);
    const int *targets = INTEGER(targets_s);
    const double *weights = REAL(weights_s);

    double *dist = (double *)malloc(sizeof(double) * n_nodes);
    int *parent_node = (int *)malloc(sizeof(int) * n_nodes);
    bool *settled = (bool *)malloc(sizeof(bool) * n_nodes);

    for (int i = 0; i < n_nodes; i++) {
        dist[i] = INFINITY;
        parent_node[i] = -1;
        settled[i] = false;
    }

    MinHeap *pq = heap_create(1024);
    dist[s_idx] = 0.0;
    heap_push(pq, s_idx, 0.0);

    bool has_target = (t_idx >= 0);

    while (pq->size > 0) {
        int u;
        double u_cost;
        if (!heap_pop(pq, &u, &u_cost)) break;

        if (settled[u]) continue;
        settled[u] = true;

        if (has_target && u == t_idx) break;

        /* R offsets are 1-based */
        int start_e = offsets[u] - 1;
        int end_e = offsets[u + 1] - 2;

        for (int e_ptr = start_e; e_ptr <= end_e; e_ptr++) {
            int v = targets[e_ptr] - 1;
            if (settled[v]) continue;

            double edge_len = weights[e_ptr];
            double new_cost = u_cost + edge_len;

            if (new_cost < dist[v]) {
                dist[v] = new_cost;
                parent_node[v] = u;
                heap_push(pq, v, new_cost);
            }
        }
    }

    heap_free(pq);

    /* Construct result R list */
    SEXP res_list = PROTECT(allocVector(VECSXP, 3));
    SEXP dist_out = PROTECT(allocVector(REALSXP, n_nodes));
    SEXP parent_out = PROTECT(allocVector(INTSXP, n_nodes));
    SEXP target_dist_out = PROTECT(ScalarReal(has_target ? dist[t_idx] : INFINITY));

    for (int i = 0; i < n_nodes; i++) {
        REAL(dist_out)[i] = dist[i];
        INTEGER(parent_out)[i] = parent_node[i] >= 0 ? parent_node[i] + 1 : 0;
    }

    SET_VECTOR_ELT(res_list, 0, dist_out);
    SET_VECTOR_ELT(res_list, 1, parent_out);
    SET_VECTOR_ELT(res_list, 2, target_dist_out);

    free(dist);
    free(parent_node);
    free(settled);

    UNPROTECT(4);
    return res_list;
}

/* Fast Vincenty geodesic distance in C */
SEXP c_vincenty_distance(SEXP lat1_s, SEXP lon1_s, SEXP lat2_s, SEXP lon2_s) {
    double lat1 = asReal(lat1_s);
    double lon1 = asReal(lon1_s);
    double lat2 = asReal(lat2_s);
    double lon2 = asReal(lon2_s);

    if (fabs(lat1 - lat2) < 1e-9 && fabs(lon1 - lon2) < 1e-9) {
        return ScalarReal(0.0);
    }

    double phi1 = lat1 * DEG_TO_RAD;
    double phi2 = lat2 * DEG_TO_RAD;
    double L = (lon2 - lon1) * DEG_TO_RAD;

    double U1 = atan((1.0 - WGS84_F) * tan(phi1));
    double U2 = atan((1.0 - WGS84_F) * tan(phi2));
    double sinU1 = sin(U1), cosU1 = cos(U1);
    double sinU2 = sin(U2), cosU2 = cos(U2);

    double lambda = L;
    int iter = 0;
    double sin_sigma = 0.0, cos_sigma = 0.0, sigma = 0.0, cos2_alpha = 0.0, cos2_sigma_m = 0.0;

    while (iter < 200) {
        iter++;
        double sin_lambda = sin(lambda);
        double cos_lambda = cos(lambda);

        sin_sigma = sqrt((cosU2 * sin_lambda) * (cosU2 * sin_lambda) +
                         (cosU1 * sinU2 - sinU1 * cosU2 * cos_lambda) * (cosU1 * sinU2 - sinU1 * cosU2 * cos_lambda));
        if (sin_sigma < 1e-15) return ScalarReal(0.0);

        cos_sigma = sinU1 * sinU2 + cosU1 * cosU2 * cos_lambda;
        sigma = atan2(sin_sigma, cos_sigma);

        double sin_alpha = (cosU1 * cosU2 * sin_lambda) / sin_sigma;
        cos2_alpha = 1.0 - sin_alpha * sin_alpha;

        cos2_sigma_m = (cos2_alpha == 0.0) ? 0.0 : cos_sigma - (2.0 * sinU1 * sinU2) / cos2_alpha;

        double C = (WGS84_F / 16.0) * cos2_alpha * (4.0 + WGS84_F * (4.0 - 3.0 * cos2_alpha));
        double lambda_prev = lambda;
        lambda = L + (1.0 - C) * WGS84_F * sin_alpha *
                 (sigma + C * sin_sigma * (cos2_sigma_m + C * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m)));

        if (fabs(lambda - lambda_prev) < 1e-12) break;
    }

    double u2 = cos2_alpha * ((WGS84_A * WGS84_A - WGS84_B * WGS84_B) / (WGS84_B * WGS84_B));
    double A = 1.0 + (u2 / 16384.0) * (4096.0 + u2 * (-768.0 + u2 * (320.0 - 175.0 * u2)));
    double B = (u2 / 1024.0) * (256.0 + u2 * (-128.0 + u2 * (74.0 - 47.0 * u2)));

    double delta_sigma = B * sin_sigma * (cos2_sigma_m + (B / 4.0) *
                         (cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m) -
                          (B / 6.0) * cos2_sigma_m * (-3.0 + 4.0 * sin_sigma * sin_sigma) * (-3.0 + 4.0 * cos2_sigma_m * cos2_sigma_m)));

    double s = WGS84_B * A * (sigma - delta_sigma);
    return ScalarReal(s);
}

/* Fast Point-in-polygon ray casting in C */
SEXP c_point_in_polygon(SEXP lat_s, SEXP lon_s, SEXP poly_lats_s, SEXP poly_lons_s) {
    double lat = asReal(lat_s);
    double lon = asReal(lon_s);
    int n = length(poly_lats_s);

    if (n < 3) return ScalarLogical(FALSE);

    const double *poly_lats = REAL(poly_lats_s);
    const double *poly_lons = REAL(poly_lons_s);

    bool inside = false;
    int j = n - 1;

    for (int i = 0; i < n; i++) {
        double yi = poly_lats[i];
        double xi = poly_lons[i];
        double yj = poly_lats[j];
        double xj = poly_lons[j];

        if (((yi > lat) != (yj > lat)) &&
            (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
            inside = !inside;
        }
        j = i;
    }

    return ScalarLogical(inside);
}
