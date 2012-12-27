/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */
  
encapsulated package Initialization
" file:        Initialization.mo
  package:     Initialization 
  description: Initialization.mo contains everything needed to set up the 
               BackendDAE for the initial system.

  RCS: $Id$"

public import Absyn;
public import BackendDAE;
public import DAE;
public import Env;
public import Util;

protected import BackendDAEOptimize;
protected import BackendDAEUtil;
protected import BackendDump;
protected import BackendEquation;
protected import BackendVariable;
protected import CheckModel;
protected import ComponentReference;
protected import Debug;
protected import Error;
protected import Expression;
protected import Flags;
protected import List;
protected import System;

// =============================================================================
// section for all public functions
//
// These are functions, that can be used to do anything regarding 
// initialization.
// =============================================================================

public function solveInitialSystem "function solveInitialSystem
  author: lochel
  This function generates a algebraic system of equations for the initialization and solves it."
  input BackendDAE.BackendDAE inDAE;
  input list<BackendDAE.Var> itempVar;
  output Option<BackendDAE.BackendDAE> outInitDAE;
  output list<BackendDAE.Var> otempVar;
protected 
  BackendDAE.BackendDAE dae;
  BackendDAE.Variables initVars;
algorithm
  dae := inlineWhenForInitialization(inDAE);
  Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpBackendDAE, dae, "inlineWhenForInitialization");

  initVars := selectInitializationVariablesDAE(dae);
  Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpVariables, initVars, "selected initialization variables");

  (outInitDAE,otempVar) := solveInitialSystem1(dae, initVars, itempVar);
end solveInitialSystem;

// =============================================================================
// section for inlining when-clauses
//
// This section contains all the helper functions to replace all when-clauses 
// from a given BackenDAE to get the initial equation system.
// =============================================================================

protected function inlineWhenForInitialization "function inlineWhenForInitialization
  author: lochel
  This function inlines when-clauses for the initialization."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
protected
  BackendDAE.EqSystems systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs, shared) := inDAE;
  systs := List.map(systs, inlineWhenForInitialization1);
  outDAE := BackendDAE.DAE(systs, shared);
end inlineWhenForInitialization;

protected function inlineWhenForInitialization1 "function inlineWhenForInitialization1
  author: lochel
  This is a helper function for inlineWhenForInitialization."
  input BackendDAE.EqSystem inEqSystem;
  output BackendDAE.EqSystem outEqSystem;
protected  
  BackendDAE.Variables orderedVars;
  BackendDAE.EquationArray orderedEqs;
  BackendDAE.EquationArray eqns;
  BackendDAE.StateSets stateSets;
  list<BackendDAE.Equation> eqnlst;
algorithm
  BackendDAE.EQSYSTEM(orderedVars=orderedVars, orderedEqs=orderedEqs, stateSets=stateSets) := inEqSystem;
  
  eqnlst := BackendEquation.traverseBackendDAEEqns(orderedEqs, inlineWhenForInitialization2, {});
  eqns := BackendEquation.listEquation(eqnlst);

  outEqSystem := BackendDAE.EQSYSTEM(orderedVars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(),stateSets);
end inlineWhenForInitialization1;

protected function inlineWhenForInitialization2 "function inlineWhenForInitialization2
  author: lochel
  This is a helper function for inlineWhenForInitialization1."
  input tuple<BackendDAE.Equation, list<BackendDAE.Equation>> inTpl;
  output tuple<BackendDAE.Equation, list<BackendDAE.Equation>> outTpl;
protected
  BackendDAE.Equation eqn;
  list<BackendDAE.Equation> eqnlst;
algorithm
  (eqn, eqnlst) := inTpl;
  eqnlst := inlineWhenForInitialization3(eqn,eqnlst);
  outTpl := (eqn, eqnlst);
end inlineWhenForInitialization2;

protected function inlineWhenForInitialization3 "function inlineWhenForInitialization3
  author: lochel
  This is a helper function for inlineWhenForInitialization2."
  input BackendDAE.Equation inEqn;
  input list<BackendDAE.Equation> iEqns;
  output list<BackendDAE.Equation> outEqns;
algorithm
  outEqns := matchcontinue(inEqn,iEqns)
    local
      DAE.Exp condition        "The when-condition" ;
      DAE.ComponentRef left    "Left hand side of equation" ;
      DAE.Exp right            "Right hand side of equation" ;
      DAE.ElementSource source "origin of equation";
      BackendDAE.Equation eqn;
      DAE.Type identType;
      DAE.Algorithm alg;
      Integer size;
      list< DAE.Statement> stmts;
      list< BackendDAE.Equation> eqns;
      
    // active when equation during initialization
    case (BackendDAE.WHEN_EQUATION(whenEquation=BackendDAE.WHEN_EQ(condition=condition, left=left, right=right), source=source),_)
      equation
        true = Expression.containsInitialCall(condition, false);  // do not use Expression.traverseExp
        identType = ComponentReference.crefType(left);
        eqn = BackendDAE.EQUATION(DAE.CREF(left, identType), right, source, false);
      then
        eqn::iEqns;
    
    // inactive when equation during initialization
    case (BackendDAE.WHEN_EQUATION(whenEquation=BackendDAE.WHEN_EQ(condition=condition, left=left, right=right), source=source),_)
      equation
        false = Expression.containsInitialCall(condition, false);
        eqn = generateInactiveWhenEquationForInitialization(left, source);
      then
        eqn::iEqns;
    
    // algorithm
    case (BackendDAE.ALGORITHM(size=size, alg=alg, source=source),_)
      equation
        DAE.ALGORITHM_STMTS(statementLst=stmts) = alg;
        (stmts,eqns) = generateInitialWhenAlg(stmts,true,iEqns);
        alg = DAE.ALGORITHM_STMTS(stmts);
        eqns = List.consOnTrue(List.isNotEmpty(stmts), BackendDAE.ALGORITHM(size, alg, source), eqns);
    then
       eqns;
    
    else then inEqn::iEqns;
  end matchcontinue;
end inlineWhenForInitialization3;

protected function generateInitialWhenAlg "function generateInitialWhenAlg
  author: lochel
  This function generates out of a given when-algorithm, a algorithm for the initialization-problem.
  This is a helper function for inlineWhenForInitialization3."
  input list< DAE.Statement> inStmts;
  input Boolean first;
  input list< BackendDAE.Equation> iEqns;
  output list< DAE.Statement> outStmts;
  output list< BackendDAE.Equation> oEqns;
