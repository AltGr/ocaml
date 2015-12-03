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

include Ext_types.Identifiable

val create : ?current_compilation_unit:Compilation_unit.t -> string -> t
val of_ident : Ident.t -> t

(** For [Flambda_to_clambda] only. *)
val unique_ident : t -> Ident.t

val freshen : t -> t

val rename
   : ?current_compilation_unit:Compilation_unit.t
  -> ?append:string
  -> t
  -> t

val in_compilation_unit : t -> Compilation_unit.t -> bool

val output_full : out_channel -> t -> unit