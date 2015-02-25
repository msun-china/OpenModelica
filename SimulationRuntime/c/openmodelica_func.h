/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THE BSD NEW LICENSE OR THE
 * GPL VERSION 3 LICENSE OR THE OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the OSMC (Open Source Modelica Consortium)
 * Public License (OSMC-PL) are obtained from OSMC, either from the above
 * address, from the URLs: http://www.openmodelica.org or
 * http://www.ida.liu.se/projects/OpenModelica, and in the OpenModelica
 * distribution. GNU version 3 is obtained from:
 * http://www.gnu.org/copyleft/gpl.html. The New BSD License is obtained from:
 * http://www.opensource.org/licenses/BSD-3-Clause.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, EXCEPT AS
 * EXPRESSLY SET FORTH IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE
 * CONDITIONS OF OSMC-PL.
 *
 */

/* File: modelica.h
 * Description: This is the C header file for the C code generated from
 * Modelica. It includes e.g. the C object representation of the builtin types
 * and arrays, etc.
 */

#ifndef OPENMODELICAFUNC_H_
#define OPENMODELICAFUNC_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "simulation_data.h"

#include "util/memory_pool.h"
#include "util/index_spec.h"
#include "util/boolean_array.h"
#include "util/integer_array.h"
#include "util/real_array.h"
#include "util/string_array.h"
#include "util/modelica_string.h"
#include "util/division.h"
#include "util/utility.h"

