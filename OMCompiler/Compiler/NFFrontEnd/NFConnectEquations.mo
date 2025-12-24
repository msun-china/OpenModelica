/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package NFConnectEquations
" file:        NFConnectEquations.mo
  package:     NFConnectEquations
  description: Functions that generate connect equations from connection sets.

  This module implements the Modelica connection semantics for three types of
  connector variables:
  
  1. Potential variables (no prefix): Generate equality equations
     For n connected elements, generate n-1 equations: x1=x2, x1=x3, ..., x1=xn
  
  2. Flow variables (flow prefix): Generate sum-to-zero equations
     For n connected elements with inside/outside faces, generate:
     flow1 - flow2 + flow3 - ... = 0 (signs depend on connector face)
  
  3. Stream variables (stream prefix): Generate mixing equations
     Complex equations based on flow directions and connection topology.
     See ConnectEquations.md for detailed documentation.

"

public
import Connector = NFConnector;
import DAE;
import ConnectionSets = NFConnectionSets.ConnectionSets;
import Equation = NFEquation;
import CardinalityTable = NFCardinalityTable;
import Variable = NFVariable;

protected
import ComponentReference;
import ComponentRef = NFComponentRef;
import Config;
import ElementSource;
import Expression = NFExpression;
import Face = NFConnector.Face;
import List;
import NFPrefixes.{Variability, Purity, ConnectorType};
import Operator = NFOperator;
import Type = NFType;
import Call = NFCall;
import NFBuiltinFuncs;
import NFInstNode.InstNode;
import Class = NFClass;
import Binding = NFBinding;
import NFFunction.Function;
import Global;
import BuiltinCall = NFBuiltinCall;
import ComplexType = NFComplexType;
import ExpandExp = NFExpandExp;
import Prefixes = NFPrefixes;
import Component = NFComponent;
import Ceval = NFCeval;
import MetaModelica.Dangerous.listReverseInPlace;
import SimplifyExp = NFSimplifyExp;
import UnorderedMap;
import Flatten = NFFlatten;
import Subscript = NFSubscript;
import Structural = NFStructural;

constant Expression EQ_ASSERT_STR =
  Expression.STRING("Connected constants/parameters must be equal");

public
function generateEquations
  "Generates equations for all connection sets.
  
   This is the main entry point for connect equation generation.
   Each connection set is processed based on its connector type:
   - Potential sets: Generate equality equations (x1=x2, x1=x3, ...)
   - Flow sets: Generate sum-to-zero equations (f1+f2+f3=0)
   - Stream sets: Generate mixing equations based on flow directions
   
   See ConnectEquations.md for detailed rules and examples."
  input array<list<Connector>> sets;
  input UnorderedMap<ComponentRef, Variable> variables;
  output list<Equation> equations = {};
  output UnorderedSet<ComponentRef> connectedLocalIOs;
protected
  partial function potFunc
    input list<Connector> elements;
    output list<Equation> equations;
    input output UnorderedSet<ComponentRef> connectedLocalIOs;
  end potFunc;

  list<Equation> set_eql;
  potFunc potfunc;
  Expression flowThreshold;
  ConnectorType.Type cty;
algorithm
  setGlobalRoot(Global.isInStream, NONE());
  connectedLocalIOs := UnorderedSet.new(ComponentRef.hash, ComponentRef.isEqual);
  //potfunc := if Config.orderConnections() then
  //  generatePotentialEquationsOrdered else generatePotentialEquations;
  potfunc := generatePotentialEquations;
  flowThreshold := Expression.REAL(Flags.getConfigReal(Flags.FLOW_THRESHOLD));

  for set in sets loop
    cty := getSetType(set);

    if ConnectorType.isPotential(cty) then
      (set_eql, connectedLocalIOs) := potfunc(set, connectedLocalIOs);
    elseif ConnectorType.isFlow(cty) then
      set_eql := generateFlowEquations(set);
    elseif ConnectorType.isStream(cty) then
      set_eql := generateStreamEquations(set, flowThreshold, variables);
    else
      Error.addInternalError(getInstanceName() + " got connection set with invalid type '" +
        ConnectorType.toDebugString(cty) + "': " +
        List.toString(set, Connector.toString, "", "{", ", ", "}", true), sourceInfo());
      fail();
    end if;

    equations := listAppend(set_eql, equations);
  end for;
end generateEquations;

function evaluateOperators
  input Expression exp;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression evalExp;

  import NFOperator.Op;
