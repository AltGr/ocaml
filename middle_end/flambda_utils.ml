(**************************************************************************)
(*                                                                        *)
(*                                OCaml                                   *)
(*                                                                        *)
(*                       Pierre Chambart, OCamlPro                        *)
(*                  Mark Shinwell, Jane Street Europe                     *)
(*                                                                        *)
(*   Copyright 2015 Institut National de Recherche en Informatique et     *)
(*   en Automatique.  All rights reserved.  This file is distributed      *)
(*   under the terms of the Q Public License version 1.0.                 *)
(*                                                                        *)
(**************************************************************************)

let find_declaration cf ({ funs } : Flambda.function_declarations) =
  Variable.Map.find (Closure_id.unwrap cf) funs

let find_declaration_variable cf ({ funs } : Flambda.function_declarations) =
  let var = Closure_id.unwrap cf in
  if not (Variable.Map.mem var funs)
  then raise Not_found
  else var

let find_free_variable cv ({ free_vars } : Flambda.set_of_closures) =
  Variable.Map.find (Var_within_closure.unwrap cv) free_vars

let function_arity (f : Flambda.function_declaration) = List.length f.params

let variables_bound_by_the_closure cf
      (decls : Flambda.function_declarations) =
  let func = find_declaration cf decls in
  let params = Variable.Set.of_list func.params in
  let functions = Variable.Map.keys decls.funs in
  Variable.Set.diff
    (Variable.Set.diff func.free_variables params)
    functions

let description_of_toplevel_node (expr : Flambda.t) =
  match expr with
  | Var id -> Format.asprintf "var %a" Variable.print id
  | Apply _ -> "apply"
  | Assign _ -> "assign"
  | Send _ -> "send"
  | Proved_unreachable -> "unreachable"
  | Let { var; _ } -> Format.asprintf "let %a" Variable.print var
  | Let_mutable _ -> "let_mutable"
  | Let_rec _ -> "letrec"
  | If_then_else _ -> "if"
  | Switch _ -> "switch"
  | String_switch _ -> "stringswitch"
  | Static_raise  _ -> "staticraise"
  | Static_catch  _ -> "catch"
  | Try_with _ -> "trywith"
  | While _ -> "while"
  | For _ -> "for"

let compare_const (c1 : Flambda.const) (c2 : Flambda.const) =
  match c1, c2 with
  | Int v1, Int v2 -> compare v1 v2
  | Char v1, Char v2 -> compare v1 v2
  | Const_pointer v1, Const_pointer v2 -> compare v1 v2
  | Int _, _ -> -1
  | _, Int _ -> 1
  | Char _, _ -> -1
  | _, Char _ -> 1

