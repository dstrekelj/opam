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
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>

#ifdef WIN32
#include <Windows.h>
#include <WinUser.h>
#include <Shlobj.h>
#include <TlHelp32.h>

// Somewhat against my better judgement, wrap SHGetFolderPath rather than SHGetKnownFolderPath to maintain XP compatibility.
CAMLprim value Filename_SHGetFolderPath(value nFolder, value dwFlags)
{
  CAMLparam2(nFolder, dwFlags);
  CAMLlocal1(result);
  TCHAR szPath[MAX_PATH];

  if (SUCCEEDED(SHGetFolderPath(NULL, Int_val(nFolder), NULL, Int_val(dwFlags), szPath)))
    result = caml_copy_string(szPath);
  else
    caml_failwith("SHGetFolderPath");

  CAMLreturn(result);
}

static HKEY roots[] = {HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, HKEY_USERS};

CAMLprim value Env_WriteRegistry(value hKey, value lpSubKey, value lpValueName, value dwType, value lpData)
{
  CAMLparam5(hKey, lpSubKey, lpValueName, dwType, lpData);

  HKEY key;
  void* buf = NULL;
  DWORD cbData = 0;
  DWORD type = 0;

  switch (RegOpenKeyEx(roots[Int_val(hKey)], String_val(lpSubKey), 0, KEY_WRITE, &key))
  {
    case ERROR_SUCCESS:
      {
        switch (Int_val(dwType))
        {
          case 0:
            {
              buf = String_val(lpData);
              cbData = strlen(buf) + 1;
              type = REG_SZ;
              break;
            }
          default:
            {
              caml_failwith("Env_WriteRegistry: value not implemented");
              // Not necessary...
              break;
            }
        }
        if (RegSetValueEx(key, String_val(lpValueName), 0, type, (LPBYTE)buf, cbData) != ERROR_SUCCESS)
        {
          RegCloseKey(key);
          caml_failwith("RegSetValueEx");
        }
        RegCloseKey(key);
        break;
      }
    case ERROR_FILE_NOT_FOUND:
      {
        caml_raise_not_found();
        // Not necessary...
        break;
      }
    default:
      {
        caml_failwith("RegOpenKeyEx");
        // Not necessary...
        break;
      }
  }

  CAMLreturn(Val_unit);
}

CAMLprim value Env_SendMessageTimeout(value hWnd, value uTimeout, value fuFlags, value msg, value wParam, value lParam)
{
  CAMLparam5(hWnd, msg, wParam, lParam, fuFlags);
  CAMLxparam1(uTimeout);
  CAMLlocal1(result);

  DWORD dwReturnValue;
  HRESULT lResult;
  WPARAM rwParam;
  LPARAM rlParam;
  UINT rMsg;

  switch (Int_val(msg))
  {
    case 0:
      {
        rMsg = WM_SETTINGCHANGE;
        rwParam = Int_val(wParam);
        rlParam = (LPARAM)String_val(lParam);
        break;
      }
    default:
      {
        caml_failwith("Env_SendMessageTimeout: message not implemented");
        // Not necessary...
        break;
      }
  }

  lResult = SendMessageTimeout(Int_val(hWnd), rMsg, rwParam, rlParam, Int_val(fuFlags), Int_val(uTimeout), &dwReturnValue);

  switch (Int_val(msg))
  {
    case 0:
      {
        result = caml_alloc(2, 0);
        Store_field(result, 0, Val_int(lResult));
        Store_field(result, 1, Val_int(dwReturnValue));
        break;
      }
  }

  CAMLreturn(result);
}

