{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.LibTCC - Self-contained TCC (Tiny C Compiler) wrapper

  Loads libtcc.dll from an embedded resource via StdApp.DllLoader and
  serves TCC's include/lib files from an embedded ZIP archive via IAT
  hooking (StdApp.ZipVFS). This allows the host application to compile
  C code at runtime as a single self-contained executable with zero
  external dependencies.

  Key types:
  - TLibTCC: Workflow-enforced TCC wrapper -- NewState, SetOutput,
    AddIncludePath/Library, CompileString/File, Relocate, GetSymbol,
    Run. Tracks workflow state to prevent out-of-order calls.
  - TLibTCCOutput: Output mode (Memory, EXE, OBJ, DLL, PreProcess)
  - TLibTCCSubsystem: Console or GUI subsystem

  Resources required (RT_RCDATA):
  - LIBTCC_DLL: The libtcc.dll binary
  - TCC_FILES: ZIP archive containing include/ and lib/ directories

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Console
===============================================================================}
unit StdApp.LibTCC;

{$I StdApp.Defines.inc}

interface

uses
  WinApi.Windows,
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Math,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console;

const
  // TCC/C backend error codes
  TCC_ERR = 'C001';
  TCC_WRN = 'C002';
  TCC_HNT = 'C003';

type
  { TLibTCCOutput }
  TLibTCCOutput = (
    opMemory=1,
    opEXE=2,
    opOBJ=3,
    opDLL=4,
    opPreProcess=5
  );

  { TLibTCCPrintCallback }
  TLibTCCPrintCallback = reference to procedure(const AError: string; const AUserData: Pointer);

  { TLibTCCSubsystem }
  TLibTCCSubsystem = (
    ssConsole,
    ssGUI
  );

  { TLibTCC }
  TLibTCC = class(TBaseObject)
  protected type
    { TWorkflowState }
    TWorkflowState = (wsNew, wsConfigured, wsCompiled, wsRelocated, wsFinalized);

    { TCallback }
    TCallback<T> = record
      Handler: T;
      UserData: Pointer;
    end;
  protected
    FMarshaller: TMarshaller;
    FState: Pointer;
    FWorkflowState: TWorkflowState;
    FOutput: TLibTCCOutput;
    FOutputSet: Boolean;
    FPrintCallback: TCallback<TLibTCCPrintCallback>;

    function AsUTF8(const AText: string): Pointer;
    procedure InternalPrintCallback(const AError: string; const AUserData: Pointer);

    procedure NewState();
    procedure FreeState();

  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Reset();
    procedure Clear();
    procedure SetPrintCallback(const AUserData: Pointer; const AHandler: TLibTCCPrintCallback);
    procedure Print(const AText: string; const AArgs: array of const);
    function AddIncludePath(const APathName: string): Boolean;
    function AddSystemIncludePath(const APathName: string): Boolean;
    function AddLibraryPath(const APathName: string): Boolean;
    function AddLibrary(const ALibraryName: string): Boolean;
    function DefineSymbol(const ASymbol, AValue: string): Boolean;
    function UndefineSymbol(const ASymbol: string): Boolean;
    function SetOuput(const AOutput: TLibTCCOutput): Boolean;
    function SetOption(const AOption: string): Boolean;
    function SetSubsystem(const ASubsystem: TLibTCCSubsystem): Boolean;
    function SetDebugInfo(const AEnabled: Boolean): Boolean;
    function DisableWarnings(): Boolean;
    function SetWarningsAsErrors(): Boolean;
    function SetUnsignedChar(): Boolean;
    function SetSignedChar(): Boolean;
    function CompileString(const ACode: string; const AFilename: string='source.c'): Boolean;
    function CompileFile(const AFilename: string): Boolean;
    function AddFile(const AFilename: string): Boolean;
    function OutputFile(const AFilename: string): Boolean;
    function Run(const AArgc: Integer; const AArgv: Pointer): Integer;
    function Relocate(): Boolean;
    function AddSymbol(const AName: string; const AValue: Pointer): Boolean;
    function GetSymbol(const AName: string): Pointer;
    function SetPreprocessOutput(const AFilename: string): Boolean;
    procedure ClosePreprocessOutput();
    procedure ShowStats(const ATotalTimeMs: Cardinal; const AIndent: string = '');
  end;

