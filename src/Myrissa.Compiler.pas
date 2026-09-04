{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.Compiler - Top-level compiler driver

  Owns and orchestrates the full pipeline:
    Parser -> Semantics -> Codegen (TMyrNativeBackend)

  All components share a single error handler via SetErrors. Status callbacks
  propagate to all components via SetStatusCallback override.

  The caller configures build settings (target, output path, optimize level,
  etc.) before calling Compile(). Compile() runs the full pipeline in one
  shot: parse, analyze, generate C++23, wire generated files into ZigBuild,
  and build the native binary.

  Dependencies: Myrissa.Common, Myrissa.Frontend, Myrissa.Backend
===============================================================================}

unit Myrissa.Compiler;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  Myrissa.Common,
  Myrissa.Frontend,
  Myrissa.Backend,
  Myrissa.Emitter;

const
  MYR_ERR_CMP_001 = 'CMP001';  // Source file not found
  MYR_ERR_CMP_002 = 'CMP002';  // Cannot auto-run

type

  // Forwards
  TMyrCompiler = class;

  // Callbacks
  TMyrPreParseCallback = reference to procedure(const ACompiler: TMyrCompiler;
    const AUserData: Pointer);
  TMyrPreParseCallbackEntry = TCallback<TMyrPreParseCallback>;
  TMyrPreParseCallbackList = TList<TMyrPreParseCallbackEntry>;
  TMyrPreBuildCallback = reference to procedure(const ACompiler: TMyrCompiler;
    const AUserData: Pointer);
  TMyrPreBuildCallbackEntry = TCallback<TMyrPreBuildCallback>;
  TMyrPreBuildCallbackList = TList<TMyrPreBuildCallbackEntry>;

  { TMyrCompiler }
  TMyrCompiler = class(TBaseObject)
  protected
    FParser: TMyrParser;
    FSemantics: TMyrSemantics;
    FBackend: TMyrNativeBackend;  // replaces FCodegen + FZigBuild
    FMasterAST: TMyrMasterAST;
    FOutputPath: string;
    FOutputFilename: string;
    FSubsystem: TMyrSubsystem;
    FLastExitCode: DWORD;
    FPreParseCallbacks: TMyrPreParseCallbackList;
    FPreBuildCallbacks: TMyrPreBuildCallbackList;
    FKeyValues: TDictionary<string, string>;
    FModulePaths: TStringList;
    FCopyDlls: TStringList;
    // Version info accumulated from @vi* directives / SetVI* calls, handed
    // to the backend in one SetVersionInfo call before Build
    FVIMajor: Word;
    FVIMinor: Word;
    FVIPatch: Word;
    FVIProductName: string;
    FVIDescription: string;
    FVIFilename: string;
    FVICompanyName: string;
    FVICopyright: string;
    procedure DoProcessDirectives();
    procedure DoProcessImportedModuleDirectives(const AModule: TMyrModuleNode);
    // Individual directive handlers
    procedure DoProcessTargetDirective(const ADir: TMyrDirectiveNode; const AModule: TMyrModuleNode);
    procedure DoProcessSubsystemDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessOptimizeDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessModulePathDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessCopyDllDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessLibraryPathDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessMessageDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessExeIconDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessResFileDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessOutputPathDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessUnitTestModeDirective(const ADir: TMyrDirectiveNode; const AModule: TMyrModuleNode);
    procedure DoProcessAddVerInfoDirective(const ADir: TMyrDirectiveNode);
    procedure DoProcessVerInfoDirective(const ADir: TMyrDirectiveNode);
    procedure DoFirePreParseCallbacks();
    procedure DoFirePreBuildCallbacks();
    procedure DoSetupPlatformDefines();
    function DoPreScanTarget(const ASourceFile: string): TMyrTargetKind;
    procedure DoCLIDirectives();
    function DoValidateUnitModule(): Boolean;
    procedure DoCollectBreakpoints();
    procedure DoCollectBreakpointsInStmtList(const AList: TObjectList<TMyrASTNode>);
    procedure DoPostBuildCopyDlls();
    procedure DoEmitCode();
    function DoResolveSSADumpFilename(const ASourceFile: string): string;
    procedure DoDeleteSSADump(const ASourceFile: string);
    procedure DoWriteSSADump(const ASourceFile: string);
    function DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil); override;

    procedure SetDumpIR(const AValue: Boolean);

    // Full compilation pipeline: .cpas -> C++23 -> native binary
    procedure Compile(const ASourceFile: string; const AOutputPath: string;
      const AAutoRun: Boolean = False);

    // Run the last built artifact
    function Run(): Boolean;

    // Build configuration (set before calling Compile)
    procedure SetOptimizeLevel(const ALevel: Integer);
    procedure SetSubsystem(const ASubsystem: TMyrSubsystem);
    procedure SetTarget(const ATarget: TMyrTargetKind);

    // Defines
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string; const AValue: string); overload;
    procedure SetDefines(const ADefineNames: array of string);

    // Undefines
    procedure UnsetDefine(const ADefineName: string);
    procedure RemoveUndefine(const ADefineName: string);
    procedure ClearUndefines();

    // Link libraries
    procedure AddLibraryPath(const APath: string);
    procedure AddModulePath(const APath: string);

    // Post-build
    procedure AddCopyDLL(const ADLLPath: string);

    // Version info
    procedure SetAddVersionInfo(const AValue: Boolean);
    procedure SetVIMajor(const AValue: Word);
    procedure SetVIMinor(const AValue: Word);
    procedure SetVIPatch(const AValue: Word);
    procedure SetVIProductName(const AValue: string);
    procedure SetVIDescription(const AValue: string);
    procedure SetVIFilename(const AValue: string);
    procedure SetVICompanyName(const AValue: string);
    procedure SetVICopyright(const AValue: string);
    procedure SetExeIcon(const AValue: string);

    // Breakpoints
    procedure AddBreakpoint(const AFileName: string; const ALineNumber: Integer);

    // Pre-parse callbacks (fired before parsing begins)
    procedure AddPreParseCallback(const ACallback: TMyrPreParseCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreParseCallbacks();

    // Pre-build callbacks (fired after directives, before ZigBuild)
    procedure AddPreBuildCallback(const ACallback: TMyrPreBuildCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreBuildCallbacks();

    // Key-value store (generic property bag for cross-phase data)
    procedure SetKeyValue(const AKey: string; const AValue: string);
    function GetKeyValue(const AKey: string; const ADefault: string = ''): string;
    procedure ClearKeyValue(const AKey: string);

    // Getters
    function GetLastExitCode(): DWORD;
    function GetOutputPath(): string;
    function GetOptimizeLevel(): Integer;
    function GetSubsystem(): TMyrSubsystem;
    function GetTarget(): string;
    function GetOutputFilename(): string;
  end;

implementation

uses
  System.IOUtils;

{ TMyrCompiler }
constructor TMyrCompiler.Create();
begin
  inherited;

  FParser := TMyrParser.Create();
  FParser.SetErrors(FErrors);

  FSemantics := TMyrSemantics.Create();
  FSemantics.SetErrors(FErrors);

  FBackend := TMyrNativeBackend.Create();
  FBackend.SetErrors(FErrors);

  FPreParseCallbacks := TMyrPreParseCallbackList.Create();
  FPreBuildCallbacks := TMyrPreBuildCallbackList.Create();
  FKeyValues := TDictionary<string, string>.Create();
  FModulePaths := TStringList.Create();
  FModulePaths.Duplicates := dupIgnore;
  FCopyDlls := TStringList.Create();
  FCopyDlls.Duplicates := dupIgnore;
  FMasterAST := nil;
end;

destructor TMyrCompiler.Destroy();
begin
  FMasterAST.Free();
  FCopyDlls.Free();
  FModulePaths.Free();
  FKeyValues.Free();
  FPreBuildCallbacks.Free();
  FPreParseCallbacks.Free();
  FBackend.Free();
  FSemantics.Free();
  FParser.Free();

  inherited;
end;

procedure TMyrCompiler.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited;

  FParser.SetStatusCallback(ACallback, AUserData);
  FSemantics.SetStatusCallback(ACallback, AUserData);
  FBackend.SetStatusCallback(ACallback, AUserData);
end;

procedure TMyrCompiler.SetDumpIR(const AValue: Boolean);
begin
  FBackend.SetDumpIR(AValue);
end;

procedure TMyrCompiler.DoSetupPlatformDefines();
var
  LTarget: TMyrTargetKind;
  LOptLevel: string;
begin
  // Platform defines based on target
  FParser.Undefine('WINDOWS');
  FParser.Undefine('MSWINDOWS');
  FParser.Undefine('WIN64');
  FParser.Undefine('TARGET_WIN64');
  FParser.Undefine('LINUX');
  FParser.Undefine('TARGET_LINUX64');

  LTarget := FBackend.GetTarget();

  case LTarget of
    tgLinux64:
    begin
      FParser.SetDefine('LINUX', '1');
      FParser.SetDefine('TARGET_LINUX64', '1');
    end;
    tgWin64:
    begin
      FParser.SetDefine('WINDOWS', '1');
      FParser.SetDefine('MSWINDOWS', '1');
      FParser.SetDefine('WIN64', '1');
      FParser.SetDefine('TARGET_WIN64', '1');
    end;
  end;

  // Optimization level -- key-value store overrides backend default
  FParser.Undefine('DEBUG');
  FParser.Undefine('RELEASE');

  LOptLevel := GetKeyValue('optimize');
  if LOptLevel <> '' then
  begin
    if LOptLevel = 'none' then
      FParser.SetDefine('DEBUG', '1')
    else
      FParser.SetDefine('RELEASE', '1');
  end
  else
  begin
    if FBackend.GetOptimizationLevel() = 0 then
      FParser.SetDefine('DEBUG', '1')
    else
      FParser.SetDefine('RELEASE', '1');
  end;
end;

procedure TMyrCompiler.DoProcessTargetDirective(const ADir: TMyrDirectiveNode;
  const AModule: TMyrModuleNode);
begin
  if AModule.ResolvedTargetTriple <> '' then
    SetTarget(AModule.ResolvedTarget);
end;

procedure TMyrCompiler.DoProcessSubsystemDirective(const ADir: TMyrDirectiveNode);
var
  LValue: string;
begin
  LValue := ADir.DirectiveValue.ToLower();
  if LValue = 'console' then
    SetSubsystem(ssConsole)
  else if LValue = 'gui' then
    SetSubsystem(ssGui)
  else
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
      'Unknown @subsystem value ''%s''; expected console or gui',
      [ADir.DirectiveValue]);
end;

procedure TMyrCompiler.DoProcessOptimizeDirective(const ADir: TMyrDirectiveNode);
var
  LValue: string;
begin
  LValue := ADir.DirectiveValue.ToLower();
  if LValue = 'none' then
    SetOptimizeLevel(0)
  else if LValue = 'basic' then
    SetOptimizeLevel(1)
  else if LValue = 'full' then
    SetOptimizeLevel(2)
  else
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
      'Unknown @optimize value ''%s''; expected none, basic, or full',
      [ADir.DirectiveValue]);