algorithm
  (outStmts,oEqns) := matchcontinue(inStmts,first,iEqns)
    local
      DAE.Exp condition        "The when-condition" ;
      DAE.ComponentRef left    "Left hand side of equation" ;
      DAE.Exp right            "Right hand side of equation" ;
      BackendDAE.Equation eqn;
      DAE.Type identType;
      String errorMessage;
      list< DAE.ComponentRef> crefLst;
      DAE.Statement stmt;
      list< DAE.Statement> stmts, rest;
      Integer size "size of equation" ;
      DAE.Algorithm alg;
      DAE.ElementSource source "origin of when-stmt";
      DAE.ElementSource algSource "origin of algorithm";
      list< BackendDAE.Equation> eqns;
      
    case ({},_,_) then ({},iEqns);
    
    // active when equation during initialization
    case (DAE.STMT_WHEN(exp=condition, statementLst=stmts)::rest,_,_)
      equation
        true = Expression.containsInitialCall(condition, false);
        (rest,eqns) = generateInitialWhenAlg(rest,false,iEqns);
        stmts = listAppend(stmts, rest);
      then
       (stmts,eqns);

    // single inactive when equation during initialization
    case (((stmt as (DAE.STMT_WHEN(exp=condition, source=source)))::{}),true,_)
      equation
        false = Expression.containsInitialCall(condition, false);
        crefLst = CheckModel.algorithmStatementListOutputs({stmt});
        eqns = List.map1(crefLst, generateInactiveWhenEquationForInitialization, source);
        eqns = listAppend(iEqns,eqns);
      then
        ({},eqns); 
            
    // inactive when equation during initialization
    case (((stmt as (DAE.STMT_WHEN(exp=condition, source=source)))::rest),_,_)
      equation
        false = Expression.containsInitialCall(condition, false);
        crefLst = CheckModel.algorithmStatementListOutputs({stmt});
        stmts = List.map1(crefLst, generateInactiveWhenAlgStatementForInitialization, source);
        (rest,eqns) = generateInitialWhenAlg(rest,false,iEqns);
        stmts = listAppend(stmts, rest);
      then
        (stmts,eqns);
    
    // no when equation
    case (stmt::rest,_,_)
      equation
        // false = isWhenStmt(stmt);
        (rest,eqns) = generateInitialWhenAlg(rest,false,iEqns);
      then 
        (stmt::rest,eqns);
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function generateInitialWhenAlg failed"});
    then fail();
  end matchcontinue;
end generateInitialWhenAlg;

protected function generateInactiveWhenEquationForInitialization "function generateInactiveWhenEquationForInitialization
  author: lochel
  This is a helper function for inlineWhenForInitialization3."
  input DAE.ComponentRef inCRef;
  input DAE.ElementSource inSource;
  output BackendDAE.Equation outEqn;
protected
  DAE.Type identType;
  DAE.ComponentRef preCR;
algorithm
  identType := ComponentReference.crefType(inCRef);
  preCR := ComponentReference.crefPrefixPre(inCRef);
  outEqn := BackendDAE.EQUATION(DAE.CREF(inCRef, identType), DAE.CREF(preCR, identType), inSource, false);
end generateInactiveWhenEquationForInitialization;

protected function generateInactiveWhenAlgStatementForInitialization "function generateInactiveWhenAlgStatementForInitialization
  author: lochel
  This is a helper function for generateInitialWhenAlg."
  input DAE.ComponentRef inCRef;
  input DAE.ElementSource inSource;
  output DAE.Statement outAlgStatement;
protected
  DAE.Type identType;
  DAE.ComponentRef preCR;
algorithm
  identType := ComponentReference.crefType(inCRef);
  preCR := ComponentReference.crefPrefixPre(inCRef);
  outAlgStatement := DAE.STMT_ASSIGN(identType, DAE.CREF(inCRef, identType), DAE.CREF(preCR, identType), inSource);
end generateInactiveWhenAlgStatementForInitialization;

// =============================================================================
// section for selecting initialization variables
// 
//   - unfixed state
//   - unfixed parameter
//   - unfixed discrete -> pre(vd)
// =============================================================================

protected function selectInitializationVariablesDAE "function selectInitializationVariablesDAE
  author: lochel
  This function wraps selectInitializationVariables."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.Variables outVars;
protected
  BackendDAE.EqSystems systs;
  BackendDAE.Variables knownVars,alias;
algorithm
  BackendDAE.DAE(systs, BackendDAE.SHARED(knownVars=knownVars,aliasVars=alias)) := inDAE;
  outVars := selectInitializationVariables(systs);
  outVars := BackendVariable.traverseBackendDAEVars(knownVars, selectInitializationVariables2, outVars);
  /* what is with alias variables, I guess this one should also be checked for unfixed discrete */
  outVars := BackendVariable.traverseBackendDAEVars(alias, selectInitializationVariables2, outVars);
end selectInitializationVariablesDAE;

protected function selectInitializationVariables "function selectInitializationVariables
  author: lochel"
  input BackendDAE.EqSystems inEqSystems;
  output BackendDAE.Variables outVars;
algorithm
  outVars := BackendVariable.emptyVars();
  outVars := List.fold(inEqSystems, selectInitializationVariables1, outVars);
end selectInitializationVariables;

protected function selectInitializationVariables1 "function selectInitializationVariables1
  author: lochel"
  input BackendDAE.EqSystem inEqSystem;
  input BackendDAE.Variables inVars;
  output BackendDAE.Variables outVars;
protected
  BackendDAE.Variables vars;
  BackendDAE.StateSets stateSets;
algorithm
  BackendDAE.EQSYSTEM(orderedVars=vars,stateSets=stateSets) := inEqSystem;
  outVars := BackendVariable.traverseBackendDAEVars(vars, selectInitializationVariables2, inVars);
  // ignore not the states of the statesets
  outVars := List.fold(stateSets,selectInitialStateSetVars,outVars);
end selectInitializationVariables1;

protected function selectInitialStateSetVars
  input BackendDAE.StateSet inSet;
  input BackendDAE.Variables inVars;
  output BackendDAE.Variables outVars;
protected
  list< BackendDAE.Var> statescandidates;
algorithm
  BackendDAE.STATESET(statescandidates=statescandidates) := inSet;
  outVars := List.fold(statescandidates,selectInitialStateSetVar,inVars);
end selectInitialStateSetVars;

protected function selectInitialStateSetVar
  input BackendDAE.Var inVar;
  input BackendDAE.Variables inVars;
  output BackendDAE.Variables outVars;