CAMLprim value Env_SendMessageTimeout_byte(value * argv, int argn)
{
  return Env_SendMessageTimeout(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/*
 * Env_parent_putenv is implemented using Process Injection.
 * Idea inspired by Bill Stewart's editvar (http://www.westmesatech.com/editv.html)
 * Full technical details at http://www.codeproject.com/Articles/4610/Three-Ways-to-Inject-Your-Code-into-Another-Proces#section_3
 */

char* getCurrentProcess(PROCESSENTRY32 *entry)
{
  // Create a Toolhelp Snapshot of running processes
  HANDLE hProcessSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  entry->dwSize = sizeof(PROCESSENTRY32);

  if (hProcessSnapshot == INVALID_HANDLE_VALUE)
    return "Env_parent_putenv: could not create snapshot";

  // Locate our process
  if (!Process32First(hProcessSnapshot, entry))
  {
    CloseHandle(hProcessSnapshot);
    return "Env_parent_putenv: could not walk process tree";
  }

  DWORD processId = GetCurrentProcessId();

  while (entry->th32ProcessID != processId)
  {
    if (!Process32Next(hProcessSnapshot, entry))
    {
      CloseHandle(hProcessSnapshot);
      return "Env_parent_putenv: could not find process!";
    }
  }

  // Finished with the snapshot
  CloseHandle(hProcessSnapshot);

  return NULL;
}

CAMLprim value Env_parent_putenv(value key, value val)
{
  CAMLparam2(key, val);
  CAMLlocal1(res);

  if (caml_string_length(key) > MAX_PATH || caml_string_length(val) > MAX_PATH)
    caml_invalid_argument("Strings too long");

  PROCESSENTRY32 entry;
  char* msg = getCurrentProcess(&entry);
  if (!msg)
    caml_failwith(msg);

  char* result = InjectSetEnvironmentVariable(entry.th32ParentProcessID, String_val(key), String_val(val));

  if (result == NULL)
  {
    res = Val_true;
  }
  else if (strlen(result) == 0)
  {
    res = Val_false;
  }
  else
  {
    caml_failwith(result);
  }

  CAMLreturn(res);
}

typedef BOOL (WINAPI *LPFN_ISWOW64PROCESS) (HANDLE, PBOOL);

CAMLprim value Env_IsWoW64Mismatch(value unit)
{
  CAMLparam1(unit);

  PROCESSENTRY32 entry;
  char* msg = getCurrentProcess(&entry);
  if (msg)
    caml_failwith(msg);

  // 32-bit versions may or may not have IsWow64Process (depends on age). Recommended way is to use
  // GetProcAddress to obtain IsWow64Process, rather than relying on Windows.h.
  // See http://msdn.microsoft.com/en-gb/library/windows/desktop/ms684139(v=vs.85).aspx
  LPFN_ISWOW64PROCESS IsWoW64Process;
  IsWoW64Process = (LPFN_ISWOW64PROCESS)GetProcAddress(GetModuleHandle("kernel32"), "IsWow64Process");
  BOOL pidWoW64 = FALSE, ppidWoW64 = FALSE;
  HANDLE hProcess;
  if (IsWoW64Process)
  {
    IsWoW64Process(GetCurrentProcess(), &pidWoW64);
    if ((hProcess = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, entry.th32ParentProcessID)))
    {
      IsWoW64Process(hProcess, &ppidWoW64);
      CloseHandle(hProcess);
    }
  }

  CAMLreturn(Val_int((pidWoW64 != ppidWoW64 ? entry.th32ParentProcessID : 0)));
}
#else
CAMLprim value Filename_SHGetSpecialFolderPath(value nFolder, value dwFlags)
{
  CAMLparam2(nFolder, dwFlags);

  CAMLreturn(Val_unit);
}

CAMLprim value Env_WriteRegistry(value hKey, value lpSubKey, value lpValueName, value dwType, value lpData)
{
  CAMLparam5(hKey, lpSubKey, lpValueName, dwType, lpData);

  CAMLreturn(Val_unit);
}

CAMLprim value Env_SendMessageTimeout(value hWnd, value msg, value uTimeout, value fuFlags, value wParam, value lParam)
{
  CAMLparam5(hWnd, msg, wParam, lParam, fuFlags);
  CAMLxparam1(uTimeout);

  CAMLreturn(Val_unit);
}

CAMLprim value Env_SendMessageTimeout_byte(value * argv, int argn)
{
  CAMLreturn(Val_unit);
}

CAMLprim value Env_parent_putenv(value key, value value)
{
  CAMLparam2(key, value);

  CAMLreturn(Val_unit);
}

CAMLprim value Env_IsWoW64Mismatch(value unit)
{
  CAMLparam1(unit);

  CAMLreturn(Val_int(0));
}
#endif