algorithm
  evalExp := match exp
    local
      Call call;
      Boolean expanded;

    case Expression.CALL(call = call)
      then match call
        case Call.TYPED_CALL()
          then match Function.name(call.fn)
            case Absyn.IDENT("inStream")
              then evaluateInStream(Expression.toCref(listHead(call.arguments)), sets, setsArray, variables, ctable);
            case Absyn.IDENT("actualStream")
              algorithm
                evalExp :=
                evaluateActualStream(Expression.toCref(listHead(call.arguments)), sets, setsArray, variables, ctable);
              then
                evalExp;
            case Absyn.IDENT("cardinality")
              then CardinalityTable.evaluateCardinality(listHead(call.arguments), ctable);
            else Expression.mapShallow(exp,
              function evaluateOperators(sets = sets, setsArray = setsArray, variables = variables, ctable = ctable));
          end match;

        // inStream/actualStream can't handle non-literal subscripts, so reductions and array
        // constructors containing such calls needs to be expanded to get rid of the iterators.
        case Call.TYPED_REDUCTION()
          guard Expression.contains(call.exp, isStreamCall)
          then evaluateOperatorReductionExp(exp, sets, setsArray, variables, ctable);

        case Call.TYPED_ARRAY_CONSTRUCTOR()
          guard Expression.contains(call.exp, isStreamCall)
          then evaluateOperatorArrayConstructorExp(exp, sets, setsArray, variables, ctable);

        else Expression.mapShallow(exp,
          function evaluateOperators(sets = sets, setsArray = setsArray, variables = variables, ctable = ctable));
      end match;

    case Expression.BINARY(exp1 = Expression.CREF(),
                           operator = Operator.OPERATOR(op = Op.MUL),
                           exp2 = Expression.CALL(call = call as Call.TYPED_CALL()))
      guard AbsynUtil.isNamedPathIdent(Function.name(call.fn), "actualStream")
      then evaluateActualStreamMul(exp.exp1, listHead(call.arguments), exp.operator, sets, setsArray, variables, ctable);

    case Expression.BINARY(exp1 = Expression.CALL(call = call as Call.TYPED_CALL()),
                           operator = Operator.OPERATOR(op = Op.MUL),
                           exp2 = Expression.CREF())
      guard AbsynUtil.isNamedPathIdent(Function.name(call.fn), "actualStream")
      then evaluateActualStreamMul(exp.exp2, listHead(call.arguments), exp.operator, sets, setsArray, variables, ctable);

    else Expression.mapShallow(exp,
      function evaluateOperators(sets = sets, setsArray = setsArray, variables = variables, ctable = ctable));
  end match;
end evaluateOperators;

protected
function getSetType
  input list<Connector> set;
  output ConnectorType.Type cty;
algorithm
  // All connectors in a set should have the same type, so pick the first.
  Connector.CONNECTOR(cty = cty) :: _ := set;
end getSetType;

function generatePotentialEquations
  "Generates equations for a set of potential (non-flow, non-stream) connector variables.
   
   RULE: For a connection set with n potential variables, generate n-1 equality equations
   by equating all variables to the first one.
   
   Example: For set {X, Y.A, Z.B}, generate:
     X = Y.A
     X = Z.B
   
   VARIABILITY HANDLING:
   - If variability > PARAMETER: Generate equality equations (x1 = x2)
   - If variability ≤ PARAMETER: Generate assertion checks (assert(x1 == x2))
     to verify that constant/parameter values are equal at compile time
   
   ARRAY HANDLING:
   - For array connectors, wrap equations in for-loops over array dimensions
   
   LOCAL I/O EXPOSURE:
   - If flag --exposeLocalIOs > 0, collect input/output variables that are
     inside connectors for later processing"
  input list<Connector> elements;
  output list<Equation> equations;
  input output UnorderedSet<ComponentRef> connectedLocalIOs;
protected
  Connector c1;
algorithm
  c1 := listHead(elements);

  if Connector.variability(c1) > Variability.PARAMETER then
    equations := list(makeEqualityEquation(c1.name, c1.source, c2.name, c2.source)
      for c2 in listRest(elements));
    // collect inputs and outputs that are inside in connections if --nonStdExposeLocalIOs > 0
    // strip array indices so that the variables will be found later
    if Flags.getConfigInt(Flags.EXPOSE_LOCAL_IOS) > 0 then
      for c in elements loop
        if (Connector.isInside(c) and (ComponentRef.isInput(c.name) or ComponentRef.isOutput(c.name))) then
          UnorderedSet.add(ComponentRef.stripSubscripts(c.name), connectedLocalIOs);
        end if;
      end for;
    end if;
  else
    // don't create asserts for empty arrays
    if Type.isEmptyArray(c1.ty) then
      equations := {};
    else
      equations := list(makeEqualityAssert(c1.name, c1.source, c2.name, c2.source)
        for c2 in listRest(elements));
    end if;
  end if;
end generatePotentialEquations;

//function generatePotentialEquationsOrdered
//  "Like generatePotentialEquations, but orders the connectors with
//   shouldFlipPotentialEquation."
//  input list<Connector> elements;
//  output list<Equation> equations = {};
//protected
//  partial function eqFunc
//    input ComponentRef lhsCref;
//    input DAE.ElementSource lhsSource;
//    input ComponentRef rhsCref;
//    input DAE.ElementSource rhsSource;
//    output Equation eq;
//  end eqFunc;
//
//  Connector c1;
//  ComponentRef cr1, cr2;
//  DAE.ElementSource source;
//  eqFunc eqfunc;
//algorithm
//  if listEmpty(elements) then
//    return;
//  end if;
//
//  c1 := listHead(elements);
//  eqfunc := if Connector.variability(c1) > Variability.PARAMETER then
//    makeEqualityEquation else makeEqualityAssert;
//
//  cr1 := c1.name;
//
//  for c2 in listRest(elements) loop
//    cr2 := c2.name;
//    (cr1, cr2) := Util.swap(shouldFlipPotentialEquation(cr1, c1.source), cr1, cr2);
//    equations := eqfunc(cr1, c2.source, cr2, c2.source) :: equations;
//    c1 := c2;
//    cr1 := cr2;
//  end for;
//end generatePotentialEquationsOrdered;

function makeEqualityEquation
  input ComponentRef lhsCref;
  input DAE.ElementSource lhsSource;
  input ComponentRef rhsCref;
  input DAE.ElementSource rhsSource;
  output Equation equalityEq;
protected
  DAE.ElementSource source;
algorithm
  source := ElementSource.mergeSources(lhsSource, rhsSource);
  //source := ElementSource.addElementSourceConnect(source, (lhsCref, rhsCref));
  equalityEq := Equation.makeCrefEquality(lhsCref, rhsCref, InstNode.EMPTY_NODE(), source);
end makeEqualityEquation;

