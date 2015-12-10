(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2015 OCamlPro                                        *)
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

open OpamTypes
open OpamProcess.Job.Op

let log fmt = OpamConsole.log "CURL" fmt

let curl_args = [
  CString "--write-out", None;
  CString "%%{http_code}\\n", None;
  CString "--insecure", None;
  CString "--retry", None; CIdent "retry", None;
  CString "--retry-delay", None; CString "2", None;
  CString "--compressed",
  Some (FIdent (OpamFilter.ident_of_string "compressed"));
  CString "-L", None;
  CString "-o", None; CIdent "out", None;
  CIdent "url", None;
]

let wget_args = [
  CString "--content-disposition", None;
  CString "--no-check-certificate", None;
  CString "-t", None; CIdent "retry", None;
  CString "-O", None; CIdent "out", None;
  CIdent "url", None;
]

let download_args ~url ~out ~retry ?checksum ~compress =
  let cmd, _ = Lazy.force OpamRepositoryConfig.(!r.download_tool) in
  let cmd =
    match cmd with
    | [(CIdent "wget"), _] -> cmd @ wget_args
    | [_] -> cmd @ curl_args (* Assume curl if the command is a single arg *)
    | _ -> cmd
  in
  OpamFilter.single_command (fun v ->
      if not (OpamVariable.Full.is_global v) then None else
      match OpamVariable.to_string (OpamVariable.Full.variable v) with
      | "curl" -> Some (S "curl")
      | "wget" -> Some (S "wget")
      | "url" -> Some (S (OpamUrl.to_string url))
      | "out" -> Some (S out)
      | "retry" -> Some (S (string_of_int retry))
      | "compress" -> Some (B compress)
      | "checksum" -> OpamStd.Option.map (fun c -> S c) checksum
      | _ -> None)
    cmd

let tool_return url ret =
  match Lazy.force OpamRepositoryConfig.(!r.download_tool) with
  | _, `Default -> Done (OpamSystem.raise_on_process_error ret)
  | _, `Curl ->
    OpamSystem.raise_on_process_error ret;
    match ret.OpamProcess.r_stdout with
    | [] ->
      OpamSystem.internal_error "curl: empty response while downloading %s"
        (OpamUrl.to_string url)
    | l  ->
      let code = List.hd (List.rev l) in
      let num = try int_of_string code with Failure _ -> 999 in
      if num >= 400 then
        OpamSystem.internal_error "curl: code %s while downloading %s" code
          (OpamUrl.to_string url)
      else Done ()

let download_command ~compress ?checksum ~url ~dst =
  let cmd, args =
    match
      download_args
        ~url
        ~out:dst
        ~retry:OpamRepositoryConfig.(!r.retries)
        ?checksum
        ~compress
    with
    | cmd::args -> cmd, args
    | [] -> OpamConsole.error_and_exit "Empty custom download command"
  in
  OpamSystem.make_command cmd args @@> tool_return url

let developer_index = "index.opam"

let check_cache =
  let directory = OpamCoreConfig.(devopts.cache) in
  let cache = Filename.concat directory developer_index in
  if OpamCoreConfig.developer && Sys.file_exists directory && (Unix.stat directory).Unix.st_kind = Unix.S_DIR && Sys.file_exists cache then
    (*
     * Switch all \ to / for maximum Windows-compatibility.
     *)
    begin
      let directory = String.map (function '\\' -> '/' | c -> c) directory in
      fun src ->
        let c = open_in cache in
        let result = ref "" in
          try
            while true do
              let line = input_line c in
              if String.length line > 32 then
                if String.sub line 33 (String.length line - 33) = src then begin
                  result := directory ^ "/" ^ String.sub line 0 32;
                  raise Exit
                end
            done;
            ""
          with Exit -> !result
             | End_of_file ->
                 close_in c;
                 ""
    end
  else
    fun _ -> ""

