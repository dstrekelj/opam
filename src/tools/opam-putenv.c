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

#include <stdio.h>
// This will be being built for a different architecture, so it's easier just to #include the code,
// rather than having to deal with .o files for different architectures.
#include "opamInject.c"

int main(int argc, char *argv[], char *envp[])
{
  if (argc < 4 || (argc & 1) != 0)
  {
    printf("Invalid command line: this utility is an internal part of OPAM\n");
  }
  else
  {
    DWORD pid = atoi(argv[1]);
    int i;
    for (i = 2; i < argc; i += 2)
    {
      InjectSetEnvironmentVariable(pid, argv[i], argv[i + 1]);
    }
  }
}
