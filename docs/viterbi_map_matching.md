# Polaris Hidden Markov Model Map Matching Specification

## 1. Mathematical Formulation

Map matching aligns an ordered sequence of noisy geographic observations $Z = (z_1, z_2, \dots, z_T)$ with the topological road network graph $G = (V, E)$. The problem is formulated as a Hidden Markov Model (HMM) where:
- Observations $z_t = (\text{lat}_t, \text{lon}_t, t_t)$ are measured GPS pings.
- Hidden states $S_t = \{ x_{t,1}, x_{t,2}, \dots, x_{t,K} \}$ are candidate projections onto candidate road segments $e \in E$.
- The goal is to compute the Maximum A Posteriori (MAP) state sequence:
  $$S^* = \arg\max_{s_1, \dots, s_T} p(z_1, \dots, z_T \mid s_1, \dots, s_T) \prod_{t=2}^T p(s_t \mid s_{t-1})$$

---

## 2. Spatial Emission Probability Models

The emission probability $p(z_t \mid x_{t,k})$ models measurement error between the true vehicle location $x_{t,k}$ and observed sensor coordinate $z_t$.

### 2.1 Gaussian Emission Model
For open-sky environments with standard GPS noise:
$$p(z_t \mid x_{t,k}) = \frac{1}{\sqrt{2\pi \sigma^2}} \exp\left( -\frac{\|z_t - x_{t,k}\|^2}{2\sigma^2} \right)$$
Where $\sigma \approx 4.07$ meters represents typical GPS horizontal accuracy.

### 2.2 Student-t Robust Emission Model
In urban canyons with frequent multipath reflections and heavy-tailed errors:
$$p(z_t \mid x_{t,k}) = \frac{\Gamma\left(\frac{\nu + 1}{2}\right)}{\sqrt{\nu \pi} \sigma \Gamma\left(\frac{\nu}{2}\right)} \left( 1 + \frac{\|z_t - x_{t,k}\|^2}{\nu \sigma^2} \right)^{-\frac{\nu + 1}{2}}$$
With degrees of freedom $\nu = 3.0$, downweighting severe outlier multipath reflections.

---

## 3. Network Transition Probability Model

The transition probability $p(x_{t,k} \mid x_{t-1,j})$ quantifies the plausibility of transitioning from candidate $x_{t-1,j}$ on edge $e_a$ to candidate $x_{t,k}$ on edge $e_b$.

Let $d_{\text{route}}(x_{t-1,j}, x_{t,k})$ be the shortest network distance traversing valid directed links, and $d_{\text{gc}}(z_{t-1}, z_t)$ be the Great Circle distance between raw GPS pings. Under nominal vehicle movement, network distance closely tracks sensor displacement:
$$p(x_{t,k} \mid x_{t-1,j}) = \frac{1}{\beta} \exp\left( -\frac{|d_{\text{route}} - d_{\text{gc}}|}{\beta} \right)$$

If $d_{\text{route}} = \infty$ (e.g., disconnected road segments or prohibited one-way violation), the transition probability is strictly zero (or $-\infty$ in log space).

---

## 4. Log-Space Viterbi Trellis Propagation

To avoid numerical underflow across long trajectories, Polaris computes the Viterbi trellis strictly in log space:

### 4.1 Forward Trellis Step
For each time step $t = 2, \dots, T$ and each candidate $k \in \{1, \dots, K_t\}$:
$$V_t(k) = \max_{j \in \{1, \dots, K_{t-1}\}} \left[ V_{t-1}(j) + \ln p(x_{t,k} \mid x_{t-1,j}) \right] + \ln p(z_t \mid x_{t,k})$$
The optimal predecessor index is recorded:
$$B_t(k) = \arg\max_{j \in \{1, \dots, K_{t-1}\}} \left[ V_{t-1}(j) + \ln p(x_{t,k} \mid x_{t-1,j}) \right]$$

### 4.2 Backtracking Sequence Recovery
At step $T$, select the candidate with maximum probability:
$$k_T^* = \arg\max_k V_T(k)$$
Trace backward for $t = T-1, \dots, 1$:
$$k_t^* = B_{t+1}(k_{t+1}^*)$$

---

## 5. Candidate Road Projection Geometry

For each GPS ping $P$ and road segment $AB$:
1. Vector projection computes scalar parameter:
   $$\hat{t} = \frac{(P - A) \cdot (B - A)}{\|B - A\|^2}$$
2. Clamping ensures projection lies on the finite segment:
   $$t^* = \max(0, \min(1, \hat{t}))$$
3. The projected coordinate is:
   $$X = A + t^* (B - A)$$
4. Cross-track error is the geodesic distance from $P$ to $X$.
