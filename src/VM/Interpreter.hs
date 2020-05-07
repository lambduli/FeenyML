module VM.Interpreter where

import qualified Data.Sequence as Seq
import Data.Sequence ((<|), (|>))
import qualified Data.Map.Strict as Map
import Data.Map.Strict ((!))

import VM.Program.Value (Value(..),Index)
import VM.Value (vals, vars, super, cl, Pointer(..))
import qualified VM.Value as Runtime

import VM.Program.Instruction (Instruction(..))
-- import qualified VM.Program.Instruction as Inst

import VM.State (State(..), Context, GlobalVarMap, SubprogramDir, OperandStack, Output, ConstPool, FunctionList)
import VM.Program
import VM.Memory
import VM.Frame

import qualified VM.Lib.Stack as Stack


runProgram :: Program -> State -> Output
runProgram program state = output
  where
    CS { out = output } =
      runProgram' program state
      -- (CS
      --   { c = []
      --   , g = Map.empty
      --   , p = subProgram program
      --   , s = Stack.empty
      --   , o = Seq.empty
      --   , cp = getConstPool program
      --   , ia = 0
      --   , m = initMemory
      --   , gs = initGlobals program
      --   , fns = initFunctions program })

-- TODO: please refactor more -- this is ugly
runProgram' :: Program -> State -> State
runProgram' program@P { el = (_, addr), right = r } s@CS { instaddr = ia } =
  case r of
    [] -> if ia > addr then s else runProgram' program cs
    _ -> runProgram' program cs
    where
      P { el = (inst, _) } = setToInstruction ia program
      cs = runInstruction inst s

--
--


-- initFunctions :: Program -> FunctionList
-- initFunctions program = []

getFn :: String -> FunctionList -> Value
getFn = undefined

operand2Value :: Runtime.Value -> GlobalVarMap -> Value
operand2Value op gl = undefined

operand2RValue :: Pointer -> Memory -> Runtime.Value
operand2RValue (Pointer addr) (_, mem) = mem ! addr
-- operand2RValue val cp = const.id $ val cp
-- operand2RValue Runtime.Null _ = Runtime.Null
-- operand2RValue (Runtime.Int i) _ = Runtime.Int i

slot2String :: Value -> ConstPool -> String
slot2String (Slot i) cp = str
  where
    String str = cp ! i

valueToOperand_P :: Value -> Runtime.Value
valueToOperand_P Null = Runtime.Null
valueToOperand_P (Int i) = Runtime.Int i
-- this function is partial

variableCount :: Value -> Int
variableCount = undefined

-- getConstPool :: Program -> ConstPool
-- getConstPool = undefined

-- initGlobals :: Program -> Globals
-- initGlobals = undefined
-- TODO: iterate over Globals - Index by Index and pull each Value from Program.ConstPool by Index
-- if the value is Function/Method -> get its indexName -> get the Name from the Program.ConstPool
-- that String is the Key for the Program.GlobalVarMap and the whole Function is the Value
-- if the value is a Slot -> do basically the same thing -> but this time I don't have a value
-- either choose between Null or create another constructor for Value - like NoValue
-- and put it inside Program.GlobalVarMap by String name

-- subProgram :: Program -> SubprogramDir
-- subProgram = undefined
--
-- initMemory :: Memory
-- initMemory = (0, Map.empty)

formatOut :: String -> [Runtime.Value] -> String
formatOut = undefined

-- tohle musi vzit z Objectu Class a v te classe musi najit pozici indexu kerej ukazuje na slot s obsahem stejnym jako name
-- pak vzit tu pozici a z Object Values vzit hodnotu
-- zmenil jsem navratovy typ na Operand - proto, ze predpokladam, ze bude delat ten Refactor a zrusim Operand a Runtime Value
-- pracovat se bude jenom s jednim a ten druhej bude jenom wrapper kolem Object/Array 
-- mozna se vykaslu na wrapper a budu proste mit datatype Object a datatype Array
getObjVar :: String -> Runtime.Value -> Pointer
getObjVar name ob = undefined

-- 

getFromLocal :: Int -> Context -> Pointer
getFromLocal index (Frame { arguments = args, variables = vars } : fs) =
  (args ++ vars) !! index
-- getFromLocal index (Global Frame { arguments = args, variables = vars }) =
--   (args ++ vars) ! index
-- getFromLocal index (Local Frame { arguments = args, variables = vars } _) =
--   (args ++ vars) ! index