end;

procedure TMyrCompiler.DoProcessModulePathDirective(const ADir: TMyrDirectiveNode);
begin
  AddModulePath(TUtils.ResolvePath(ADir.ResolvedValue));
end;

procedure TMyrCompiler.DoProcessCopyDllDirective(const ADir: TMyrDirectiveNode);
begin
  AddCopyDLL(TUtils.ResolvePath(ADir.ResolvedValue));
end;

procedure TMyrCompiler.DoProcessLibraryPathDirective(const ADir: TMyrDirectiveNode);
begin
  // Resolve $P: and friends here so the backend receives an absolute path
  AddLibraryPath(TUtils.ResolvePath(ADir.ResolvedValue));
end;

procedure TMyrCompiler.DoProcessMessageDirective(const ADir: TMyrDirectiveNode);
var
  LValue: string;
begin
  LValue := ADir.ResolvedValue.ToLower();
  if LValue = 'hint' then
    FErrors.Add(ADir.Location, esHint, MYR_ERR_CMP_001, '%s', [ADir.ResolvedValue2])
  else if LValue = 'warn' then
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001, '%s', [ADir.ResolvedValue2])
  else if LValue = 'error' then
    FErrors.Add(ADir.Location, esError, MYR_ERR_CMP_001, '%s', [ADir.ResolvedValue2])
  else if LValue = 'fatal' then
    FErrors.Add(ADir.Location, esFatal, MYR_ERR_CMP_001, '%s', [ADir.ResolvedValue2])
  else
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
      'Unknown @message severity ''%s''; expected hint, warn, error, or fatal',
      [ADir.DirectiveValue]);
