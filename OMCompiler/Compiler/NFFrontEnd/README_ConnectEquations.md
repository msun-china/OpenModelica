# New Front End (NF) - Connect Equation Generation

This directory contains the implementation of connect equation generation for the OpenModelica new front end.

## Connect Equations Documentation

For detailed documentation on how connect equations are generated, see:

- **ConnectEquations.md** - Comprehensive technical documentation of connect equation generation rules and implementation
- **../../doc/ConnectEquations.md** - User-friendly quick reference guide (English)
- **../../doc/ConnectEquations_zh.md** - User-friendly quick reference guide (中文)

## Key Files

### Connection Processing
- **NFConnectEquations.mo** - Main equation generation from connection sets
- **NFConnections.mo** - Connection management and storage
- **NFConnection.mo** - Individual connection representation
- **NFConnectionSets.mo** - Building connection sets from connections
- **NFConnector.mo** - Connector element data structure

### Special Connection Types
- **NFArrayConnections.mo** - Array connection handling
- **NFExpandableConnectors.mo** - Expandable connector support
- **NFOCConnectionGraph.mo** - Over-constrained connection graphs

### Related Modules
- **NFCardinalityTable.mo** - Cardinality operator support (deprecated)

## Connector Types

OpenModelica supports three types of connector variables:

1. **Potential variables** (no prefix) - Must be equal across connections
2. **Flow variables** (`flow` prefix) - Must sum to zero (conservation)
3. **Stream variables** (`stream` prefix) - Flow-weighted mixing equations

See the documentation files for complete rules and examples.

## Quick Example

```modelica
connector Pin
  Real v;              // Potential variable
  flow Real i;         // Flow variable
end Pin;

model Circuit
  Resistor R1, R2;
equation
  connect(R1.p, R2.p);
end Circuit;
```

Generated equations:
```modelica
R1.p.v = R2.p.v;      // Potential equation
R1.p.i + R2.p.i = 0;  // Flow equation
```

## Development

When modifying connect equation generation:

1. Ensure changes comply with Modelica Language Specification Chapter 9
2. Update ConnectEquations.md if rules change
3. Add test cases in testsuite/flattening/modelica/connectors/
4. Run regression tests
