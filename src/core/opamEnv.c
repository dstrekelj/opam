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

/* SetEnvironmentVariable function pointer type */
typedef LRESULT (WINAPI *SETENVIRONMENTVARIABLE)(LPCTSTR,LPCTSTR);

/*
 * Data structure to pass to the remote thread
 */
typedef struct {
  SETENVIRONMENTVARIABLE SetEnvironmentVariable;
  TCHAR lpName[MAX_PATH + 1];
  TCHAR lpValue[MAX_PATH + 1];
  BOOL result;
} INJDATA, *PINJDATA;

/*
 * Code to inject into the parent process
 */
static DWORD WINAPI ThreadFunc (INJDATA *pData)
{
  // Call the provided function pointer with its two arguments and return the result
  pData->result = pData->SetEnvironmentVariable(pData->lpName, pData->lpValue);

  return 0;
}

/*
 * This is a dummy function used to calculate the code size of ThreadFunc.
 * This assumes that the linker does not re-order the functions.
 *   If it's a worry, could make the symbols public and use /ORDER (http://msdn.microsoft.com/en-us/library/00kh39zz.aspx)
 *   Presumably there's a gcc equivalent for mingw.
 */
static void AfterThreadFunc (void)
{
  return;
}

CAMLprim value Env_parent_putenv(value key, value val)
{
  CAMLparam2(key, val);

  if (caml_string_length(key) > MAX_PATH || caml_string_length(val) > MAX_PATH)
    caml_invalid_argument("Strings too long");

  // Create a Toolhelp Snapshot of running processes
  HANDLE hProcessSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

  if (hProcessSnapshot == INVALID_HANDLE_VALUE)
    caml_failwith("Env_parent_putenv: could not create snapshot");

  // Locate our process
  PROCESSENTRY32 entry;
  if (!Process32First(hProcessSnapshot, &entry))
  {
    CloseHandle(hProcessSnapshot);
    caml_failwith("Env_parent_putenv: could not walk process tree");
  }

  DWORD processId = GetCurrentProcessId();

  while (entry.th32ProcessID != processId)
  {
    if (!Process32Next(hProcessSnapshot, &entry))
    {
      CloseHandle(hProcessSnapshot);
      caml_failwith("Env_parent_putenv: could not find process!");
    }
  }

  // Finished with the snapshot
  CloseHandle(hProcessSnapshot);

  // Open the parent process for code injection
  HANDLE hProcess = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, entry.th32ParentProcessID);

  if (!hProcess)
    caml_failwith("Env_parent_putenv: could not open parent process");

  // Set-up the instruction
  INJDATA payload = {(SETENVIRONMENTVARIABLE)GetProcAddress(GetModuleHandle("kernel32"), "SetEnvironmentVariableA"), FALSE, "", ""};
  strcpy(payload.lpName, String_val(key));
  strcpy(payload.lpValue, String_val(val));

  // Allocate a page in the parent process to hold the instruction and copy payload to it
  INJDATA *pData = (INJDATA*)VirtualAllocEx(hProcess, 0, sizeof(INJDATA), MEM_COMMIT, PAGE_READWRITE);
  if (!pData)
  {
    CloseHandle(hProcess);
    caml_failwith("Env_parent_putenv: could not allocate page in parent process");
  }
  if (!WriteProcessMemory(hProcess, pData, &payload, sizeof(INJDATA), NULL))
  {
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    caml_failwith("Env_parent_putenv: could not copy data to parent process");
  }

  // Allocate a page in the parent process to hold ThreadFunc and copy the code there
  const int codeSize = ((LPBYTE)AfterThreadFunc - (LPBYTE)ThreadFunc);
  DWORD* pCode = (PDWORD)VirtualAllocEx(hProcess, 0, codeSize, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  if (!pCode)
  {
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    caml_failwith("Env_parent_putenv: could not allocate executable page in parent process");
  }
  if (!WriteProcessMemory(hProcess, pCode, &ThreadFunc, codeSize, NULL))
  {
    VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    caml_failwith("Env_parent_putenv: could not copy code to parent process");
  }

  // Start the remote thread
  HANDLE hThread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)pCode, pData, 0, NULL);
  if (!hThread)
  {
    VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
    VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
    CloseHandle(hProcess);
    caml_failwith("Env_parent_putenv: could not start remote thread in parent");
  }

  // Wait for the thread to terminate
  // Intentionally not releasing the OCaml runtime lock (i.e. I haven't considered if it's safe to do so!)
  WaitForSingleObject(hThread, INFINITE);
  CloseHandle(hThread);

  // Get the result back
  ReadProcessMemory(hProcess, pData, &payload, sizeof(INJDATA), NULL);

  // Release the memory
  VirtualFreeEx(hProcess, pCode, 0, MEM_RELEASE);
  VirtualFreeEx(hProcess, pData, 0, MEM_RELEASE);
  CloseHandle(hProcess);

  CAMLreturn(Val_bool(payload.result));
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
#endif