let rec same (l1 : Flambda.t) (l2 : Flambda.t) =
  l1 == l2 || (* it is ok for the string case: if they are physically the same,
                 it is the same original branch *)
  match (l1, l2) with
  | Var v1 , Var v2  -> Variable.equal v1 v2
  | Var _, _ | _, Var _ -> false
  | Apply a1 , Apply a2  ->
    a1.kind = a2.kind
      && Variable.equal a1.func a2.func
      && Misc.samelist Variable.equal a1.args a2.args
  | Apply _, _ | _, Apply _ -> false
  | Let { var = var1; defining_expr = defining_expr1; body = body1; _ },
      Let { var = var2; defining_expr = defining_expr2; body = body2; _ } ->
    Variable.equal var1 var2 && same_named defining_expr1 defining_expr2
      && same body1 body2
  | Let _, _ | _, Let _ -> false
  | Let_mutable (mv1, v1, b1), Let_mutable (mv2, v2, b2) ->
    Mutable_variable.equal mv1 mv2
      && Variable.equal v1 v2
      && same b1 b2
  | Let_mutable _, _ | _, Let_mutable _ -> false
  | Let_rec (bl1, a1), Let_rec (bl2, a2) ->
    Misc.samelist samebinding bl1 bl2 && same a1 a2
  | Let_rec _, _ | _, Let_rec _ -> false
  | Switch (a1, s1), Switch (a2, s2) ->
    Variable.equal a1 a2 && sameswitch s1 s2
  | Switch _, _ | _, Switch _ -> false
  | String_switch (a1, s1, d1), String_switch (a2, s2, d2) ->
    Variable.equal a1 a2 &&
      Misc.samelist (fun (s1, e1) (s2, e2) -> s1 = s2 && same e1 e2) s1 s2 &&
      Misc.sameoption same d1 d2
  | String_switch _, _ | _, String_switch _ -> false
  | Static_raise (e1, a1), Static_raise (e2, a2) ->
    Static_exception.equal e1 e2 && Misc.samelist same a1 a2
  | Static_raise _, _ | _, Static_raise _ -> false
  | Static_catch (s1, v1, a1, b1), Static_catch (s2, v2, a2, b2) ->
    Static_exception.equal s1 s2 && Misc.samelist Variable.equal v1 v2 &&
      same a1 a2 && same b1 b2
  | Static_catch _, _ | _, Static_catch _ -> false
  | Try_with (a1, v1, b1), Try_with (a2, v2, b2) ->
    same a1 a2 && Variable.equal v1 v2 && same b1 b2
  | Try_with _, _ | _, Try_with _ -> false
  | If_then_else (a1, b1, c1), If_then_else (a2, b2, c2) ->
    Variable.equal a1 a2 && same b1 b2 && same c1 c2
  | If_then_else _, _ | _, If_then_else _ -> false
  | While (a1, b1), While (a2, b2) ->
    same a1 a2 && same b1 b2
  | While _, _ | _, While _ -> false
  | For { bound_var = bound_var1; from_value = from_value1;
          to_value = to_value1; direction = direction1; body = body1; },
    For { bound_var = bound_var2; from_value = from_value2;
          to_value = to_value2; direction = direction2; body = body2; } ->
    Variable.equal bound_var1 bound_var2
      && Variable.equal from_value1 from_value2
      && Variable.equal to_value1 to_value2
      && direction1 = direction2
      && same body1 body2
  | For _, _ | _, For _ -> false
  | Assign { being_assigned = being_assigned1; new_value = new_value1; },
    Assign { being_assigned = being_assigned2; new_value = new_value2; } ->
    Mutable_variable.equal being_assigned1 being_assigned2
      && Variable.equal new_value1 new_value2
  | Assign _, _ | _, Assign _ -> false
  | Send { kind = kind1; meth = meth1; obj = obj1; args = args1; dbg = _; },
    Send { kind = kind2; meth = meth2; obj = obj2; args = args2; dbg = _; } ->
    kind1 = kind2
      && Variable.equal meth1 meth2
      && Variable.equal obj1 obj2
      && Misc.samelist Variable.equal args1 args2
  | Send _, _ | _, Send _ -> false
  | Proved_unreachable, Proved_unreachable -> true

and same_named (named1 : Flambda.named) (named2 : Flambda.named) =
  match named1, named2 with
  | Symbol s1 , Symbol s2  -> Symbol.equal s1 s2
  | Symbol _, _ | _, Symbol _ -> false
  | Const c1, Const c2 -> compare_const c1 c2 = 0
  | Const _, _ | _, Const _ -> false
  | Allocated_const c1, Allocated_const c2 ->
    Allocated_const.compare c1 c2 = 0
  | Allocated_const _, _ | _, Allocated_const _ -> false
  | Read_mutable mv1, Read_mutable mv2 -> Mutable_variable.equal mv1 mv2
  | Read_mutable _, _ | _, Read_mutable _ -> false
  | Read_symbol_field (s1, i1), Read_symbol_field (s2, i2) ->
    Symbol.equal s1 s2 && i1 = i2
  | Read_symbol_field _, _ | _, Read_symbol_field _ -> false
  | Set_of_closures s1, Set_of_closures s2 -> same_set_of_closures s1 s2
  | Set_of_closures _, _ | _, Set_of_closures _ -> false
  | Project_closure f1, Project_closure f2 -> same_project_closure f1 f2
  | Project_closure _, _ | _, Project_closure _ -> false
  | Project_var v1, Project_var v2 ->
    Variable.equal v1.closure v2.closure
      && Closure_id.equal v1.closure_id v2.closure_id
      && Var_within_closure.equal v1.var v2.var
  | Project_var _, _ | _, Project_var _ -> false
  | Move_within_set_of_closures m1, Move_within_set_of_closures m2 ->
    same_move_within_set_of_closures m1 m2
  | Move_within_set_of_closures _, _ | _, Move_within_set_of_closures _ ->
    false
  | Prim (p1, al1, _), Prim (p2, al2, _) ->
    p1 = p2 && Misc.samelist Variable.equal al1 al2
  | Prim _, _ | _, Prim _ -> false
  | Expr e1, Expr e2 -> same e1 e2

