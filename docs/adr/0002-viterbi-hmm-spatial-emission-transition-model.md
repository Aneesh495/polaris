# ADR 0002: Hidden Markov Model with Log-Space Viterbi Decoding for Map Matching

## Status
Accepted

## Context
Raw telemetry collected from GPS, GNSS, and mobile tracking sensors exhibits spatial noise, multipath reflection, and sensor dropout. Naively snapping each GPS coordinate to its nearest spatial road link produces discontinuous trajectories, unrealistic zig-zag maneuvers, and topological impossibilities (e.g., teleporting across parallel highway lanes or turning against one-way restrictions).

We require a principled, probabilistic sequence decoding engine capable of inferring the most likely sequence of underlying road segments that produced the observed sequence of spatial coordinates.

## Decision Drivers
1. Topological Consistency: Trajectories must follow connected, directed road sequences.
2. Temporal Dynamics: Road network travel distance must align with elapsed sensor time.
3. Numerical Stability: Avoid floating-point underflow across long observation chains.
4. Robustness to Outliers: Gracefully mitigate urban canyon multipath reflections.
5. Sparse Trajectories: Support varying sampling intervals from 1 second to 120 seconds.

## Considered Options
- Option 1: Hidden Markov Model (HMM) with Viterbi Trellis Decoding (Newson and Krumm, 2009).
- Option 2: Fréchet Distance Curve Matching (Alt and Godau, 1995).
- Option 3: Incremental Point-to-Curve Geometric Projection.

## Decision Outcome
Chosen Option: Option 1 (Hidden Markov Model with Log-Space Viterbi Decoding).

The HMM formulation cleanly decouples spatial measurement error (emission probability) from topological network connectivity (transition probability), allowing joint optimization over the entire trajectory.

## Technical Details

### 1. Emission Probability Model
The emission probability models the likelihood that a vehicle at candidate projection point $x_{i,j}$ on road segment $j$ generates GPS observation $z_i$:
$$p(z_i \mid x_{i,j}) = \frac{1}{\sqrt{2\pi \sigma^2}} \exp\left( -\frac{\|z_i - x_{i,j}\|^2}{2\sigma^2} \right)$$
In log-space:
$$\ln p(z_i \mid x_{i,j}) = -\ln(\sigma \sqrt{2\pi}) - \frac{\|z_i - x_{i,j}\|^2}{2\sigma^2}$$
Where $\sigma \approx 4.07$ meters represents typical GPS horizontal accuracy. Polaris also supports heavy-tailed Student-t emission distributions for high-multipath urban canyons.

### 2. Transition Probability Model
The transition probability models the likelihood of transitioning from candidate $x_{i-1,j}$ to candidate $x_{i,k}$:
$$p(x_{i,k} \mid x_{i-1,j}) = \frac{1}{\beta} \exp\left( -\frac{|d_{\text{route}}(x_{i-1,j}, x_{i,k}) - d_{\text{euclidean}}(z_{i-1}, z_i)|}{\beta} \right)$$
In log-space:
$$\ln p(x_{i,k} \mid x_{i-1,j}) = -\ln(\beta) - \frac{|d_{\text{route}} - d_{\text{greatcircle}}|}{\beta}$$
Where $\beta$ is an empirical scaling parameter calibrated to typical driver behavior.

### 3. Log-Space Trellis Propagation
To eliminate underflow across chains of hundreds of points, recurrence is computed strictly in log space:
$$V_t(k) = \max_{j} \left( V_{t-1}(j) + \ln p(x_{t,k} \mid x_{t-1,j}) \right) + \ln p(z_t \mid x_{t,k})$$
The backpointer matrix records the argmax index at each step:
$$B_t(k) = \arg\max_{j} \left( V_{t-1}(j) + \ln p(x_{t,k} \mid x_{t-1,j}) \right)$$

### 4. Extended Kalman Pre-filtering
Before emission scoring, raw pings can optionally pass through an Extended Kalman Filter (EKF) tracking position $(x, y)$, heading $\theta$, and velocity $v$. Outliers exhibiting standardized innovation residuals $> 3.0$ are flagged and downweighted.

## Consequences

### Positive
- Globally optimal path decoding across noisy and sparse GPS traces.
- Complete resistance to floating-point underflow.
- Resilient to parallel highway frontage road ambiguities.

### Negative
- Evaluating network shortest paths between all candidate pairs across consecutive steps requires $O(K^2)$ routing checks per step. Mitigated by R-Tree spatial pruning ($K \le 8$) and cached distance checks.