algorithm
  ((_,outVars)) := selectInitializationVariables2((inVar,inVars));
end selectInitialStateSetVar;

protected function selectInitializationVariables2 "function selectInitializationVariables2
  author: lochel"
  input tuple<BackendDAE.Var, BackendDAE.Variables> inTpl;
  output tuple<BackendDAE.Var, BackendDAE.Variables> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      BackendDAE.Var var, preVar;
      BackendDAE.Variables vars;
      DAE.ComponentRef cr, preCR;
      DAE.Type ty;
      DAE.InstDims arryDim;
    
    // unfixed state
    case((var as BackendDAE.VAR(varName=cr,varKind=BackendDAE.STATE()), vars)) equation
      false = BackendVariable.varFixed(var);
      // ignore stateset variables
      false = isStateSetVar(cr);
      vars = BackendVariable.addVar(var, vars);
    then ((var, vars));
    
    // unfixed parameter
    case((var as BackendDAE.VAR(varKind=BackendDAE.PARAM()), vars)) equation
      false = BackendVariable.varFixed(var);
      vars = BackendVariable.addVar(var, vars);
    then ((var, vars));
    
    // unfixed discrete -> pre(vd)
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.DISCRETE(), varType=ty, arryDim=arryDim), vars)) equation
      false = BackendVariable.varFixed(var);
      preCR = ComponentReference.crefPrefixPre(cr);  // cr => $PRE.cr
      preVar = BackendDAE.VAR(preCR, BackendDAE.VARIABLE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      vars = BackendVariable.addVar(preVar, vars);
    then ((var, vars));
    
    else
    then inTpl;
  end matchcontinue;
end selectInitializationVariables2;

protected function isStateSetVar
  input DAE.ComponentRef cr;
  output Boolean isStateSet;
algorithm
  isStateSet := match(cr)
    local 
      DAE.Ident ident;
      Integer i;
    case DAE.CREF_QUAL(ident=ident)
      equation
        i = System.strncmp("$STATESET",ident,9);
      then
        intEq(i,0);
    else then false;
  end match;
end isStateSetVar;

// =============================================================================
// 
// 
// 
// =============================================================================

protected function solveInitialSystem1 "function solveInitialSystem1
  author: jfrenkel, lochel
  This function generates a algebraic system of equations for the initialization and solves it."
  input BackendDAE.BackendDAE inDAE;
  input BackendDAE.Variables inInitVars;
  input list<BackendDAE.Var> itempVar;
  output Option<BackendDAE.BackendDAE> outInitDAE;
  output list<BackendDAE.Var> otempVar;
algorithm
  (outInitDAE,otempVar) := matchcontinue(inDAE, inInitVars, itempVar)
    local
      BackendDAE.EqSystems systs;
      BackendDAE.Shared shared;
      BackendDAE.Variables knvars, vars, fixvars, evars, eavars, avars;
      BackendDAE.EquationArray inieqns, eqns, emptyeqns, reeqns;
      BackendDAE.EqSystem initsyst;
      BackendDAE.BackendDAE initdae;
      Env.Cache cache;
      Env.Env env;
      DAE.FunctionTree functionTree;
      array<DAE.Constraint> constraints;
      array<DAE.ClassAttributes> classAttrs;
      list<BackendDAE.Var> tempVar;
    case(BackendDAE.DAE(systs, shared as BackendDAE.SHARED(knownVars=knvars,
                                                 aliasVars=avars,
                                                 initialEqs=inieqns,
                                                 constraints=constraints,
                                                 classAttrs=classAttrs,
                                                 cache=cache,
                                                 env=env,
                                                 functionTree=functionTree)), _, _) equation
      true = Flags.isSet(Flags.SOLVE_INITIAL_SYSTEM);
      
      // collect vars and eqns for initial system
      vars = BackendVariable.emptyVars();
      fixvars = BackendVariable.emptyVars();
      eqns = BackendEquation.emptyEqns();
      reeqns = BackendEquation.emptyEqns();

      ((vars, fixvars, tempVar)) = BackendVariable.traverseBackendDAEVars(avars, collectInitialAliasVars, (vars, fixvars, itempVar));
      ((vars, fixvars)) = BackendVariable.traverseBackendDAEVars(knvars, collectInitialVars, (vars, fixvars));
      ((eqns, reeqns)) = BackendEquation.traverseBackendDAEEqns(inieqns, collectInitialEqns, (eqns, reeqns));
      
      Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpEquationArray, eqns, "initial equations");
      
      ((vars, fixvars, eqns, reeqns)) = List.fold(systs, collectInitialVarsEqnsSystem, ((vars, fixvars, eqns, reeqns)));
      ((eqns, reeqns)) = BackendVariable.traverseBackendDAEVars(vars, collectInitialBindings, (eqns, reeqns));

      // collect pre(var) from alias
      // ((_, vars, fixvars)) = traverseBackendDAEExpsEqns(eqns, collectAliasPreVars, (avars, vars, fixvars));
      // ((_, vars, fixvars)) = traverseBackendDAEExpsEqns(reeqns, collectAliasPreVars, (avars, vars, fixvars));

      // generate initial system
      initsyst = BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(),{});
      // remove unused variables
      initsyst = removeUnusedInitialVars(initsyst);
      
      evars = BackendVariable.emptyVars();
      eavars = BackendVariable.emptyVars();
      emptyeqns = BackendEquation.emptyEqns();
      shared = BackendDAE.SHARED(fixvars,
                                                 evars,
                                                 eavars,
                                                 emptyeqns,
                                                 reeqns,
                                                 constraints,
                                                 classAttrs,
                                                 cache,
                                                 env,
                                                 functionTree,
                                                 BackendDAE.EVENT_INFO({},{},{},{},0,0),
                                                 {},
                                                 BackendDAE.INITIALSYSTEM(),
                                                 {});

      // split it in independend subsystems
      (systs,shared) = BackendDAEOptimize.partitionIndependentBlocksHelper(initsyst,shared,Error.getNumErrorMessages(),true);
      initdae = BackendDAE.DAE(systs,shared);
      // analzye initial system
      initdae = analyzeInitialSystem(initdae, inDAE, inInitVars);

      // some debug prints
      Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpBackendDAE, initdae, "initial system");
      
      // now let's solve the system!
      (initdae,_) = BackendDAEUtil.mapEqSystemAndFold(initdae,solveInitialSystem3,inDAE);
      initdae = solveInitialSystem2(initdae);
    then 
      (SOME(initdae),tempVar);
      
    case (_, _, _)
      then 
        (NONE(),itempVar);
  end matchcontinue;
