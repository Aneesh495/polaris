# ADR 0004: Static User Equilibrium Traffic Assignment via Frank-Wolfe Optimization

## Status
Accepted

## Context
In urban road networks, travel times are congestion-dependent. When thousands of drivers navigate simultaneously, link travel times increase according to non-linear congestion volume-delay functions. Simply assigning each driver to the shortest path under free-flow conditions (All-or-Nothing assignment) leads to severe overload on primary arterials while parallel secondary routes remain empty.

Under Wardrop's First Principle of User Equilibrium, traffic distributes such that the journey times on all used routes are equal, and no individual driver can unilaterally decrease their journey time by switching routes. Mathematically, this corresponds to Beckmann's convex optimization formulation.

We require a scalable optimization algorithm to compute equilibrium link flows and convergence metrics across road networks.

## Decision Drivers
1. Theoretical Convergence: Must converge monotonically to Wardrop User Equilibrium.
2. Nonlinear Congestion Handling: Support standard Bureau of Public Roads (BPR) volume-delay functions.
3. Computational Scalability: Scale to networks with tens of thousands of directed links and multiple origin-destination pairs.
4. Objective Verification: Provide a rigorous relative gap metric to verify equilibrium achievement.

## Considered Options
- Option 1: Frank-Wolfe Algorithm with Golden Section Line Search (Frank and Wolfe, 1956; Sheffi, 1985).
- Option 2: Method of Successive Averages (MSA).
- Option 3: Origin-Based Assignment (OBA) (Bar-Gera, 2002).
- Option 4: Path-Based Gradient Projection.

## Decision Outcome
Chosen Option: Option 1 (Frank-Wolfe with Golden Section Line Search).

The Frank-Wolfe convex optimization algorithm computes a sequence of descent directions via All-or-Nothing (AON) subproblems, followed by an exact one-dimensional line search finding the optimal convex combination step size $\lambda \in [0, 1]$.

## Technical Details

### 1. Beckmann's Mathematical Program
$$\min_{x \ge 0} \sum_{a \in E} \int_{0}^{x_a} t_a(\omega) \, d\omega$$
Subject to origin-destination conservation constraints:
$$\sum_{k \in K_{rs}} f_k^{rs} = q_{rs}, \quad x_a = \sum_{rs} \sum_{k \in K_{rs}} f_k^{rs} \delta_{a,k}^{rs}, \quad f_k^{rs} \ge 0$$
Where BPR link performance functions are:
$$t_a(x_a) = t_a^0 \left( 1 + \alpha \left( \frac{x_a}{C_a} \right)^\beta \right)$$
With default parameters $\alpha = 0.15$ and $\beta = 4.0$. The integral evaluates analytically to:
$$\int_0^{x_a} t_a(\omega) \, d\omega = t_a^0 \left( x_a + \frac{\alpha}{(\beta + 1) C_a^\beta} x_a^{\beta + 1} \right)$$

### 2. Algorithmic Steps
1. Initialization: Set $x_a^{(0)}$ using AON assignment on free-flow times $t_a^0$.
2. For iteration $k = 1, 2, \dots, K_{\max}$:
   - Update link travel times: $t_a^{(k)} = t_a(x_a^{(k-1)})$.
   - Direction Finding: Compute auxiliary link flows $y_a^{(k)}$ via AON loading on updated travel times $t_a^{(k)}$.
   - Descent Direction: $d_a^{(k)} = y_a^{(k)} - x_a^{(k-1)}$.
   - Line Search: Find step size $\lambda^* \in [0, 1]$ minimizing Beckmann objective:
     $$\lambda^* = \arg\min_{\lambda \in [0, 1]} \sum_{a \in E} \int_0^{x_a^{(k-1)} + \lambda d_a^{(k)}} t_a(\omega) \, d\omega$$
     using 1D Golden Section search.
   - Flow Update: $x_a^{(k)} = x_a^{(k-1)} + \lambda^* d_a^{(k)}$.
   - Convergence Evaluation: Calculate relative gap:
     $$\text{Gap}^{(k)} = \frac{\sum_a x_a^{(k)} t_a(x_a^{(k)}) - \sum_a y_a^{(k)} t_a(x_a^{(k)})}{\sum_a x_a^{(k)} t_a(x_a^{(k)})}$$
   - If $\text{Gap}^{(k)} \le \epsilon$ (typically $10^{-3}$ or $10^{-4}$), terminate.

## Consequences

### Positive
- Mathematically proven global convergence for convex optimization programs.
- Low memory requirement: only stores current link flows $x_a$ and auxiliary flows $y_a$.
- High fidelity modeling of urban arterial and highway congestion.

### Negative
- Asymptotic convergence can slow near the optimal solution. Mitigated by configurable relative gap thresholds and CSR graph acceleration.
