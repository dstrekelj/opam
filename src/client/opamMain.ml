(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2013 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

open OpamArg

let () =
  OpamMisc.at_exit (fun () ->
      flush stderr;
      flush stdout;
      if !OpamGlobals.print_stats then (
        OpamFile.print_stats ();
        OpamSystem.print_stats ();
      );
      OpamJson.output ()
    );
  if OpamMisc.os () = OpamMisc.Win32 && Array.length Sys.argv > 1 && Sys.argv.(1) = "--fork" then
    let () = set_binary_mode_in stdin true in
    let (f : unit -> unit) = Marshal.from_channel stdin in
    f ()
  else
    run default commands