(*
 * If OPAM is compiled in developer mode, the value of DEVELOPER_CACHE is captured
 * (default ~/.opam-cache) and stored in OpamCoreConfig.devops.cache.
 *
 * This directory can have a file index.opam placed into it which is queried whenever
 * a file download is requested. Each line of the index consists of the hexadecimal MD5
 * digest of the file, followed by a space, followed by the URL. The file should be placed
 * in the directory named as its checksum. For example:
 *   12e6322c12c638ce1ab7d624f98b35f5 https://opam.ocaml.org/1.3/urls.txt
 *   c145619f4796e2aecf5483903d45f281 https://opam.ocaml.org/1.3/index.tar.gz
 * with https://opam.ocaml.org/urls.txt downloaded and renamed 12e6322c12c638ce1ab7d624f98b35f5
 * and https://opam.ocaml.org/1.3/index.tar.gz downloaded and renamed c145619f4796e2aecf5483903d45f281
 *
 * Very useful when working on OPAM without an internet connection...
 *)
let really_download ~overwrite ?(compress=false) ?checksum ~url ~dst =
  assert (url.OpamUrl.backend = `http);
  let url_str = OpamUrl.to_string url in
  let cache = check_cache url_str in
  if cache = "" then
    let tmp_dst = dst ^ ".part" in
    if Sys.file_exists tmp_dst then OpamSystem.remove tmp_dst;
    log "Will download %s" url_str;
    OpamProcess.Job.catch
      (function
      | OpamSystem.Internal_error s as e ->
          OpamSystem.remove tmp_dst;
          OpamConsole.error "%s" s;
          raise e
        | e ->
          OpamSystem.remove tmp_dst;
          OpamStd.Exn.fatal e;
          log "Could not download file at %s." url_str;
          raise e)
      (download_command ~compress ?checksum ~url ~dst:tmp_dst
       @@+ fun () ->
       if not (Sys.file_exists tmp_dst) then
         OpamSystem.internal_error "Downloaded file not found"
       else if Sys.file_exists dst && not overwrite then
         OpamSystem.internal_error "The downloaded file will overwrite %s." dst;
       let directory = OpamCoreConfig.(devopts.cache) in
       let cache = Filename.concat directory developer_index in
       if OpamCoreConfig.developer && Sys.file_exists directory && (Unix.stat directory).Unix.st_kind = Unix.S_DIR then begin
         let digest = Digest.to_hex (Digest.file tmp_dst) in
         OpamSystem.copy tmp_dst (Filename.concat directory digest);
         let c = open_out_gen [Open_wronly; Open_append; Open_creat; Open_text] 0o666 cache in
         output_string c (digest ^ " " ^ url_str ^ "\n");
         close_out c;
       end;
       OpamSystem.mv tmp_dst dst;
       Done ())
  else
    begin
      log "Retrieved %s from developer cache" url_str;
      if Sys.file_exists dst && not overwrite then
        OpamSystem.internal_error "The downloaded file will overwrite %s." dst;
      OpamSystem.copy cache dst;
      Done ()
    end

let download_as ~overwrite ?compress ?checksum url dst =
  match OpamUrl.local_file url with
  | Some src ->
    if src = dst then Done () else
      (if OpamFilename.exists dst then
         if overwrite then OpamFilename.remove dst else
           OpamSystem.internal_error "The downloaded file will overwrite %s."
             (OpamFilename.to_string dst);
       OpamFilename.copy ~src ~dst;
       Done ())
  | None ->
    OpamFilename.(mkdir (dirname dst));
    really_download ~overwrite ?compress ?checksum
      ~url
      ~dst:(OpamFilename.to_string dst)

let download ~overwrite ?compress ?checksum url dstdir =
  let dst =
    OpamFilename.(create dstdir (Base.of_string (OpamUrl.basename url)))
  in
  download_as ~overwrite ?compress ?checksum url dst @@| fun () -> dst
