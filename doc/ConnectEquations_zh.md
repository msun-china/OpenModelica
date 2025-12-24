# OpenModelica Connect方程生成规则

## 概述

本文档描述了OpenModelica如何从Modelica的`connect`语句生成方程。这是Modelica语言中实现组件连接的核心机制。

## 连接器变量的三种类型

Modelica连接器变量有三种类型，每种都有不同的方程生成规则：

### 1. 势变量（Potential Variables）

**声明方式**: 无特殊前缀（或使用`input`/`output`）

**物理含义**: 表示在所有连接点必须相等的物理量

**典型例子**: 
- 电压（voltage）
- 压力（pressure）  
- 位置（position）
- 角度（angle）

**方程生成规则**: 
对于n个连接的势变量，生成n-1个相等方程。

**示例**:
```modelica
connector Pin
  Real v;  // 电压（势变量）
  flow Real i;  // 电流（流变量）
end Pin;

model Circuit
  Resistor R1, R2;
equation
  connect(R1.p, R2.p);  // 连接两个引脚
end Circuit;

// 生成的方程：
// R1.p.v = R2.p.v  （电压相等）
```

### 2. 流变量（Flow Variables）

**声明方式**: 使用`flow`前缀

**物理含义**: 表示必须满足守恒定律的物理量（求和为零）

**典型例子**:
- 电流（current）
- 质量流量（mass flow rate）
- 力（force）
- 力矩（torque）

**方程生成规则**: 
所有流变量的和等于零（实现守恒定律）。

**示例**:
```modelica
connector Pin
  Real v;
  flow Real i;  // 流变量
end Pin;

// 三个组件连接到一个节点
connect(R1.p, node);
connect(R2.p, node);  
connect(R3.p, node);

// 生成的方程（基尔霍夫电流定律）：
// R1.p.i + R2.p.i + R3.p.i = 0
```

**符号约定**:
- INSIDE（内部）连接器: 正贡献
- OUTSIDE（外部）连接器: 负贡献（流入组件）

### 3. 流变量（Stream Variables）

**声明方式**: 使用`stream`前缀

**物理含义**: 表示由流携带的强度性质（如温度、浓度等）

**典型例子**:
- 比焓（specific enthalpy）
- 质量分数（mass fraction）
- 温度（temperature）
- 浓度（concentration）

**方程生成规则**: 
根据流动方向和连接拓扑生成复杂的混合方程。

**简单示例**（两个连接器）:
```modelica
connector FluidPort
  Real p;                    // 压力（势变量）
  flow Real m_flow;          // 质量流量（流变量）
  stream Real h_outflow;     // 比焓（流变量）
end FluidPort;

connect(pipe1.port_b, pipe2.port_a);

// 生成的方程：
// pipe1.port_b.h_outflow = inStream(pipe2.port_a.h_outflow);
// pipe2.port_a.h_outflow = pipe1.port_b.h_outflow;
```

**复杂示例**（多路混合）:
当多个流在一个节点混合时，生成基于流量加权平均的混合方程：

```
混合后的性质 = (Σ(流入流量i × 性质i)) / (Σ流入流量)
```

## 连接器面（Connector Face）

每个连接器元素都有一个"面"属性，决定了方程的符号：

- **INSIDE（内部）**: 在组件内部声明的连接器
- **OUTSIDE（外部）**: 组件实例上的连接器

**示例**:
```modelica
model Resistor
  Pin p;  // 内部连接器
  Pin n;  // 内部连接器
end Resistor;

model Circuit
  Resistor R;
  // R.p 和 R.n 从Circuit的角度看是外部连接器
end Circuit;
```

面影响流方程的符号：
- 内部流：正贡献
- 外部流：负贡献（流入组件）

## 特殊操作符

### `inStream(c)`

返回如果流反向时流入组件的流变量值。

**使用场景**:
```modelica
T_in = inStream(port.T);  // 流入的温度
```

