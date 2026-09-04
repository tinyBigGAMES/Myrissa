{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}
program myr;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UMyr in 'UMyr.pas',
  Myrissa.Backend in '..\..\src\Myrissa.Backend.pas',
  Myrissa.CImporter in '..\..\src\Myrissa.CImporter.pas',
  Myrissa.CImporter.Script in '..\..\src\Myrissa.CImporter.Script.pas',
  Myrissa.CLI in '..\..\src\Myrissa.CLI.pas',
  Myrissa.Common in '..\..\src\Myrissa.Common.pas',
  Myrissa.Compiler in '..\..\src\Myrissa.Compiler.pas',
  Myrissa.Debug in '..\..\src\Myrissa.Debug.pas',
  Myrissa.Emitter in '..\..\src\Myrissa.Emitter.pas',
  Myrissa.Frontend in '..\..\src\Myrissa.Frontend.pas',
  Myrissa.LSP in '..\..\src\Myrissa.LSP.pas',
  Myrissa.Script in '..\..\src\Myrissa.Script.pas',
  StdApp.Resources in '..\..\src\StdApp.Resources.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  RunCLI();
end.
