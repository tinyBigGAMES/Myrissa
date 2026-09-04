{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2025-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit UMyrTester;

interface

procedure RunTestbed();

implementation

uses
  System.SysUtils,
  StdApp.Utils,
  StdApp.Console,
  StdApp.Console.Menu,
  Myrissa.Common,
  Myrissa.Backend,
  Myrissa.Compiler,
  Myrissa.Tester,
  UTestCase.Script,
  UTestCase.LSP;

procedure RegisterComplianceTests(const ATester: TMyrTester);
begin
  // SetCategory sets a CURRENT category that every following RegisterTest
  // inherits, so registrations are grouped by concern and each category is
  // kept contiguous.
  //
  // Test IDs follow the 50-BOUNDARY RULE: every category starts at the next
  // multiple of 50 and numbers upward from there. That leaves 50 free slots
  // per category, so a new test is appended to its own concern without
  // renumbering anything else - which is what keeps IDs stable across
  // SaveTests. See PROJECT.md, Test Registration.

  // Standalone EXE compliance
  ATester.SetCategory('EXE');
  ATester.RegisterTest(0000, 'bnf_exe_compliance', rmExecute);

  // DLL build + consumer
  ATester.SetCategory('DLL');
  ATester.RegisterTest(0050, 'bnf_dll_compliance', rmNone);
  ATester.RegisterTests(0051, 'test_exe_dll_compliance',
    ['bnf_dll_compliance'], rmExecute);

  // LIB build + consumer
  ATester.SetCategory('LIB');
  ATester.RegisterTest(0100, 'bnf_lib_compliance', rmNone);
  ATester.RegisterTests(0101, 'test_exe_lib_compliance',
    ['bnf_lib_compliance'], rmExecute);

  // Unit build + consumer
  ATester.SetCategory('Unit');
  ATester.RegisterTest(0150, 'bnf_unit_compliance', rmNone);
  ATester.RegisterTests(0151, 'test_exe_unit_compliance',
    ['bnf_unit_compliance'], rmExecute);

  // Unit test framework
  ATester.SetCategory('Unit Tests');
  ATester.RegisterTest(0200, 'bnf_unittest_compliance', rmExecute);

  // Link tests -- multiple lib deps then consumer
  ATester.SetCategory('Link');
  ATester.RegisterTest(0250, 'bnf_link_lib_inner', rmNone);
  ATester.RegisterTest(0251, 'bnf_link_lib_outer', rmNone);
  ATester.RegisterTest(0252, 'bnf_link_lib_dllvar', rmNone);
  ATester.RegisterTest(0253, 'bnf_link_lib_path', rmNone);
  ATester.RegisterTest(0254, 'bnf_link_lib_seh', rmNone);
  ATester.RegisterTest(0255, 'bnf_link_dll_addr64', rmNone);
  ATester.RegisterTests(0256, 'bnf_link_compliance',
    ['bnf_link_lib_inner', 'bnf_link_lib_outer', 'bnf_link_lib_dllvar',
     'bnf_link_lib_path', 'bnf_link_lib_seh', 'bnf_link_dll_addr64'],
    rmExecute);

  ATester.SetCategory('Debug');
  ATester.RegisterTest(0300, 'debug_compliance', rmDebug, '', '', [tgWin64]);

  // Simple smoke test
  ATester.SetCategory('Smoke');
  ATester.RegisterTest(0350, 'hello', rmExecute);

  ATester.SaveTests();
  ATester.DumpSSA := True;
  // All three levels. olBasic is a REAL middle setting, not an interpolation
  // between the other two: it runs constant folding, copy propagation and DCE
  // but NOT CSE. Gating only olNone and olFull leaves every defect that lives
  // in that gap invisible, and made the sikAddressOf operand-substitution bug
  // reproduce at olFull with no way to tell which pass introduced it.
  ATester.OptLevels := [olNone, olBasic, olFull];
end;

procedure RegisterTestCase(const AMenu: TConsoleMenu);
begin
  AMenu.SetCategory('LSP');
  AMenu.AddTestCase(TCPLSPTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Script');
  AMenu.AddTestCase(TCPScriptTests);
  AMenu.ClearCategory();
end;

procedure RegisterDemos(const ATester: TMyrTester);
begin
  ATester.TestFolder := '$P:res/demos';

  ATester.SetCategory('Raylib');
  ATester.RegisterTest(0000, 'raylib/hellowindow', rmExecute, '', '', [tgWin64, tgLinux64]);

  ATester.SetCategory('SDL3');
  ATester.RegisterTest(0050, 'sdl3/colorboxes', rmExecute, '', '', [tgWin64]);
  ATester.RegisterTest(0051, 'sdl3/imagetexture', rmExecute, '', '', [tgWin64]);
  ATester.RegisterTest(0052, 'sdl3/mixermusic', rmExecute, '', '', [tgWin64]);

  ATester.OptLevels := [olNone, olBasic, olFull];
end;

procedure Menu();
var
  LTester: TMyrTester;
  LMenu:   TConsoleMenu;
  LCompliance: TConsoleMenu;
  LTestCases: TConsoleMenu;
  LDemos: TMyrTester;
  LDemosMenu: TConsoleMenu;
begin
  LTester := TMyrTester.Create();
  try
    RegisterComplianceTests(LTester);
    LMenu := TConsoleMenu.Create();
    LMenu.Pause := True;
    try
      LMenu.Title('Myrissa Tester');

      LCompliance := TMyrTester.CreateMenu(LTester);
      LMenu.AddSubmenu(LCompliance, 'Compliance Tests');

      LTestCases := LMenu.AddSubmenu('Test Cases');
      LTestCases.Pause := False;
      RegisterTestCase(LTestCases);

      LDemos := TMyrTester.Create();
      try
        RegisterDemos(LDemos);
        LDemosMenu := TMyrTester.CreateMenu(LDemos);
        LMenu.AddSubmenu(LDemosMenu, 'Demos');

        if not LTester.CLI() then
          LMenu.Run();
      finally
        LDemos.Free();
      end;
    finally
      LMenu.Free();
    end;
  finally
    LTester.Free();
  end;
end;

{ RunTestbed }
procedure RunTestbed();
begin
  try
    Menu();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);

      if TUtils.RunFromIDE() then
        TConsole.Pause();
    end;
  end;

end;

end.