function makeEqualityAssert
  input ComponentRef lhsCref;
  input DAE.ElementSource lhsSource;
  input ComponentRef rhsCref;
  input DAE.ElementSource rhsSource;
  output Equation equalityAssert;
protected
  DAE.ElementSource source;
  Expression lhs_exp, rhs_exp, exp;
  Type ty, elem_ty;
  list<InstNode> iterators = {};
  list<Expression> ranges;
  list<Subscript> subs;
algorithm
  source := ElementSource.mergeSources(lhsSource, rhsSource);
  //source := ElementSource.addElementSourceConnect(source, (lhsCref, rhsCref));

  ty := ComponentRef.getSubscriptedType(lhsCref);

  // if the type is array, get subscripts and add them to the cref
  // use the iterators and ranges later to generate the for loop
  if Type.isArray(ty) then
    (iterators, ranges, subs) := Flatten.makeIterators(lhsCref, Type.arrayDims(ty));
    subs := listReverseInPlace(subs);
    lhs_exp := Expression.fromCref(ComponentRef.mergeSubscripts(subs, lhsCref));
    rhs_exp := Expression.fromCref(ComponentRef.mergeSubscripts(subs, rhsCref));
  else
    lhs_exp := Expression.fromCref(lhsCref);
    rhs_exp := Expression.fromCref(rhsCref);
  end if;

  elem_ty := Type.arrayElementType(ty);
  if Type.isReal(elem_ty) then
    // Modelica doesn't allow == for Reals, so to keep the flat Modelica
    // somewhat valid we use 'abs(lhs - rhs) <= 0' instead.
    exp := Expression.BINARY(lhs_exp, Operator.makeSub(elem_ty), rhs_exp);
    exp := Expression.CALL(Call.makeTypedCall(NFBuiltinFuncs.ABS_REAL, {exp}, Expression.variability(exp), Purity.PURE));
    exp := Expression.RELATION(exp, Operator.makeLessEq(elem_ty), Expression.REAL(0.0));
  else
    // For any other type, generate assertion for 'lhs == rhs'.
    exp := Expression.RELATION(lhs_exp, Operator.makeEqual(elem_ty), rhs_exp);
  end if;

  equalityAssert := Equation.ASSERT(exp, EQ_ASSERT_STR, NFBuiltin.ASSERTIONLEVEL_ERROR, InstNode.EMPTY_NODE(), source);

  // wrap the equation in for loop if necessary
  while not listEmpty(iterators) loop
    equalityAssert := Equation.FOR(listHead(iterators), SOME(listHead(ranges)), {equalityAssert}, InstNode.EMPTY_NODE(), source);
    iterators := listRest(iterators);
    ranges := listRest(ranges);
  end while;
end makeEqualityAssert;

//protected function shouldFlipPotentialEquation
//  "If the flag +orderConnections=false is used, then we should keep the order of
//   the connector elements as they occur in the connection (if possible). In that
//   case we check if the cref of the first argument to the first connection
//   stored in the element source is a prefix of the connector element cref. If
//   it isn't, indicate that we should flip the generated equation."
//  input DAE.ComponentRef lhsCref;
//  input DAE.ElementSource lhsSource;
//  output Boolean shouldFlip;
//algorithm
//  shouldFlip := match lhsSource
//    local
//      DAE.ComponentRef lhs;
//
//    case DAE.SOURCE(connectEquationOptLst = (lhs, _) :: _)
//      then not ComponentReference.crefPrefixOf(lhs, lhsCref);
//
//    else false;
//  end match;
//end shouldFlipPotentialEquation;

function generateFlowEquations
  "Generates sum-to-zero equation for a set of flow connector variables.
   
   RULE: For a connection set with flow variables, generate a single equation
   that sums all flows to zero, applying sign conventions based on connector face.
   
   SIGN CONVENTION:
   - INSIDE connectors: Positive contribution (+flow)
   - OUTSIDE connectors: Negative contribution (-flow)
   
   Example: For connection set {f1(inside), f2(outside), f3(inside)}:
     f1 - f2 + f3 = 0
   
   PHYSICAL MEANING:
   This implements conservation laws (Kirchhoff's current law for electrical,
   mass conservation for fluid, force/torque balance for mechanical).
   
   ARRAY HANDLING:
   - For array connectors, wrap equation in for-loops over array dimensions
   - Each array element gets its own sum equation"
  input list<Connector> elements;
  output list<Equation> equations;
protected
  Connector c;
  list<Connector> c_rest;
  DAE.ElementSource src;
  Expression sum;
  list<InstNode> iterators = {};
  list<Expression> ranges = {};
  list<Subscript> subs = {};
  Equation eq;
algorithm
  c :: c_rest := elements;
  src := c.source;

  if Connector.isArray(c) then
    (iterators, ranges, subs) := Flatten.makeIterators(c.name, Type.arrayDims(c.ty));
    subs := listReverseInPlace(subs);
    c :: c_rest := list(Connector.addSubscripts(subs, e) for e in elements);
  end if;

  if listEmpty(c_rest) then
    sum := Expression.fromCref(c.name);
  else
    sum := makeFlowExp(c);

    for e in c_rest loop
      sum := Expression.BINARY(sum, Operator.makeAdd(Type.REAL()), makeFlowExp(e));
      src := ElementSource.mergeSources(src, e.source);
    end for;
  end if;

  equations := {Equation.EQUALITY(sum, Expression.REAL(0.0), Type.arrayElementType(c.ty), InstNode.EMPTY_NODE(), src)};

  while not listEmpty(iterators) loop
    equations := {Equation.FOR(listHead(iterators), SOME(listHead(ranges)), equations, InstNode.EMPTY_NODE(), src)};
    iterators := listRest(iterators);
    ranges := listRest(ranges);
  end while;
