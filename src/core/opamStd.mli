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

(** {2 Signatures and functors} *)

(** Sets with extended interface and infix operators *)
module type SET = sig

  include Set.S

  val map: (elt -> elt) -> t -> t

  (** Return one element. Fail if the set is not a singleton. *)
  val choose_one : t -> elt

  val of_list: elt list -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t
  val find: (elt -> bool) -> t -> elt

  (** Raises Failure in case the element is already present *)
  val safe_add: elt -> t -> t

  module Op : sig
    val (++): t -> t -> t (** Infix set union *)

    val (--): t -> t -> t (** Infix set difference *)

    val (%%): t -> t -> t (** Infix set intersection *)
  end

end

(** Maps with extended interface *)
module type MAP = sig

  include Map.S

  val to_string: ('a -> string) -> 'a t  -> string
  val to_json: ('a -> OpamJson.t) -> 'a t -> OpamJson.t
  val keys: 'a t -> key list
  val values: 'a t -> 'a list

  (** A key will be in the union of [m1] and [m2] if it is appears
      either [m1] or [m2], with the corresponding value. If a key
      appears in both [m1] and [m2], then the resulting value is built
      using the function given as argument. *)
  val union: ('a -> 'a -> 'a) -> 'a t -> 'a t -> 'a t

  val of_list: (key * 'a) list -> 'a t

  (** Raises Failure in case the element is already present *)
  val safe_add: key -> 'a -> 'a t -> 'a t

end

(** A signature for handling abstract keys and collections thereof *)
module type ABSTRACT = sig

  type t

  val of_string: string -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t

  module Set: SET with type elt = t
  module Map: MAP with type key = t
end

(** A basic implementation of ABSTRACT using strings *)
module AbstractString : ABSTRACT with type t = string

(** {3 Generators for set and map modules with printers} *)

module type OrderedType = sig
  include Set.OrderedType
  val to_string: t -> string
  val to_json: t -> OpamJson.t
end

module Set: sig
  module Make (S: OrderedType): SET with type elt = S.t
end

module Map: sig
  module Make (S: OrderedType): MAP with type key = S.t
end


(** {2 Integer collections} *)

(** Map of ints *)
module IntMap: MAP with type key = int

(** Set of ints *)
module IntSet: SET with type elt = int


(** {2 Utility modules extending the standard library on base types} *)

module Option: sig
  val map: ('a -> 'b) -> 'a option -> 'b option

  val iter: ('a -> unit) -> 'a option -> unit

  val default: 'a -> 'a option -> 'a

  val default_map: 'a option -> 'a option -> 'a option

  val compare: ('a -> 'a -> int) -> 'a option -> 'a option -> int

  val to_string: ?none:string -> ('a -> string) -> 'a option -> string

  val some: 'a -> 'a option

  val none: 'a -> 'b option

  (** [of_Not_found f x] calls [f x], catches [Not_found] and returns [None] *)
  val of_Not_found: ('a -> 'b) -> 'a -> 'b option

  module Op: sig
    val (>>=): 'a option -> ('a -> 'b option) -> 'b option
    val (>>|): 'a option -> ('a -> 'b) -> 'b option
    val (>>+): 'a option -> (unit -> 'a option) -> 'a option
    val (+!): 'a option -> 'a -> 'a
    val (++): 'a option -> 'a option -> 'a option
  end
end

module List : sig

  (** Convert list items to string and concat. [sconcat_map sep f x] is equivalent
      to String.concat sep (List.map f x) but tail-rec. *)
  val concat_map:
    ?left:string -> ?right:string -> ?nil:string ->
    string -> ('a -> string) -> 'a list -> string

  val to_string: ('a -> string) -> 'a list -> string

  (** Removes consecutive duplicates in a list *)
  val remove_duplicates: 'a list -> 'a list

  (** Sorts the list, removing duplicates *)
  val sort_nodup: ('a -> 'a -> int) -> 'a list -> 'a list

  (** Filter and map *)
  val filter_map: ('a -> 'b option) -> 'a list -> 'b list

  (** Retrieves [Some] values from a list *)
  val filter_some: 'a option list -> 'a list

  (** Insert a value in an ordered list *)
  val insert: ('a -> 'a -> int) -> 'a -> 'a list -> 'a list

end

module String : sig

  (** {3 Collections} *)

  module Map: MAP with type key = string

  module Set: SET with type elt = string

  (** Set of string sets *)
  module SetSet: SET with type elt = Set.t

  (** Map of string sets *)
  module SetMap: MAP with type key = Set.t

  (** {3 Checks} *)

  val starts_with: prefix:string -> string -> bool
  val ends_with: suffix:string -> string -> bool
  val contains: string -> char -> bool
  val exact_match: Re.re -> string -> bool

  (** {3 Manipulation} *)

  val map: (char -> char) -> string -> string
  val strip: string -> string
  val sub_at: int -> string -> string
  val remove_prefix: prefix:string -> string -> string
  val remove_suffix: suffix:string -> string -> string

  (** {4 Transformations} *)

  (** Cut a string at the first occurence of the given char *)
  val cut_at: string -> char -> (string * string) option

  (** Same as [cut_at], but starts from the right *)
  val rcut_at: string -> char -> (string * string) option

  (** Split a string at occurences of a given characters. Empty strings are
      skipped. *)
  val split: string -> char -> string list

  (** The same as [split], but keep empty strings (leading, trailing or between
      contiguous delimiters) *)
  val split_delim: string -> char -> string list

  val fold_left: ('a -> char -> 'a) -> 'a -> string -> 'a

end

module Format : sig

  (** {4 Querying information} *)

  (** Returns the length of the string in terminal chars, ignoring ANSI color
      sequences from OpamConsole.colorise *)
  val visual_length: string -> int

  (** {4 Text formatting functions} *)

  (** left indenting. [~visual] can be used to indent eg. ANSI colored
      strings and should correspond to the visible characters of s *)
  val indent_left: string -> ?visual:string -> int -> string

  val indent_right: string -> ?visual:string -> int -> string

  (** Pads fields in a table with spaces for alignment. *)
  val align_table: string list list -> string list list

  (** Cut long lines in string according to the terminal width *)
  val reformat: ?start_column:int -> ?indent:int -> string -> string

  (** Convert a list of items to string as a dashed list *)
  val itemize: ?bullet:string -> ('a -> string) -> 'a list -> string

  (** Display a pretty list: ["x";"y";"z"] -> "x, y and z".
      "and" can be changed by specifying [last] *)
  val pretty_list: ?last:string -> string list -> string

  (** {4 Printing} *)

  (** Prints a table *)
  val print_table: (string -> unit) -> sep:string -> string list list -> unit
end

module Exn : sig

  (** To use when catching default exceptions: ensures we don't catch fatal errors
      like C-c. try-with should _always_ (by decreasing order of preference):
      - either catch specific exceptions
      - or re-raise the same exception
      - or call this function on the caught exception *)
  val fatal: exn -> unit

  (** Register a backtrace for when you need to process a finalizer (that
      internally uses exceptions) and then re-raise the same exception.
      To be printed by pretty_backtrace. *)
  val register_backtrace: exn -> unit

  (** Return a pretty-printed backtrace *)
  val pretty_backtrace: exn -> string

end

(** {2 Manipulation and query of environment variables} *)

module Env : sig
  (** Remove from a c-separated list of string the one with the given prefix *)
  val reset_value: prefix:string -> char -> string -> string list

  (** split a c-separated list of string in two according to the first
      occurrences of the string with the given [prefix]. The list of
      elements occurring before is returned in reverse order. If there are
      other elements with the same [prefix] they are kept in the second list.
  *)
  val cut_value: prefix:string -> char -> string -> string list * string list

  val get: string -> string

  val getopt: string -> string option

  val list: unit -> (string * string) list
end

(** {2 Windows-specific functions} *)
module Win32 : sig
  (** Win32 WSTR - UCS2-ish string, opaque to prevent accidental printing *)
  module WSTR : sig
    type t

    val to_string : t -> string
  end

  (** CONSOLE_FONT_INFOEX (see https://msdn.microsoft.com/en-us/library/windows/desktop/ms682069.aspx)
  *)
  type console_font_infoex = {
    font: int; (** Index of the font within the system console font table *)
    fontSize: int * int; (** Width and height of the characters in logical units *)
    fontFamily: int; (** Font pitch and family. See tmPitchAndFamily in https://msdn.microsoft.com/en-us/library/windows/desktop/dd145132.aspx *)
    fontWeight: int; (** Font weight (100--1000) *)
    faceName: WSTR.t; (** Name of the font *)
  }

  (** CONSOLE_SCREEN_BUFFER_INFO (see https://msdn.microsoft.com/en-us/library/windows/desktop/ms682093.aspx)
  *)
  type console_screen_buffer_info = {
    size: int * int; (** width and height of the screen buffer *)
    cursorPosition: int * int; (** current position of the console cursor (caret) *)
    attributes: int; (** screen attributes; see https://msdn.microsoft.com/en-us/library/windows/desktop/ms682088.aspx#_win32_character_attributes *)
    window: int * int * int * int; (** Coordinates of the upper-left and lower-right corners of the display window within the screen buffer *)
    maximumWindowSize: int * int; (** Maximum displayable size of the console for this screen buffer *)
  }

  (** Win32 Registry Hives and Values *)
  module RegistryHive : sig
    (** Registry root keys (hives) *)
    type t =
    | HKEY_CLASSES_ROOT
    | HKEY_CURRENT_USER
    | HKEY_LOCAL_MACHINE
    | HKEY_USERS

    (** Registry values *)
    type value =
    | REG_SZ (** String values *)

    val of_string : string -> t
    val to_string : t -> string
  end

  (** Win32 API handles *)
  type handle

  (** Windows Messages (at least, one of them!) *)
  type winmessage =
  | WM_SETTINGCHANGE
    (** See https://msdn.microsoft.com/en-us/library/windows/desktop/ms725497.aspx *)

  external getStdHandle : int -> handle = "OPAMW_GetStdHandle"
  (** Return a standard handle. Standard output is handle -11 (winbase.h; STD_OUTPUT_HANDLE)
  *)

  external getConsoleScreenBufferInfo : handle -> console_screen_buffer_info = "OPAMW_GetConsoleScreenBufferInfo"
  (** Return current Console screen buffer information
  *)

  external setConsoleTextAttribute : handle -> int -> unit = "OPAMW_SetConsoleTextAttribute"
  (** Set the consoles text attribute setting
  *)

  external writeRegistry : RegistryHive.t -> string -> string -> RegistryHive.value -> 'a -> unit = "OPAMW_WriteRegistry"
  (** [writeRegistry root subKey valueName valueType value] (over)writes a value in the Windows registry
   *)

  external getConsoleOutputCP : unit -> int = "OPAMW_GetConsoleOutputCP"
  (** Retrieves the current Console Output Code Page
   *)

  external setConsoleOutputCP : int -> bool = "OPAMW_SetConsoleOutputCP"
  (** Sets the Console Output Code Page
   *)

  external setConsoleCP : int -> bool = "OPAMW_SetConsoleCP"
  (** Sets the Console Input Code Page
   *)

  external getCurrentConsoleFontEx : handle -> bool -> console_font_infoex = "OPAMW_GetCurrentConsoleFontEx"
  (** Gets information on the current console output font
   *)

  external checkGlyphs : WSTR.t -> int list -> int -> bool list = "OPAMW_CheckGlyphs"
  (** [checkGlyphs font chars length] takes a list of [length] BMP Unicode code-points to check for
   * in the given font. The return result is a list of the same length with the value [true]
   * indicating that the corresponding UTF16 character has a glyph in the font.
   *)

  external writeWindowsConsole : handle -> string -> unit = "OPAMW_output"
  (** Writes output to the Windows Console using WriteConsoleW
  *)

  val parent_of_parent : unit -> unit
  (** Alters parent_putenv to manipulate the parent of the parent process. Required for Clink
   * automatic execution of opam config env (because Lua's os.execute calls cmd). This function
   * has no effect if called after the first call to {!parent_putenv}.
   *)

  val parent_putenv : string -> string -> bool
  (** Update an environment variable in the parent (i.e. shell) process's environment
   *)

  external shGetFolderPath : int -> int -> string = "OPAMW_SHGetFolderPath"
  (** [shGetFolderPath nFolder dwFlags] retrieves the location of a special folder by CSIDL value.
   * See https://msdn.microsoft.com/en-us/library/windows/desktop/bb762181.aspx
   *)

  external sendMessageTimeout : int -> int -> int -> winmessage -> 'a -> 'b -> int * 'c = "OPAMW_SendMessageTimeout_byte" "OPAMW_SendMessageTimeout"
  (** [sendMessageTimeout hwnd timeout flags message wParam lParam] sends a message to the given hwnd
   * but is guaranteed to return within [timeout] milliseconds. The result consists of two parts, [fst]
   * is the return value from SendMessageTimeout, [snd] depends on both the message and [fst].
   *)

  val persistHomeDirectory : string -> unit
  (** [persistHomeDirectory value] sets the HOME environment variable in this and the parent process
   * and also persists the setting to the user's registry and broadcasts the change to other processes.
   *)

  external getConsoleAlias : string -> string -> string = "OPAMW_GetConsoleAlias"
  (** [getConsoleAlias alias exeName] retrieves the value for a given executable or [""] if the alias
   * is not defined.
   *)
end

(** {2 System query and exit handling} *)

module Sys : sig

  (** {3 Querying} *)

  (** true if stdout is bound to a terminal *)
  val tty_out : bool

  (** Queried lazily, but may change on SIGWINCH *)
  val terminal_columns : unit -> int

  (** The user's home directory. Queried lazily *)
  val home: unit -> string

  type os = Darwin
          | Linux
          | FreeBSD
          | OpenBSD
          | NetBSD
          | DragonFly
          | Cygwin
          | Win32
          | Unix
          | Other of string

  (** Queried lazily *)
  val os: unit -> os

  val os_string: unit -> string

  (** Queried lazily *)
  val arch: unit -> string

  (** clink user scripts directory (Windows only) *)
  val clink_scripts: unit -> string option

  (** Guess the shell compat-mode *)
  val guess_shell_compat: unit -> [`csh|`zsh|`sh|`bash|`fish|`cmd|`clink]

  (** Guess the location of .profile *)
  val guess_dot_profile: [`csh|`zsh|`sh|`bash|`fish|`cmd|`clink] -> string

  (** The separator character used in the PATH variable (varies depending on
      OS) *)
  val path_sep: unit -> char

  (** {3 Exit handling} *)

  (** Like Pervasives.at_exit but with the possibility to call manually
      (eg. before exec()) *)
  val at_exit: (unit -> unit) -> unit

  (** Calls the functions registered in at_exit. Unneeded if exiting normally *)
  val exec_at_exit: unit -> unit

  (** Indicates intention to exit the program with given exit code *)
  exception Exit of int

  (** Indicates intention to exec() the given command (paramters as per
      [Unix.execvpe]), after proper finalisations. It's the responsibility of
      the main function to catch this, call [exec_at_exit], and
      [Unix.execvpe]. *)
  exception Exec of string * string array * string array

  (** Raises [Exit i] *)
  val exit: int -> 'a

end

(** {2 General use infix function combinators} *)

module Op: sig

  (** Function application (with lower priority) (predefined in OCaml 4.01+) *)
  val (@@): ('a -> 'b) -> 'a -> 'b

  (** Pipe operator -- reverse application (predefined in OCaml 4.01+) *)
  val (|>): 'a -> ('a -> 'b) -> 'b

  (** Function composition : (f @* g) x =~ f (g x) *)
  val (@*): ('b -> 'c) -> ('a -> 'b) -> 'a -> 'c

  (** Reverse function composition : (f @> g) x =~ g (f x) *)
  val (@>): ('a -> 'b) -> ('b -> 'c) -> 'a -> 'c

end

(** {2 Helper functions to initialise configuration from the environment} *)

module Config : sig

  type env_var = string

  val env_bool: env_var -> bool option

  val env_int: env_var -> int option

  (* Like [env_int], but accept boolean values for 0 and 1 *)
  val env_level: env_var -> int option

  val env_string: env_var -> string option

  val env_float: env_var -> float option

  val env_when: env_var -> [ `Always | `Never | `Auto ] option

  val env_when_ext: env_var -> [ `Extended | `Always | `Never | `Auto ] option

  val resolve_when: auto:(bool Lazy.t) -> [ `Always | `Never | `Auto ] -> bool

  (** Sets the OpamCoreConfig options, reading the environment to get default
      values when unspecified *)
  val init: ?noop:_ -> (unit -> unit) OpamCoreConfig.options_fun

  (** Like [init], but returns the given value. For optional argument
      stacking *)
  val initk: 'a -> 'a OpamCoreConfig.options_fun

  module type Sig = sig

    (** Read-only record type containing the lib's configuration options *)
    type t

    (** Type of functions with optional arguments for setting each of [t]'s
        fields, similarly named, and returning ['a] *)
    type 'a options_fun

    (** The default values of the options to use at startup *)
    val default: t

    (** Use to update any option in a [t], using the optional arguments of
        [options_fun]. E.g. [set opts ?option1:1 ?option4:"x" ()] *)
    val set: t -> (unit -> t) options_fun

    (** Same as [set], but passes the result to a continuation, allowing
        argument stacking *)
    val setk: (t -> 'a) -> t -> 'a options_fun

    (** The global reference containing the currently set library options.
        Access using [OpamXxxConfig.(!r.field)]. *)
    val r: t ref

    (** Updates the currently set options in [r] according to the optional
        arguments *)
    val update: ?noop:_ -> (unit -> unit) options_fun

    (** Sets the options, reading the environment to get default values when
        unspecified *)
    val init: ?noop:_ -> (unit -> unit) options_fun

    (** Sets the options like [init], but returns the given value (for arguments
        stacking) *)
    val initk: 'a -> 'a options_fun

  end

end