and sameclosure (c1 : Flambda.function_declaration)
      (c2 : Flambda.function_declaration) =
  Misc.samelist Variable.equal c1.params c2.params
    && same c1.body c2.body

and same_set_of_closures (c1 : Flambda.set_of_closures)
      (c2 : Flambda.set_of_closures) =
  Variable.Map.equal sameclosure c1.function_decls.funs c2.function_decls.funs
    && Variable.Map.equal Variable.equal c1.free_vars c2.free_vars
    && Variable.Map.equal Variable.equal c1.specialised_args
        c2.specialised_args

and same_project_closure (s1 : Flambda.project_closure)
      (s2 : Flambda.project_closure) =
  Variable.equal s1.set_of_closures s2.set_of_closures
    && Closure_id.equal s1.closure_id s2.closure_id

and same_move_within_set_of_closures (m1 : Flambda.move_within_set_of_closures)
      (m2 : Flambda.move_within_set_of_closures) =
  Variable.equal m1.closure m2.closure
    && Closure_id.equal m1.start_from m2.start_from
    && Closure_id.equal m1.move_to m2.move_to

and samebinding (v1, n1) (v2, n2) =
  Variable.equal v1 v2 && same_named n1 n2

and sameswitch (fs1 : Flambda.switch) (fs2 : Flambda.switch) =
  let samecase (n1, a1) (n2, a2) = n1 = n2 && same a1 a2 in
  fs1.numconsts = fs2.numconsts
    && fs1.numblocks = fs2.numblocks
    && Misc.samelist samecase fs1.consts fs2.consts
    && Misc.samelist samecase fs1.blocks fs2.blocks
    && Misc.sameoption same fs1.failaction fs2.failaction

let can_be_merged = same

(* CR mshinwell: change "toplevel" name, potentially misleading *)
(* CR mshinwell: this should use the explicit ignore functions *)
let toplevel_substitution sb tree =
  let sb v = try Variable.Map.find v sb with Not_found -> v in
  let aux (flam : Flambda.t) : Flambda.t =
    match flam with
    | Var var -> Var (sb var)
    | Let_mutable (mut_var, var, body) ->
      Let_mutable (mut_var, sb var, body)
    | Assign { being_assigned; new_value; } ->
      Assign { being_assigned; new_value = sb new_value; }
    | Apply { func; args; kind; dbg; } ->
      Apply { func = sb func; args = List.map sb args; kind; dbg; }
    | If_then_else (cond, e1, e2) -> If_then_else (sb cond, e1, e2)
    | Switch (cond, sw) -> Switch (sb cond, sw)
    | String_switch (cond, branches, def) ->
      String_switch (sb cond, branches, def)
    | Send { kind; meth; obj; args; dbg } ->
      Send { kind; meth = sb meth; obj = sb obj; args = List.map sb args; dbg }
    | For { bound_var; from_value; to_value; direction; body } ->
      For { bound_var; from_value = sb from_value; to_value = sb to_value;
            direction; body }
    | Static_raise _ | Static_catch _ | Try_with _ | While _
    | Let _ | Let_rec _ | Proved_unreachable -> flam
  in
  let aux_named (named : Flambda.named) : Flambda.named =
    match named with
    | Symbol _ | Const _ | Expr _ -> named
    | Allocated_const _ | Read_mutable _ -> named
    | Read_symbol_field _ -> named
    | Set_of_closures set_of_closures ->
      let set_of_closures =
        Flambda.create_set_of_closures
          ~function_decls:set_of_closures.function_decls
          ~free_vars:(Variable.Map.map sb set_of_closures.free_vars)
          ~specialised_args:
            (Variable.Map.map sb set_of_closures.specialised_args)
      in
      Set_of_closures set_of_closures
    | Project_closure project_closure ->
      Project_closure {
        project_closure with
        set_of_closures = sb project_closure.set_of_closures;
      }
    | Move_within_set_of_closures move_within_set_of_closures ->
      Move_within_set_of_closures {
        move_within_set_of_closures with
        closure = sb move_within_set_of_closures.closure;
      }
    | Project_var project_var ->
      Project_var {
        project_var with
        closure = sb project_var.closure;
      }
    | Prim (prim, args, dbg) ->
      Prim (prim, List.map sb args, dbg)
  in
  Flambda_iterators.map_toplevel aux aux_named tree