replaceNth :: Int -> a -> [a] -> [a]
replaceNth i e lst =
  let (first, (x : xs)) = splitAt i lst
  in first ++ e : xs

updateLocal :: Int -> Pointer -> Context -> Context
updateLocal index ptr (f@Frame { arguments = args, variables = vars } : fs)
  | index < length args = f { arguments = replaceNth index ptr args } : fs
  | index == length args = f { variables = ptr : tail vars } : fs
  | index > length args = f { variables = replaceNth (index - length args) ptr vars } : fs

getFromGlobal :: String -> GlobalVarMap -> Pointer
getFromGlobal name globals = globals ! name

updateGlobal :: String -> Pointer -> GlobalVarMap -> GlobalVarMap
updateGlobal name ptr globals = Map.insert name ptr globals

getNull :: Map.Map Int Runtime.Value -> Runtime.Value
getNull mem = mem ! 0 -- NOTE: NULL is at index 0

--
--

runInstruction :: Instruction -> State -> State
runInstruction (Lit index) cs@(CS { stack = s, constpool = cp, instaddr = ia, memory = (si, mem) }) =
  -- get index's value from the const-pool (Int or Null) and push it to the Stack 
  cs { stack = s', instaddr = ia + 1, memory = (si + 1, m') }
    where
      object = cp ! index
      m' = Map.insert si (valueToOperand_P object) mem
      s' = Stack.push (Pointer si) s

runInstruction Array cs@(CS { stack = s, instaddr = ia, memory = (si, mem) }) =
  -- pop initvalue, length from the Stack, create Array object and push it to the Stack
  cs { stack = Stack.push ptr s', instaddr = ia + 1, memory = m' }
    where
      initVal = Stack.top s
      s'' = Stack.pop s
      len = Stack.top s''
      s' = Stack.pop s''
      arr = Runtime.Array { vals = repeat initVal }
      m' = (si + 1, Map.insert si arr mem)
      ptr = Runtime.Pointer si

runInstruction (Print format count) cs@(CS { stack = s, out = o, instaddr = ia, memory = (_, mem) }) =
  -- pop count arguments from the Stack, modify the Output and push Null to the Stack
  cs { stack = s', out = o', instaddr = ia + 1 }
    where
      (ptrs, s'') = Stack.popN count s
      vals = map (\(Pointer addr) -> mem ! addr) ptrs
      s' = Stack.push (Pointer 0) s'' -- address 0 is address of NULL -- Stack.push Runtime.Null s''
      o' = o |> (formatOut format vals)

runInstruction (SetLocal index) cs@(CS { ctx = c, stack = s, instaddr = ia, memory = (_, mem) }) =
  -- set index'th value in current frame to the top Stack's value
  cs { ctx = c', stack = s', instaddr = ia + 1 }
    where
      ptr = Stack.top s
      s' = Stack.pop s
      c' = updateLocal index ptr c