implementation

{$R StdApp.LibTCC.res}

uses
  StdApp.DLLLoader,
  StdApp.IATHook,
  StdApp.ZipVFS;

const
  TCC_OUTPUT_MEMORY     = 1;
  TCC_OUTPUT_EXE        = 2;
  TCC_OUTPUT_DLL        = 4;
  TCC_OUTPUT_OBJ        = 3;
  TCC_OUTPUT_PREPROCESS = 5;

  { Resource names for embedded content }
  RES_LIBTCC_DLL = 'LIBTCC_DLL';
  RES_TCC_FILES  = 'TCC_FILES';

type
  TCCState = type Pointer;
  TCCReallocFunc = function(ptr: Pointer; size: Cardinal): Pointer; cdecl;
  TCCErrorFunc = procedure(opaque: Pointer; msg: PAnsiChar); cdecl;
  TCCSymbolCallback = procedure(ctx: Pointer; name: PAnsiChar; val: Pointer); cdecl;
  TCCBtFunc = function(udata, pc: Pointer; file_: PAnsiChar; line: Integer; func, msg: PAnsiChar): Integer; cdecl;

var
  tcc_set_realloc: procedure(my_realloc: TCCReallocFunc); cdecl;
  tcc_new: function(): TCCState; cdecl;
  tcc_delete: procedure(s: TCCState); cdecl;
  tcc_set_lib_path: procedure(s: TCCState; path: PAnsiChar); cdecl;
  tcc_set_error_func: procedure(s: TCCState; error_opaque: Pointer; error_func: TCCErrorFunc); cdecl;
  tcc_set_options: function(s: TCCState; str: PAnsiChar): Integer; cdecl;
  tcc_add_include_path: function(s: TCCState; pathname: PAnsiChar): Integer; cdecl;
  tcc_add_sysinclude_path: function(s: TCCState; pathname: PAnsiChar): Integer; cdecl;
  tcc_define_symbol: procedure(s: TCCState; sym, value: PAnsiChar); cdecl;
  tcc_undefine_symbol: procedure(s: TCCState; sym: PAnsiChar); cdecl;
  tcc_add_file: function(s: TCCState; filename: PAnsiChar): Integer; cdecl;
  tcc_compile_string: function(s: TCCState; buf: PAnsiChar): Integer; cdecl;
  tcc_set_output_type: function(s: TCCState; output_type: Integer): Integer; cdecl;
  tcc_add_library_path: function(s: TCCState; pathname: PAnsiChar): Integer; cdecl;
  tcc_add_library: function(s: TCCState; libraryname: PAnsiChar): Integer; cdecl;
  tcc_add_symbol: function(s: TCCState; name: PAnsiChar; val: Pointer): Integer; cdecl;
  tcc_output_file: function(s: TCCState; filename: PAnsiChar): Integer; cdecl;
  tcc_run: function(s: TCCState; argc: Integer; argv: PPAnsiChar): Integer; cdecl;
  tcc_relocate: function(s1: TCCState): Integer; cdecl;
  tcc_get_symbol: function(s: TCCState; name: PAnsiChar): Pointer; cdecl;
  tcc_list_symbols: procedure(s: TCCState; ctx: Pointer; symbol_cb: TCCSymbolCallback); cdecl;
  tcc_set_backtrace_func: procedure(s1: TCCState; userdata: Pointer; bt: TCCBtFunc); cdecl;
  tcc_print_stats: procedure(s: TCCState; total_time: Cardinal); cdecl;
  tcc_set_pp_outfile: function(s: TCCState; filename: PAnsiChar): Integer; cdecl;
  tcc_close_pp_outfile: procedure(s: TCCState); cdecl;


{ TLibTCC }
procedure LibTCC_ErrorFunc(AOpaque: Pointer; AMsg: PAnsiChar); cdecl;
var
  LSelf: TLibTCC;
begin
  LSelf := AOpaque;
  if not Assigned(LSelf) then Exit;
  LSelf.InternalPrintCallback(string(AMsg), AOpaque);
  //writeln(amsg);
end;

function LibTCC_ReallocFunc(APtr: Pointer; ASize: Cardinal): Pointer; cdecl;
begin
  if ASize = 0 then
  begin
    if APtr <> nil then
      FreeMem(APtr);
    Result := nil;
  end
  else if APtr = nil then
  begin
    GetMem(Result, ASize);
  end
  else
  begin
    ReallocMem(APtr, ASize);
    Result := APtr;
  end;