end generateFlowEquations;

function makeFlowExp
  "Creates an expression from a connector element, which is the element itself
   if it's an inside connector, or the element negated if it's outside."
  input Connector element;
  output Expression exp;
protected
  Face face;
algorithm
  exp := Expression.fromCref(element.name);

  // TODO: Remove unnecessary variable 'face' once #4502 is fixed.
  face := element.face;
  if face == Face.OUTSIDE then
    exp := Expression.UNARY(Operator.makeUMinus(Type.REAL()), exp);
  end if;
end makeFlowExp;

function generateStreamEquations
  "Generates equations for a stream connection set.
   
   Stream variables represent intensive properties (like temperature, concentration)
   that are transported by flows. The equations generated depend on the connection
   topology and flow directions.
   
   CONNECTION CASES:
   
   1. Unconnected (single inside, no outside):
      No equation generated
   
   2. Two inside connectors:
      No equation generated (both inside same component)
   
   3. Two outside connectors (c1, c2):
      c1 = inStream(c2)
      c2 = inStream(c1)
   
   4. One inside, one outside (c_in, c_out):
      c_in = c_out
   
   5. General case (N inside, M outside):
      For each outside connector, generate mixing equation that computes
      the mixed stream value based on all incoming flows:
      
      stream_i = (sum(max(flow_j, eps)*inStream(stream_j) for j≠i in outside) +
                  sum(max(-flow_k, eps)*stream_k for k in inside)) /
                 (sum(max(flow_j, eps) for j≠i in outside) +
                  sum(max(-flow_k, eps) for k in inside))
      
      where eps is the flow threshold to prevent division by zero.
   
   FLOW ASSOCIATION:
   Each stream variable must have an associated flow variable in the same
   connector that determines the flow direction and magnitude.
   
   OPTIMIZATION:
   Connectors with provably zero flow (based on min/max attributes) are
   excluded from the equations to simplify the result."
  input list<Connector> elements;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output list<Equation> equations;
protected
  ComponentRef cr1, cr2;
  DAE.ElementSource src, src1, src2;
  Expression cref1, cref2, e1, e2;
  list<Connector> inside, outside;
  Variability var1, var2;
algorithm
  (outside, inside) := List.splitOnTrue(elements, Connector.isOutside);
  inside := list(s for s guard not isNoFlowInside(s, variables) in inside);

  equations := match (inside, outside)
    // Unconnected stream connector, do nothing.
    case ({_}, {}) then {};

    // Both inside, do nothing.
    case ({_, _}, {}) then {};

    // Both outside:
    // cr1 = inStream(cr2);
    // cr2 = inStream(cr1);
    case ({}, {Connector.CONNECTOR(name = cr1, source = src1),
               Connector.CONNECTOR(name = cr2, source = src2)})
      algorithm
        cref1 := Expression.fromCref(cr1);
        cref2 := Expression.fromCref(cr2);
        e1 := makeInStreamCall(cref2);
        e2 := makeInStreamCall(cref1);
        src := ElementSource.mergeSources(src1, src2);
      then
        {Equation.EQUALITY(cref1, e1, Type.REAL(), InstNode.EMPTY_NODE(), src),
         Equation.EQUALITY(cref2, e2, Type.REAL(), InstNode.EMPTY_NODE(), src)};

    // One inside, one outside:
    // cr1 = cr2;
    case ({Connector.CONNECTOR(name = cr1, source = src1)},
          {Connector.CONNECTOR(name = cr2, source = src2)})
      algorithm
        src := ElementSource.mergeSources(src1, src2);
      then
        {Equation.makeCrefEquality(cr1, cr2, InstNode.EMPTY_NODE(), src)};

    // The general case with N inside connectors and M outside:
    else streamEquationGeneral(outside, inside, flowThreshold, variables);

  end match;
end generateStreamEquations;

function streamEquationGeneral
  "Generates an equation for an outside stream connector element."
  input list<Connector> outsideElements;
  input list<Connector> insideElements;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output list<Equation> equations = {};
protected
  list<Connector> reduced_outside, outside;
  Expression cref_exp, res;
  DAE.ElementSource src;
algorithm
  reduced_outside := list(s for s guard not isNoFlowOutside(s, variables) in outsideElements);

  for e in outsideElements loop
    cref_exp := Expression.fromCref(e.name);
    outside := removeStreamSetElement(e.name, reduced_outside);

    if listEmpty(outside) and listEmpty(insideElements) then
      res := Expression.INTEGER(0);
    else
      res := streamSumEquationExp(outside, insideElements, flowThreshold, variables);
    end if;

    src := ElementSource.addAdditionalComment(e.source, " equation generated from stream connection");
    equations := Equation.EQUALITY(cref_exp, res, Type.REAL(), InstNode.EMPTY_NODE(), src) :: equations;
  end for;
end streamEquationGeneral;

function streamSumEquationExp
  "Generates the sum expression used by stream connector equations.
   
   This implements the mixing equation for stream variables based on flow-weighted
   averaging of the incoming streams.
   
   FORMULA:
   Given M outside connectors and N inside connectors, generate:
   
     (sum(max(flow_i, eps) * inStream(stream_i) for i in M) +
      sum(max(-flow_j, eps) * stream_j for j in N)) /
     (sum(max(flow_i, eps) for i in M) +
      sum(max(-flow_j, eps) for j in N))
   
   where eps = flowThreshold (prevents division by zero)
   
   PHYSICAL INTERPRETATION:
   This computes the mixed stream property value based on the mass-flow-weighted
   average of all incoming streams. For example, if two streams with different
   temperatures mix, the result is the flow-weighted average temperature.
   
   FLOW THRESHOLD (eps):
   - Default value from --flowThreshold flag
   - Multiplied by flow's nominal value if available
   - Ensures numerical stability when all flows are near zero
   
   OPTIMIZATION:
   Connectors with provably zero flow (from min/max attributes) are filtered
   out before equation generation to simplify the result."
  input list<Connector> outsideElements;
  input list<Connector> insideElements;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression sumExp;