end;

procedure TMyrCompiler.DoProcessExeIconDirective(const ADir: TMyrDirectiveNode);
begin
  FBackend.AddExeIcon(TUtils.ResolvePath(ADir.ResolvedValue));
end;

procedure TMyrCompiler.DoProcessResFileDirective(const ADir: TMyrDirectiveNode);
begin
  FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
    '@resfile is not yet implemented');
end;

procedure TMyrCompiler.DoProcessOutputPathDirective(const ADir: TMyrDirectiveNode);
begin
  FOutputPath := TUtils.ResolvePath(ADir.ResolvedValue);
end;

procedure TMyrCompiler.DoProcessUnitTestModeDirective(const ADir: TMyrDirectiveNode; const AModule: TMyrModuleNode);
var
  LValue: string;
begin
  // Directive spelling is read here only; the fact is recorded on the module node
  LValue := ADir.DirectiveValue.ToLower();
  if LValue = 'on' then
  begin
    AModule.UnitTestMode := True;
    FParser.SetDefine('UNITTESTMODE', '1');
  end
  else if LValue = 'off' then
  begin
    AModule.UnitTestMode := False;
    FParser.Undefine('UNITTESTMODE');
  end
  else
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
      'Unknown @unittestmode value ''%s''; expected on or off',
      [ADir.DirectiveValue]);
end;

procedure TMyrCompiler.DoProcessAddVerInfoDirective(const ADir: TMyrDirectiveNode);
var
  LValue: string;
begin
  LValue := ADir.DirectiveValue.ToLower();
  if LValue = 'on' then
    FBackend.AddVersionInfo(True)
  else if LValue = 'off' then
    FBackend.AddVersionInfo(False)
  else
    FErrors.Add(ADir.Location, esWarning, MYR_ERR_CMP_001,
      'Unknown @addverinfo value ''%s''; expected on or off',
      [ADir.DirectiveValue]);
end;

procedure TMyrCompiler.DoProcessVerInfoDirective(const ADir: TMyrDirectiveNode);
var
  LName: string;
begin
  LName := ADir.DirectiveName.ToLower();
  if LName = 'vimajor' then
    SetVIMajor(StrToIntDef(ADir.DirectiveValue, 0))
  else if LName = 'viminor' then
    SetVIMinor(StrToIntDef(ADir.DirectiveValue, 0))
  else if LName = 'vipatch' then
    SetVIPatch(StrToIntDef(ADir.DirectiveValue, 0))
  else if LName = 'viproductname' then
    SetVIProductName(ADir.ResolvedValue)
  else if LName = 'videscription' then
    SetVIDescription(ADir.ResolvedValue)
  else if LName = 'vifilename' then
    SetVIFilename(ADir.ResolvedValue)
  else if LName = 'vicompanyname' then
    SetVICompanyName(ADir.ResolvedValue)
  else if LName = 'vicopyright' then
    SetVICopyright(ADir.ResolvedValue);
end;

procedure TMyrCompiler.DoProcessDirectives();
var
  LMainModule: TMyrModuleNode;
  LDir: TMyrDirectiveNode;
  LName: string;
  I: Integer;
begin
  if (FMasterAST = nil) or (FMasterAST.Modules.Count = 0) then
    Exit;

  // Main module (index 0): all directives
  LMainModule := FMasterAST.Modules[0];
  for I := 0 to LMainModule.Directives.Count - 1 do
  begin
    LDir := LMainModule.Directives[I];
    LName := LDir.DirectiveName.ToLower();

    if LName = 'target' then
      DoProcessTargetDirective(LDir, LMainModule)
    else if LName = 'subsystem' then
      DoProcessSubsystemDirective(LDir)
    else if LName = 'optimize' then
      DoProcessOptimizeDirective(LDir)
    else if LName = 'modulepath' then
      DoProcessModulePathDirective(LDir)
    else if LName = 'copydll' then
      DoProcessCopyDllDirective(LDir)
    else if LName = 'addlibrarypath' then
      DoProcessLibraryPathDirective(LDir)
    else if LName = 'message' then
      DoProcessMessageDirective(LDir)
    else if LName = 'exeicon' then
      DoProcessExeIconDirective(LDir)
    else if LName = 'resfile' then
      DoProcessResFileDirective(LDir)
    else if LName = 'outputpath' then
      DoProcessOutputPathDirective(LDir)
    else if LName = 'unittestmode' then
      DoProcessUnitTestModeDirective(LDir, LMainModule)
    else if LName = 'addverinfo' then
      DoProcessAddVerInfoDirective(LDir)
    else if (LName = 'vimajor') or (LName = 'viminor') or (LName = 'vipatch')
         or (LName = 'viproductname') or (LName = 'videscription')
         or (LName = 'vifilename') or (LName = 'vicompanyname')
         or (LName = 'vicopyright') then
      DoProcessVerInfoDirective(LDir);
  end;

  // Imported modules: resource and message directives only
  for I := 1 to FMasterAST.Modules.Count - 1 do
    DoProcessImportedModuleDirectives(FMasterAST.Modules[I]);