struct OpenModelicaGeneratedFunctionCallbacks {
int (*performSimulation)(DATA* data, void* solverInfo);
/* Function for calling external object constructors */
void (*callExternalObjectConstructors)(DATA *data);
/* Function for calling external object deconstructors */
void (*callExternalObjectDestructors)(DATA *_data);

/*! \fn initialNonLinearSystem
 *
 *  This function initialize nonlinear system structure.
 *
 *  \param [ref] [data]
 */
void (*initialNonLinearSystem)(int nNonLinearSystems, NONLINEAR_SYSTEM_DATA *data);

/*! \fn initialLinearSystem
 *
 *  This function initialize nonlinear system structure.
 *
 *  \param [ref] [data]
 */
void (*initialLinearSystem)(int nLinearSystems, LINEAR_SYSTEM_DATA *data);

/*! \fn initialNonLinearSystem
 *
 *  This function initialize nonlinear system structure.
 *
 *  \param [ref] [data]
 */
void (*initialMixedSystem)(int nMixedSystems, MIXED_SYSTEM_DATA *data);

/*! \fn initialNonLinearSystem
 *
 *  This function initialize state set structure.
 *
 *  \param [ref] [data]
 */
void (*initializeStateSets)(int nStateSets, STATE_SET_DATA* statesetData, DATA *data);

/* functionODE contains those equations that are needed
 * to calculate the dynamic part of the system */
int (*functionODE)(DATA *data);

/* functionAlgebraics contains all continuous equations that
 * are not part of the dynamic part of the system */
int (*functionAlgebraics)(DATA *data);

/* function for calculating all equation sorting order
   uses in EventHandle  */
int (*functionDAE)(DATA *data);

/* functions for input and output */
int (*input_function)(DATA*);
int (*input_function_init)(DATA*);
int (*output_function)(DATA*);

/* function for storing value histories of delayed expressions
 * called from functionDAE_output()
 */
int (*function_storeDelayed)(DATA *data);

/*! \fn updateBoundVariableAttributes
 *
 *  This function updates all bound start, nominal, min, and max values.
 *
 *  \param [ref] [data]
 */
int (*updateBoundVariableAttributes)(DATA *data);

/*! \var useSymbolicInitialization
 *
 * is 1 if a system to solve the initial problem symbolically is generated, otherwise 0
 */
const int useSymbolicInitialization;

/*! \var useHomotopy
 *
 * is 1 if homotopy(...) is used during initialization, otherwise 0
 */
const int useHomotopy;

/*! \fn functionInitialEquations
 *
 * function for calculate initial values from the initial equations and initial algorithms
 *
 *  \param [ref] [data]
 */
int (*functionInitialEquations)(DATA *data);

/*! \fn functionRemovedInitialEquations
 *
 * This function contains removed equations from the initialization problem,
 * which need to be checked to verify the consistency of the initialization
 * problem.
 *
 *  \param [ref] [data]
 */
int (*functionRemovedInitialEquations)(DATA *data);

/*! \fn updateBoundParameters
 *
 *  This function calculates bound parameters that depend on other parameters,
 *  e.g. parameter Real n=1/m;
 *  obsolete: bound_parameters
 *
 *  \param [ref] [data]
 */
int (*updateBoundParameters)(DATA *data);

/* function for checking for asserts and terminate */
int (*checkForAsserts)(DATA *data);

/*! \fn function_ZeroCrossingsEquations
 *
 *  This function updates all equations to evaluate function_ZeroCrossings
 *
 *  \param [ref] [data]
 */
int (*function_ZeroCrossingsEquations)(DATA *data);

/*! \fn function_ZeroCrossings
 *
 *  This function evaluates if a sign change occurs at the current state
 *
 *  \param [ref] [data]
 *  \param [ref] [gout]
 */
int (*function_ZeroCrossings)(DATA *data, double* gout);

/*! \fn function_updateRelations
 *
 *  This function evaluates current continuous relations.
 *
 *  \param [ref] [data]
 *  \param [in]  [evalZeroCross] flag for evaluating Relation with hysteresis
 *                              function or without
 */
int (*function_updateRelations)(DATA *data, int evalZeroCross);

/*! \fn checkForDiscreteChanges
 *
 *  This function checks if any discrete variable changed
 *
 *  \param [ref] [data]
 */
int (*checkForDiscreteChanges)(DATA *data);

/*! \var zeroCrossingDescription
 *
 * This variable contains a description string for zero crossing condition.
 */
const char *(*zeroCrossingDescription)(int i, int **out_EquationIndexes);

/*! \var relationDescription
 *
 * This variable contains a description string for continuous relations.
 */
const char *(*relationDescription)(int i);

/*! \fn function_initSample
 *
 *  This function initialize the sample-info struct.
 *
 *  \param [ref] [data]
 */
void (*function_initSample)(DATA *data);

/* function for calculation Jacobian */
/*#ifdef D_OMC_JACOBIAN*/
const int INDEX_JAC_A;
const int INDEX_JAC_B;
const int INDEX_JAC_C;
const int INDEX_JAC_D;

/*
 * These functions initialize specific jacobians.
 * Return-value 0: jac is present
 * Return-value 1: jac is not present
 */
int (*initialAnalyticJacobianA)(void* data);
int (*initialAnalyticJacobianB)(void* data);
int (*initialAnalyticJacobianC)(void* data);
int (*initialAnalyticJacobianD)(void* data);

/*
 * These functions calculate specific jacobian column.
 */
int (*functionJacA_column)(void* data);
int (*functionJacB_column)(void* data);
int (*functionJacC_column)(void* data);
int (*functionJacD_column)(void* data);

/*#endif*/

const char *(*linear_model_frame)(void); /* printf format-string with holes for 6 strings */

/*
 * This function is used only for optimization purpose
 * and calculates the mayer term. In case it's not present
 * a dummy function is added which return -1.
 */
int (*mayer)(DATA* data, modelica_real** res, short *);

/*
 * This function is used only for optimization purpose
 * and calculates the lagrange term. In case it's not present
 * a dummy function is added which return -1.
 */
int (*lagrange)(DATA* data, modelica_real** res, short *, short *);

/*
 * This function is used only for optimization purpose
 * and pick up the bounds of inputs. In case it's not present
 * a dummy function is added which return -1.
 */
int (*pickUpBoundsForInputsInOptimization)(DATA* data, modelica_real* min, modelica_real* max, modelica_real*nominal, modelica_boolean *useNominal, char ** name, modelica_real * start, modelica_real * startTimeOpt);

/*
 * This function is used only for optimization purpose
 * and set simulationInfo.inputVars. In case it's not present
 * a dummy function is added which return -1.
 */
int (*setInputData)(DATA* data);




};

#ifdef __cplusplus
}
#endif

#endif