end;

function TLibTCC.AsUTF8(const AText: string): Pointer;
begin
  Result := FMarshaller.AsUtf8(AText).ToPointer;
end;

procedure TLibTCC.InternalPrintCallback(const AError: string; const AUserData: Pointer);
var
  LParts: TArray<string>;
  LFilename: string;
  LLine: Integer;
  LMessage: string;
  LSeverity: TErrorSeverity;
  LSeverityAndMsg: string;
  LStartIdx: Integer;
  I: Integer;
begin
  LParts := AError.Split([':']);

  if Length(LParts) < 3 then
  begin
    if Assigned(FPrintCallback.Handler) then
      FPrintCallback.Handler(AError, FPrintCallback.UserData);
    Exit;
  end;

  if (LParts[0].Trim.ToLower = 'tcc') then
  begin
    LSeverityAndMsg := LParts[1].Trim.ToLower;

    if LSeverityAndMsg.Contains('error') then
      LSeverity := esError
    else if LSeverityAndMsg.Contains('warning') then
      LSeverity := esWarning
    else
      LSeverity := esHint;

    LMessage := '';
    for I := 2 to High(LParts) do
    begin
      if I > 2 then
        LMessage := LMessage + ':';
      LMessage := LMessage + LParts[I];
    end;
    LMessage := LMessage.Trim;

    if Assigned(FErrors) then
    begin
      case LSeverity of
        esError: FErrors.Add('', 0, 0, LSeverity, TCC_ERR, LMessage);
        esWarning: FErrors.Add('', 0, 0, LSeverity, TCC_WRN, LMessage);
      else
        FErrors.Add('', 0, 0, LSeverity, TCC_HNT, LMessage);
      end;
    end;

    if Assigned(FPrintCallback.Handler) then
      FPrintCallback.Handler(AError, FPrintCallback.UserData);
    Exit;
  end;


  if (Length(LParts) >= 4) and
     (Length(LParts[0]) = 1) and
     CharInSet(LParts[0][1], ['A'..'Z', 'a'..'z']) and
     (Length(LParts[1]) > 0) and
     CharInSet(LParts[1][1], ['\', '/']) then
  begin
    LFilename := LParts[0] + ':' + LParts[1];
    LStartIdx := 2;
  end
  else
  begin
    LFilename := LParts[0];
    LStartIdx := 1;
  end;

  if LStartIdx >= Length(LParts) then
    Exit;

  LFilename := LFilename.Trim;
  LLine := StrToIntDef(LParts[LStartIdx].Trim, 0);

  if LLine = 0 then
  begin
    if Assigned(FPrintCallback.Handler) then
      FPrintCallback.Handler(AError, FPrintCallback.UserData);
    Exit;
  end;

  Inc(LStartIdx);

  if LStartIdx >= Length(LParts) then
    Exit;

  LSeverityAndMsg := LParts[LStartIdx].Trim.ToLower;

  if LSeverityAndMsg.Contains('error') then
    LSeverity := esError
  else if LSeverityAndMsg.Contains('warning') then
    LSeverity := esWarning
  else
    LSeverity := esHint;

  Inc(LStartIdx);
  if LStartIdx < Length(LParts) then
  begin
    LMessage := '';
    for I := LStartIdx to High(LParts) do
    begin
      if I > LStartIdx then
        LMessage := LMessage + ':';
      LMessage := LMessage + LParts[I];
    end;
    LMessage := LMessage.Trim;
  end
  else
    LMessage := '';

  if Assigned(FErrors) then
  begin
    case LSeverity of
      esError: FErrors.Add(LFilename, LLine, 1, LSeverity, TCC_ERR, LMessage);
      esWarning: FErrors.Add(LFilename, LLine, 1, LSeverity, TCC_WRN, LMessage);
    else
      FErrors.Add(LFilename, LLine, 1, LSeverity, TCC_HNT, LMessage);
    end;
  end;

  if Assigned(FPrintCallback.Handler) then
    FPrintCallback.Handler(AError, FPrintCallback.UserData);
end;

procedure TLibTCC.NewState();
begin
  tcc_set_realloc(LibTCC_ReallocFunc);

  if not Assigned(FState) then
  begin
    FState := tcc_new();
    if not Assigned(FState) then
      raise Exception.Create('Failed to create tcc state');
  end;

  FWorkflowState := wsNew;
  FOutputSet := False;

  tcc_set_error_func(FState, Self, LibTCC_ErrorFunc);
end;

procedure TLibTCC.FreeState();
begin
  if Assigned(FState) then
  begin
    tcc_delete(FState);
    FState := nil;
  end;
end;

constructor TLibTCC.Create();
begin
  inherited;
  NewState();
end;

destructor TLibTCC.Destroy();
begin
  FreeState();
  inherited;
end;

procedure TLibTCC.SetPrintCallback(const AUserData: Pointer; const AHandler: TLibTCCPrintCallback);
begin
  FPrintCallback.Handler := AHandler;
  FPrintCallback.UserData := AUserData;
end;

procedure TLibTCC.Print(const AText: string; const AArgs: array of const);
var
  LText: string;
begin
  LText := Format(AText, AArgs);
  if Assigned(FPrintCallback.Handler) then
  begin
    FPrintCallback.Handler(LText, FPrintCallback.UserData);
  end;
end;

procedure TLibTCC.Reset();
begin
  FreeState();
  NewState();
end;

procedure TLibTCC.Clear();
begin
  Reset();

  FPrintCallback.Handler := nil;
  FPrintCallback.UserData := nil;
end;


function TLibTCC.AddIncludePath(const APathName: string): Boolean;
begin
  if FWorkflowState > wsCompiled then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_include_path(FState, AsUTF8(APathName)) >= 0;
end;

function TLibTCC.AddSystemIncludePath(const APathName: string): Boolean;
begin
  if FWorkflowState > wsCompiled then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_sysinclude_path(FState, AsUTF8(APathName)) >= 0;
end;

function TLibTCC.AddLibraryPath(const APathName: string): Boolean;
begin
  if FWorkflowState > wsCompiled then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_library_path(FState, AsUTF8(APathName)) >= 0;
end;

function TLibTCC.AddLibrary(const ALibraryName: string): Boolean;
begin
  if FWorkflowState > wsCompiled then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_library(FState, AsUTF8(ALibraryName)) >= 0;
end;

function TLibTCC.DefineSymbol(const ASymbol, AValue: string): Boolean;
begin
  if FWorkflowState > wsConfigured then
  begin
    Result := False;
    Exit;
  end;

  tcc_define_symbol(FState, AsUTF8(ASymbol), AsUTF8(AValue));
  Result := True;
end;

function TLibTCC.UndefineSymbol(const ASymbol: string): Boolean;
begin
  if FWorkflowState > wsConfigured then
  begin
    Result := False;
    Exit;
  end;

  tcc_undefine_symbol(FState, AsUTF8(ASymbol));
  Result := True;
end;

function  TLibTCC.SetOuput(const AOutput: TLibTCCOutput): Boolean;
begin
  if FWorkflowState <> wsNew then
  begin
    Result := False;
    Exit;
  end;

  Result := Boolean(tcc_set_output_type(FState, Ord(AOutput)) >= 0);

  if Result then
  begin
    FOutput := AOutput;
    FOutputSet := True;
    FWorkflowState := wsConfigured;
  end;
end;

function TLibTCC.SetOption(const AOption: string): Boolean;
var
  LOption: string;
begin
  Result := False;

  LOption := AOption.Trim.ToLower;

  // -g must be set BEFORE output type (TCC requirement)
  if LOption = '-g' then
  begin
    if FWorkflowState > wsNew then
      Exit;
  end
  else
  begin
    if not FOutputSet or (FWorkflowState > wsCompiled) then
      Exit;
  end;

  // Block backtrace options (not supported in this context)
  if (LOption = '-b') or LOption.StartsWith('-bt') then
    Exit;

  if tcc_set_options(FState, AsUTF8(AOption)) = 0 then
    Result := True;
end;

function TLibTCC.SetSubsystem(const ASubsystem: TLibTCCSubsystem): Boolean;
const
  CSubsystemOptions: array[TLibTCCSubsystem] of string = (
    '-Wl,-subsystem=console',
    '-Wl,-subsystem=windows'
  );
begin
  Result := False;

  if not (FOutput in [opEXE, opDLL]) then
    Exit;

  Result := SetOption(CSubsystemOptions[ASubsystem]);
end;

function TLibTCC.SetDebugInfo(const AEnabled: Boolean): Boolean;
begin
  if AEnabled then
    Result := SetOption('-g')
  else
    Result := True;
end;

function TLibTCC.DisableWarnings(): Boolean;
begin
  Result := SetOption('-w');
end;

function TLibTCC.SetWarningsAsErrors(): Boolean;
begin
  Result := SetOption('-Werror');
end;

function TLibTCC.SetUnsignedChar(): Boolean;
begin
  Result := SetOption('-funsigned-char');
end;

function TLibTCC.SetSignedChar(): Boolean;
begin
  Result := SetOption('-fsigned-char');
end;


function TLibTCC.CompileString(const ACode, AFilename: string): Boolean;
var
  LCode: string;
begin
  if not FOutputSet or (FWorkflowState <> wsConfigured) and (FWorkflowState <> wsCompiled) then
  begin
    Result := False;
    Exit;
  end;

  LCode := '#line 1 "' + AFilename + '"' + #13#10 + ACode;
  Result := Boolean(tcc_compile_string(FState, AsUTF8(LCode)) >= 0);
  if Result then
    FWorkflowState := wsCompiled;
end;

function TLibTCC.CompileFile(const AFilename: string): Boolean;
begin
  Result := AddFile(AFilename);

  if Result and (FWorkflowState = wsConfigured) then
    FWorkflowState := wsCompiled;
end;

function TLibTCC.AddFile(const AFilename: string): Boolean;
begin
  if not FOutputSet or (FWorkflowState <> wsConfigured) and (FWorkflowState <> wsCompiled) then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_file(FState, AsUTF8(AFilename)) >= 0;
  if Result then
    FWorkflowState := wsCompiled;
end;

function TLibTCC.OutputFile(const AFilename: string): Boolean;
begin
  if (FOutput = opMemory) or (FWorkflowState <> wsCompiled) then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_output_file(FState, AsUTF8(AFilename)) >= 0;
  if Result then
    FWorkflowState := wsFinalized;
end;

function TLibTCC.Run(const AArgc: Integer; const AArgv: Pointer): Integer;
begin
  if (FOutput <> opMemory) or (FWorkflowState <> wsCompiled) then
  begin
    Result := -1;
    Exit;
  end;

  Result := tcc_run(FState, AArgc, AArgv);
  if Result >= 0 then
    FWorkflowState := wsFinalized;
end;

function TLibTCC.Relocate: Boolean;
begin
  if (FOutput <> opMemory) or (FWorkflowState <> wsCompiled) then
  begin
    Result := False;
    Exit;
  end;

  Result := Boolean(tcc_relocate(FState) >= 0);
  if Result then
    FWorkflowState := wsRelocated;
end;

function TLibTCC.AddSymbol(const AName: string; const AValue: Pointer): Boolean;
begin
  if (FWorkflowState <> wsCompiled) or
     ((FOutput = opMemory) and (FWorkflowState >= wsRelocated)) then
  begin
    Result := False;
    Exit;
  end;

  Result := tcc_add_symbol(FState, AsUTF8(AName), AValue) >= 0;
end;

function TLibTCC.GetSymbol(const AName: string): Pointer;
begin
  if (FOutput <> opMemory) or (FWorkflowState <> wsRelocated) then
  begin
    Result := nil;
    Exit;
  end;

  Result := tcc_get_symbol(FState, AsUTF8(AName));
end;

function TLibTCC.SetPreprocessOutput(const AFilename: string): Boolean;
begin
  Result := False;

  if not Assigned(FState) then
    Exit;

  Result := tcc_set_pp_outfile(FState, AsUTF8(AFilename)) >= 0;
end;

procedure TLibTCC.ClosePreprocessOutput();
begin
  if Assigned(FState) then
    tcc_close_pp_outfile(FState);
end;

procedure TLibTCC.ShowStats(const ATotalTimeMs: Cardinal; const AIndent: string);
type
  TFreopen = function(filename, mode, stream: Pointer): Pointer; cdecl;
  TFflush = function(stream: Pointer): Integer; cdecl;
  TIobFunc = function: Pointer; cdecl;
var
  LMsvcrt: THandle;
  LFreopen: TFreopen;
  LFflush: TFflush;
  LIobFunc: TIobFunc;
  LStderr: Pointer;
  LTempFile: string;
  LOutput: TStringList;
  LI: Integer;
  LLine: string;
begin
  if not Assigned(FState) then
    Exit;

  if FWorkflowState < wsCompiled then
    Exit;

  LMsvcrt := GetModuleHandle('msvcrt.dll');
  if LMsvcrt = 0 then
    LMsvcrt := WinApi.Windows.LoadLibrary('msvcrt.dll');
  if LMsvcrt = 0 then
  begin
    tcc_print_stats(FState, ATotalTimeMs);
    Exit;
  end;

  @LFreopen := GetProcAddress(LMsvcrt, 'freopen');
  @LFflush := GetProcAddress(LMsvcrt, 'fflush');
  @LIobFunc := GetProcAddress(LMsvcrt, '__iob_func');

  if not Assigned(LFreopen) or not Assigned(LFflush) or not Assigned(LIobFunc) then
  begin
    tcc_print_stats(FState, ATotalTimeMs);
    Exit;
  end;

  LStderr := Pointer(NativeUInt(LIobFunc()) + 2 * 48);

  LTempFile := TPath.GetTempFileName();
  if LFreopen(PAnsiChar(AnsiString(LTempFile)), PAnsiChar('w'), LStderr) = nil then
  begin
    tcc_print_stats(FState, ATotalTimeMs);
    Exit;
  end;

  try
    tcc_print_stats(FState, ATotalTimeMs);
    LFflush(LStderr);
  finally
    LFreopen(PAnsiChar('CONOUT$'), PAnsiChar('w'), LStderr);
  end;

  LOutput := TStringList.Create();
  try
    if TFile.Exists(LTempFile) then
    begin
      LOutput.LoadFromFile(LTempFile);
      for LI := 0 to LOutput.Count - 1 do
      begin
        LLine := LOutput[LI];
        if LLine.StartsWith('# ') then
          LLine := LLine.Substring(2);
        if LLine <> '' then
        begin
          if LI = 0 then
            TConsole.PrintLn(AIndent + 'Stats: ' + LLine)
          else
            TConsole.PrintLn(AIndent + '       ' + LLine);
        end;
      end;
      TFile.Delete(LTempFile);
    end;
  finally
    LOutput.Free();
  end;
end;

//  Module Loading - Uses Dlluminator for memory loading and ZipVFS for file I/O
var
  LTCCDllHandle: THandle = 0;
  LZipVFSInitialized: Boolean = False;

function LoadTCCFromResource(out AError: string): Boolean;
var
  LResStream: TResourceStream;
  LDllBytes: TBytes;
begin
  Result := False;

  { Check if already loaded }
  if LTCCDllHandle <> 0 then
  begin
    Result := True;
    Exit;
  end;

  { Load libtcc.dll from embedded resource }
  try
    LResStream := TResourceStream.Create(HInstance, RES_LIBTCC_DLL, RT_RCDATA);
    try
      SetLength(LDllBytes, LResStream.Size);
      if LResStream.Size > 0 then
        LResStream.ReadBuffer(LDllBytes[0], LResStream.Size);
    finally
      LResStream.Free();
    end;
  except
    on E: Exception do
    begin
      AError := Format('Failed to load %s resource: %s', [RES_LIBTCC_DLL, E.Message]);
      Exit;
    end;
  end;

  if Length(LDllBytes) = 0 then
  begin
    AError := Format('Resource %s is empty', [RES_LIBTCC_DLL]);
    Exit;
  end;

  { Load DLL from memory using Dlluminator }
  LTCCDllHandle := StdApp.DLLLoader.LoadLibrary(@LDllBytes[0], Length(LDllBytes));
  if LTCCDllHandle = 0 then
  begin
    AError := Format('Dlluminator failed to load %s (Error: %d)', [RES_LIBTCC_DLL, GetLastError()]);
    Exit;
  end;

  { Initialize ZipVFS to intercept file I/O }
  if not TZipVFS.Initialize(Pointer(LTCCDllHandle), RES_TCC_FILES) then
  begin
    AError := Format('Failed to initialize ZipVFS with resource %s', [RES_TCC_FILES]);
    FreeLibrary(LTCCDllHandle);
    LTCCDllHandle := 0;
    Exit;
  end;
  LZipVFSInitialized := True;

  { Resolve TCC function pointers }
  @tcc_set_realloc := GetProcAddress(LTCCDllHandle, 'tcc_set_realloc');
  @tcc_new := GetProcAddress(LTCCDllHandle, 'tcc_new');
  @tcc_delete := GetProcAddress(LTCCDllHandle, 'tcc_delete');
  @tcc_set_lib_path := GetProcAddress(LTCCDllHandle, 'tcc_set_lib_path');
  @tcc_set_error_func := GetProcAddress(LTCCDllHandle, 'tcc_set_error_func');
  @tcc_set_options := GetProcAddress(LTCCDllHandle, 'tcc_set_options');
  @tcc_add_include_path := GetProcAddress(LTCCDllHandle, 'tcc_add_include_path');
  @tcc_add_sysinclude_path := GetProcAddress(LTCCDllHandle, 'tcc_add_sysinclude_path');
  @tcc_define_symbol := GetProcAddress(LTCCDllHandle, 'tcc_define_symbol');
  @tcc_undefine_symbol := GetProcAddress(LTCCDllHandle, 'tcc_undefine_symbol');
  @tcc_add_file := GetProcAddress(LTCCDllHandle, 'tcc_add_file');
  @tcc_compile_string := GetProcAddress(LTCCDllHandle, 'tcc_compile_string');
  @tcc_set_output_type := GetProcAddress(LTCCDllHandle, 'tcc_set_output_type');
  @tcc_add_library_path := GetProcAddress(LTCCDllHandle, 'tcc_add_library_path');
  @tcc_add_library := GetProcAddress(LTCCDllHandle, 'tcc_add_library');
  @tcc_add_symbol := GetProcAddress(LTCCDllHandle, 'tcc_add_symbol');
  @tcc_output_file := GetProcAddress(LTCCDllHandle, 'tcc_output_file');
  @tcc_run := GetProcAddress(LTCCDllHandle, 'tcc_run');
  @tcc_relocate := GetProcAddress(LTCCDllHandle, 'tcc_relocate');
  @tcc_get_symbol := GetProcAddress(LTCCDllHandle, 'tcc_get_symbol');
  @tcc_list_symbols := GetProcAddress(LTCCDllHandle, 'tcc_list_symbols');
  @tcc_set_backtrace_func := GetProcAddress(LTCCDllHandle, 'tcc_set_backtrace_func');
  @tcc_print_stats := GetProcAddress(LTCCDllHandle, 'tcc_print_stats');
  @tcc_set_pp_outfile := GetProcAddress(LTCCDllHandle, 'tcc_set_pp_outfile');
  @tcc_close_pp_outfile := GetProcAddress(LTCCDllHandle, 'tcc_close_pp_outfile');

  { Verify essential functions were resolved }
  if not Assigned(tcc_new) or not Assigned(tcc_delete) or not Assigned(tcc_compile_string) then
  begin
    AError := 'Failed to resolve essential TCC functions';
    TZipVFS.Finalize();
    LZipVFSInitialized := False;
    FreeLibrary(LTCCDllHandle);
    LTCCDllHandle := 0;
    Exit;
  end;

  Result := True;
end;

procedure UnloadTCC();
begin
  if LTCCDllHandle = 0 then Exit;

  { Finalize ZipVFS (removes IAT hooks) }
  if LZipVFSInitialized then
  begin
    TZipVFS.Finalize();
    LZipVFSInitialized := False;
  end;

  { Free the DLL }
  FreeLibrary(LTCCDllHandle);
  LTCCDllHandle := 0;
end;

procedure ShowError(const AError: string);
begin
  MessageBox(0, PWideChar(AError), 'Fatal Error', MB_ICONERROR);
end;

procedure Load();
var
  LError: string;
begin
  if not LoadTCCFromResource(LError) then
  begin
    ShowError(LError);
    Exit;
  end;
end;

procedure Unload();
begin
  UnloadTCC();
end;

initialization
begin
  SetExceptionMask(GetExceptionMask + [exOverflow, exInvalidOp]);
  Load();
end;

finalization
begin
  Unload();
end;

end.
