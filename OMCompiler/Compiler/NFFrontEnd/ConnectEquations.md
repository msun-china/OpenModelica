# Connect Equation Generation Rules and Characteristics

## Overview

This document describes how OpenModelica generates equations from `connect` statements in Modelica models. The connect equation generation is implemented in the `NFConnectEquations` module.

## Connector Types

In Modelica, connector variables can have three different types of semantics:

### 1. Potential Variables (no prefix or `input`/`output`)
- **Characteristic**: Represent values that must be equal across all connections
- **Examples**: Voltage, pressure, position, angle
- **Equation Generation Rule**: For n connected potential variables, generate n-1 equality equations

### 2. Flow Variables (`flow` prefix)
- **Characteristic**: Represent quantities that must sum to zero (conservation law)
- **Examples**: Current, mass flow rate, force, torque
- **Equation Generation Rule**: Sum of all flows equals zero, with sign depending on connector face (inside/outside)

### 3. Stream Variables (`stream` prefix)
- **Characteristic**: Represent intensive properties transported by flows
- **Examples**: Specific enthalpy, mass fractions, chemical concentrations
- **Equation Generation Rule**: Complex equations depending on flow direction and connection topology

## Connector Face

Each connector element has a **face** that determines how equations are generated:

- **INSIDE**: Connector declared within a component (appears on the left side of connect)
- **OUTSIDE**: Connector on a component instance (appears on the right side of connect)

The face affects:
- Flow equation signs (inside flows are positive, outside flows are negative)
- Stream equation structure

## Detailed Generation Rules

### Potential Variable Equations

**Rule**: For a connection set with potential variables {X, Y.A, Z.B}, generate:
```
X = Y.A
X = Z.B
```

**Variability considerations**:
- If variability > PARAMETER: Generate equality equations
- If variability ≤ PARAMETER: Generate assertions to check equality at compile time

**Array handling**:
- For array connectors, generate for-loop equations with iterators over array dimensions

**Implementation**: `generatePotentialEquations()` function

### Flow Variable Equations

**Rule**: For a connection set with flow variables {f1, f2, f3}, generate:
```
f1 + f2 + f3 = 0
```

**Sign convention**:
- INSIDE connectors: Positive contribution
- OUTSIDE connectors: Negative contribution (multiplied by -1)

