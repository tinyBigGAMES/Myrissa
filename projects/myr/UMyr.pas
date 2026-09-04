{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit UMyr;

{$I StdApp.Defines.inc}

interface

procedure RunCLI();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Console,
  Myrissa.CLI;

procedure RunCLI();
var
  LCLI: TMyrCLI;
begin
 try
    ExitCode := 0;
    LCLI := TMyrCLI.Create();
    try
      LCLI.Execute();
    finally
      LCLI.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: ' + E.Message + COLOR_RESET);
    end;
  end;
end;

end.