end solveInitialSystem1;

protected function solveInitialSystem3 "function solveInitialSystem2
  author: jfrenkel, lochel
  This is a helper function of solveInitialSystem and solves the generated system."
  input BackendDAE.EqSystem isyst; 
  input tuple<BackendDAE.Shared,BackendDAE.BackendDAE> sharedOptimized;
  output BackendDAE.EqSystem osyst;
  output tuple<BackendDAE.Shared,BackendDAE.BackendDAE> osharedOptimized;
algorithm
  (osyst,osharedOptimized):=
  matchcontinue (isyst,sharedOptimized)  
    local
      BackendDAE.EqSystem syst;
      list<tuple<BackendDAEUtil.pastoptimiseDAEModule, String, Boolean>> pastOptModules;
      tuple<BackendDAEUtil.StructurallySingularSystemHandlerFunc, String, BackendDAEUtil.stateDeselectionFunc, String> daeHandler;
      tuple<BackendDAEUtil.matchingAlgorithmFunc, String> matchingAlgorithm;
      Integer nVars, nEqns;
      BackendDAE.Variables vars;
      BackendDAE.EquationArray eqns;
      BackendDAE.BackendDAE inDAE;
      
    // over-determined system
    case(_, _) 
      equation
        nVars = BackendVariable.varsSize(BackendVariable.daeVars(isyst));
        nEqns = BackendDAEUtil.systemSize(isyst);
        true = intGt(nEqns, nVars);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "It was not possible to solve the over-determined initial system (" +& intString(nEqns) +& " equations and " +& intString(nVars) +& " variables)");
    then fail();
    
    // equal  
    case( _, _) 
      equation
        nVars = BackendVariable.varsSize(BackendVariable.daeVars(isyst));
        nEqns = BackendDAEUtil.systemSize(isyst);
        true = intEq(nEqns, nVars);
    then
       (isyst,sharedOptimized);
    
    // under-determined system  
    case( _, _) 
      equation
        nVars = BackendVariable.varsSize(BackendVariable.daeVars(isyst));
        nEqns = BackendDAEUtil.systemSize(isyst);
        true = intLt(nEqns, nVars);
      
        Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "It was not possible to solve the under-determined initial system (" +& intString(nEqns) +& " equations and " +& intString(nVars) +& " variables)");
    then fail();
  end matchcontinue;
end solveInitialSystem3;

protected function solveInitialSystem2 "function solveInitialSystem2
  author: jfrenkel, lochel
  This is a helper function of solveInitialSystem and solves the generated system."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
protected
  list<tuple<BackendDAEUtil.pastoptimiseDAEModule, String, Boolean>> pastOptModules;
  tuple<BackendDAEUtil.StructurallySingularSystemHandlerFunc, String, BackendDAEUtil.stateDeselectionFunc, String> daeHandler;
  tuple<BackendDAEUtil.matchingAlgorithmFunc, String> matchingAlgorithm;
algorithm
  pastOptModules := BackendDAEUtil.getPastOptModules(SOME({"constantLinearSystem", /* here we need a special case and remove only alias and constant (no variables of the system) variables "removeSimpleEquations", */ "tearingSystem"}));
  matchingAlgorithm := BackendDAEUtil.getMatchingAlgorithm(NONE());
  daeHandler := BackendDAEUtil.getIndexReductionMethod(NONE());
      
  // solve system
  outDAE := BackendDAEUtil.transformBackendDAE(inDAE, SOME((BackendDAE.NO_INDEX_REDUCTION(), BackendDAE.EXACT())), NONE(), NONE());
      
  // simplify system
 (outDAE, Util.SUCCESS()) := BackendDAEUtil.pastoptimiseDAE(outDAE, pastOptModules, matchingAlgorithm, daeHandler);
      
  Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpBackendDAE, outDAE, "solved initial system");

end solveInitialSystem2;

protected function analyzeInitialSystem "function analyzeInitialSystem
  author: lochel
  This function fixes discrete and state variables to balance the initial equation system."
  input BackendDAE.BackendDAE initDAE;
  input BackendDAE.BackendDAE inDAE;      // original DAE
  input BackendDAE.Variables inInitVars;
  output BackendDAE.BackendDAE outDAE;
algorithm
  (outDAE,_) := BackendDAEUtil.mapEqSystemAndFold(initDAE,analyzeInitialSystem2,(inDAE,inInitVars));
end analyzeInitialSystem;

protected function removeUnusedInitialVars
  input BackendDAE.EqSystem inSystem;
  output BackendDAE.EqSystem outSystem;
protected
  BackendDAE.Variables orderedVars;
  BackendDAE.EquationArray orderedEqs;
  BackendDAE.Matching matching;
  BackendDAE.StateSets stateSets;
  Boolean b;
  BackendDAE.IncidenceMatrix mt;
algorithm
  (_,_, mt) := BackendDAEUtil.getIncidenceMatrix(inSystem, BackendDAE.NORMAL());
  BackendDAE.EQSYSTEM(orderedVars=orderedVars,orderedEqs=orderedEqs,stateSets=stateSets) := inSystem;
  (orderedVars,b) := removeUnusedInitialVarsWork(arrayLength(mt),mt,orderedVars,false);
  outSystem := Util.if_(b,BackendDAE.EQSYSTEM(orderedVars,orderedEqs,NONE(),NONE(),BackendDAE.NO_MATCHING(),stateSets),inSystem);
end removeUnusedInitialVars;

protected function removeUnusedInitialVarsWork
  input Integer n;
  input BackendDAE.IncidenceMatrix mt;
  input BackendDAE.Variables iVars;
  input Boolean iB;
  output BackendDAE.Variables oVars;
  output Boolean oB;
algorithm
  (oVars,oB) := match(n,mt,iVars,iB)
    local
      list<Integer> row;
      Boolean b;
      BackendDAE.Variables vars;
    case(0,_,_,false) then (iVars,false);
    case(0,_,_,true)
      equation
        vars = BackendVariable.listVar1(BackendVariable.varList(iVars));
      then
        (vars,true);
    case(_,_,_,_)
      equation
        row = mt[n];
        b = List.isEmpty(row);
        row = Util.if_(b,{n},{});
        (vars,_) = BackendVariable.removeVars(row,iVars,{});
        (vars,b) = removeUnusedInitialVarsWork(n-1,mt,vars,b or iB);
      then
        (vars,b);
  end match;
