module VM.Machine where

import qualified Data.Sequence as Seq
import qualified Data.Map.Strict as Map
import VM.Data.Value (Value(..), Operand(..), Index, RuntimeValue(..))
import qualified VM.Data.Value as Dat
import VM.Data.Instruction (Instruction(..))
import qualified VM.Data.Instruction as Inst
import VM.State (State(..), Context, GlobalVarMap, SubprogramDir, OperandStack, Output, ConstPool)
import VM.Data.Program
import VM.Data.Memory
import VM.Data.Frame


runProgram :: Program -> Output
runProgram program =
  runProgram' program (CS { c = initMemory, p = subProgram program, s = empty, o = Seq.empty, cp = getConstPool program })

runProgram' :: Program -> State -> State
runProgram' p@P { left = l, elem = EOP, right = [] } s = s

runProgram' p@P { left = l, elem = e, right = r } state =
  runProgram (setToInstruction ia p) cs
    where
      cs@CS { ia = ia } = runInstruction e state

--
--

valueToOperand_P :: Value -> Operand
valueToOperand_P Null = Null
valueToOperand_P Int i = Int i
-- this function is partial

getConstPool :: Program -> ConstPool
getConstPool = undefined

subProgram :: Program -> SubprogramDir
subProgram = undefined
--
initMemory :: Memory
initMemory = (0, Map.empty)

formatOut :: String -> [Operand] -> String
formatOut = undefined

-- tohle musi vzit z Objectu Class a v te classe musi najit pozici indexu kerej ukazuje na slot s obsahem stejnym jako name
-- pak vzit tu pozici a z Object Values vzit hodnotu
getObjVar :: String -> RuntimeValue -> RuntimeValue
getObjVar name ob = undefined

-- 

getFromLocal :: Int -> Context -> Operand
getFromLocal index (Frame { arguments = args, variables = vars } : fs) =
  (args ++ vars) ! index
-- getFromLocal index (Global Frame { arguments = args, variables = vars }) =
--   (args ++ vars) ! index
-- getFromLocal index (Local Frame { arguments = args, variables = vars } _) =
--   (args ++ vars) ! index

replaceNth :: Int -> [a] -> a -> [a]
replaceNth i lst e =
  let (first, (x : xs)) = splitAt i
  in first ++ e : xs

updateLocal :: Int -> Operand -> Context -> Context
updateLocal index value f@Frame { arguments = args, variables = vars }
  | index < args.length = f { arguments = replaceNth index args }
  | index == args.length = f { variables = value : tail vars }
  | index > args.length = f { variables = replaceNth (index - args.length) vars }

getFromGlobal :: String -> GlobalVarMap -> Operand
getFromGlobal name globals = globals ! name

updateGlobal :: String -> Operand -> GlobalVarMap -> GlobalVarMap
updateGlobal name value globals = Map.insert name value

--
--

runInstruction :: Instruction -> State -> State
runInstruction (Lit index) cs@(CS { c = c, p = p, s = s, o = o, cp = cp, ia = ia }) =
  -- get index's value from the const-pool (Int or Null) and push it to the Stack 
  cs { s = push (valueToOperand_P $ cp ! index) s, ia = ia + 1 }

runInstruction Inst.Array cs@(CS { s = s, ia = ia, m = (si, mem) }) =
  -- pop initvalue, length from the Stack, create Array object and push it to the Stack
  cs { s = push ptr s', ia = ia + 1, m = m' }
    where
      initVal = top s
      s'' = pop s
      len = top s''
      s' = pop s''
      arr = Dat.Array { vals = repeat initVal }
      ptr = s
      m' = (si + 1, Map.insert s arr)

runInstruction (Print format count) cs@(CS { s = s, o = o, ia = ia }) =
  -- pop count arguments from the Stack, modify the Output and push Null to the Stack
  cs { s = s', o = o', ia = ia + 1 }
    where
      (vals, s'') = popN count s
      s' = push Null s''
      o' = o |> (formatOut format vals)

runInstruction (SetLocal index) cs@(CS { c = c, s = s, ia = ia }) =
  -- set index'th value in current frame to the top Stack's value
  cs { c = c', s = s', ia = ia + 1 }
    where
      v = top s
      s' = pop s
      c' = updateLocal index v c

runInstruction (GetLocal index) cs@(CS { c = c, s = s, ia = ia }) =
  -- push the index'th value from local frame to the top of the Stack
  cs { c = c', s = s', ia = ia + 1 }
    where
      v = getFromLocal index c
      s' = push v s