**求值规则**:
1. 未连接的连接器: `inStream(c) = c`
2. 两个内部连接器: `inStream(c1) = c2`, `inStream(c2) = c1`
3. 一内一外: `inStream(内部) = inStream(外部)`（递归求值）
4. 一般情况: 使用混合方程计算

### `actualStream(c)`

返回考虑流动方向的实际流变量值。

**定义**:
```modelica
actualStream(c) = if flow(c) > 0 then inStream(c) else c;
```

**编译时优化**:
如果可以从min/max属性确定流向：
- 流量始终为正: `actualStream(c) = inStream(c)`
- 流量始终为负: `actualStream(c) = c`

## 常见连接模式

### 星型连接（多个组件连到一个节点）
```modelica
connect(R1.p, node);
connect(R2.p, node);
connect(R3.p, node);
```
所有电压相等，电流和为零。

### 串联连接（链式）
```modelica
connect(R1.n, R2.p);
connect(R2.n, R3.p);
```
创建电压关系和电流相等。

### 流体混合节点
```modelica
connect(inlet1, junction);
connect(inlet2, junction);
connect(outlet, junction);
```
为流变量（温度、浓度等）生成混合方程。

## 方程生成详细规则

### 势变量方程

**规则**: 将所有连接的势变量等同于第一个。

**变异性处理**:
- 如果变异性 > PARAMETER: 生成相等方程 `x1 = x2`
- 如果变异性 ≤ PARAMETER: 生成断言检查 `assert(x1 == x2)`

**数组处理**:
- 对数组连接器，用for循环包装方程

### 流变量方程

**规则**: 所有流的和等于零。

**符号约定**:
- INSIDE连接器: 正值
- OUTSIDE连接器: 负值

**物理意义**: 守恒定律（基尔霍夫电流定律、质量守恒等）

### 流变量方程

**最复杂的情况**，根据连接拓扑分为几种情况：

1. **未连接**: 不生成方程
2. **两个内部**: 不生成方程
3. **两个外部**: 相互引用inStream
4. **一内一外**: 直接相等
5. **一般情况**: 生成混合方程

**混合方程公式**:
```
stream_i = (Σ(max(flow_j, eps) * inStream(stream_j)) + 
            Σ(max(-flow_k, eps) * stream_k)) /
           (Σ(max(flow_j, eps)) + Σ(max(-flow_k, eps)))
```

其中:
- eps = 流量阈值（防止除零）
- flow_j: 外部连接器的流量
- flow_k: 内部连接器的流量

## 配置选项

### 流量阈值
控制流方程中的epsilon值：
```bash
omc +flowThreshold=1e-7 model.mo
```

### 暴露本地I/O
使内部输入/输出变量可见：
```bash
omc +exposeLocalIOs=1 model.mo
```

## 实现文件

核心实现文件位于 `OMCompiler/Compiler/NFFrontEnd/`:

- **NFConnectEquations.mo**: 主要方程生成逻辑
- **NFConnector.mo**: 连接器数据结构
- **NFConnections.mo**: 连接管理
- **NFConnectionSets.mo**: 连接集构建
- **NFArrayConnections.mo**: 数组连接处理
- **NFExpandableConnectors.mo**: 可扩展连接器支持
- **NFOCConnectionGraph.mo**: 过约束连接图（高级）

## 详细文档

- **实现详情**: `OMCompiler/Compiler/NFFrontEnd/ConnectEquations.md` (英文)
- **快速参考**: `doc/ConnectEquations.md` (英文)
- **源代码**: `OMCompiler/Compiler/NFFrontEnd/NFConnectEquations.mo`
- **Modelica规范**: 第9章 - 连接器和连接

## 测试用例

查看OpenModelica测试套件中的示例：
- `testsuite/flattening/modelica/connectors/`
- `testsuite/simulation/modelica/connectors/`

## 参考文献

1. Modelica语言规范 3.5，第9章
2. "Stream Connectors - An Extension of Modelica for Device-Oriented Modeling" (Franke等，2009)
3. OpenModelica用户指南
