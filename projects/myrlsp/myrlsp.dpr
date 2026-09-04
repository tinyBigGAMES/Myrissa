{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

program myrlsp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UMyrLSP in 'UMyrLSP.pas',
  Myrissa.LSP in '..\..\src\Myrissa.LSP.pas';

begin
  RunLSP();
end.
