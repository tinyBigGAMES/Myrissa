{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.CImporter.Script - CImport Script Execution via Script Engine

  Wraps TMyrScriptEngine to execute .cps CImport scripts. Registers all
  CImporter commands as builtins so scripts use full Myrissa syntax:

    module script mylib;
    begin
      SetHeader("mylib.h");
      SetModuleName("mylib");
      Process();
    end.

  Public API is unchanged from the previous TCISLexer-based implementation.

  Dependencies: Myrissa.Script, Myrissa.CImporter, Myrissa.Common, StdApp.Base
===============================================================================}

unit Myrissa.CImporter.Script;

interface

uses
  System.SysUtils,
  System.Rtti,
  StdApp.Base,
  Myrissa.Common,
  Myrissa.Backend,
  Myrissa.CImporter,
  Myrissa.Script;

const
  { MYR_ERR_CIS_001 }
  MYR_ERR_CIS_001 = 'CIS001';

type
  { TMyrCImportScript }
  TMyrCImportScript = class(TBaseObject)
  private
    FImporter: TMyrCImporter;
    FEngine: TMyrScriptEngine;
    procedure RegisterBuiltins();
    function ResolveTarget(const AValue: string): TMyrTargetKind;
    function ResolveBindingMode(const AValue: string): TMyrBindingMode;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil); override;
    procedure ShowHelp();
    function ExecuteFile(const AFilename: string): Boolean;
  end;

implementation

uses
  StdApp.Console;

{ TMyrCImportScript }

constructor TMyrCImportScript.Create();
begin
  inherited;

  FImporter := TMyrCImporter.Create();
  FEngine := TMyrScriptEngine.Create();
  FEngine.SetErrors(FErrors);
  RegisterBuiltins();
end;

destructor TMyrCImportScript.Destroy();
begin
  FreeAndNil(FEngine);
  FreeAndNil(FImporter);

  inherited;
end;

procedure TMyrCImportScript.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited;

  FImporter.SetStatusCallback(ACallback, AUserData);
  FEngine.SetStatusCallback(ACallback, AUserData)
end;

function TMyrCImportScript.ResolveTarget(const AValue: string): TMyrTargetKind;
begin
  if not MyrTryParseTarget(AValue, Result) then
  begin
    FErrors.Add(esError, MYR_ERR_CIS_001,
      'Unknown target platform: %s', [AValue]);
    Result := tgWin64;
  end;
end;

function TMyrCImportScript.ResolveBindingMode(const AValue: string): TMyrBindingMode;
var
  LText: string;
begin
  LText := AValue.ToLower();
  if LText = 'dynamic' then
    Result := bmDynamic
  else
  begin
    FErrors.Add(esError, MYR_ERR_CIS_001,
      'Unknown binding mode: %s', [AValue]);
    Result := bmDynamic;
  end;
end;

