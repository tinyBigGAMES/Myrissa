{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit UTest.Common;

interface

uses
  StdApp.Console;

const
  COutputPath = 'output';


procedure StatusCallback(const AText: string; const AUserData: Pointer);

implementation

procedure StatusCallback(const AText: string; const AUserData: Pointer);
begin
  TConsole.PrintLn(AText);
end;

end.