runInstruction (GetLocal index) cs@(CS { ctx = c, stack = s, instaddr = ia }) =
  -- push the index'th value from local frame to the top of the Stack
  cs { stack = s', instaddr = ia + 1 }
    where
      ptr = getFromLocal index c
      s' = Stack.push ptr s

runInstruction (SetGlobal index) cs@(CS { gvm = g, stack = s, constpool = cp, instaddr = ia }) =
  -- set the global variable named as index'th String slot to the top of the Stack
  cs { gvm = g', stack = s', instaddr = ia + 1 }
    where
      name = slot2String (cp ! index) cp
      ptr = Stack.top s
      s' = Stack.pop s
      g' = updateGlobal name ptr g

runInstruction (GetGlobal index) cs@(CS { gvm = g, stack = s, constpool = cp, instaddr = ia }) =
  -- get global variable named as index'th String slot and push it's value to the top of the Stack
  cs { stack = s', instaddr = ia + 1 }
    where
      name = slot2String (cp ! index) cp
      ptr = getFromGlobal name g
      s' = Stack.push ptr s

runInstruction Drop cs@(CS { stack = s, instaddr = ia }) =
  -- pop single value
  cs { stack = s', instaddr = ia + 1 }
    where
      s' = Stack.pop s

runInstruction (Object index) cs@(CS { ctx = c, stack = s, constpool = cp, instaddr = ia, memory = (si, mem) }) =
  -- get Object's class at index, then check how many variables it has, pop so many values from the Stack and pop one more - superclass, then push the Object on the Stack
  cs { stack = s', instaddr = ia + 1, memory = m' }
    where
      cl = cp ! index
      count = variableCount cl
      (ptrs, s''') = Stack.popN count s
      super = Stack.top s'''
      s'' = Stack.pop s'''
      o = Runtime.Object { vars = ptrs, super = super, cl = cp ! index }
      m' = (si + 1, Map.insert si o mem)
      s' = Stack.push (Pointer si) s

runInstruction (GetSlot index) cs@(CS { stack = s, constpool = cp, instaddr = ia, memory = (_, mem) }) =
  -- pop Object from the Stack, index'th slot is String - Object variable name which's value will be pushed to the Stack
  cs { stack = s', instaddr = ia + 1 }
    where
      Pointer addr = Stack.top s
      ob = mem ! addr
      s'' = Stack.pop s
      name = slot2String (cp ! index) cp
      ptr = getObjVar name ob
      s' = Stack.push ptr s''

runInstruction (SetSlot index) cs@(CS { ctx = c, stack = s, constpool = cp, instaddr = ia, memory = (si, mem) }) =
  -- pop value, pop Object, then change the variable named as index'th in the Object to the firstly poped value
  cs { stack = s', instaddr = ia + 1, memory = m' }
    where
      Pointer valAddr = Stack.top s
      val = mem ! valAddr
      s'' = Stack.pop s
      Pointer addr = Stack.top s''
      s' = Stack.pop s''
      name = slot2String (cp ! index) cp
      ob = case mem ! addr of
        Runtime.Object { vars = vs, super = su, cl = cl } -> undefined
          -- search through cl for slot which points to the value with the content of the name
          -- then return position on which this slot is in the class list of slots
          -- then in the object on the same position there's gonna be value which needs to be changed
      m' = (si, Map.insert addr ob mem)

-- TODO: implement
-- abstraction for the syntax sugars like: arr[0], arr[n], 3 + 4
runInstruction (CallSlot index count) cs@(CS { ctx = c, labels = l, stack = s, out = o, constpool = cp, instaddr = ia }) = undefined
-- this has to implement stuff like arr[i] and numA + numB
  -- when assigning variables to the Frame - check if the value is Object or Array - then store the name to the Object or Array 
  -- pop count values from the Stack, pop receiver Object, index points to the String - name of the method, then call the method

runInstruction (Label index) cs = cs
  -- names the current instruction, index points to the String with the name
  -- probably not gonna do anything

runInstruction (Branch index) cs@(CS { labels = l, stack = s, constpool = cp, instaddr = ia, memory = (_, mem) }) =
  -- pop value from the Stack, if the value is not Null, then jump to the index'th Label
  cs { stack = s', instaddr = ia' }
    where
      Pointer addr = Stack.top s
      val = mem ! addr
      s' = Stack.pop s
      label = cp ! index
      ia' =
        case val of
          Runtime.Null -> ia + 1
          _ -> l ! (slot2String label cp) -- TODO: maybe check if label is (Slot addr)

runInstruction (Goto index) cs@(CS { labels = l, constpool = cp, instaddr = ia, memory = (_, mem) }) =
  -- jump to the index'th Label
  cs { instaddr = ia' }
    where
      String str = cp ! index
      -- slot = mem ! str
      -- name = slot2String slot cp
      ia' = l ! str

runInstruction (Return) cs@(CS { ctx = (Frame { caller = r } : fs), instaddr = ia }) =
  cs { ctx = fs, instaddr = r }

runInstruction (Call index count) cs@(CS { ctx = c, gvm = g, stack = s, constpool = cp, instaddr = ia, memory = (_, mem), fns = fns }) =
  -- pop count values from the Stack, the name of the function is at the indexth slot
  state { instaddr = ia + 1 }
    where
      name = slot2String (cp ! index) cp
      (ptrs, s') = Stack.popN count s
      Function { argsCnt = argC, varsCnt = varC, body = b } = getFn name fns --       g ! name
      initVals = replicate varC (Pointer 0) -- Runtime.Null
      bodyProg = instructions2Program b
      state =
        runProgram' bodyProg $ cs { ctx = Frame { arguments = ptrs, variables = initVals, caller = ia } : c, stack = s', instaddr = 0 }
