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

/* @@DRA Adapted from otherlibs/win32unix/winwait.c -- check Licence compat. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>
#include <caml/fail.h>
#include <sys/types.h>

#ifdef WIN32
#include <Windows.h>

static value Parallel_alloc_process_status(HANDLE pid, int status)
{
  value res, st;

  st = alloc(1, 0);
  Field(st, 0) = Val_int(status);
  Begin_root (st);
    res = alloc_small(2, 0);
    Field(res, 0) = Val_long((intnat) pid);
    Field(res, 1) = st;
  End_roots();
  return res;
}

enum { CAML_WNOHANG = 1, CAML_WUNTRACED = 2 };

static int wait_flag_table[] = { CAML_WNOHANG, CAML_WUNTRACED };

CAMLprim value Parallel_waitpids(value vpid_reqs, value vpid_len)
{
  int i;
  DWORD status, retcode;
  HANDLE pid_req;
  DWORD err = 0;
  int len = Int_val(vpid_len);
  HANDLE *lpHandles = (HANDLE*)malloc(sizeof(HANDLE) * len);

  if (lpHandles == NULL)
    caml_raise_out_of_memory();

  value ptr = vpid_reqs;
  for (i = 0; i < len; i++) {
    lpHandles[i] = Long_val(Field(ptr, 0));
    ptr = Field(ptr, 1);
  }

  enter_blocking_section();
  retcode = WaitForMultipleObjects(len, lpHandles, FALSE, INFINITE);
  if (retcode == WAIT_FAILED) err = GetLastError();
  leave_blocking_section();
  if (err) {
    win32_maperr(err);
    uerror("waitpid", Nothing);
  }
  pid_req = lpHandles[retcode - WAIT_OBJECT_0];
  free(lpHandles);
  if (! GetExitCodeProcess(pid_req, &status)) {
    win32_maperr(GetLastError());
    uerror("waitpid", Nothing);
  }
  // @@DRA STILL_ACTIVE should be impossible??
  if (status == STILL_ACTIVE)
    return Parallel_alloc_process_status((HANDLE) 0, 0);
  else {
    CloseHandle(pid_req);
    return Parallel_alloc_process_status(pid_req, status);
  }
}
#else

CAMLprim value Parallel_waitpids(value vpid_reqs, value vpid_len)
{
  CAMLparam2(vpid_reqs, vpid_len);

  CAMLreturn(Val_unit);
}

#endif