end;

procedure TMyrCompiler.DoProcessImportedModuleDirectives(
  const AModule: TMyrModuleNode);
var
  LDir: TMyrDirectiveNode;
  LName: string;
  I: Integer;
begin
  for I := 0 to AModule.Directives.Count - 1 do
  begin
    LDir := AModule.Directives[I];
    LName := LDir.DirectiveName.ToLower();

    if LName = 'copydll' then
      DoProcessCopyDllDirective(LDir)
    else if LName = 'addlibrarypath' then
      DoProcessLibraryPathDirective(LDir)
    else if LName = 'message' then
      DoProcessMessageDirective(LDir);
  end;
end;

procedure TMyrCompiler.DoFirePreParseCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreParseCallbacks.Count - 1 do
    FPreParseCallbacks[I].Callback(Self, FPreParseCallbacks[I].UserData);
end;

procedure TMyrCompiler.AddPreParseCallback(const ACallback: TMyrPreParseCallback;
  const AUserData: Pointer);
var
  LEntry: TMyrPreParseCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreParseCallbacks.Add(LEntry);
end;

procedure TMyrCompiler.ClearPreParseCallbacks();
begin
  FPreParseCallbacks.Clear();
end;

procedure TMyrCompiler.SetKeyValue(const AKey: string; const AValue: string);
begin
  FKeyValues.AddOrSetValue(AKey, AValue);
end;

function TMyrCompiler.GetKeyValue(const AKey: string; const ADefault: string): string;
begin
  if not FKeyValues.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

procedure TMyrCompiler.ClearKeyValue(const AKey: string);
begin
  FKeyValues.Remove(AKey);
end;

function TMyrCompiler.DoPreScanTarget(const ASourceFile: string): TMyrTargetKind;
var
  LSource: string;
  LStripped: string;
  LLines: TArray<string>;
  LTrimmed: string;
  LTarget: TMyrTargetKind;
  LValue: string;
  LPos: Integer;
  LSrc: Integer;
  LLen: Integer;
  I: Integer;