runInstruction (SetGlobal index) cs@(CS { g = g, s = s, cp = cp, ia = ia }) =
  -- set the global variable named as index'th String slot to the top of the Stack
  cs { g = g', s = s', ia = ia + 1 }
    where
      name = cp ! index
      v = top s
      s' = pop s
      g' = updateGlobal name v g

runInstruction (GetGlobal index) cs@(CS { g = g, s = s, cp = cp, ia = ia }) =
  -- get global variable named as index'th String slot and push it's value to the top of the Stack
  cs { s = s', ia = ia + 1 }
    where
      name = cp ! index
      v = getFromGlobal name g
      s' = push v s

runInstruction Drop cs@(CS { s = s, ia = ia }) =
  -- pop single value
  cs { s = s', ia = ia + 1 }
    where
      s' = pop s

runInstruction (Inst.Object index) cs@(CS { c = c, p = p, s = s, o = o, cp = cp, ia = ia, m = (si, mem) }) =
  -- get Object's class at index, then check how many variables it has, pop so many values from the Stack and pop one more - superclass, then push the Object on the Stack
  cs { s = s', ia = ia + 1, m = m' }
    where
      cl = cp ! i
      count = variableCount cl
      vals = popN count s
      super = top s
      s'' = pop s
      o = Dat.Object { vars = vals, super = super, cl = cp ! index }
      m' = (si + 1, Map.insert s o)
      s' = push $ Pointer s

runInstruction (GetSlot index) cs@(CS { s = s, cp = cp, ia = ia, m = (_, mem) }) =
  -- pop Object from the Stack, index'th slot is String - Object variable name which's value will be pushed to the Stack
  cs { s = s', ia = ia + 1 }
    where
      Pointer addr = top s
      ob = mem ! addr
      s'' = pop top
      name = cp ! index
      val = getObjVar name ob
      s' = push val s''

runInstruction (SetSlot index) cs@(CS { c = c, s = s, cp = cp, ia = ia, m = (si, mem) }) =
  -- pop value, pop Object, then change the variable named as index'th in the Object to the firstly poped value
  cs { s = s', ia = ia + 1, m = m' }
    where
      val = top s
      s'' = pop s
      Pointer addr = top s''
      s' = pop s''
      name = cp ! index
      ob = case map ! add of
        Dat.Object { vars = vs, super = su, cl = cl } -> undefined
          -- search through cl for slot which points to the value with the content of the name
          -- then return position on which this slot is in the class list of slots
          -- then in the object on the same position there's gonna be value which needs to be changed
      m' = (si, Map.insert addr ob mem)

-- TODO: implement
-- abstraction for the syntax sugars like: arr[0], arr[n], 3 + 4
runInstruction (CallSlot index count) cs@(CS { c = c, p = p, s = s, o = o, cp = cp, ia = ia }) = undefined
-- this has to implement stuff like arr[i] and numA + numB
  -- when assigning variables to the Frame - check if the value is Object or Array - then store the name to the Object or Array 
  -- pop count values from the Stack, pop receiver Object, index points to the String - name of the method, then call the method

runInstruction (Label index) cs = cs
  -- names the current instruction, index points to the String with the name
  -- probably not gonna do anything

runInstruction (Branch index) cs@(CS { s = s, ia = ia }) =
  -- pop value from the Stack, if the value is not Null, then jump to the index'th Label
  cs { s = s', ia = ia + 1 }
    where
      v = top s
      s' = pop s
      ia' =
        case v of
          Null -> s ! cp ! index
          _ -> ia + 1

runInstruction (Goto index) cs@(CS { ia = ia }) =
  -- jump to the index'th Label
  cs { ia = ia' }
    where
      name = cp ! index
      ia' = s ! name

-- TODO: implement
runInstruction (Call index count) cs@(CS { c = c, g = g, p = p, s = s, o = o, cp = cp, ia = ia, m = m }) =
  -- 
  --


  -- also when the value is Object or Array, give the Object or Array it's real name 
  -- index point to the function name, count is number of values to pop from the Stack - arguments
  -- 
  cs {}
    where
      -- how is a function executed?
      -- you add new Frame to the chain and then what?
      -- then I need to execute the body of the function
      -- when the function ends its execution I need to drop one Frame from the State and continue
      -- no dropping - current Context is - Global + Local
      -- when calling function I take the Global part and create fresh new Local
      -- when execution ends - i just keep going with Global + Local from before