protected
  Expression outside_sum1, outside_sum2, inside_sum1, inside_sum2, res;
algorithm
  if listEmpty(outsideElements) then
    // No outside components.
    inside_sum1 := sumMap(insideElements, sumInside1, flowThreshold, variables);
    inside_sum2 := sumMap(insideElements, sumInside2, flowThreshold, variables);
    sumExp := Expression.BINARY(inside_sum1, Operator.makeDiv(Type.REAL()), inside_sum2);
  elseif listEmpty(insideElements) then
    // No inside components.
    outside_sum1 := sumMap(outsideElements, sumOutside1, flowThreshold, variables);
    outside_sum2 := sumMap(outsideElements, sumOutside2, flowThreshold, variables);
    sumExp := Expression.BINARY(outside_sum1, Operator.makeDiv(Type.REAL()), outside_sum2);
  else
    // Both outside and inside components.
    outside_sum1 := sumMap(outsideElements, sumOutside1, flowThreshold, variables);
    outside_sum2 := sumMap(outsideElements, sumOutside2, flowThreshold, variables);
    inside_sum1 := sumMap(insideElements, sumInside1, flowThreshold, variables);
    inside_sum2 := sumMap(insideElements, sumInside2, flowThreshold, variables);
    sumExp := Expression.BINARY(
      Expression.BINARY(outside_sum1, Operator.makeAdd(Type.REAL()), inside_sum1),
      Operator.makeDiv(Type.REAL()),
      Expression.BINARY(outside_sum2, Operator.makeAdd(Type.REAL()), inside_sum2));
  end if;
end streamSumEquationExp;

function sumMap
  "Creates a sum expression by applying the given function on the list of
  elements and summing up the resulting expressions."
  input list<Connector> elements;
  input FuncType func;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression exp;

  partial function FuncType
    input Connector element;
    input Expression flowThreshold;
    input UnorderedMap<ComponentRef, Variable> variables;
    output Expression exp;
  end FuncType;
algorithm
  exp := func(listHead(elements), flowThreshold, variables);
  for e in listRest(elements) loop
    exp := Expression.BINARY(func(e, flowThreshold, variables), Operator.makeAdd(Type.REAL()), exp);
  end for;
end sumMap;

function streamFlowExp
  "Returns the stream and flow component in a stream set element as expressions."
  input Connector element;
  output Expression streamExp;
  output Expression flowExp;
protected
  ComponentRef stream_cr;
algorithm
  stream_cr := Connector.name(element);
  streamExp := Expression.fromCref(stream_cr);
  flowExp := Expression.fromCref(associatedFlowCref(stream_cr));
end streamFlowExp;

function flowExp
  "Returns the flow component in a stream set element as an expression."
  input Connector element;
  output Expression flowExp;
protected
  ComponentRef flow_cr;
algorithm
  flow_cr := associatedFlowCref(Connector.name(element));
  flowExp := Expression.fromCref(flow_cr);
end flowExp;

function sumOutside1
  "Helper function to streamSumEquationExp. Returns the expression
    max(flow_exp, eps) * inStream(stream_exp)
   given a stream set element."
  input Connector element;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression exp;
protected
  Expression stream_exp, flow_exp;
algorithm
  (stream_exp, flow_exp) := streamFlowExp(element);
  exp := Expression.BINARY(makePositiveMaxCall(flow_exp, element, flowThreshold, variables),
    Operator.makeMul(Type.REAL()), makeInStreamCall(stream_exp));
end sumOutside1;

function sumInside1
  "Helper function to streamSumEquationExp. Returns the expression
    max(-flow_exp, eps) * stream_exp
   given a stream set element."
  input Connector element;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression exp;
protected
  Expression stream_exp, flow_exp, flow_threshold;
algorithm
  (stream_exp, flow_exp) := streamFlowExp(element);
  flow_exp := Expression.UNARY(Operator.makeUMinus(Type.REAL()), flow_exp);
  exp := Expression.BINARY(makePositiveMaxCall(flow_exp, element, flowThreshold, variables),
    Operator.makeMul(Type.REAL()), stream_exp);
end sumInside1;

function sumOutside2
  "Helper function to streamSumEquationExp. Returns the expression
    max(flow_exp, eps)
   given a stream set element."
  input Connector element;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression exp;
protected
  Expression flow_exp;
algorithm
  flow_exp := flowExp(element);
  exp := makePositiveMaxCall(flow_exp, element, flowThreshold, variables);
end sumOutside2;

function sumInside2
  "Helper function to streamSumEquationExp. Returns the expression
    max(-flow_exp, eps)
   given a stream set element."
  input Connector element;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression exp;
protected
  Expression flow_exp;
algorithm
  flow_exp := flowExp(element);
  flow_exp := Expression.UNARY(Operator.makeUMinus(Type.REAL()), flow_exp);
  exp := makePositiveMaxCall(flow_exp, element, flowThreshold, variables);
end sumInside2;

function makeInStreamCall
  "Creates an inStream call expression."
  input Expression streamExp;
  output Expression inStreamCall;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  inStreamCall := Expression.CALL(Call.makeTypedCall(
    NFBuiltinFuncs.IN_STREAM, {streamExp}, Expression.variability(streamExp), Purity.PURE));
