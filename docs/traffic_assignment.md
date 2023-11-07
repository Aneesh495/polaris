# Polaris Traffic Assignment & User Equilibrium Specification

## 1. Wardrop's Principle & Beckmann's Formulation

In urban networks, link travel times increase as link traffic volume approaches or exceeds design capacity. Under Wardrop's First Principle of User Equilibrium:
"The journey times on all the routes actually used are equal, and less than those which would be experienced by a single vehicle on any unused route."

This behavioral equilibrium is formulated as Beckmann's convex mathematical optimization program:
$$\min_{x \ge 0} Z(x) = \sum_{a \in E} \int_{0}^{x_a} t_a(\omega) \, d\omega$$
Subject to:
$$\sum_{k \in K_{rs}} f_k^{rs} = q_{rs} \quad \forall (r, s) \in \text{OD}$$
$$x_a = \sum_{rs} \sum_{k \in K_{rs}} f_k^{rs} \delta_{a,k}^{rs} \quad \forall a \in E$$
$$f_k^{rs} \ge 0$$

Where:
- $q_{rs}$: Total trip demand between origin $r$ and destination $s$.
- $f_k^{rs}$: Traffic flow assigned to path $k$.
- $x_a$: Total volume on link $a$.
- $\delta_{a,k}^{rs}$: Indicator variable equal to 1 if link $a$ belongs to path $k$, and 0 otherwise.

---

## 2. Bureau of Public Roads (BPR) Congestion Functions

Polaris implements the standard Bureau of Public Roads (BPR) volume-delay relationship:
$$t_a(x_a) = t_a^0 \left[ 1 + \alpha \left( \frac{x_a}{C_a} \right)^\beta \right]$$
Where:
- $t_a^0$: Free-flow travel time (seconds).
- $C_a$: Practical design capacity (vehicles / hour).
- $\alpha$: Calibration parameter (default $\alpha = 0.15$).
- $\beta$: Congestion sensitivity exponent (default $\beta = 4.0$).

The definite integral of the BPR function evaluates to:
$$\int_0^{x_a} t_a(\omega) \, d\omega = t_a^0 \left[ x_a + \frac{\alpha}{(\beta + 1) C_a^\beta} x_a^{\beta + 1} \right]$$

---

## 3. The Frank-Wolfe Algorithm with Golden Section Line Search

The Frank-Wolfe convex optimization algorithm computes a sequence of descent directions by repeatedly solving linear approximation subproblems via All-or-Nothing (AON) assignment.

### 3.1 Algorithmic Iteration
1. Free-flow initialization: $x^{(0)} \leftarrow \text{AON}(t^0)$. Set $k \leftarrow 1$.
2. Update travel times: Evaluate $t_a^{(k)} = t_a(x_a^{(k-1)})$ for all $a \in E$.
3. Direction finding: Solve linear programming subproblem by computing auxiliary flow $y^{(k)} \leftarrow \text{AON}(t^{(k)})$.
4. Optimal line search: Compute step size $\lambda^* \in [0, 1]$ that minimizes the Beckmann objective along the descent vector $d^{(k)} = y^{(k)} - x^{(k-1)}$:
   $$\lambda^* = \arg\min_{\lambda \in [0, 1]} Z(x^{(k-1)} + \lambda (y^{(k)} - x^{(k-1)}))$$
   Polaris solves this 1D convex minimization problem using Golden Section Search with golden ratio $\phi = \frac{\sqrt{5} - 1}{2} \approx 0.618034$.
5. Convex update: $x^{(k)} = x^{(k-1)} + \lambda^* (y^{(k)} - x^{(k-1)})$.
6. Convergence test: Compute relative gap:
   $$\text{RelativeGap}^{(k)} = \frac{\sum_a x_a^{(k)} t_a(x_a^{(k)}) - \sum_a y_a^{(k)} t_a(x_a^{(k)})}{\sum_a x_a^{(k)} t_a(x_a^{(k)})}$$
   If $\text{RelativeGap}^{(k)} \le \epsilon$ (e.g., $10^{-3}$ or $10^{-4}$), equilibrium is achieved.

---

## 4. Macroscopic Fundamental Diagram & Queue Spillback

To support dynamic traffic modeling, Polaris incorporates a macroscopic queue spillback simulation:
- Inflow and outflow rates are governed by link capacity and downstream storage limits.
- Shockwave propagation tracks queue formation when link density exceeds jam density $k_{\text{jam}}$.