end removeUnusedInitialVarsWork;

protected function analyzeInitialSystem2 "function analyzeInitialSystem2
  author lochel"
  input BackendDAE.EqSystem isyst; 
  input tuple<BackendDAE.Shared,tuple<BackendDAE.BackendDAE,BackendDAE.Variables>> sharedOptimized;
  output BackendDAE.EqSystem osyst;
  output tuple<BackendDAE.Shared,tuple<BackendDAE.BackendDAE,BackendDAE.Variables>> osharedOptimized;
algorithm
  (osyst,osharedOptimized):= matchcontinue(isyst,sharedOptimized)
    local
      BackendDAE.EqSystem system;
      Integer nVars, nEqns;
      BackendDAE.Variables vars,initVars;
      BackendDAE.EquationArray eqns;
      BackendDAE.BackendDAE inDAE;
      BackendDAE.Shared shared;
      DAE.ComponentRef cr,pcr;
      String msg;
      
    // over-determined system
    case(BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns),(shared,(inDAE,initVars)))
      equation
        nVars = BackendVariable.varsSize(vars);
        nEqns = BackendDAEUtil.equationSize(eqns);
        true = intGt(nEqns, nVars);
        Debug.fcall2(Flags.PEDANTIC, BackendDump.dumpEqSystem, isyst, "Trying to fix over-determined initial system");
        msg = "Trying to fix over-determined initial system Variables " +& intString(nVars) +& " Equations " +& intString(nEqns) +& "... [not implemented yet!]";
        Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, msg);
      then fail();

    // under-determined system with var = pre(var) and only var and pre(var) 
    case(BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns),(shared,(inDAE,initVars)))
      equation
        2 = BackendVariable.varsSize(vars);
        1 = BackendDAEUtil.equationSize(eqns);
        
        // var = pre(var)
        BackendDAE.EQUATION(exp=DAE.CREF(componentRef=cr),scalar=DAE.CREF(componentRef=DAE.CREF_QUAL(ident="$PRE",componentRef=pcr))) = BackendEquation.equationNth(eqns,1);
        true = ComponentReference.crefEqualNoStringCompare(cr, pcr);
        
        // return empty system
        vars = BackendVariable.emptyVars();
        eqns = BackendEquation.emptyEqns();
        system = BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(),{});
    then
       (system,(shared,(inDAE,initVars)));
    
    // under-determined system  
    case(BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns),(shared,(inDAE,initVars)))
      equation
        nVars = BackendVariable.varsSize(vars);
        nEqns = BackendDAEUtil.equationSize(eqns);
        true = intLt(nEqns, nVars);
      
        (true, vars, eqns) = fixUnderDeterminedInitialSystem(inDAE, vars, eqns, initVars);
      
        system = BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(),{});
        (system,_, _) = BackendDAEUtil.getIncidenceMatrix(system, BackendDAE.NORMAL());
    then
       (system,(shared,(inDAE,initVars)));

    else
    then (isyst,sharedOptimized);
  end matchcontinue;
end analyzeInitialSystem2;

protected function fixUnderDeterminedInitialSystem "function fixUnderDeterminedInitialSystem
  author: lochel"
  input BackendDAE.BackendDAE inDAE;
  input BackendDAE.Variables inVars;
  input BackendDAE.EquationArray inEqns;
  input BackendDAE.Variables inInitVars;
  output Boolean outSucceed;
  output BackendDAE.Variables outVars;
  output BackendDAE.EquationArray outEqns;
algorithm
  (outSucceed, outVars, outEqns) := matchcontinue(inDAE, inVars, inEqns, inInitVars)
    local    
      BackendDAE.EquationArray eqns;
      Integer nVars, nInitVars, nEqns;
      list<BackendDAE.Var> initVarList;
      BackendDAE.BackendDAE dae;
      BackendDAE.SparsePattern sparsityPattern;
      list<BackendDAE.Var> outputs;   // $res1 ... $resN (initial equations)
      list<tuple< DAE.ComponentRef, list< DAE.ComponentRef>>> dep;
      list< DAE.ComponentRef> selectedVars;
    
    // fix all free variables
    case(_, _, eqns, _) equation
      nInitVars = BackendVariable.varsSize(inInitVars);
      nVars = BackendVariable.varsSize(inVars);
      nEqns = BackendDAEUtil.equationSize(inEqns);
      true = intEq(nVars, nEqns+nInitVars);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "Assuming fixed start value for the following " +& intString(nVars-nEqns) +& " variables:");
      initVarList = BackendVariable.varList(inInitVars);
      eqns = addStartValueEquations(initVarList, eqns);
    then (true, inVars, eqns);
    
    // fix a subset of unfixed variables
    case(_, _, eqns, _) equation
      nVars = BackendVariable.varsSize(inVars);
      nEqns = BackendDAEUtil.equationSize(eqns);
      true = intLt(nEqns, nVars);
      
      initVarList = BackendVariable.varList(inInitVars);
      (dae, outputs) = BackendDAEOptimize.generateInitialMatricesDAE(inDAE);
      (sparsityPattern, _) = BackendDAEOptimize.generateSparsePattern(dae, initVarList, outputs);
      
      (dep, _) = sparsityPattern;
      selectedVars = collectIndependentVars(dep, {});
      
      Debug.fcall2(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dumpSparsityPattern, sparsityPattern, "Sparsity Pattern");
      true = intEq(nVars-nEqns, listLength(selectedVars));  // fix only if it is definite
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "Assuming fixed start value for the following " +& intString(nVars-nEqns) +& " variables:");
      eqns = addStartValueEquations1(selectedVars, eqns);
    then (true, inVars, eqns);
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"It is not possible to determine unique which additional initial conditions should be added by auto-fixed variables."});
    then (false, inVars, inEqns);
  end matchcontinue;
end fixUnderDeterminedInitialSystem;

protected function collectIndependentVars "function collectIndependentVars
  author lochel"
  input list<tuple< DAE.ComponentRef, list< DAE.ComponentRef>>> inPattern;
  input list< DAE.ComponentRef> inVars;
  output list< DAE.ComponentRef> outVars;