**Physical meaning**: Conservation law (Kirchhoff's current law, mass conservation, etc.)

**Array handling**:
- For array connectors, generate for-loop equations
- Each array element gets its own sum equation

**Implementation**: `generateFlowEquations()` function

### Stream Variable Equations

Stream variables are the most complex connector type. The equations generated depend on the connection topology.

#### Case 1: Unconnected Stream Connector
**Topology**: Single inside connector, no connections
**Equation**: None generated (unconnected)

#### Case 2: Two Inside Connectors
**Topology**: Two inside connectors connected
**Equation**: None generated (both inside)

#### Case 3: Two Outside Connectors
**Topology**: c1 and c2 are both outside connectors
**Equations**:
```
c1 = inStream(c2)
c2 = inStream(c1)
```

#### Case 4: One Inside, One Outside
**Topology**: c1 inside, c2 outside
**Equation**:
```
c1 = c2
```

#### Case 5: General Case (N inside, M outside)
**Topology**: Multiple inside and/or outside connectors

For each outside stream connector, generate:
```
stream_i = (sum(max(flow_j, eps) * inStream(stream_j) for j in outside, j≠i) +
            sum(max(-flow_k, eps) * stream_k for k in inside)) /
           (sum(max(flow_j, eps) for j in outside, j≠i) +
            sum(max(-flow_k, eps) for k in inside))
```

Where:
- `eps` is the flow threshold (configurable via `--flowThreshold`)
- Flow directions are determined by associated flow variables
- The equation represents mixing of streams weighted by flow rates

**Flow association**: Each stream variable must have an associated flow variable in the same connector

**Nominal values**: If a flow has a `nominal` attribute, eps is multiplied by it

**Implementation**: `generateStreamEquations()` and `streamSumEquationExp()` functions

## Special Operators

### inStream(c)

Evaluates to the value the stream variable would have if flow reverses.

**Evaluation rules**:
- Unconnected: `inStream(c) = c`
- Two inside: `inStream(c1) = c2`, `inStream(c2) = c1`
- One inside, one outside: `inStream(c_inside) = inStream(c_outside)`
- General case: Computed using the mixing equation

**Implementation**: `evaluateInStream()` function

### actualStream(c)

Evaluates to the actual stream value considering flow direction.

**Definition**:
```
actualStream(c) = if flow(c) > 0 then inStream(c) else c
```

**Optimization**: If flow direction can be determined at compile time (via min/max attributes):
- If flow always positive: `actualStream(c) = inStream(c)`
- If flow always negative: `actualStream(c) = c`

**Implementation**: `evaluateActualStream()` function

### cardinality(c)

Returns the number of connections to connector c (deprecated in Modelica 3.4+).

**Implementation**: Evaluated using the `CardinalityTable`

## Flow Threshold

The flow threshold (eps) prevents division by zero in stream equations when all flows are zero.

**Configuration**: `--flowThreshold=<value>` (default based on compiler settings)

**Usage**: Used in `max(flow, eps)` calls in stream equations

**Nominal adjustment**: Multiplied by flow's nominal value if available

## Optimization Techniques

### 1. Stream Variable Filtering

Connectors with flow variables that are provably zero are excluded from stream equations:

- **Outside connectors**: Excluded if `max <= 0` (no positive flow possible)
- **Inside connectors**: Excluded if `min >= 0` (no negative flow possible)

**Implementation**: `isNoFlowOutside()` and `isNoFlowInside()` functions

### 2. Flow Direction Analysis

If flow direction can be determined from min/max attributes:
- Simplify `actualStream()` calls
- Eliminate conditional expressions

**Implementation**: `evaluateFlowDirection()` function

### 3. Smooth Wrapping

Expressions like `flow * actualStream(c)` where flow appears in the condition are wrapped with `smooth(0, ...)` for better numerical behavior.

**Implementation**: `evaluateActualStreamMul()` function

## Array Connections

When connecting array connectors, equations are generated for each array element:

**For potential/flow**:
- Use for-loops with iterators over array dimensions
- Each element follows the same rules as scalar connectors

**For streams**:
- More complex handling via `NFArrayConnections` module
- May require expansion of array constructors and reductions

## Expandable Connectors

Expandable connectors have special semantics:

- Automatically add unconnected elements
- Virtual connections for undeclared variables
- Handled by `NFExpandableConnectors` module

## Connection Sets

Before equation generation, connections are organized into **connection sets**:

- Each set contains all connector elements that are directly or transitively connected
- Connection sets are built by `NFConnectionSets` module
- Each set has a consistent connector type (potential, flow, or stream)

## Source Information

Generated equations preserve source information for error reporting:

- Merge source information from all connected elements
- Include connect statement locations
- Used for error messages and debugging

## Flags and Configuration

Several flags affect connect equation generation:

- `--flowThreshold`: Sets epsilon for stream equations (default: see Flags.mo)
- `--exposeLocalIOs`: Exposes local input/output variables (>0 enables)
- Configuration via `Flags.getConfigReal()` and `Flags.getConfigInt()`

## Examples

### Example 1: Simple Electrical Connection

```modelica
connect(R.p, C.p);  // Connect positive pins
```

Generated equations (potential):
```
R.p.v = C.p.v  // Voltage equality
```

Generated equations (flow):
```
R.p.i + C.p.i = 0  // Current sum to zero
```

### Example 2: Three-way Fluid Connection

```modelica
connect(pipe1.port_b, junction.port_a);
connect(pipe2.port_b, junction.port_a);
connect(pipe3.port_a, junction.port_a);
```

For stream variable `h_outflow` (specific enthalpy):
```
junction.port_a.h_outflow = 
  (max(pipe1.port_b.m_flow, eps) * pipe1.port_b.h_outflow +
   max(pipe2.port_b.m_flow, eps) * pipe2.port_b.h_outflow +
   max(-pipe3.port_a.m_flow, eps) * inStream(pipe3.port_a.h_outflow)) /
  (max(pipe1.port_b.m_flow, eps) +
   max(pipe2.port_b.m_flow, eps) +
   max(-pipe3.port_a.m_flow, eps))
```

## Implementation Files

- **NFConnectEquations.mo**: Main equation generation logic
- **NFConnector.mo**: Connector data structure and utilities
- **NFConnections.mo**: Connection management
- **NFConnectionSets.mo**: Connection set building
- **NFArrayConnections.mo**: Array connection handling
- **NFExpandableConnectors.mo**: Expandable connector support
- **NFOCConnectionGraph.mo**: Over-constrained connection graphs (advanced)

## References

- Modelica Language Specification 3.5, Chapter 9: Connectors and Connections
- "Stream Connectors - An Extension of Modelica for Device-Oriented Modeling of Convective Transport Phenomena" (Franke et al., 2009)
