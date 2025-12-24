# OpenModelica Connect Equation Generation

## Quick Reference

This document provides a quick reference for understanding how OpenModelica generates equations from Modelica `connect` statements.

## Connection Types

OpenModelica supports three types of connector variables, each with different equation generation rules:

### 1. Potential Variables

**Declaration**: No special prefix (or `input`/`output`)

**Examples**: 
```modelica
Real voltage;
Real pressure;
input Real angle;
```

**Equation Rule**: All connected potential variables are set equal.

**Example**:
```modelica
// Model
connect(component1.pin, component2.pin);
connect(component2.pin, component3.pin);

// Generated equations
component1.pin.v = component2.pin.v;
component2.pin.v = component3.pin.v;
```

### 2. Flow Variables

**Declaration**: `flow` prefix

**Examples**:
```modelica
flow Real current;
flow Real massFlowRate;
```

**Equation Rule**: Sum of all flows equals zero (conservation law).

**Example**:
```modelica
// Model with 3 connections at a node
connect(pipe1.port, junction.port);
connect(pipe2.port, junction.port);
connect(pipe3.port, junction.port);

// Generated equation (Kirchhoff's law)
pipe1.port.m_flow + pipe2.port.m_flow + pipe3.port.m_flow = 0;
```

**Note**: Sign depends on connector direction (inside/outside).

### 3. Stream Variables

**Declaration**: `stream` prefix

**Examples**:
```modelica
stream Real specificEnthalpy;
stream Real massFraction[nSpecies];
```

**Equation Rule**: Flow-weighted mixing equations.

**Simple Example** (two connectors):
```modelica
connect(pipe1.port_b, pipe2.port_a);

// Generated equation
pipe1.port_b.h_outflow = inStream(pipe2.port_a.h_outflow);
pipe2.port_a.h_outflow = pipe1.port_b.h_outflow;
```

**Complex Example** (junction with multiple flows):
The equation computes the mixed stream property based on flow-weighted average of all incoming streams.

## Special Operators

### `inStream(c)`

Returns the stream value that would flow into the component if flow reverses.

**Usage**:
```modelica
T_in = inStream(port.T);  // Temperature flowing in
```

### `actualStream(c)`

Returns the actual stream value considering flow direction.

**Definition**:
```modelica
actualStream(c) = if flow(c) > 0 then inStream(c) else c;
```

## Connector Face (Inside vs Outside)

- **Inside connector**: Declared within a component
- **Outside connector**: Accessed on a component instance

**Example**:
```modelica
model Resistor
  Pin p;  // Inside connector
  Pin n;  // Inside connector
end Resistor;

model Circuit
  Resistor R;
  // R.p and R.n are outside connectors from Circuit's perspective
end Circuit;
```

The face affects flow signs:
- Inside flows: positive contribution
- Outside flows: negative contribution (entering the component)

## Common Patterns

### Star Connection (multiple components to one node)
```modelica
connect(R1.p, node);
connect(R2.p, node);
connect(R3.p, node);
```
All voltages equal, currents sum to zero.

### Serial Connection (chain)
```modelica
connect(R1.n, R2.p);
connect(R2.n, R3.p);
```
Creates voltage relationships and current equalities.

### Junction with Streams (fluid mixing)
```modelica
connect(inlet1, junction);
connect(inlet2, junction);
connect(outlet, junction);
```
Generates mixing equations for stream variables (temperature, concentration, etc.).

## Advanced Features

### Array Connections
When connecting arrays, equations are generated element-by-element:
```modelica
connect(bus1.signals, bus2.signals);  // If signals is an array
```

### Expandable Connectors
Allow adding elements dynamically based on usage.

### Over-Constrained Connections
Support for graphs with redundant connections (advanced mechanical systems).

## Configuration

### Flow Threshold
Control the epsilon value in stream equations:
```bash
omc +flowThreshold=1e-7 model.mo
```

### Expose Local I/Os
Make internal input/output variables visible:
```bash
omc +exposeLocalIOs=1 model.mo
```

## Detailed Documentation

For implementation details and complete specification:
- **Implementation**: `OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md`
- **Source code**: `OMCompiler/Compiler/NFFrontEnd/NFConnectEquations.mo`
- **Modelica Spec**: Chapter 9 - Connectors and Connections

## Examples Repository

See the OpenModelica testsuite for examples:
- `testsuite/flattening/modelica/connectors/`
- `testsuite/simulation/modelica/connectors/`

## References

1. Modelica Language Specification, Chapter 9
2. "Stream Connectors - An Extension of Modelica" (Franke et al., 2009)
3. OpenModelica User's Guide
