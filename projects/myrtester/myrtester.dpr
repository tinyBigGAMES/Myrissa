{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

program myrtester;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UMyrTester in 'UMyrTester.pas',
  UTest.Common in 'UTest.Common.pas',
  Myrissa.Compiler in '..\..\src\Myrissa.Compiler.pas',
  Myrissa.Tester in '..\..\src\Myrissa.Tester.pas',
  UTestCase.LSP in 'UTestCase.LSP.pas',
  UTestCase.Script in 'UTestCase.Script.pas';

begin
  RunTestbed();
end.
