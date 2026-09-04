{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit UMyrLSP;

interface

procedure RunLSP();

implementation

uses
  System.SysUtils,
  StdApp.Console,
  StdApp.Utils,
  Myrissa.LSP;

procedure RunLSP();
var
  LServer: TMyrLSPServer;
begin
  try
    LServer := TMyrLSPServer.Create();
    try
      ExitCode := LServer.Run();
    finally
      LServer.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);
    end;
  end;
end;

end.
