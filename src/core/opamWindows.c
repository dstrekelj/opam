/**************************************************************************/
/*                                                                        */
/*    Copyright 2012-2013 OCamlPro                                        */
/*    Copyright 2012 INRIA                                                */
/*                                                                        */
/*  All rights reserved.This file is distributed under the terms of the   */
/*  GNU Lesser General Public License version 3.0 with linking            */
/*  exception.                                                            */
/*                                                                        */
/*  OPAM is distributed in the hope that it will be useful, but WITHOUT   */
/*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    */
/*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        */
/*  License for more details.                                             */
/*                                                                        */
/**************************************************************************/

#define CAML_NAME_SPACE
#include <stdio.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>

#ifdef WIN32

#include <Windows.h>
#include <TlHelp32.h>

#include "stubs.c"

#else

#include "opamOther.c"

#endif