let make_closure_declaration ~id ~body ~params : Flambda.t =
  let free_variables = Flambda.free_variables body in
  let param_set = Variable.Set.of_list params in
  if not (Variable.Set.subset param_set free_variables) then begin
    Misc.fatal_error "Flambda_utils.make_closure_declaration"
  end;
  let sb =
    Variable.Set.fold
      (fun id sb -> Variable.Map.add id (Variable.freshen id) sb)
      free_variables Variable.Map.empty in
  let body = toplevel_substitution sb body in
  let subst id = Variable.Map.find id sb in
  let function_declaration =
    Flambda.create_function_declaration ~params:(List.map subst params)
      ~body ~stub:false ~dbg:Debuginfo.none
  in
  assert (Variable.Set.equal (Variable.Set.map subst free_variables)
    function_declaration.free_variables);
  let free_vars =
    (* CR mshinwell: can be simplified now *)
    Variable.Map.fold (fun id id' fv' ->
        Variable.Map.add id' id fv')
      (Variable.Map.filter (fun id _ -> not (Variable.Set.mem id param_set)) sb)
      Variable.Map.empty
  in
  let compilation_unit = Compilation_unit.get_current_exn () in
  let set_of_closures_var =
    Variable.create "set_of_closures"
      ~current_compilation_unit:compilation_unit
  in
  let set_of_closures =
    let function_decls =
      Flambda.create_function_declarations
        ~set_of_closures_id:(Set_of_closures_id.create compilation_unit)
        ~funs:(Variable.Map.singleton id function_declaration)
        ~compilation_unit
    in
    Flambda.create_set_of_closures ~function_decls ~free_vars
      ~specialised_args:Variable.Map.empty
  in
  let project_closure : Flambda.named =
    Project_closure {
        set_of_closures = set_of_closures_var;
        closure_id = Closure_id.wrap id;
      }
  in
  let project_closure_var =
    Variable.create "project_closure"
      ~current_compilation_unit:compilation_unit
  in
  Flambda.create_let set_of_closures_var (Set_of_closures set_of_closures)
    (Flambda.create_let project_closure_var project_closure
      (Var (project_closure_var)))

let bind ~bindings ~body =
  List.fold_left (fun expr (var, var_def) ->
      Flambda.create_let var var_def expr)
    body bindings

let name_expr ?(name = "named") (named : Flambda.named) : Flambda.t =
  let var =
    Variable.create
      ~current_compilation_unit:(Compilation_unit.get_current_exn ())
      name
  in
  Flambda.create_let var named (Var var)

let rec all_lifted_constants (program : Flambda.program) =
  match program with
  | Let_symbol (symbol, decl, program) ->
    (symbol, decl) ::
    (all_lifted_constants program)
  | Let_rec_symbol (decls, program) ->
    List.fold_left (fun l (symbol, decl) ->
        (symbol, decl) :: l)
      (all_lifted_constants program)
      decls
  | Initialize_symbol (_, _, _, program)
  | Effect (_, program)
  | Import_symbol (_, program) ->
    all_lifted_constants program
  | End _ -> []