begin
  // Lightweight text scan for @target directive BEFORE the full parse.
  // When @target linux64 appears in source, @ifdef TARGET_LINUX64 must
  // evaluate TRUE during parsing. The full parse discovers @target too
  // late -- @ifdef has already been evaluated by then.
  //
  // Strip all comments first (// line and /* block */), then scan
  // the clean text for @target. This matches how the parser sees the
  // source -- commented-out directives are invisible.
  Result := FBackend.GetTarget();

  if not TFile.Exists(ASourceFile) then
    Exit;

  LSource := TFile.ReadAllText(ASourceFile);
  LLen := Length(LSource);

  // Strip comments: build a clean copy with comments replaced by spaces
  // (preserving line structure for the line-by-line scan below).
  SetLength(LStripped, LLen);
  LSrc := 1;
  while LSrc <= LLen do
  begin
    // Block comment: /* ... */
    if (LSrc < LLen) and (LSource[LSrc] = '/') and (LSource[LSrc + 1] = '*') then
    begin
      // Replace opening /* with spaces
      LStripped[LSrc] := ' ';
      LStripped[LSrc + 1] := ' ';
      Inc(LSrc, 2);
      while LSrc <= LLen do
      begin
        if (LSrc < LLen) and (LSource[LSrc] = '*') and (LSource[LSrc + 1] = '/') then
        begin
          LStripped[LSrc] := ' ';
          LStripped[LSrc + 1] := ' ';
          Inc(LSrc, 2);
          Break;
        end;
        // Preserve newlines so line structure stays intact
        if LSource[LSrc] = #10 then
          LStripped[LSrc] := #10
        else if LSource[LSrc] = #13 then
          LStripped[LSrc] := #13
        else
          LStripped[LSrc] := ' ';
        Inc(LSrc);
      end;
      Continue;
    end;

    // Line comment: // ... until end of line
    if (LSrc < LLen) and (LSource[LSrc] = '/') and (LSource[LSrc + 1] = '/') then
    begin
      while (LSrc <= LLen) and (LSource[LSrc] <> #10) and (LSource[LSrc] <> #13) do
      begin
        LStripped[LSrc] := ' ';
        Inc(LSrc);
      end;
      Continue;
    end;

    // Normal character: copy as-is
    LStripped[LSrc] := LSource[LSrc];
    Inc(LSrc);
  end;

  // Scan stripped text for @target directive
  LLines := LStripped.Split([#10]);
  for I := 0 to Length(LLines) - 1 do
  begin
    LTrimmed := LLines[I].Trim();
    if LTrimmed.ToLower().StartsWith('@target ') then
    begin
      LValue := LTrimmed.Substring(8).Trim();
      LPos := LValue.IndexOf(';');
      if LPos >= 0 then
        LValue := LValue.Substring(0, LPos).Trim();
      if MyrTryParseTarget(LValue, LTarget) then
        Result := LTarget;
      Break;
    end;
  end;
end;

procedure TMyrCompiler.DoCLIDirectives();
var
  LValue: string;
  LLower: string;
begin
  // Apply CLI overrides from key-value store -- these override source directives
  LValue := GetKeyValue('target');
  if LValue <> '' then
  begin
    LLower := LValue.ToLower();
    if LLower = 'win64' then
      FBackend.SetTarget(tgWin64)
    else if LLower = 'linux64' then
      FBackend.SetTarget(tgLinux64)
    else
      FErrors.Add(esError, MYR_ERR_CMP_001,
        'Unknown target ''%s''; expected win64 or linux64', [LValue]);
  end;

  LValue := GetKeyValue('optimize');
  if LValue <> '' then
  begin
    LLower := LValue.ToLower();
    if (LLower = 'none') or (LLower = 'debug') then
      FBackend.SetOptimizationLevel(0)
    else if LLower = 'basic' then
      FBackend.SetOptimizationLevel(1)
    else if LLower = 'full' then
      FBackend.SetOptimizationLevel(2)
    else
      FErrors.Add(esError, MYR_ERR_CMP_001,
        'Unknown optimize level ''%s''; expected none, basic, or full', [LValue]);
  end;

  LValue := GetKeyValue('subsystem');
  if LValue <> '' then
  begin
    LLower := LValue.ToLower();
    if LLower = 'console' then
      FSubsystem := ssConsole
    else if LLower = 'gui' then
      FSubsystem := ssGui
    else
      FErrors.Add(esError, MYR_ERR_CMP_001,
        'Unknown subsystem ''%s''; expected console or gui', [LValue]);
  end;

  LValue := GetKeyValue('outputpath');
  if LValue <> '' then
  begin
    FOutputPath := TUtils.ResolvePath(LValue);
  end;

  LValue := GetKeyValue('dumpssa');
  if LValue <> '' then
  begin
    SetDumpIR(True);
    writeln('DBUG: enabled ssa dump');
  end;
end;

procedure TMyrCompiler.DoFirePreBuildCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreBuildCallbacks.Count - 1 do
    FPreBuildCallbacks[I].Callback(Self, FPreBuildCallbacks[I].UserData);
end;

procedure TMyrCompiler.AddPreBuildCallback(const ACallback: TMyrPreBuildCallback;
  const AUserData: Pointer);
var
  LEntry: TMyrPreBuildCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreBuildCallbacks.Add(LEntry);
end;

procedure TMyrCompiler.ClearPreBuildCallbacks();
begin
  FPreBuildCallbacks.Clear();
end;

procedure TMyrCompiler.DoCollectBreakpointsInStmtList(const AList: TObjectList<TMyrASTNode>);
var
  LI: Integer;
  LJ: Integer;
  LNode: TMyrASTNode;
begin
  if AList = nil then
    Exit;

  for LI := 0 to AList.Count - 1 do
  begin
    LNode := AList[LI];
    if LNode = nil then
      Continue;

    // Check if this is a @breakpoint directive
    if (LNode is TMyrDirectiveNode) and
       (TMyrDirectiveNode(LNode).DirectiveName = 'breakpoint') then
    begin
      // Register at line + 1 so the debugger breaks on the next source line
      AddBreakpoint(
        TUtils.ResolvePath(LNode.Location.Filename),
        LNode.Location.StartLine + 1);
    end;

    // Recurse into control flow bodies
    if LNode is TMyrIfNode then
    begin
      DoCollectBreakpointsInStmtList(TMyrIfNode(LNode).ThenBody);
      DoCollectBreakpointsInStmtList(TMyrIfNode(LNode).ElseBody);
    end
    else if LNode is TMyrWhileNode then
      DoCollectBreakpointsInStmtList(TMyrWhileNode(LNode).Body)
    else if LNode is TMyrForNode then
      DoCollectBreakpointsInStmtList(TMyrForNode(LNode).Body)
    else if LNode is TMyrRepeatNode then
      DoCollectBreakpointsInStmtList(TMyrRepeatNode(LNode).Body)
    else if LNode is TMyrGuardNode then
    begin
      DoCollectBreakpointsInStmtList(TMyrGuardNode(LNode).GuardBody);
      DoCollectBreakpointsInStmtList(TMyrGuardNode(LNode).ExceptBody);
      DoCollectBreakpointsInStmtList(TMyrGuardNode(LNode).FinallyBody);
    end
    else if LNode is TMyrMatchNode then
    begin
      for LJ := 0 to TMyrMatchNode(LNode).Arms.Count - 1 do
        DoCollectBreakpointsInStmtList(TMyrMatchNode(LNode).Arms[LJ].Body);
      DoCollectBreakpointsInStmtList(TMyrMatchNode(LNode).ElseBody);
    end;
  end;
end;

procedure TMyrCompiler.DoCollectBreakpoints();
var
  LModIdx: Integer;
  LDeclIdx: Integer;
  LTestIdx: Integer;
  LModule: TMyrModuleNode;
  LDecl: TMyrASTNode;
begin
  for LModIdx := 0 to FMasterAST.Modules.Count - 1 do
  begin
    LModule := FMasterAST.Modules[LModIdx];

    // Walk routine bodies in declarations
    for LDeclIdx := 0 to LModule.Declarations.Count - 1 do
    begin
      LDecl := LModule.Declarations[LDeclIdx];
      if (LDecl is TMyrRoutineDeclNode) and
         (TMyrRoutineDeclNode(LDecl).Body <> nil) then
        DoCollectBreakpointsInStmtList(TMyrRoutineDeclNode(LDecl).Body);
    end;

    // Walk init, final, and main bodies
    DoCollectBreakpointsInStmtList(LModule.InitBody);
    DoCollectBreakpointsInStmtList(LModule.FinalBody);
    DoCollectBreakpointsInStmtList(LModule.MainBody);

    // Walk test blocks
    for LTestIdx := 0 to LModule.TestBlocks.Count - 1 do
      DoCollectBreakpointsInStmtList(LModule.TestBlocks[LTestIdx].Body);
  end;
end;

procedure TMyrCompiler.DoPostBuildCopyDlls();
var
  LI: Integer;
  LSrc: string;
  LDst: string;
begin
  for LI := 0 to FCopyDlls.Count - 1 do
  begin
    LSrc := FCopyDlls[LI];
    if not TFile.Exists(LSrc) then
    begin
      Status('WARNING: @copydll source not found: %s', [LSrc]);
      Continue;
    end;

    LDst := TPath.Combine(FOutputPath, TPath.GetFileName(LSrc));
    try
      Status('Copying %s...', [TPath.GetFileName(LSrc)]);
      TFile.Copy(LSrc, LDst, True);
    except
      on E: Exception do
        Status('WARNING: @copydll failed to copy %s: %s',
          [TPath.GetFileName(LSrc), E.Message]);
    end;
  end;
end;

procedure TMyrCompiler.DoEmitCode();
var
  LEmitter: TMyrEmitter;
  LOrdered: TList<TMyrModuleNode>;
  LVisited: TList<TMyrModuleNode>;
  I: Integer;

  // Depth-first post-order: a module is appended only after every module it
  // imports has been. Emitting in that order guarantees a type, global, or
  // routine is registered with the backend before any module refers to it.
  // The parse queue is breadth-first (main first), which is the wrong order
  // for emission and was the cause of I0002 on cross-module locals.
  // LVisited stops the walk on a module already seen, so an import cycle
  // cannot recurse without end.
  procedure Visit(const AModule: TMyrModuleNode);
  var
    LI: Integer;
    LDep: TMyrModuleNode;
  begin
    if LVisited.Contains(AModule) then
      Exit;
    LVisited.Add(AModule);
    for LI := 0 to AModule.Imports.Count - 1 do
    begin
      LDep := FMasterAST.GetModule(AModule.Imports[LI].ModuleName);
      if LDep <> nil then
        Visit(LDep);
    end;
    LOrdered.Add(AModule);
  end;

begin
  Status('Emitting code...');

  LOrdered := TList<TMyrModuleNode>.Create();
  LVisited := TList<TMyrModuleNode>.Create();
  LEmitter := TMyrEmitter.Create();
  try
    LEmitter.SetErrors(FErrors);
    for I := 0 to FMasterAST.Modules.Count - 1 do
      Visit(FMasterAST.Modules[I]);
    for I := 0 to LOrdered.Count - 1 do
      LEmitter.EmitModule(LOrdered[I], FBackend);
  finally
    LEmitter.Free();
    LVisited.Free();
    LOrdered.Free();
  end;
end;

function TMyrCompiler.DoResolveSSADumpFilename(const ASourceFile: string): string;
begin
  // Dump goes beside the generated exe in the output directory
  Result := TPath.Combine(FOutputPath,
    Format('%s_%s_%d.txt',
      [TPath.GetFileNameWithoutExtension(ASourceFile),
       TMyrTargetInfo.TargetText(FBackend.GetTarget()),
       FBackend.GetOptimizationLevel()]));
end;

procedure TMyrCompiler.DoDeleteSSADump(const ASourceFile: string);
var
  LFilename: string;
begin
  if not FBackend.GetDumpIR() then
    Exit;

  LFilename := DoResolveSSADumpFilename(ASourceFile);
  try
    if TFile.Exists(LFilename) then
      TFile.Delete(LFilename);
  except
    on E: Exception do
      Status('SSA dump: could not remove stale file "%s" (%s)',
        [LFilename, E.Message]);
  end;
end;

procedure TMyrCompiler.DoWriteSSADump(const ASourceFile: string);
var
  LFilename: string;
begin
  if not FBackend.GetDumpIR() then
    Exit;

  LFilename := DoResolveSSADumpFilename(ASourceFile);
  try
    if TFile.Exists(LFilename) then
      TFile.Delete(LFilename);
    TUtils.CreateDirInPath(LFilename);
    TFile.WriteAllText(LFilename, FBackend.GetSSADump());
  except
    on E: Exception do
      Status('SSA dump: write failed for "%s" (%s)',
        [LFilename, E.Message]);
  end;
end;

function TMyrCompiler.DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
var
  LModuleKind: TMyrModuleKind;
begin
  if not AAutoRun then
    Exit(False);

  Result := True;
  LModuleKind := FMasterAST.Modules[0].ModuleKind;

  // Only exe modules can be run
  if LModuleKind <> mkExe then
  begin
    if LModuleKind = mkDll then
      FErrors.Add(FMasterAST.Modules[0].Location, esError, MYR_ERR_CMP_002,
        RSSemCannotRunModule, ['dll'])
    else if LModuleKind = mkLib then
      FErrors.Add(FMasterAST.Modules[0].Location, esError, MYR_ERR_CMP_002,
        RSSemCannotRunModule, ['lib'])
    else
      FErrors.Add(FMasterAST.Modules[0].Location, esError, MYR_ERR_CMP_002,
        RSSemCannotRunModule, ['unit']);
    Result := False;
    Exit;
  end;

  // Only native targets can be run -- both win64 and linux64 are runnable
  // (TMyrNativeBackend.Run handles WSL for linux64)
  // All supported targets are native, so this is always valid
end;

function TMyrCompiler.DoValidateUnitModule(): Boolean;
begin
  Result := FMasterAST.Modules[0].ModuleKind = mkUnit;
  if not Result then
    Exit;

  Status('Unit ''%s'' validated successfully.',
    [FMasterAST.Modules[0].ModuleName]);
  Status('Warning: Unit modules produce no output. Import this unit from an exe, dll, or lib module.');
end;

procedure TMyrCompiler.Compile(const ASourceFile: string;
  const AOutputPath: string; const AAutoRun: Boolean);
var
  LProjectName: string;
  LSourceFile: string;
  LSourceDir: string;
  LModule: TMyrModuleNode;
  LPendingName: string;
  LPendingFile: string;
  LTargetKind: TMyrTargetKind;
  I: Integer;
  LOutputFilename: string;
begin
  FErrors.Clear();
  FreeAndNil(FMasterAST);
  FMasterAST := TMyrMasterAST.Create();

  try
    // Normalize source file extension
    LSourceFile := TUtils.ResolvePath(TPath.ChangeExtension(ASourceFile, MYR_SRCFILE_EXT));

    if not TFile.Exists(LSourceFile) then
    begin
      FErrors.Add(esFatal, MYR_ERR_CMP_001,
        'Source file not found: %s', [LSourceFile]);
      Exit;
    end;

    LProjectName := TPath.GetFileNameWithoutExtension(LSourceFile);
    LSourceDir := TPath.GetDirectoryName(TPath.GetFullPath(LSourceFile));

    FOutputPath := TUtils.ResolvePath(AOutputPath);

    // Phase 1: Parse -- queue-based import processing
    // Fire pre-parse callbacks (CLI stores key-values here)
    DoFirePreParseCallbacks();

    // The CLI target must be on the backend BEFORE the platform defines
    // are computed, or every -t linux64 build parses with the win64
    // symbols set. DoCLIDirectives re-applies it later (after source
    // directives) which is correct for overriding but too late for @ifdef.
    if GetKeyValue('target') <> '' then
    begin
      if MyrTryParseTarget(GetKeyValue('target'), LTargetKind) then
        SetTarget(LTargetKind);
    end
    else
    begin
      // No CLI target -- pre-scan source for @target directive so that
      // @ifdef TARGET_* conditionals see the correct defines during parse.
      SetTarget(DoPreScanTarget(LSourceFile));
    end;

    // Set up platform defines before parsing begins
    DoSetupPlatformDefines();

    // Default module search paths
    AddModulePath(TUtils.ResolvePath('$P:res/libs/std'));

    // Parse the main module, then process any imports it declares
    Status('Parsing %s...', [TPath.GetFileName(LSourceFile)]);
    LModule := FParser.ParseModule(LSourceFile, FMasterAST);
    if LModule = nil then
      Exit;
    FMasterAST.AddModule(LModule);
    if FErrors.HasErrors() then
      Exit;

    // Collect @modulepath directives from main module before resolving imports
    for I := 0 to LModule.Directives.Count - 1 do
    begin
      if LModule.Directives[I].DirectiveName.ToLower() = 'modulepath' then
        AddModulePath(TUtils.ResolvePath(
          LModule.Directives[I].DirectiveValue.DeQuotedString('"')));
    end;

    // Process pending imports until queue is empty
    while FMasterAST.HasPending() do
    begin
      LPendingName := FMasterAST.DequeuePending();

      // Resolve import name to file path
      // First search: source file's own directory
      LPendingFile := TPath.Combine(LSourceDir,
        TPath.ChangeExtension(LPendingName, MYR_SRCFILE_EXT));

      // Search @modulepath directories if not found in source dir
      if not TFile.Exists(LPendingFile) then
      begin
        for I := 0 to FModulePaths.Count - 1 do
        begin
          LPendingFile := TPath.Combine(FModulePaths[I],
            TPath.ChangeExtension(LPendingName, MYR_SRCFILE_EXT));
          if TFile.Exists(LPendingFile) then
            Break;
        end;
      end;

      if not TFile.Exists(LPendingFile) then
      begin
        FErrors.Add(esError, MYR_ERR_CMP_001,
          'Imported module file not found: %s', [LPendingName]);
        Exit;
      end;

      Status('Parsing %s...', [TPath.GetFileName(LPendingFile)]);
      LModule := FParser.ParseModule(LPendingFile, FMasterAST);
      if LModule = nil then
        Exit;

      // Verify imported module is a unit
      if LModule.ModuleKind <> mkUnit then
      begin
        FErrors.Add(LModule.Location, esError, MYR_ERR_CMP_001,
          'Cannot import module ''%s'': only unit modules can be imported',
          [LModule.ModuleName]);
        LModule.Free();
        Exit;
      end;

      FMasterAST.AddModule(LModule);
      if FErrors.HasErrors() then
        Exit;
    end;

    // Fire pre-build callbacks (user hooks)
    Status('Processing pre-build callbacks...');
    DoFirePreBuildCallbacks();

    // Phase 2: Semantic analysis
    Status('Analyzing...');
    FErrors.RaiseOnError := True;
    try
      FSemantics.Analyze(FMasterAST);
    except
      on EStdAppException do;
    end;
    FErrors.RaiseOnError := False;
    if FErrors.HasErrors() then
      Exit;

    // Process directives from enriched AST (after semantics)
    // Directives and CLI can override the output path set above
    Status('Processing directives...');
    DoProcessDirectives();

    // Apply CLI directive overrides from key-value store
    DoCLIDirectives();

    if FErrors.HasErrors() then
      Exit;

  //  PrintErrors();

    // Unit modules: validate only, no codegen or build
    if DoValidateUnitModule() then
      Exit;

    // Record @breakpoint markers in the backend source map before codegen
    DoCollectBreakpoints();

    // Clear stale SSA dump before codegen
    DoDeleteSSADump(LSourceFile);

    // Phase 3: Code generation via TMyrEmitter
    DoEmitCode();

    if FErrors.HasErrors() then
      Exit;

    // Phase 4: Build via TMyrNativeBackend

    // Configure output target (exe/dll/lib) with output path
    LOutputFilename := TPath.Combine(FOutputPath, FMasterAST.Modules[0].ModuleName);

    case FMasterAST.Modules[0].ModuleKind of
      mkExe:
        begin
           FBackend.TargetExe(LOutputFilename, FSubsystem);
        end;
      mkDll:
        begin
          FBackend.TargetDll(LOutputFilename);
         end;
      mkLib:
        begin
          FBackend.TargetLib(LOutputFilename);
        end;
    end;

    // Hand the accumulated @vi* values to the backend in one call
    FBackend.SetVersionInfo(FVIMajor, FVIMinor, FVIPatch,
      FVIProductName, FVIDescription, FVIFilename, FVICompanyName,
      FVICopyright);

    if not FBackend.Build(False) then
      Exit;

    // Post-build: copy DLLs listed by @copydll to the output directory
    DoPostBuildCopyDlls();

    // Run the built artifact if requested
    if DoValidateAutoRun(AAutoRun) then
      Run();

  except
    on E: Exception do
    begin
      if not FErrors.HasErrors() then
        FErrors.Add(esFatal, MYR_ERR_CMP_001,
          'Internal compiler error: %s', [E.Message]);
    end;
  end;

  // Write SSA dump even on failure -- a failed build is exactly when the
  // dump is most useful
  DoWriteSSADump(LSourceFile);
end;

function TMyrCompiler.Run(): Boolean;
var
  LExitCode: Cardinal;
begin
  LExitCode := 0;
  Result := FBackend.Run(@LExitCode);
  FLastExitCode := LExitCode;
end;

procedure TMyrCompiler.SetOptimizeLevel(const ALevel: Integer);
begin
  FBackend.SetOptimizationLevel(ALevel);
end;

procedure TMyrCompiler.SetSubsystem(const ASubsystem: TMyrSubsystem);
begin
  FSubsystem := ASubsystem;
end;

procedure TMyrCompiler.SetTarget(const ATarget: TMyrTargetKind);
begin
  FBackend.SetTarget(ATarget);
end;

procedure TMyrCompiler.SetDefine(const ADefineName: string);
begin
  FParser.SetDefine(ADefineName, '1');
end;

procedure TMyrCompiler.SetDefine(const ADefineName: string; const AValue: string);
begin
  FParser.SetDefine(ADefineName, AValue);
end;

procedure TMyrCompiler.SetDefines(const ADefineNames: array of string);
var
  I: Integer;
begin
  for I := 0 to Length(ADefineNames) - 1 do
    FParser.SetDefine(ADefineNames[I], '1');
end;

procedure TMyrCompiler.UnsetDefine(const ADefineName: string);
begin
  FParser.Undefine(ADefineName);
end;

procedure TMyrCompiler.RemoveUndefine(const ADefineName: string);
begin
  FParser.Undefine(ADefineName);
end;

procedure TMyrCompiler.ClearUndefines();
begin
  // No bulk clear on parser -- individual Undefine calls are the mechanism
end;

{ TMyrCompiler.AddLibraryPath }
procedure TMyrCompiler.AddLibraryPath(const APath: string);
begin
  FBackend.AddLibPath(TUtils.ResolvePath(APath));
end;

{ TMyrCompiler.AddModulePath }
procedure TMyrCompiler.AddModulePath(const APath: string);
begin
  if APath <> '' then
    FModulePaths.Add(APath);
end;

procedure TMyrCompiler.AddCopyDLL(const ADLLPath: string);
begin
  FCopyDlls.Add(ADLLPath);
end;

procedure TMyrCompiler.SetAddVersionInfo(const AValue: Boolean);
begin
  FBackend.AddVersionInfo(AValue);
end;

procedure TMyrCompiler.SetVIMajor(const AValue: Word);
begin
  FVIMajor := AValue;
end;

procedure TMyrCompiler.SetVIMinor(const AValue: Word);
begin
  FVIMinor := AValue;
end;

procedure TMyrCompiler.SetVIPatch(const AValue: Word);
begin
  FVIPatch := AValue;
end;

procedure TMyrCompiler.SetVIProductName(const AValue: string);
begin
  FVIProductName := AValue;
end;

procedure TMyrCompiler.SetVIDescription(const AValue: string);
begin
  FVIDescription := AValue;
end;

procedure TMyrCompiler.SetVIFilename(const AValue: string);
begin
  FVIFilename := AValue;
end;

procedure TMyrCompiler.SetVICompanyName(const AValue: string);
begin
  FVICompanyName := AValue;
end;

procedure TMyrCompiler.SetVICopyright(const AValue: string);
begin
  FVICopyright := AValue;
end;

procedure TMyrCompiler.SetExeIcon(const AValue: string);
begin
  FBackend.AddExeIcon(AValue);
end;

procedure TMyrCompiler.AddBreakpoint(const AFileName: string;
  const ALineNumber: Integer);
begin
  FBackend.AddBreakpoint(AFileName, ALineNumber);
end;

function TMyrCompiler.GetLastExitCode(): DWORD;
begin
  Result := FLastExitCode;
end;

function TMyrCompiler.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

function TMyrCompiler.GetOptimizeLevel(): Integer;
begin
  Result := FBackend.GetOptimizationLevel();
end;

function TMyrCompiler.GetSubsystem(): TMyrSubsystem;
begin
  Result := FSubsystem;
end;

function TMyrCompiler.GetTarget(): string;
begin
  Result := TMyrTargetInfo.TargetText(FBackend.GetTarget());
end;

function TMyrCompiler.GetOutputFilename(): string;
begin
  Result := FBackend.GetOutputPath();
end;

end.