procedure TMyrCImportScript.RegisterBuiltins();
begin
  // -- No-arg commands --

  FEngine.RegisterGlobalRoutine(
    'routine Process(): boolean',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    var
      LResult: Boolean;
    begin
      LResult := FImporter.Process();
      if not LResult then
        FErrors.Add(esError, MYR_ERR_CIS_001,
          'Process failed: %s', [FImporter.GetLastError()]);
      Result := TValue.From<Boolean>(LResult);
    end);

  FEngine.RegisterGlobalRoutine(
    'routine Clear()',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.Clear();
      Result := TValue.Empty;
    end);

  // -- Single string commands --

  FEngine.RegisterGlobalRoutine(
    'routine SetHeader(const AFilename: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetHeader(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetModuleName(const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetModuleName(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetDllName(const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetDllName(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetDllPath(const APath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetDllPath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetOutputPath(const APath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetOutputPath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddSourcePath(const APath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddSourcePath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddExcludedType(const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddExcludedType(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddExcludedFunction(const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddExcludedFunction(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddUsesUnit(const AUnit: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddUsesUnit(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddUndefine(const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddUndefine(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  // -- Boolean command --

  FEngine.RegisterGlobalRoutine(
    'routine SetSavePreprocessed(const AValue: boolean)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetSavePreprocessed(AArgs[0].AsBoolean);
      Result := TValue.Empty;
    end);

  // -- Binding mode (string -> enum) --

  FEngine.RegisterGlobalRoutine(
    'routine SetBindingMode(const AMode: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetBindingMode(ResolveBindingMode(AArgs[0].AsString));
      Result := TValue.Empty;
    end);

  // -- Target + string commands --

  FEngine.RegisterGlobalRoutine(
    'routine SetTargetDllName(const ATarget: string; const AName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.SetDllName(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddCopyDll(const ATarget: string; const APath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddCopyDll(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddLinkLibrary(const ATarget: string; const APath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddLinkLibrary(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  // -- Two string commands --

  FEngine.RegisterGlobalRoutine(
    'routine AddIncludePath(const APath: string; const AModule: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      if AArgs[1].AsString <> '' then
        FImporter.AddIncludePath(AArgs[0].AsString, AArgs[1].AsString)
      else
        FImporter.AddIncludePath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddDefine(const AName: string; const AValue: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      if AArgs[1].AsString <> '' then
        FImporter.AddDefine(AArgs[0].AsString, AArgs[1].AsString)
      else
        FImporter.AddDefine(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddFunctionRename(const AOriginal: string; const ANewName: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddFunctionRename(AArgs[0].AsString, AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddDepDll(const ADllName: string; const ADllPath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddDepDll(AArgs[0].AsString, AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  // -- Three string commands --

  FEngine.RegisterGlobalRoutine(
    'routine AddDllNameMap(const APath: string; const ADllName: string; const ADllPath: string)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.AddDllNameMap(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsString);
      Result := TValue.Empty;
    end);

  // -- Two strings + occurrence commands --

  FEngine.RegisterGlobalRoutine(
    'routine InsertTextAfter(const ATarget: string; const AText: string; const AOccurrence: int32)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.InsertTextAfter(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertTextBefore(const ATarget: string; const AText: string; const AOccurrence: int32)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.InsertTextBefore(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertFileAfter(const ATarget: string; const AFile: string; const AOccurrence: int32)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.InsertFileAfter(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertFileBefore(const ATarget: string; const AFile: string; const AOccurrence: int32)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.InsertFileBefore(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine ReplaceText(const AOld: string; const ANew: string; const AOccurrence: int32)',
    function(const AArgs: TMyrScriptArgs;
      const AInterpreter: TMyrScriptInterpreter;
      const AUserData: Pointer): TMyrScriptValue
    begin
      FImporter.ReplaceText(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);
end;

procedure TMyrCImportScript.ShowHelp();
begin
  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  cpas ' + COLOR_CYAN + 'cimport <script.cps>' + COLOR_RESET);
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'SCRIPT FORMAT:');
  TConsole.PrintLn('  CImport scripts use standard Myrissa script syntax:');
  TConsole.PrintLn('');
  TConsole.PrintLn('    module script mylib;');
  TConsole.PrintLn('    begin');
  TConsole.PrintLn('      SetHeader("mylib.h");');
  TConsole.PrintLn('      SetModuleName("mylib");');
  TConsole.PrintLn('      Process();');
  TConsole.PrintLn('    end.');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'SCRIPT COMMANDS:');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Configuration:');
  TConsole.PrintLn(COLOR_CYAN + '    SetHeader' + COLOR_RESET +
    '("filename")                          C header file to import');
  TConsole.PrintLn(COLOR_CYAN + '    SetModuleName' + COLOR_RESET +
    '("name")                           Output module name');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllName' + COLOR_RESET +
    '("name")                              DLL name');
  TConsole.PrintLn(COLOR_CYAN + '    SetTargetDllName' + COLOR_RESET +
    '("target", "name")              DLL name for specific target');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllPath' + COLOR_RESET +
    '("path")                              Path to DLL for preprocessing');
  TConsole.PrintLn(COLOR_CYAN + '    SetOutputPath' + COLOR_RESET +
    '("path")                           Output directory');
  TConsole.PrintLn(COLOR_CYAN + '    SetBindingMode' + COLOR_RESET +
    '("mode")                          Binding mode');
  TConsole.PrintLn(COLOR_CYAN + '    SetSavePreprocessed' + COLOR_RESET +
    '(bool)                       Save preprocessor output');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Paths & Filtering:');
  TConsole.PrintLn(COLOR_CYAN + '    AddIncludePath' + COLOR_RESET +
    '("path", "module")               C include search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddSourcePath' + COLOR_RESET +
    '("path")                            C source search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedType' + COLOR_RESET +
    '("name")                          Skip a C type');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedFunction' + COLOR_RESET +
    '("name")                      Skip a C function');
  TConsole.PrintLn(COLOR_CYAN + '    AddFunctionRename' + COLOR_RESET +
    '("original", "newname")         Rename an imported function');
  TConsole.PrintLn(COLOR_CYAN + '    AddUsesUnit' + COLOR_RESET +
    '("unit")                              Add a uses dependency');
  TConsole.PrintLn(COLOR_CYAN + '    AddDefine' + COLOR_RESET +
    '("name", "value")                      Preprocessor #define');
  TConsole.PrintLn(COLOR_CYAN + '    AddUndefine' + COLOR_RESET +
    '("name")                              Preprocessor #undef');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Text Manipulation:');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextAfter' + COLOR_RESET +
    '("target", "text", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextBefore' + COLOR_RESET +
    '("target", "text", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileAfter' + COLOR_RESET +
    '("target", "file", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileBefore' + COLOR_RESET +
    '("target", "file", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    ReplaceText' + COLOR_RESET +
    '("old", "new", occurrence)');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Linking:');
  TConsole.PrintLn(COLOR_CYAN + '    AddCopyDll' + COLOR_RESET +
    '("target", "path")                    Copy DLL to output');
  TConsole.PrintLn(COLOR_CYAN + '    AddLinkLibrary' + COLOR_RESET +
    '("target", "path")               Library search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddDllNameMap' + COLOR_RESET +
    '("path", "dllname", "dllpath")    DLL name mapping');
  TConsole.PrintLn(COLOR_CYAN + '    AddDepDll' + COLOR_RESET +
    '("dllname", "dllpath")                 Dependency DLL');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Execution:');
  TConsole.PrintLn(COLOR_CYAN + '    Process' + COLOR_RESET +
    '()                                       Run the import');
  TConsole.PrintLn(COLOR_CYAN + '    Clear' + COLOR_RESET +
    '()                                         Reset all settings');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'TARGET VALUES:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '"win64"' + COLOR_RESET +
    ', ' + COLOR_CYAN + '"linux64"' + COLOR_RESET);
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'BINDING MODES:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '"dynamic"' + COLOR_RESET);
  TConsole.PrintLn('');
end;

function TMyrCImportScript.ExecuteFile(const AFilename: string): Boolean;
begin
  Result := FEngine.ExecuteFile(AFilename);
end;

end.