let all_lifted_constants_as_map program =
  Symbol.Map.of_list (all_lifted_constants program)

let rec initialize_symbols (program:Flambda.program) =
  match program with
  | Initialize_symbol (symbol, tag, fields, program) ->
    (symbol, tag, fields) :: (initialize_symbols program)
  | Effect (_, program)
  | Let_symbol (_, _, program)
  | Let_rec_symbol (_, program)
  | Import_symbol (_, program) ->
    initialize_symbols program
  | End _ -> []

let rec imported_symbols (program:Flambda.program) =
  match program with
  | Effect (_, program)
  | Let_symbol (_, _, program)
  | Let_rec_symbol (_, program)
  | Initialize_symbol (_, _, _, program) ->
    imported_symbols program
  | Import_symbol (symbol, program) ->
    Symbol.Set.add symbol (imported_symbols program)
  | End _ ->
    Symbol.Set.empty

let needed_import_symbols (program:Flambda.program) =
  let dependencies =
    let set = ref Symbol.Set.empty in
    Flambda_iterators.iter_symbols_on_program program
      ~f:(fun s -> set := Symbol.Set.add s !set);
    !set
  in
  let defined_symbol =
    Symbol.Set.union
      (Symbol.Set.of_list
         (List.map fst (all_lifted_constants program)))
      (Symbol.Set.of_list
         (List.map (fun (s, _, _) -> s) (initialize_symbols program)))
  in
  Symbol.Set.diff dependencies defined_symbol

let introduce_needed_import_symbols program : Flambda.program =
  Symbol.Set.fold (fun symbol program ->
      Flambda.Import_symbol (symbol, program))
    (Symbol.Set.diff
       (needed_import_symbols program)
       (imported_symbols program))
    program

let rec root_symbol (program:Flambda.program) =
  match program with
  | Effect (_, program)
  | Let_symbol (_, _, program)
  | Let_rec_symbol (_, program)
  | Initialize_symbol (_, _, _, program)
  | Import_symbol (_, program) ->
    root_symbol program
  | End root ->
    root

let might_raise_static_exn flam stexn =
  try
    Flambda_iterators.iter_on_named
      (function
        | Flambda.Static_raise (ex, _) when Static_exception.equal ex stexn ->
          raise Exit
        | _ -> ())
      (fun _ -> ())
      flam;
    false
  with Exit -> true

let make_closure_map program =
  let map = ref Closure_id.Map.empty in
  let add_set_of_closures : Flambda.set_of_closures -> unit = fun
    { function_decls } ->
    Variable.Map.iter (fun var _ ->
        let closure_id = Closure_id.wrap var in
        map := Closure_id.Map.add closure_id function_decls !map)
      function_decls.funs
  in
  Flambda_iterators.iter_on_set_of_closures_of_program
    program
    ~f:add_set_of_closures;
  !map

let make_closure_map' input =
  let map = ref Closure_id.Map.empty in
  let add_set_of_closures _ (function_decls : Flambda.function_declarations) =
    Variable.Map.iter (fun var _ ->
        let closure_id = Closure_id.wrap var in
        map := Closure_id.Map.add closure_id function_decls !map)
      function_decls.funs
  in
  Set_of_closures_id.Map.iter add_set_of_closures input;
  !map

let all_lifted_constant_sets_of_closures program =
  let set = ref Set_of_closures_id.Set.empty in
  List.iter (function
      | (_, Flambda.Set_of_closures {
          function_decls = { set_of_closures_id } }) ->
        set := Set_of_closures_id.Set.add set_of_closures_id !set
      | _ -> ())
    (all_lifted_constants program);
  !set

let all_sets_of_closures program =
  let list = ref [] in
  Flambda_iterators.iter_on_set_of_closures_of_program program
    ~f:(fun set_of_closures ->
        list := set_of_closures :: !list);
  !list

