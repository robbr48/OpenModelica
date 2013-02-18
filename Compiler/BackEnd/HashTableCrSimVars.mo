encapsulated package HashTableCrSimVars "
  This file is an extension to OpenModelica.

  Copyright (c) 2007 MathCore Engineering AB

  All rights reserved.

  file:        HashTableCrSimVars.mo
  package:     HashTableCrSimVars
  description: DAE.CR to DAE.Exp

  RCS: $Id: HashTableCrSimVars.mo 8796 2011-05-03 19:43:08Z adrpo $

  "
  
/* Below is the instance specific code. For each hashtable the user must define:

Key       - The key used to uniquely define elements in a hashtable
Value     - The data to associate with each key
hashFunc   - A function that maps a key to a positive integer.
keyEqual   - A comparison function between two keys, returns true if equal.
*/

/* HashTable instance specific code */

public import BaseHashTable;
public import DAE;
public import SimCode;
protected import ComponentReference;
protected import System;
protected import List;

public type Key = DAE.ComponentRef;
public type Value = list<SimCode.SimVar>;

public type HashTableCrefFunctionsType = tuple<FuncHashCref,FuncCrefEqual,FuncCrefStr,FuncExpStr>;
public type HashTable = tuple<
  array<list<tuple<Key,Integer>>>,
  tuple<Integer,Integer,array<Option<tuple<Key,Value>>>>,
  Integer,
  Integer,
  HashTableCrefFunctionsType
>;

partial function FuncHashCref
  input Key cr;
  input Integer mod;
  output Integer res;
end FuncHashCref;

partial function FuncCrefEqual
  input Key cr1;
  input Key cr2;
  output Boolean res;
end FuncCrefEqual;

partial function FuncCrefStr
  input Key cr;
  output String res;
end FuncCrefStr;

partial function FuncExpStr
  input Value exp;
  output String res;
end FuncExpStr;

public function emptyHashTable
"
  Returns an empty HashTable.
  Using the default bucketsize..
"
  output HashTable hashTable;
algorithm
  hashTable := emptyHashTableSized(BaseHashTable.defaultBucketSize);
end emptyHashTable;

public function emptyHashTableSized
"Returns an empty HashTable.
 Using the bucketsize size."
  input Integer size;
  output HashTable hashTable;
algorithm
  hashTable := BaseHashTable.emptyHashTableWork(size,(ComponentReference.hashComponentRefMod,ComponentReference.crefEqual,ComponentReference.printComponentRefStr,printVarListStr));
end emptyHashTableSized;

public function printVarListStr
  input list<SimCode.SimVar> ilst;
  output String res;
algorithm
  res := "{" +& stringDelimitList(List.map(ilst, simVarString), ",") +& "}";
end printVarListStr;

protected function simVarString
  input SimCode.SimVar var;
  output String res;
protected
  DAE.ComponentRef cr;
algorithm
  SimCode.SIMVAR(name=cr) := var;
  res := ComponentReference.printComponentRefStr(cr);
end simVarString;



end HashTableCrSimVars;