end makeInStreamCall;

function makePositiveMaxCall
  "Generates a max(flow_exp, eps) call for stream equations.
   
   PURPOSE:
   Ensures that the flow term is always positive (or at least eps) to prevent
   division by zero in stream mixing equations and to handle flow reversal.
   
   NOMINAL VALUE ADJUSTMENT:
   If the associated flow variable has a 'nominal' attribute, multiply the
   threshold by it:
     max(flow_exp, eps * nominal)
   
   This scaling ensures that the threshold is appropriate for the magnitude
   of the flow variable.
   
   GLOBAL FLAG:
   Sets global flag indicating we're inside a stream equation, which affects
   how certain expressions are processed."
  input Expression flowExp;
  input Connector element;
  input Expression flowThreshold;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Expression positiveMaxCall;
protected
  //InstNode flow_node;
  ComponentRef flow_name;
  Option<Expression> nominal_oexp;
  Expression nominal_exp, flow_threshold;
algorithm
  flow_name := associatedFlowCref(Connector.name(element));
  nominal_oexp := lookupVarAttr(flow_name, "nominal", variables);

  if isSome(nominal_oexp) then
    SOME(nominal_exp) := nominal_oexp;
    flow_threshold := Expression.BINARY(flowThreshold, Operator.makeMul(Type.REAL()), nominal_exp);
  else
    flow_threshold := flowThreshold;
  end if;

  positiveMaxCall := Expression.CALL(Call.makeTypedCall(NFBuiltinFuncs.POSITIVE_MAX_REAL,
    {flowExp, flow_threshold}, Connector.variability(element), Purity.PURE));

  setGlobalRoot(Global.isInStream, SOME(true));
end makePositiveMaxCall;

function isStreamCall
  input Expression exp;
  output Boolean streamCall;
algorithm
  streamCall := match exp
    local
      String name;

    case Expression.CALL()
      then match Function.name(Call.typedFunction(exp.call))
        case Absyn.IDENT("inStream") then true;
        case Absyn.IDENT("actualStream") then true;
        else false;
      end match;

    else false;
  end match;
end isStreamCall;

function evaluateOperatorReductionExp
  input Expression exp;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression evalExp;
protected
  Call call;
  Function fn;
  Type ty;
  Expression arg, iter_exp;
  list<tuple<InstNode, Expression>> iters = {};
  InstNode iter_node;
algorithm
  evalExp := match exp
    case Expression.CALL(call = call as Call.TYPED_REDUCTION())
      algorithm
        ty := Expression.typeOf(call.exp);

        for iter in call.iters loop
          (iter_node, iter_exp) := iter;

          if Component.variability(InstNode.component(iter_node)) > Variability.PARAMETER then
            print("Iteration range in reduction containing connector operator calls must be a parameter expression.");
            fail();
          end if;

          iter_exp := Ceval.evalExp(iter_exp);
          ty := Type.liftArrayLeftList(ty, Type.arrayDims(Expression.typeOf(iter_exp)));
          iters := (iter_node, iter_exp) :: iters;
        end for;

        iters := listReverseInPlace(iters);
        arg := ExpandExp.expandArrayConstructor(call.exp, ty, iters);
      then
        Expression.CALL(Call.makeTypedCall(call.fn, {arg}, call.var, Purity.PURE, call.ty));

  end match;

  evalExp := evaluateOperators(evalExp, sets, setsArray, variables, ctable);
end evaluateOperatorReductionExp;

function evaluateOperatorArrayConstructorExp
  input Expression exp;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression evalExp;
protected
  Boolean expanded;
algorithm
  (evalExp, expanded) := ExpandExp.expand(exp);

  if not expanded then
    Error.addInternalError(getInstanceName() +
      " failed to expand call containing stream operator: " +
      Expression.toString(exp), sourceInfo());
  end if;

  evalExp := evaluateOperators(evalExp, sets, setsArray, variables, ctable);
end evaluateOperatorArrayConstructorExp;

function evaluateInStream
  "Evaluates the inStream operator with the given cref as argument.
   
   The inStream(c) operator returns the value that the stream variable c
   would have if the flow were reversed (flowing into the component).
   
   EVALUATION RULES:
   
   1. Unconnected connector (single inside, no connections):
      inStream(c) = c
   
   2. Two inside connectors (c1, c2):
      inStream(c1) = c2
      inStream(c2) = c1
   
   3. One inside, one outside (different faces):
      inStream(c_inside) = inStream(c_outside)
      (recursively evaluate the outside connector)
   
   4. General case (multiple connectors):
      Compute mixing equation considering all connected streams
      weighted by their flow rates (see generateInStreamExp)
   
   This function is called during expression evaluation when inStream()
   appears in the model equations."
  input ComponentRef cref;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression exp;
protected
  Connector c;
  list<Connector> sl;
  Integer set;
  ComponentRef cr;
algorithm
  cr := ComponentRef.evaluateSubscripts(cref);
  c := Connector.CONNECTOR(cr, Type.UNKNOWN(), Face.INSIDE,
    ConnectorType.STREAM, DAE.emptyElementSource);

  try
    set := ConnectionSets.findSetArrayIndex(c, sets);
    sl := arrayGet(setsArray, set);
  else
    sl := {c};
  end try;

  exp := generateInStreamExp(cr, sl, sets, setsArray, variables, ctable,
    Flags.getConfigReal(Flags.FLOW_THRESHOLD));
end evaluateInStream;

