# Connect Equation Documentation Index

This index helps you find the right documentation for understanding connect equation generation in OpenModelica.

## For Users

### Quick Start
- **[Quick Reference (English)](ConnectEquations.md)** - User-friendly guide with examples
- **[快速参考 (中文)](ConnectEquations_zh.md)** - 中文用户友好指南

### What to Read
Start with the quick reference guides above. They explain:
- The three types of connector variables (potential, flow, stream)
- How equations are generated for each type
- Common connection patterns
- Special operators (inStream, actualStream)
- Configuration options

## For Developers

### Implementation Documentation
- **[ConnectEquations.md](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md)** - Comprehensive technical documentation
- **[README_ConnectEquations.md](../OMCompiler/Compiler/NFFrontEnd/README_ConnectEquations.md)** - Developer overview

### Source Code
Primary implementation files in `OMCompiler/Compiler/NFFrontEnd/`:
- **NFConnectEquations.mo** - Main equation generation logic
- **NFConnector.mo** - Connector data structure
- **NFConnections.mo** - Connection management
- **NFConnectionSets.mo** - Connection set building
- **NFArrayConnections.mo** - Array connection handling
- **NFExpandableConnectors.mo** - Expandable connector support
- **NFOCConnectionGraph.mo** - Over-constrained connection graphs

### Test Cases
Examples and test cases in `testsuite/`:
- `testsuite/flattening/modelica/connectors/` - Connector flattening tests
- `testsuite/flattening/modelica/streams/` - Stream connector tests
- `testsuite/simulation/modelica/connectors/` - Connector simulation tests

## Topics Covered

### Basic Concepts
- Connector types: potential, flow, stream
- Connection sets and equation generation
- Connector face (inside vs outside)
- Sign conventions for flow variables

### Advanced Features
- Stream mixing equations
- inStream() and actualStream() operators
- Flow direction analysis and optimization
- Flow threshold configuration
- Array connections
- Expandable connectors
- Over-constrained connection graphs (broken edge handling)

### Configuration
- `--flowThreshold` - Set epsilon for stream equations
- `--exposeLocalIOs` - Expose local input/output variables

## References

1. **Modelica Language Specification**, Chapter 9: Connectors and Connections
2. **"Stream Connectors - An Extension of Modelica"** by Franke, Casella, Sielemann et al., 2009
3. **OpenModelica User's Guide**

## Contributing

When modifying connect equation generation:
1. Update the relevant documentation files
2. Ensure changes comply with the Modelica specification
3. Add test cases in the testsuite
4. Update this index if new files are added

## Quick Links by Topic

| Topic | User Docs | Technical Docs | Source Code |
|-------|-----------|----------------|-------------|
| Potential Variables | [Quick Ref](ConnectEquations.md#1-potential-variables) | [Tech Doc](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md#potential-variable-equations) | NFConnectEquations.mo:222 |
| Flow Variables | [Quick Ref](ConnectEquations.md#2-flow-variables) | [Tech Doc](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md#flow-variable-equations) | NFConnectEquations.mo:400 |
| Stream Variables | [Quick Ref](ConnectEquations.md#3-stream-variables) | [Tech Doc](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md#stream-variable-equations) | NFConnectEquations.mo:478 |
| inStream() | [Quick Ref](ConnectEquations.md#instreamc) | [Tech Doc](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md#instream) | NFConnectEquations.mo:817 |
| actualStream() | [Quick Ref](ConnectEquations.md#actualstreamc) | [Tech Doc](../OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md#actualstream) | NFConnectEquations.mo:986 |

## Version History

- **2024-12**: Initial comprehensive documentation created
  - Added technical documentation (ConnectEquations.md in NFFrontEnd)
  - Added user guides (English and Chinese)
  - Enhanced code comments
  - Created this index

---

**Last Updated**: December 2024  
**Maintained by**: OpenModelica Development Team