algorithm
  outVars := matchcontinue(inPattern, inVars)
    local
      tuple< DAE.ComponentRef, list< DAE.ComponentRef>> curr;
      list<tuple< DAE.ComponentRef, list< DAE.ComponentRef>>> rest;
      DAE.ComponentRef cr;
      list< DAE.ComponentRef> crList, vars;
      
    case ({}, _)
    then inVars;
    
    case (curr::rest, _) equation
      (cr, crList) = curr;
      true = List.isEmpty(crList);
    
      vars = collectIndependentVars(rest, inVars);
      vars = cr::vars;
    then vars;
    
    case (curr::rest, _) equation
      vars = collectIndependentVars(rest, inVars);
    then vars;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function collectIndependentVars failed"});
    then fail();
  end matchcontinue;
end collectIndependentVars;

protected function addStartValueEquations "function addStartValueEquations
  author lochel"
  input list<BackendDAE.Var> inVars;
  input BackendDAE.EquationArray inEqns;
  output BackendDAE.EquationArray outEqns;
algorithm
  outEqns := matchcontinue(inVars, inEqns)
    local
      BackendDAE.Var var;
      list<BackendDAE.Var> vars;
      BackendDAE.Equation eqn;
      BackendDAE.EquationArray eqns;
      DAE.Exp e, e1, crefExp, startExp;
      DAE.ComponentRef cref, preCref;
      DAE.Type tp;
      String crStr;
      
    case ({}, _)
    then inEqns;
    
    case (var::vars, eqns) equation
      preCref = BackendVariable.varCref(var);
      true = ComponentReference.isPreCref(preCref);
      cref = ComponentReference.popPreCref(preCref);
      tp = BackendVariable.varType(var);
      
      crefExp = DAE.CREF(preCref, tp);
      
      e = Expression.crefExp(cref);
      tp = Expression.typeof(e);
      startExp = Expression.makeBuiltinCall("$_start", {e}, tp);
      
      eqn = BackendDAE.EQUATION(crefExp, startExp, DAE.emptyElementSource, false);
      
      crStr = ComponentReference.crefStr(cref);
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "  [discrete] " +& crStr);
      
      eqns = BackendEquation.equationAdd(eqn, eqns);
      eqns = addStartValueEquations(vars, eqns);
    then eqns;
    
    case (var::vars, eqns) equation
      cref = BackendVariable.varCref(var);
      tp = BackendVariable.varType(var);
      
      crefExp = DAE.CREF(cref, tp);
      
      e = Expression.crefExp(cref);
      tp = Expression.typeof(e);
      startExp = Expression.makeBuiltinCall("$_start", {e}, tp);
      
      eqn = BackendDAE.EQUATION(crefExp, startExp, DAE.emptyElementSource, false);
      
      crStr = ComponentReference.crefStr(cref);
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "  [continuous] " +& crStr);
      
      eqns = BackendEquation.equationAdd(eqn, eqns);
      eqns = addStartValueEquations(vars, eqns);
    then eqns;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function addStartValueEquations failed"});
    then fail();
  end matchcontinue;
end addStartValueEquations;

protected function addStartValueEquations1 "function addStartValueEquations1
  author lochel
  Same as addStartValueEquations - just with list<DAE.ComponentRef> instead of list<BackendDAE.Var>"
  input list<DAE.ComponentRef> inVars;
  input BackendDAE.EquationArray inEqns;
  output BackendDAE.EquationArray outEqns;
algorithm
  outEqns := matchcontinue(inVars, inEqns)
    local
      DAE.ComponentRef var, cref;
      list<DAE.ComponentRef> vars;
      BackendDAE.Equation eqn;
      BackendDAE.EquationArray eqns;
      DAE.Exp e, e1, crefExp, startExp;
      DAE.Type tp;
      String crStr;
      
    case ({}, _)
    then inEqns;
    
    case (var::vars, eqns) equation
      true = ComponentReference.isPreCref(var);
      cref = ComponentReference.popPreCref(var);
      crefExp = DAE.CREF(var, DAE.T_REAL_DEFAULT);
      
      e = Expression.crefExp(cref);
      tp = Expression.typeof(e);
      startExp = Expression.makeBuiltinCall("$_start", {e}, tp);
      
      eqn = BackendDAE.EQUATION(crefExp, startExp, DAE.emptyElementSource, false);
      
      crStr = ComponentReference.crefStr(cref);
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "  [discrete] " +& crStr);
      
      eqns = BackendEquation.equationAdd(eqn, eqns);
      eqns = addStartValueEquations1(vars, eqns);
    then eqns;
    
    case (var::vars, eqns) equation      
      crefExp = DAE.CREF(var, DAE.T_REAL_DEFAULT);
      
      e = Expression.crefExp(var);
      tp = Expression.typeof(e);
      startExp = Expression.makeBuiltinCall("$_start", {e}, tp);
      
      eqn = BackendDAE.EQUATION(crefExp, startExp, DAE.emptyElementSource, false);
      
      crStr = ComponentReference.crefStr(var);
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "  [continuous] " +& crStr);
      
      eqns = BackendEquation.equationAdd(eqn, eqns);
      eqns = addStartValueEquations1(vars, eqns);
    then eqns;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function addStartValueEquations1 failed"});
    then fail();
  end matchcontinue;
end addStartValueEquations1;

protected function collectInitialVarsEqnsSystem "function collectInitialVarsEqnsSystem
  author: lochel, Frenkel TUD 2012-10
  This function collects variables and equations for the initial system out of an given EqSystem."
  input BackendDAE.EqSystem isyst;
  input tuple<BackendDAE.Variables, BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.EquationArray> iTpl;
  output tuple<BackendDAE.Variables, BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.EquationArray> oTpl;
protected
  BackendDAE.Variables orderedVars, vars, fixvars;
  BackendDAE.EquationArray orderedEqs, eqns, reqns;
  BackendDAE.StateSets stateSets;
algorithm
  BackendDAE.EQSYSTEM(orderedVars=orderedVars, orderedEqs=orderedEqs,stateSets=stateSets) := isyst;
  (vars, fixvars, eqns, reqns) := iTpl;

  ((vars, fixvars)) := BackendVariable.traverseBackendDAEVars(orderedVars, collectInitialVars, (vars, fixvars));
  ((eqns, reqns)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, collectInitialEqns, (eqns, reqns));
  ((fixvars,eqns)) := List.fold(stateSets,collectInitialStateSetVars,(fixvars,eqns));

  oTpl := (vars, fixvars, eqns, reqns);
end collectInitialVarsEqnsSystem;