function generateInStreamExp
  "Helper function to evaluateInStream. Generates an expression for inStream
   given a connection set."
  input ComponentRef streamCref;
  input list<Connector> streams;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  input Real flowThreshold;
  output Expression exp;
protected
  list<Connector> reducedStreams, inside, outside;
  ComponentRef cr;
  Face f1, f2;
algorithm
  reducedStreams := list(s for s guard not isNoFlowMinMax(s, streamCref, variables) in streams);

  exp := match reducedStreams
    // Unconnected stream connector:
    //   inStream(c) = c;
    case {Connector.CONNECTOR(face = Face.INSIDE)}
      then Expression.fromCref(streamCref);

    // Two inside connected stream connectors:
    //   inStream(c1) = c2;
    //   inStream(c2) = c1;
    case {Connector.CONNECTOR(face = Face.INSIDE),
          Connector.CONNECTOR(face = Face.INSIDE)}
      algorithm
        {Connector.CONNECTOR(name = cr)} :=
          removeStreamSetElement(streamCref, reducedStreams);
      then
        Expression.fromCref(cr);

    // One inside, one outside connected stream connector:
    //   inStream(c1) = inStream(c2);
    case {Connector.CONNECTOR(face = f1),
          Connector.CONNECTOR(face = f2)} guard f1 <> f2
      algorithm
        {Connector.CONNECTOR(name = cr)} :=
          removeStreamSetElement(streamCref, reducedStreams);
      then
        evaluateInStream(cr, sets, setsArray, variables, ctable);

    // The general case:
    else
      algorithm
        (outside, inside) := List.splitOnTrue(reducedStreams, Connector.isOutside);
        inside := removeStreamSetElement(streamCref, inside);
        exp := streamSumEquationExp(outside, inside, Expression.REAL(flowThreshold), variables);
        // Evaluate any inStream calls that were generated.
        exp := evaluateOperators(exp, sets, setsArray, variables, ctable);
      then
        exp;

  end match;
end generateInStreamExp;

function isNoFlowMinMax
  "Returns true if the given flow attribute of a connector is zero."
  input Connector conn;
  input ComponentRef streamCref;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Boolean noFlow;
algorithm
  if ComponentRef.isEqual(streamCref, conn.name) then
    noFlow := false;
  elseif Connector.isOutside(conn) then
    noFlow := isNoFlowOutside(conn, variables);
  else
    noFlow := isNoFlowInside(conn, variables);
  end if;
end isNoFlowMinMax;

function isNoFlowOutside
  "Returns true if the given outside stream connector has no flow, which occurs
   when its max attribute <= 0."
  input Connector conn;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Boolean noFlow;
algorithm
  noFlow := isNoFlow(conn, "max", Expression.isNonPositive, variables);
end isNoFlowOutside;

function isNoFlowInside
  "Returns true if the given inside stream connector has no flow, which occurs
   when its min attribute >= 0."
  input Connector conn;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Boolean noFlow;
algorithm
  noFlow := isNoFlow(conn, "min", Expression.isNonNegative, variables);
end isNoFlowInside;

function isNoFlow
  "Returns true if a given stream connector has no flow."
  input Connector element;
  input String attr;
  input FlowPred pred;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Boolean noFlow;

  partial function FlowPred
    input Expression exp;
    output Boolean res;
  end FlowPred;
protected
  ComponentRef flow_name;
  Option<Expression> attr_oexp;
  Expression attr_exp;
  Variability var;
algorithm
  flow_name := Expression.toCref(flowExp(element));
  attr_oexp := lookupVarAttr(flow_name, attr, variables);

  if isSome(attr_oexp) then
    SOME(attr_exp) := attr_oexp;
    var := Expression.variability(attr_exp);

    if var == Variability.PARAMETER and not Structural.isExpressionNotFixed(attr_exp) then
      Structural.markExp(attr_exp);
      var := Variability.STRUCTURAL_PARAMETER;
    end if;

    if var <= Variability.STRUCTURAL_PARAMETER then
      attr_exp := Ceval.evalExp(attr_exp);
    end if;

    noFlow := pred(attr_exp);
  else
    noFlow := false;
  end if;
end isNoFlow;

protected function evaluateActualStream
  "Evaluates the actualStream operator for a component reference.
   
   The actualStream(c) operator returns the actual value of the stream variable
   considering the flow direction:
   
   DEFINITION:
     actualStream(c) = if flow(c) > 0 then inStream(c) else c
   
   COMPILE-TIME OPTIMIZATION:
   If the flow direction can be determined at compile time from min/max attributes:
   - If flow always positive (min >= 0): actualStream(c) = inStream(c)
   - If flow always negative (max <= 0): actualStream(c) = c
   - Otherwise: Generate the full if-expression
   
   ASSOCIATED FLOW:
   The function identifies the associated flow variable in the same connector
   to determine the flow direction.
   
   Returns both the evaluated expression and the flow cref for further processing."
  input ComponentRef streamCref;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression exp;
  output ComponentRef flowCref;
protected
  ComponentRef stream_cref;
  Integer flow_dir;
  Expression flow_exp, stream_exp, instream_exp;
  Operator op;
algorithm
  stream_cref := ComponentRef.evaluateSubscripts(streamCref);
  flowCref := associatedFlowCref(stream_cref);
  flow_dir := evaluateFlowDirection(flowCref, variables);

  // Select a branch if we know the flow direction, otherwise generate the whole
  // if-equation.
  if flow_dir == 1 then
    exp := evaluateInStream(stream_cref, sets, setsArray, variables, ctable);
  elseif flow_dir == -1 then
    exp := Expression.fromCref(stream_cref);
  else
    // actualStream(stream_var) = if flow_var > 0 then inStream(stream_var) else stream_var);
    flow_exp := Expression.fromCref(flowCref);
    stream_exp := Expression.fromCref(stream_cref);
    instream_exp := evaluateInStream(stream_cref, sets, setsArray, variables, ctable);
    op := Operator.makeGreater(ComponentRef.nodeType(flowCref));

    exp := Expression.IF(
      Type.REAL(),
      Expression.RELATION(flow_exp, op, Expression.REAL(0.0)),
      instream_exp, stream_exp);
  end if;