let make_variable_symbol var =
  Symbol.create (Compilation_unit.get_current_exn ())
    (Linkage_name.create
       (Variable.unique_name (Variable.freshen var)))

let substitute_variable_to_symbol substitution expr =
  let bind var fresh_var (expr:Flambda.t) : Flambda.t =
    let symbol = Variable.Map.find var substitution in
    Flambda.create_let fresh_var (Read_symbol_field (symbol, 0)) expr
  in
  let substitute_named bindings (named:Flambda.named) : Flambda.named =
    let sb to_substitute =
      try Variable.Map.find to_substitute bindings with
      | Not_found ->
        to_substitute
    in
    match named with
    | Symbol _ | Const _ | Expr _ -> named
    | Allocated_const _ | Read_mutable _ -> named
    | Read_symbol_field _ -> named
    | Set_of_closures set_of_closures ->
      let set_of_closures =
        Flambda.create_set_of_closures
          ~function_decls:set_of_closures.function_decls
          ~free_vars:(Variable.Map.map sb set_of_closures.free_vars)
          ~specialised_args:
            (Variable.Map.map sb set_of_closures.specialised_args)
      in
      Set_of_closures set_of_closures
    | Project_closure project_closure ->
      Project_closure {
        project_closure with
        set_of_closures = sb project_closure.set_of_closures;
      }
    | Move_within_set_of_closures move_within_set_of_closures ->
      Move_within_set_of_closures {
        move_within_set_of_closures with
        closure = sb move_within_set_of_closures.closure;
      }
    | Project_var project_var ->
      Project_var {
        project_var with
        closure = sb project_var.closure;
      }
    | Prim (prim, args, dbg) ->
      Prim (prim, List.map sb args, dbg)
  in
  let make_var_subst var =
    if Variable.Map.mem var substitution then
      let fresh = Variable.freshen var in
      fresh, (fun expr -> bind var fresh expr)
    else
      var, (fun x -> x)
  in
  let f (expr:Flambda.t) : Flambda.t =
    match expr with
    | Var v when Variable.Map.mem v substitution ->
      let fresh = Variable.freshen v in
      bind v fresh (Var fresh)
    | Var _ -> expr
    | Let ({ var = v; defining_expr = named; _ } as let_expr) ->
      let to_substitute =
        Variable.Set.filter
          (fun v -> Variable.Map.mem v substitution)
          (Flambda.free_variables_named named)
      in
      if Variable.Set.is_empty to_substitute then
        expr
      else
        let bindings =
          Variable.Map.of_set Variable.freshen to_substitute
        in
        let named =
          substitute_named bindings named
        in
        let expr =
          let module W = Flambda.With_free_variables in
          W.create_let_reusing_body v named (W.of_body_of_let let_expr)
        in
        Variable.Map.fold (fun to_substitute fresh expr ->
            bind to_substitute fresh expr)
          bindings expr
    | Let_mutable (mut_var, var, body) when Variable.Map.mem var substitution ->
      let fresh = Variable.freshen var in
      bind var fresh (Let_mutable (mut_var, fresh, body))
    | Let_mutable (_mut_var, _var, _body) ->
      expr
    | Let_rec (defs, body) ->
      let free_variables_of_defs =
        List.fold_left (fun set (_, named) ->
            Variable.Set.union set (Flambda.free_variables_named named))
          Variable.Set.empty defs
      in
      let to_substitute =
        Variable.Set.filter
          (fun v -> Variable.Map.mem v substitution)
          free_variables_of_defs
      in
      if Variable.Set.is_empty to_substitute then
        expr
      else begin
        let bindings =
          Variable.Map.of_set Variable.freshen to_substitute
        in
        let defs =
          List.map (fun (var, named) ->
              var, substitute_named bindings named)
            defs
        in
        let expr =
          Flambda.Let_rec (defs, body)
        in
        Variable.Map.fold (fun to_substitute fresh expr ->
            bind to_substitute fresh expr)
          bindings expr
      end
    | If_then_else (cond, ifso, ifnot) when Variable.Map.mem cond substitution ->
      let fresh = Variable.freshen cond in
      bind cond fresh (If_then_else (fresh, ifso, ifnot))
    | If_then_else _ ->
      expr
    | Switch (cond, sw) when Variable.Map.mem cond substitution ->
      let fresh = Variable.freshen cond in
      bind cond fresh (Switch (fresh, sw))
    | Switch _ ->
      expr
    | String_switch (cond, sw, def) when Variable.Map.mem cond substitution ->
      let fresh = Variable.freshen cond in
      bind cond fresh (String_switch (fresh, sw, def))
    | String_switch _ ->
      expr
    | Assign { being_assigned; new_value } when Variable.Map.mem new_value substitution ->
      let fresh = Variable.freshen new_value in
      bind new_value fresh (Assign { being_assigned; new_value = fresh })
    | Assign _ ->
      expr
    | Static_raise (_exn, (_arg:Flambda.t list)) ->
      (* If the type change to variable, this needs to be
         updated with substitution *)
      expr
    | For { bound_var; from_value; to_value; direction; body } ->
      let from_value, bind_from_value = make_var_subst from_value in
      let to_value, bind_to_value = make_var_subst to_value in
      bind_from_value @@
      bind_to_value @@
      Flambda.For { bound_var; from_value; to_value; direction; body }
    | Apply { func; args; kind; dbg } ->
      let func, bind_func = make_var_subst func in
      let args, bind_args =
        List.split (List.map make_var_subst args)
      in
      bind_func @@
      List.fold_right (fun f expr -> f expr) bind_args @@
      Flambda.Apply { func; args; kind; dbg }
    | Send { kind; meth; obj; args; dbg } ->
      let meth, bind_meth = make_var_subst meth in
      let obj, bind_obj = make_var_subst obj in
      let args, bind_args =
        List.split (List.map make_var_subst args)
      in
      bind_meth @@
      bind_obj @@
      List.fold_right (fun f expr -> f expr) bind_args @@
      Flambda.Send { kind; meth; obj; args; dbg }
    | Proved_unreachable
    | While _
    | Try_with _
    | Static_catch _ ->
      (* No variables directly used in those expressions *)
      expr
  in
  Flambda_iterators.map_toplevel f (fun v -> v) expr