protected function collectInitialStateSetVars
"function collectInitialStateSetVars
   author Frenkel TUD
   add the vars for state set to the initial system
   Because the statevars are calculated by
   set.x = set.A*dummystates we add set.A to the
   initial system with set.A = {{1,0,0},{0,1,0}}"
   input BackendDAE.StateSet inSet;
   input tuple<BackendDAE.Variables,BackendDAE.EquationArray> iTpl;
   output tuple<BackendDAE.Variables,BackendDAE.EquationArray> oTpl;
protected
  BackendDAE.Variables vars;
  BackendDAE.EquationArray eqns;
  DAE.ComponentRef crA;
  list<BackendDAE.Var> varA,statevars;
  Integer setsize,rang;
algorithm
  (vars,eqns) := iTpl;
  BackendDAE.STATESET(rang=rang,crA=crA,statescandidates=statevars,varA=varA) := inSet;
  vars := BackendVariable.addVars(varA,vars);
//  setsize := listLength(statevars) - rang;
//  eqns := addInitalSetEqns(setsize,intGt(rang,1),crA,eqns);
  oTpl := (vars,eqns);
end collectInitialStateSetVars;

protected function addInitalSetEqns
  input Integer n;
  input Boolean twoDims;
  input DAE.ComponentRef crA;
  input BackendDAE.EquationArray iEqns;
  output BackendDAE.EquationArray oEqns;
algorithm
  oEqns := match(n,twoDims,crA,iEqns)
    local
      DAE.ComponentRef crA1;
      DAE.Exp expcrA;
      BackendDAE.EquationArray eqns;
    case(0,_,_,_) then iEqns;
    case(_,_,_,_)
      equation
        crA1 = ComponentReference.subscriptCrefWithInt(crA,n);
        crA1 = Debug.bcallret2(twoDims,ComponentReference.subscriptCrefWithInt,crA1,n,crA1);
        expcrA = Expression.crefExp(crA1);
        eqns = BackendEquation.equationAdd(BackendDAE.EQUATION(expcrA,DAE.ICONST(1),DAE.emptyElementSource,false), iEqns);
      then
        addInitalSetEqns(n-1,twoDims,crA,eqns);
  end match;
end addInitalSetEqns;