end evaluateActualStream;

function evaluateActualStreamMul
  "Handles expressions on the form flowCref * actualStream(streamCref) where
   flowCref is associated with streamCref."
  input Expression crefExp;
  input Expression actualStreamArg;
  input Operator op;
  input ConnectionSets.Sets sets;
  input array<list<Connector>> setsArray;
  input UnorderedMap<ComponentRef, Variable> variables;
  input CardinalityTable.Table ctable;
  output Expression outExp;
protected
  Expression e1, e2;
  ComponentRef cr, flow_cr;
algorithm
  e1 as Expression.CREF(cref = cr) := evaluateOperators(crefExp, sets, setsArray, variables, ctable);
  (e2, flow_cr) := evaluateActualStream(Expression.toCref(actualStreamArg), sets, setsArray, variables, ctable);
  outExp := Expression.BINARY(e1, op, e2);

  // Wrap the expression in smooth if the result would be flow_cr * (if flow_cr > 0 then ...)
  outExp := match e2
    case Expression.IF() guard ComponentRef.isEqual(cr, flow_cr) then makeSmoothCall(outExp, 0);
    else outExp;
  end match;
end evaluateActualStreamMul;

function evaluateFlowDirection
  input ComponentRef flowCref;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Integer direction = 0;
protected
  Option<Expression> omin, omax;
  Real min_val, max_val;
algorithm
  omin := lookupVarAttr(flowCref, "min", variables);
  omin := SimplifyExp.simplifyOpt(omin);
  omax := lookupVarAttr(flowCref, "max", variables);
  omax := SimplifyExp.simplifyOpt(omax);

  direction := match (omin, omax)
    // No attributes, flow direction can't be decided.
    case (NONE(), NONE()) then 0;
    // Flow is positive if min is positive.
    case (SOME(Expression.REAL(min_val)), NONE())
      then if min_val >= 0 then 1 else 0;
    // Flow is negative if max is negative.
    case (NONE(), SOME(Expression.REAL(max_val)))
      then if max_val <= 0 then -1 else 0;
    // Flow is positive if both min and max are positive, negative if they are
    // both negative, otherwise undecideable.
    case (SOME(Expression.REAL(min_val)), SOME(Expression.REAL(max_val)))
      then
        if min_val >= 0 and max_val >= min_val then 1
        elseif max_val <= 0 and min_val <= max_val then -1
        else 0;
    // Flow is undecideable if either attribute is not a constant Real value.
    else 0;
  end match;
end evaluateFlowDirection;

function makeSmoothCall
  "Creates a smooth(order, arg) call."
  input Expression arg;
  input Integer order;
  output Expression callExp;
algorithm
  callExp := Expression.CALL(Call.makeTypedCall(NFBuiltinFuncs.SMOOTH,
    {Expression.INTEGER(order), arg}, Expression.variability(arg), Purity.PURE));
end makeSmoothCall;

protected function removeStreamSetElement
  "This function removes the given cref from a connection set."
  input ComponentRef cref;
  input output list<Connector> elements;
algorithm
  elements := List.deleteMemberOnTrue(cref, elements, compareCrefStreamSet);
end removeStreamSetElement;

protected function compareCrefStreamSet
  "Helper function to removeStreamSetElement. Checks if the cref in a stream set
  element matches the given cref."
  input ComponentRef cref;
  input Connector element;
  output Boolean matches;
algorithm
  matches := ComponentRef.isEqual(cref, element.name);
end compareCrefStreamSet;

function associatedFlowCref
  "Returns the flow cref that's declared in the same connector as the given
   stream cref."
  input ComponentRef streamCref;
  output ComponentRef flowCref;
protected
  Type ty;
  ComponentRef rest_cr;
  InstNode flow_node;
algorithm
  ComponentRef.CREF(ty = ty, restCref = rest_cr) := streamCref;

  flowCref := match Type.arrayElementType(ty)
    // A connector with a single flow, append the flow node to the cref and return it.
    case Type.COMPLEX(complexTy = ComplexType.CONNECTOR(flows = {flow_node}))
      then ComponentRef.prefixCref(flow_node, InstNode.getType(flow_node), {}, streamCref);

    // Otherwise, remove the first part of the cref and try again.
    else associatedFlowCref(rest_cr);
  end match;
end associatedFlowCref;

function lookupVarAttr
  input ComponentRef varName;
  input String attrName;
  input UnorderedMap<ComponentRef, Variable> variables;
  output Option<Expression> attrValue;
protected
  Option<Variable> ovar;
  Variable var;
  Binding binding;
algorithm
  ovar := UnorderedMap.get(varName, variables);

  if isNone(ovar) then
    ovar := UnorderedMap.get(ComponentRef.stripSubscriptsAll(varName), variables);
  end if;

  if isNone(ovar) then
    Error.addInternalError(getInstanceName() + " could not find the variable " +
      ComponentRef.toString(varName) + "\n", sourceInfo());
  end if;

  SOME(var) := ovar;
  binding := Variable.lookupTypeAttribute(attrName, var);
  attrValue := Binding.typedExp(binding);
end lookupVarAttr;

annotation(__OpenModelica_Interface="frontend");
end NFConnectEquations;