(* Sharing key TODO
   Not implemented yet: this avoids sharing anything *)
(* CR mshinwell for pchambart: What is happening about this? *)

type sharing_key = unit
let make_key _ = None

module Switch_storer =
  Switch.Store
    (struct
      type t = Flambda.t
      type key = sharing_key
      let make_key = make_key
    end)

(* CR-soon mshinwell: [only_via_symbols] is a bit of a hack for
   [Invariant_params], which needs to ignore the uses in the function bodies
   that occur in lhs-of-application position.  Try to improve this. *)
let fun_vars_referenced_in_decls ?only_via_symbols
      (function_decls : Flambda.function_declarations) ~backend =
  let fun_vars = Variable.Map.keys function_decls.funs in
  let symbols_to_fun_vars =
    let module Backend = (val backend : Backend_intf.S) in
    Variable.Set.fold (fun fun_var symbols_to_fun_vars ->
        let closure_id = Closure_id.wrap fun_var in
        let symbol = Backend.closure_symbol closure_id in
        Symbol.Map.add symbol fun_var symbols_to_fun_vars)
      fun_vars
      Symbol.Map.empty
  in
  Variable.Map.map (fun (func_decl : Flambda.function_declaration) ->
      let from_symbols =
        Symbol.Set.fold (fun symbol fun_vars' ->
            match Symbol.Map.find symbol symbols_to_fun_vars with
            | exception Not_found -> fun_vars'
            | fun_var ->
              assert (Variable.Set.mem fun_var fun_vars);
              Variable.Set.add fun_var fun_vars')
          func_decl.free_symbols
          Variable.Set.empty
      in
      let from_variables =
        match only_via_symbols with
        | None -> Variable.Set.inter func_decl.free_variables fun_vars
        | Some () -> Variable.Set.empty
      in
      Variable.Set.union from_symbols from_variables)
    function_decls.funs