protected function collectInitialVars "function collectInitialVars
  author: lochel
  This function collects all the vars for the initial system."
  input tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables>> inTpl;
  output tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      BackendDAE.Var var, preVar, derVar;
      BackendDAE.Variables vars, fixvars;
      DAE.ComponentRef cr, preCR, derCR;
      Boolean isFixed;
      DAE.Type ty;
      DAE.InstDims arryDim;
      Option<DAE.Exp> startValue;
      DAE.Exp startExp, bindExp;
      String errorMessage;
    
    // state
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.STATE(), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      
      derCR = ComponentReference.crefPrefixDer(cr);  // cr => $DER.cr
      derVar = BackendDAE.VAR(derCR, BackendDAE.VARIABLE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      
      vars = BackendVariable.addVar(derVar, vars);
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, var, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, var, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    // discrete
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.DISCRETE(), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      startValue = BackendVariable.varStartValueOption(var);
      
      var = BackendVariable.setVarFixed(var, false);
      
      preCR = ComponentReference.crefPrefixPre(cr);  // cr => $PRE.cr
      preVar = BackendDAE.VAR(preCR, BackendDAE.DISCRETE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      preVar = BackendVariable.setVarFixed(preVar, isFixed);
      preVar = BackendVariable.setVarStartValueOption(preVar, startValue);
      
      vars = BackendVariable.addVar(var, vars);
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, preVar, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, preVar, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    // parameter without binding
    case((var as BackendDAE.VAR(varKind=BackendDAE.PARAM(), bindExp=NONE()), (vars, fixvars))) equation
      true = BackendVariable.varFixed(var);
      startExp = BackendVariable.varStartValueType(var);
      var = BackendVariable.setBindExp(var, startExp);
      
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      vars = BackendVariable.addVar(var, vars);
    then ((var, (vars, fixvars)));
    
    // parameter with constant binding
    case((var as BackendDAE.VAR(varKind=BackendDAE.PARAM(), bindExp=SOME(bindExp)), (vars, fixvars))) equation
      true = Expression.isConst(bindExp);
      fixvars = BackendVariable.addVar(var, fixvars);
    then ((var, (vars, fixvars)));
    
    // parameter
    case((var as BackendDAE.VAR(varKind=BackendDAE.PARAM()), (vars, fixvars))) equation
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      vars = BackendVariable.addVar(var, vars);
    then ((var, (vars, fixvars)));

    // skip constant
    case((var as BackendDAE.VAR(varKind=BackendDAE.CONST()), (vars, fixvars))) // equation
      // fixvars = BackendVariable.addVar(var, fixvars);
    then ((var, (vars, fixvars)));

    case((var as BackendDAE.VAR(bindExp=NONE()), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, var, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, var, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    case((var as BackendDAE.VAR(bindExp=SOME(_)), (vars, fixvars))) equation
      vars = BackendVariable.addVar(var, vars);
    then ((var, (vars, fixvars)));
    
    case ((var, _)) equation
      errorMessage = "./Compiler/BackEnd/Initialization.mo: function collectInitialVars failed for: " +& BackendDump.varString(var);
      Error.addMessage(Error.INTERNAL_ERROR, {errorMessage});
    then fail();

    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function collectInitialVars failed"});
    then fail();
  end matchcontinue;
end collectInitialVars;

protected function collectInitialAliasVars "function collectInitialAliasVars
  author: lochel
  This function collects all the vars for the initial system."
  input tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables, list<BackendDAE.Var>>> inTpl;
  output tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables, list<BackendDAE.Var>>> outTpl;
algorithm
  outTpl := match(inTpl)
    local
      BackendDAE.Var var, preVar, derVar;
      BackendDAE.Variables vars, fixvars;
      DAE.ComponentRef cr, preCR, derCR;
      Boolean isFixed;
      DAE.Type ty;
      DAE.InstDims arryDim;
      Option<DAE.Exp> startValue;
      DAE.Exp startExp, bindExp;
      String errorMessage;
      list<BackendDAE.Var> tempVar;
    // discrete
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.DISCRETE(), varType=ty, arryDim=arryDim), (vars, fixvars, tempVar))) equation
      isFixed = BackendVariable.varFixed(var);
      startValue = BackendVariable.varStartValueOption(var);
      
      preCR = ComponentReference.crefPrefixPre(cr);  // cr => $PRE.cr
      preVar = BackendDAE.VAR(preCR, BackendDAE.DISCRETE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      preVar = BackendVariable.setVarFixed(preVar, isFixed);
      preVar = BackendVariable.setVarStartValueOption(preVar, startValue);
      
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, preVar, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, preVar, fixvars, fixvars);
    then ((var, (vars, fixvars, preVar::tempVar)));
    
    else then inTpl;
  end match;
end collectInitialAliasVars;

protected function collectInitialBindings "function collectInitialBindings
  author: lochel
  This function collects all the vars for the initial system."
  input tuple<BackendDAE.Var, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> inTpl;
  output tuple<BackendDAE.Var, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> outTpl;
algorithm
  outTpl := match(inTpl)
    local
      BackendDAE.Var var, preVar, derVar;
      BackendDAE.Variables vars, fixvars;
      DAE.ComponentRef cr, preCR, derCR;
      Boolean isFixed;
      DAE.Type ty;
      DAE.InstDims arryDim;
      Option<DAE.Exp> startValue;
      String errorMessage;
      BackendDAE.EquationArray eqns, reeqns;
      DAE.Exp bindExp, crefExp;
      DAE.ElementSource source;
      BackendDAE.Equation eqn;
    
    // no binding
    case((var as BackendDAE.VAR(bindExp=NONE()), (eqns, reeqns))) equation
    then ((var, (eqns, reeqns)));
    
    // binding
    case((var as BackendDAE.VAR(varName=cr, bindExp=SOME(bindExp), varType=ty, source=source), (eqns, reeqns))) equation
      crefExp = DAE.CREF(cr, ty);      
      eqn = BackendDAE.EQUATION(crefExp, bindExp, source, false);
      eqns = BackendEquation.equationAdd(eqn, eqns);
    then ((var, (eqns, reeqns)));
    
    case ((var, _)) equation
      errorMessage = "./Compiler/BackEnd/Initialization.mo: function collectInitialBindings failed for: " +& BackendDump.varString(var);
      Error.addMessage(Error.INTERNAL_ERROR, {errorMessage});
    then fail();
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/Initialization.mo: function collectInitialBindings failed"});
    then fail();
  end match;
end collectInitialBindings;

protected function collectInitialEqns "function collectInitialEqns
  author: lochel"
  input tuple<BackendDAE.Equation, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> inTpl;
  output tuple<BackendDAE.Equation, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> outTpl;
protected
  BackendDAE.Equation eqn, eqn1;
  BackendDAE.EquationArray eqns, reeqns;
  Integer size;
  Boolean b;
algorithm
  (eqn, (eqns, reeqns)) := inTpl;
  
  // replace der(x) with $DER.x and replace pre(x) with $PRE.x
  (eqn1, _) := BackendEquation.traverseBackendDAEExpsEqn(eqn, replaceDerPreCref, 0);
  
  // add it, if size is zero (terminate,assert,noretcall) move to removed equations
  size := BackendEquation.equationSize(eqn1);
  b := intGt(size, 0);
  
  eqns := Debug.bcallret2(b, BackendEquation.equationAdd, eqn1, eqns, eqns);
  reeqns := Debug.bcallret2(not b, BackendEquation.equationAdd, eqn1, reeqns, reeqns);
  outTpl := (eqn, (eqns, reeqns));
end collectInitialEqns;

protected function replaceDerPreCref "function replaceDerPreCref
  author: Frenkel TUD 2011-05
  helper for collectInitialEqns"
  input tuple<DAE.Exp, Integer> inExp;
  output tuple<DAE.Exp, Integer> outExp;
protected
   DAE.Exp e;
   Integer i;  
algorithm
  (e, i) := inExp;
  outExp := Expression.traverseExp(e, replaceDerPreCrefExp, i);
end replaceDerPreCref;

protected function replaceDerPreCrefExp "function replaceDerPreCrefExp
  author: Frenkel TUD 2011-05
  helper for replaceDerCref"
  input tuple<DAE.Exp, Integer> inExp;
  output tuple<DAE.Exp, Integer> outExp;
algorithm
  outExp := matchcontinue(inExp)
    local
      DAE.ComponentRef dummyder, cr;
      DAE.Type ty;
      Integer i;

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"), expLst = {DAE.CREF(componentRef = cr)}, attr=DAE.CALL_ATTR(ty=ty)), i)) equation
      dummyder = ComponentReference.crefPrefixDer(cr);
    then ((DAE.CREF(dummyder, ty), i+1));
    
    case ((DAE.CALL(path = Absyn.IDENT(name = "pre"), expLst = {DAE.CREF(componentRef = cr)}, attr=DAE.CALL_ATTR(ty=ty)), i)) equation
      dummyder = ComponentReference.crefPrefixPre(cr);
    then ((DAE.CREF(dummyder, ty), i+1));
      
    else
    then inExp;
  end matchcontinue;
end replaceDerPreCrefExp;

// =============================================================================
// section for probably not needed code
// 
// This section can be probably removed.
// =============================================================================

protected function collectAliasPreVars "function collectAliasPreVars
  author: jfrenkel"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,BackendDAE.Variables,BackendDAE.Variables>> inTpl;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables,BackendDAE.Variables,BackendDAE.Variables>> outTpl;
algorithm
  outTpl :=
  matchcontinue inTpl
    local  
      DAE.Exp exp;
      BackendDAE.Variables avars,vars,fixvars;
    case ((exp,(avars,vars,fixvars)))
      equation
         ((_,(avars,vars,fixvars))) = Expression.traverseExp(exp,collectAliasPreVarsExp,(avars,vars,fixvars));
       then
        ((exp,(avars,vars,fixvars)));
    case _ then inTpl;
  end matchcontinue;
end collectAliasPreVars;

protected function collectAliasPreVarsExp "function collectAliasPreVarsExp
  author: jfrenkel"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,BackendDAE.Variables,BackendDAE.Variables>> inTuple;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables,BackendDAE.Variables,BackendDAE.Variables>> outTuple;
algorithm
  outTuple := matchcontinue(inTuple)
    local
      DAE.Exp e;
      BackendDAE.Variables avars,vars,fixvars;
      DAE.ComponentRef cr;
      BackendDAE.Var v;    
    // add it?
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "pre"), expLst = {DAE.CREF(componentRef = cr)}),(avars,vars,fixvars)))
      equation
         (v::_,_) = BackendVariable.getVar(cr, avars);
         ((_,(vars,fixvars))) =  collectInitialVars((v,(vars,fixvars)));
      then
        ((e, (avars,vars,fixvars)));
    else then inTuple;
  end matchcontinue;
end collectAliasPreVarsExp;

end Initialization;
