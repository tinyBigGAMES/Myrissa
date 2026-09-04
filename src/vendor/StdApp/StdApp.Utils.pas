{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Utils - General-purpose utility routines

  Static utility class covering string encoding (UTF-8, ANSI), process
  launching with output capture, PE validation, version info extraction,
  resource manipulation (icons, manifests, version, RCDATA), file
  encoding detection, path helpers, environment variables, and line
  counting. Also provides raw pointer array types for typed memory access.

  Key types:
  - TUtils: Static class -- AsUTF8, RunPE, CaptureConsoleOutput,
    GetVersionInfo, UpdateIconResource, UpdateVersionInfoResource,
    IsValidWin64PE, GetFileSHA256, GetRelativePath, GetAppType, and more
  - TCommandBuilder: Fluent command-line argument builder
  - TVersionInfo: Record holding parsed PE version resource fields
  - TAppType: Console/GUI/Unknown application type enum
  - Raw pointer array types: PInt8Array..PDoubleArray for typed access

  Dependencies: StdApp.Base, StdApp.Resources
  Notes: InitConsole() enables Windows Virtual Terminal Processing for
    ANSI escape sequences. Called automatically on first console output.
===============================================================================}

unit StdApp.Utils;

{$I StdApp.Defines.inc}

interface

uses
  WinAPI.Windows,
  WinAPI.ShellAPI,
  System.SysUtils,
  System.IOUtils,
  System.AnsiStrings,
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.Hash,
  StdApp.Base,
  StdApp.Resources;

const

  { PATH_PREFIX_PROCESS }
  // Resolve the remainder against the running process directory.
  PATH_PREFIX_PROCESS = '$P:';

  { PATH_PREFIX_CURRENT }
  // Resolve the remainder against the current working directory.
  PATH_PREFIX_CURRENT = '$D:';

  { PATH_PREFIX_SOURCE }
  // Resolve the remainder against the caller-supplied contextual base.
  // This is the explicit spelling of the default behavior.
  PATH_PREFIX_SOURCE = '$S:';

type

  { Raw Pointer Array Helpers }
  PInt8Array   = ^TInt8Array;
  TInt8Array   = array[0..MaxInt div SizeOf(Int8) - 1]   of Int8;

  PUInt8Array  = ^TUInt8Array;
  TUInt8Array  = array[0..MaxInt div SizeOf(UInt8) - 1]  of UInt8;

  PInt16Array  = ^TInt16Array;
  TInt16Array  = array[0..MaxInt div SizeOf(Int16) - 1]  of Int16;

  PUInt16Array = ^TUInt16Array;
  TUInt16Array = array[0..MaxInt div SizeOf(UInt16) - 1] of UInt16;

  PInt32Array  = ^TInt32Array;
  TInt32Array  = array[0..MaxInt div SizeOf(Int32) - 1]  of Int32;

  PUInt32Array = ^TUInt32Array;
  TUInt32Array = array[0..MaxInt div SizeOf(UInt32) - 1] of UInt32;

  PInt64Array  = ^TInt64Array;
  TInt64Array  = array[0..MaxInt div SizeOf(Int64) - 1]  of Int64;

  PUInt64Array = ^TUInt64Array;
  TUInt64Array = array[0..MaxInt div SizeOf(UInt64) - 1] of UInt64;

  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..MaxInt div SizeOf(Single) - 1] of Single;

  PDoubleArray = ^TDoubleArray;
  TDoubleArray = array[0..MaxInt div SizeOf(Double) - 1] of Double;

  { TCaptureConsoleCallback }
  TCaptureConsoleCallback = reference to procedure(const ALine: string; const AUserData: Pointer);

  { TOutputCallback }
  TOutputCallback = reference to procedure(const AText: string; const AUserData: Pointer);

  { TVersionInfo }
  TVersionInfo = record
    Major: Word;
    Minor: Word;
    Patch: Word;
    Build: Word;
    VersionString: string;
    ProductName: string;
    CompanyName: string;
    Copyright: string;
    Description: string;
    URL: string;
  end;

  { TAppType }
  TAppType = (
    atUnknown,
    atConsole,
    atGUI
  );

  { TAppType }
  TUtils = class
  private class var
    FMarshaller: TMarshaller;
  private
    class function  EnableVirtualTerminalProcessing(): Boolean; static;
    class procedure InitConsole(); static;

  public
    class procedure FailIf(const Cond: Boolean; const Msg: string; const AArgs: array of const);

    class function  GetTickCount(): DWORD; static;
    class function  GetTickCount64(): UInt64; static;

    class function  AsUTF8(const AValue: string; ALength: PCardinal = nil): Pointer; static;
    class function  ToAnsi(const AValue: string): AnsiString; static;
    class function  FromUtf8(const APtr: PAnsiChar): string; static;

    class procedure ProcessMessages(); static;

    class function  RunPE(const AExe, AParams, AWorkDir: string; const AWait: Boolean = True; const AShowCmd: Word = SW_SHOWNORMAL): Cardinal; static;
    class function  RunElf(const AElf, AWorkDir: string): Cardinal; static;
    class function  ShellOpen(const AFilename: string; const AWorkDir: string = ''; const AShowCmd: Word = SW_SHOWNORMAL): Boolean; static;
    class function  WindowsPathToWSL(const APath: string): string; static;
    class procedure CaptureConsoleOutput(const ATitle: string; const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback); static;
    class procedure CaptureConsolePTY(const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback); static;
    class function  CreateProcessWithPipes(const AExe, AParams, AWorkDir: string; out AStdinWrite: THandle; out AStdoutRead: THandle; out AProcessHandle: THandle; out AThreadHandle: THandle): Boolean; static;

    class function  CreateDirInPath(const AFilename: string): Boolean;
    class function  GetVersionInfo(out AVersionInfo: TVersionInfo; const AFilePath: string = ''): Boolean; static;
    class function  GetModuleVersionString(const AModule: HMODULE): string; static;

    class procedure CopyFilePreservingEncoding(const ASourceFile, ADestFile: string); static;
    class function  DetectFileEncoding(const AFilePath: string): TEncoding; static;
    class function  EnsureBOM(const AText: string): string; static;
    class function  EscapeString(const AText: string): string; static;
    class function  StripAnsi(const AText: string): string; static;
    class function  ExtractAnsiCodes(const AText: string): string; static;

    class function  IsValidWin64PE(const AFilePath: string): Boolean; static;
    class procedure UpdateIconResource(const AExeFilePath, AIconFilePath: string); static;
    class procedure UpdateVersionInfoResource(const PEFilePath: string; const AMajor, AMinor, APatch: Word; const AProductName, ADescription, AFilename, ACompanyName, ACopyright: string; const AURL: string = ''); static;
    class function  ResourceExist(const AResName: string): Boolean; static;
    class function  AddResManifestFromResource(const AResName: string; const AModuleFile: string; ALanguage: Integer = 1033): Boolean; static;
    class procedure UpdateRCDataResource(const AExeFilePath: string; const AResourceName: string; const AData: TStream); static;

    class function  GetFileSHA256(const APath: string): string; static;
    class function  GetRelativePath(const ABasePath, AFullPath: string): string; static;
    class function  NormalizePath(const APath: string): string; static;
    class function  DisplayPath(const APath: string): string; static;

    class function  GetEnv(const AName: string): string; static;
    class procedure SetEnv(const AName: string; const AValue: string); static;
    class function  HasEnv(const AName: string): Boolean; static;
    class function  RunFromIDE(): Boolean; static;
    class function  CountLines(const APath, APattern: string; const ARecursive: Boolean = True): Int64; static;
    class function  GetAppType(): TAppType; static;
    class function  ResolvePath(const APath: string;
      const ABaseDir: string = ''): string; static;

  end;

  { TCommandBuilder }
  TCommandBuilder = class(TBaseObject)
  private
    FParams: TStringList;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure Clear();
    procedure AddParam(const AParam: string); overload;
    procedure AddParam(const AFlag, AValue: string); overload;
    procedure AddQuotedParam(const AFlag, AValue: string); overload;
    procedure AddQuotedParam(const AValue: string); overload;
    procedure AddFlag(const AFlag: string);

    function Dump(const AId: Integer = 0): string; override;
    function GetParamCount(): Integer;
  end;

implementation

const
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;

type
  HPCON = THandle;

  PCOORD = ^COORD;
  COORD = record
    X: SmallInt;
    Y: SmallInt;
  end;

  PSTARTUPINFOEXW = ^STARTUPINFOEXW;
  STARTUPINFOEXW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: Pointer;
  end;

function AddDllDirectory(NewDirectory: LPCWSTR): Pointer; stdcall; external kernel32 name 'AddDllDirectory';
function RemoveDllDirectory(Cookie: Pointer): BOOL; stdcall; external kernel32 name 'RemoveDllDirectory';
function SetDefaultDllDirectories(DirectoryFlags: DWORD): BOOL; stdcall; external kernel32 name 'SetDefaultDllDirectories';
function GetEnvironmentStringsW(): PWideChar; stdcall; external kernel32 name 'GetEnvironmentStringsW';
function FreeEnvironmentStringsW(lpszEnvironmentBlock: PWideChar): BOOL; stdcall; external kernel32 name 'FreeEnvironmentStringsW';

// ConPTY functions
function CreatePseudoConsole(size: COORD; hInput, hOutput: THandle; dwFlags: DWORD; out phPC: HPCON): HRESULT; stdcall; external kernel32 name 'CreatePseudoConsole';
function ClosePseudoConsole(hPC: HPCON): HRESULT; stdcall; external kernel32 name 'ClosePseudoConsole';
function InitializeProcThreadAttributeList(lpAttributeList: Pointer; dwAttributeCount: DWORD; dwFlags: DWORD; var lpSize: SIZE_T): BOOL; stdcall; external kernel32 name 'InitializeProcThreadAttributeList';
function UpdateProcThreadAttribute(lpAttributeList: Pointer; dwFlags: DWORD; Attribute: DWORD_PTR; lpValue: Pointer; cbSize: SIZE_T; lpPreviousValue: Pointer; lpReturnSize: PSIZE_T): BOOL; stdcall; external kernel32 name 'UpdateProcThreadAttribute';
procedure DeleteProcThreadAttributeList(lpAttributeList: Pointer); stdcall; external kernel32 name 'DeleteProcThreadAttributeList';



{ TCbrUtils }

class function TUtils.EnableVirtualTerminalProcessing(): Boolean;
var
  LHOut: THandle;
  LMode: DWORD;
begin
  Result := False;

  LHOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if LHOut = INVALID_HANDLE_VALUE then Exit;
  if not GetConsoleMode(LHOut, LMode) then Exit;

  LMode := LMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING;
  if not SetConsoleMode(LHOut, LMode) then Exit;

  Result := True;
end;

class procedure TUtils.InitConsole();
begin
  EnableVirtualTerminalProcessing();
  SetConsoleCP(CP_UTF8);
  SetConsoleOutputCP(CP_UTF8);
end;

class procedure TUtils.FailIf(const Cond: Boolean; const Msg: string; const AArgs: array of const);
begin
  if Cond then
    raise Exception.CreateFmt(Msg, AArgs);
end;

class function TUtils.GetTickCount(): DWORD;
begin
  Result := WinApi.Windows.GetTickCount();
end;

class function TUtils.GetTickCount64(): UInt64;
begin
  Result := WinApi.Windows.GetTickCount64();
end;

class function TUtils.AsUTF8(const AValue: string; ALength: PCardinal): Pointer;
begin
  Result := FMarshaller.AsUtf8(AValue).ToPointer;
  if Assigned(ALength) then
    ALength^ := System.AnsiStrings.StrLen(PAnsiChar(Result));
end;

class function TUtils.ToAnsi(const AValue: string): AnsiString;
var
  LBytes: TBytes;
begin
  LBytes := TEncoding.ANSI.GetBytes(AValue);
  if Length(LBytes) = 0 then
    Exit('');
  SetString(Result, PAnsiChar(@LBytes[0]), Length(LBytes));
end;

class function TUtils.FromUtf8(const APtr: PAnsiChar): string;
begin
  if APtr = nil then
    Result := ''
  else
    Result := string(UTF8String(APtr));
end;

class procedure TUtils.ProcessMessages();
var
  LMsg: TMsg;
begin
  while Integer(PeekMessage(LMsg, 0, 0, 0, PM_REMOVE)) <> 0 do
  begin
    TranslateMessage(LMsg);
    DispatchMessage(LMsg);
  end;
end;

class function TUtils.RunPE(const AExe, AParams, AWorkDir: string; const AWait: Boolean; const AShowCmd: Word): Cardinal;
var
  LAppPath: string;
  LCmd: UnicodeString;
  LSI: STARTUPINFOW;
  LPI: PROCESS_INFORMATION;
  LExit: DWORD;
  LCreationFlags: DWORD;
  LWorkDirPW: PWideChar;
begin
  if AExe = '' then
    raise Exception.Create('RunPE: Executable path is empty');

  // Resolve the executable path against the workdir if only a filename was provided
  if TPath.IsPathRooted(TUtils.ResolvePath(AExe)) or (Pos('\', AExe) > 0) or (Pos('/', AExe) > 0) then
    LAppPath := TUtils.ResolvePath(AExe)
  else if AWorkDir <> '' then
    LAppPath := TPath.Combine(AWorkDir, AExe)
  else
    LAppPath := AExe; // will rely on caller's current dir / PATH

  // Quote the app path and build a mutable command line
  if AParams <> '' then
    LCmd := '"' + LAppPath + '" ' + AParams
  else
    LCmd := '"' + LAppPath + '"';
  UniqueString(LCmd);

  // Ensure the exe exists when a workdir is provided
  if (AWorkDir <> '') and (not TFile.Exists(LAppPath)) then
    raise Exception.CreateFmt('RunPE: Executable not found: %s', [LAppPath]);

  ZeroMemory(@LSI, SizeOf(LSI));
  ZeroMemory(@LPI, SizeOf(LPI));
  LSI.cb := SizeOf(LSI);
  LSI.dwFlags := STARTF_USESHOWWINDOW;
  LSI.wShowWindow := AShowCmd;

  if AWorkDir <> '' then
    LWorkDirPW := PWideChar(AWorkDir)
  else
    LWorkDirPW := nil;

  LCreationFlags := CREATE_UNICODE_ENVIRONMENT;

  // Pass the resolved path in lpApplicationName so Windows won't search using the caller's current directory
  if not CreateProcessW(
    PWideChar(LAppPath),
    PWideChar(LCmd),
    nil,
    nil,
    False,
    LCreationFlags,
    nil,
    LWorkDirPW,
    LSI,
    LPI
  ) then
    raise Exception.CreateFmt('RunPE: CreateProcess failed (%d) %s', [GetLastError, SysErrorMessage(GetLastError)]);

  try
    if AWait then
    begin
      WaitForSingleObject(LPI.hProcess, INFINITE);
      LExit := 0;
      if GetExitCodeProcess(LPI.hProcess, LExit) then
        Result := LExit
      else
        raise Exception.CreateFmt('RunPE: GetExitCodeProcess failed (%d) %s', [GetLastError, SysErrorMessage(GetLastError)]);
    end
    else
      Result := 0;
  finally
    CloseHandle(LPI.hThread);
    CloseHandle(LPI.hProcess);
  end;
end;

class function TUtils.WindowsPathToWSL(const APath: string): string;
var
  LFullPath: string;
  LDrive: Char;
begin
  LFullPath := TPath.GetFullPath(APath);

  // Convert Windows path to WSL path: C:\foo\bar -> /mnt/c/foo/bar
  if (Length(LFullPath) >= 3) and (LFullPath[2] = ':') and (LFullPath[3] = '\') then
  begin
    LDrive := LowerCase(LFullPath[1])[1];
    Result := '/mnt/' + LDrive + '/' +
      StringReplace(Copy(LFullPath, 4, MaxInt), '\', '/', [rfReplaceAll]);
  end
  else
    raise Exception.CreateFmt('WindowsPathToWSL: Expected absolute Windows path: %s', [LFullPath]);
end;

class function TUtils.RunElf(const AElf, AWorkDir: string): Cardinal;
var
  LWslPath: string;
  LCmd: UnicodeString;
  LSI: STARTUPINFOW;
  LPI: PROCESS_INFORMATION;
  LExit: DWORD;
begin
  if AElf = '' then
    raise Exception.Create('RunElf: ELF path is empty');

  // Convert Windows path to WSL path
  LWslPath := WindowsPathToWSL(AElf);

  // Step 1: chmod +x via WSL (make the ELF executable)
  LCmd := 'wsl.exe chmod +x "' + LWslPath + '"';
  UniqueString(LCmd);

  ZeroMemory(@LSI, SizeOf(LSI));
  ZeroMemory(@LPI, SizeOf(LPI));
  LSI.cb := SizeOf(LSI);
  LSI.dwFlags := STARTF_USESHOWWINDOW;
  LSI.wShowWindow := SW_HIDE;

  if not CreateProcessW(
    nil,
    PWideChar(LCmd),
    nil,
    nil,
    False,
    CREATE_UNICODE_ENVIRONMENT,
    nil,
    PWideChar(AWorkDir),
    LSI,
    LPI
  ) then
    raise Exception.CreateFmt('RunElf: chmod CreateProcess failed (%d) %s',
      [GetLastError, SysErrorMessage(GetLastError)]);

  try
    WaitForSingleObject(LPI.hProcess, INFINITE);
  finally
    CloseHandle(LPI.hThread);
    CloseHandle(LPI.hProcess);
  end;

  // Step 2: Execute the ELF binary via WSL
  LCmd := 'wsl.exe "' + LWslPath + '"';
  UniqueString(LCmd);

  ZeroMemory(@LSI, SizeOf(LSI));
  ZeroMemory(@LPI, SizeOf(LPI));
  LSI.cb := SizeOf(LSI);
  LSI.dwFlags := STARTF_USESHOWWINDOW;
  LSI.wShowWindow := SW_HIDE;

  if not CreateProcessW(
    nil,
    PWideChar(LCmd),
    nil,
    nil,
    False,
    CREATE_UNICODE_ENVIRONMENT,
    nil,
    PWideChar(AWorkDir),
    LSI,
    LPI
  ) then
    raise Exception.CreateFmt('RunElf: execute CreateProcess failed (%d) %s',
      [GetLastError, SysErrorMessage(GetLastError)]);

  try
    WaitForSingleObject(LPI.hProcess, INFINITE);
    LExit := 0;
    if GetExitCodeProcess(LPI.hProcess, LExit) then
      Result := LExit
    else
      raise Exception.CreateFmt('RunElf: GetExitCodeProcess failed (%d) %s',
        [GetLastError, SysErrorMessage(GetLastError)]);
  finally
    CloseHandle(LPI.hThread);
    CloseHandle(LPI.hProcess);
  end;
end;

{ Opens a file with its registered default handler, the way a double-click
  would. Unlike RunPE (CreateProcessW), this resolves file associations, so it
  can open documents, folders and URLs -- not just executable images.

  There is no process handle and therefore no exit code: the handler runs
  detached. Callers that need an exit code must use RunPE instead. }
class function TUtils.ShellOpen(const AFilename: string; const AWorkDir: string;
  const AShowCmd: Word): Boolean;
var
  LResult: HINST;
  LWorkDir: PChar;
begin
  Result := False;

  if AFilename = '' then
    Exit;

  if AWorkDir = '' then
    LWorkDir := nil
  else
    LWorkDir := PChar(AWorkDir);

  LResult := ShellExecute(0, 'open', PChar(AFilename), nil, LWorkDir, AShowCmd);

  // ShellExecute returns a value greater than 32 on success. Anything at or
  // below 32 is an error code, not an instance handle.
  Result := LResult > 32;
end;

class procedure TUtils.CaptureConsoleOutput(const ATitle: string; const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback);
const
  CReadBuffer = 1024 * 2;
var
  LSASecurity: TSecurityAttributes;
  LHRead: THandle;
  LHWrite: THandle;
  LSUIStartup: TStartupInfo;
  LPIProcess: TProcessInformation;
  LPBuffer: array [0 .. CReadBuffer] of AnsiChar;
  LDBuffer: array [0 .. CReadBuffer] of AnsiChar;
  LDRead: DWORD;
  LDRunning: DWORD;
  LDAvailable: DWORD;
  LCmdLine: string;
  LExitCode: DWORD;
  LWorkDirPtr: PChar;
  LLineAccumulator: TStringBuilder;
  LI: Integer;
  LChar: AnsiChar;
  LCurrentLine: string;
begin
  LSASecurity.nLength := SizeOf(TSecurityAttributes);
  LSASecurity.bInheritHandle := True;
  LSASecurity.lpSecurityDescriptor := nil;

  if CreatePipe(LHRead, LHWrite, @LSASecurity, 0) then
    try
      FillChar(LSUIStartup, SizeOf(TStartupInfo), #0);
      LSUIStartup.cb := SizeOf(TStartupInfo);
      LSUIStartup.hStdInput := LHRead;
      LSUIStartup.hStdOutput := LHWrite;
      LSUIStartup.hStdError := LHWrite;
      LSUIStartup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
      LSUIStartup.wShowWindow := SW_HIDE;

      if ATitle.IsEmpty then
        LSUIStartup.lpTitle := nil
      else
        LSUIStartup.lpTitle := PChar(ATitle);

      LCmdLine := ACommand + ' ' + AParameters;

      if AWorkDir <> '' then
        LWorkDirPtr := PChar(AWorkDir)
      else
        LWorkDirPtr := nil;

      if CreateProcess(nil, PChar(LCmdLine), @LSASecurity, @LSASecurity, True, NORMAL_PRIORITY_CLASS, nil, LWorkDirPtr, LSUIStartup, LPIProcess) then
        try
          LLineAccumulator := TStringBuilder.Create();
          try
            repeat
              LDRunning := WaitForSingleObject(LPIProcess.hProcess, 100);
              PeekNamedPipe(LHRead, nil, 0, nil, @LDAvailable, nil);

              if (LDAvailable > 0) then
                repeat
                  LDRead := 0;
                  ReadFile(LHRead, LPBuffer[0], CReadBuffer, LDRead, nil);
                  LPBuffer[LDRead] := #0;
                  OemToCharA(LPBuffer, LDBuffer);

                  // Process character-by-character to find complete lines
                  LI := 0;
                  while LI < Integer(LDRead) do
                  begin
                    LChar := LDBuffer[LI];

                    if (LChar = #13) or (LChar = #10) then
                    begin
                      // Found line terminator - emit accumulated line if not empty
                      if LLineAccumulator.Length > 0 then
                      begin
                        LCurrentLine := LLineAccumulator.ToString();
                        LLineAccumulator.Clear();

                        if Assigned(ACallback) then
                          ACallback(LCurrentLine, AUserData);
                      end;

                      // Skip paired CR+LF
                      if (LChar = #13) and (LI + 1 < Integer(LDRead)) and (LDBuffer[LI + 1] = #10) then
                        Inc(LI);
                    end
                    else
                    begin
                      // Accumulate character
                      LLineAccumulator.Append(string(LChar));
                    end;

                    Inc(LI);
                  end;
                until (LDRead < CReadBuffer);

              ProcessMessages();
            until (LDRunning <> WAIT_TIMEOUT);

            // Emit any remaining partial line
            if LLineAccumulator.Length > 0 then
            begin
              LCurrentLine := LLineAccumulator.ToString();
              if Assigned(ACallback) then
                ACallback(LCurrentLine, AUserData);
            end;

            if GetExitCodeProcess(LPIProcess.hProcess, LExitCode) then
              AExitCode := LExitCode;

          finally
            FreeAndNil(LLineAccumulator);
          end;
        finally
          CloseHandle(LPIProcess.hProcess);
          CloseHandle(LPIProcess.hThread);
        end;
    finally
      CloseHandle(LHRead);
      CloseHandle(LHWrite);
    end;
end;

class procedure TUtils.CaptureConsolePTY(const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback);
const
  CReadBuffer = 4096;
var
  LInputReadSide: THandle;
  LInputWriteSide: THandle;
  LOutputReadSide: THandle;
  LOutputWriteSide: THandle;
  LConsoleSize: COORD;
  LConsoleHandle: THandle;
  LConsoleInfo: TConsoleScreenBufferInfo;
  LPseudoConsole: HPCON;
  LAttrListSize: SIZE_T;
  LAttrList: Pointer;
  LStartupInfoEx: STARTUPINFOEXW;
  LProcessInfo: TProcessInformation;
  LCmdLine: string;
  LWorkDirPtr: PChar;
  LExitCode: DWORD;
  LBuffer: array[0..CReadBuffer - 1] of AnsiChar;
  LBytesRead: DWORD;
  LBytesAvailable: DWORD;
  LRunning: DWORD;
begin
  AExitCode := 1;
  LPseudoConsole := 0;
  LAttrList := nil;
  LInputReadSide := 0;
  LInputWriteSide := 0;
  LOutputReadSide := 0;
  LOutputWriteSide := 0;

  // Create pipes for ConPTY
  if not CreatePipe(LInputReadSide, LInputWriteSide, nil, 0) then
    Exit;

  if not CreatePipe(LOutputReadSide, LOutputWriteSide, nil, 0) then
  begin
    CloseHandle(LInputReadSide);
    CloseHandle(LInputWriteSide);
    Exit;
  end;

  try
    // Match PTY size to actual visible window size
    LConsoleSize.X := 120;
    LConsoleSize.Y := 30;
    LConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    if (LConsoleHandle <> INVALID_HANDLE_VALUE) and GetConsoleScreenBufferInfo(LConsoleHandle, LConsoleInfo) then
    begin
      LConsoleSize.X := LConsoleInfo.srWindow.Right - LConsoleInfo.srWindow.Left + 1;
      LConsoleSize.Y := LConsoleInfo.srWindow.Bottom - LConsoleInfo.srWindow.Top + 1;
    end;

    if Failed(CreatePseudoConsole(LConsoleSize, LInputReadSide, LOutputWriteSide, 0, LPseudoConsole)) then
      Exit;

    try
      // Close the handles that were given to the pseudoconsole
      CloseHandle(LInputReadSide);
      LInputReadSide := 0;
      CloseHandle(LOutputWriteSide);
      LOutputWriteSide := 0;

      // Get attribute list size
      LAttrListSize := 0;
      InitializeProcThreadAttributeList(nil, 1, 0, LAttrListSize);

      // Allocate attribute list
      LAttrList := AllocMem(LAttrListSize);
      if not InitializeProcThreadAttributeList(LAttrList, 1, 0, LAttrListSize) then
        Exit;

      try
        // Set pseudoconsole attribute
        if not UpdateProcThreadAttribute(LAttrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            Pointer(LPseudoConsole), SizeOf(HPCON), nil, nil) then
          Exit;

        // Initialize extended startup info
        FillChar(LStartupInfoEx, SizeOf(LStartupInfoEx), 0);
        LStartupInfoEx.StartupInfo.cb := SizeOf(STARTUPINFOEXW);
        LStartupInfoEx.lpAttributeList := LAttrList;

        // Build command line
        LCmdLine := string(ACommand) + ' ' + string(AParameters);

        if AWorkDir <> '' then
          LWorkDirPtr := PChar(AWorkDir)
        else
          LWorkDirPtr := nil;

        // Create process - pass nil for environment to inherit from parent
        FillChar(LProcessInfo, SizeOf(LProcessInfo), 0);
        if not CreateProcessW(nil, PWideChar(LCmdLine), nil, nil, False,
            EXTENDED_STARTUPINFO_PRESENT,
            nil, LWorkDirPtr, LStartupInfoEx.StartupInfo, LProcessInfo) then
          Exit;

        try
          repeat
            LRunning := WaitForSingleObject(LProcessInfo.hProcess, 50);

            // Read available output
            while True do
            begin
              LBytesAvailable := 0;
              if not PeekNamedPipe(LOutputReadSide, nil, 0, nil, @LBytesAvailable, nil) then
                Break;

              if LBytesAvailable = 0 then
                Break;

              LBytesRead := 0;
              if not ReadFile(LOutputReadSide, LBuffer[0], CReadBuffer - 1, LBytesRead, nil) then
                Break;

              if LBytesRead = 0 then
                Break;

              LBuffer[LBytesRead] := #0;

              // Convert UTF-8 to Unicode and pass raw to callback
              if Assigned(ACallback) then
                ACallback(UTF8ToString(PAnsiChar(@LBuffer[0])), AUserData);
            end;

            ProcessMessages();
          until LRunning <> WAIT_TIMEOUT;

          // Small delay to allow final output to be buffered
          Sleep(100);

          // Drain any remaining output after process exits
          repeat
            LBytesAvailable := 0;
            if not PeekNamedPipe(LOutputReadSide, nil, 0, nil, @LBytesAvailable, nil) then
              Break;

            if LBytesAvailable = 0 then
            begin
              // Try one more time after a brief wait
              Sleep(50);
              if not PeekNamedPipe(LOutputReadSide, nil, 0, nil, @LBytesAvailable, nil) then
                Break;
              if LBytesAvailable = 0 then
                Break;
            end;

            LBytesRead := 0;
            if not ReadFile(LOutputReadSide, LBuffer[0], CReadBuffer - 1, LBytesRead, nil) then
              Break;

            if LBytesRead = 0 then
              Break;

            LBuffer[LBytesRead] := #0;

            if Assigned(ACallback) then
              ACallback(UTF8ToString(PAnsiChar(@LBuffer[0])), AUserData);
          until False;

          // Get exit code
          if GetExitCodeProcess(LProcessInfo.hProcess, LExitCode) then
            AExitCode := LExitCode;
        finally
          CloseHandle(LProcessInfo.hProcess);
          CloseHandle(LProcessInfo.hThread);
        end;
      finally
        DeleteProcThreadAttributeList(LAttrList);
      end;
    finally
      ClosePseudoConsole(LPseudoConsole);
    end;
  finally
    if LAttrList <> nil then
      FreeMem(LAttrList);
    if LInputReadSide <> 0 then
      CloseHandle(LInputReadSide);
    if LInputWriteSide <> 0 then
      CloseHandle(LInputWriteSide);
    if LOutputReadSide <> 0 then
      CloseHandle(LOutputReadSide);
    if LOutputWriteSide <> 0 then
      CloseHandle(LOutputWriteSide);
  end;
end;

class function TUtils.CreateProcessWithPipes(const AExe, AParams, AWorkDir: string; out AStdinWrite: THandle; out AStdoutRead: THandle; out AProcessHandle: THandle; out AThreadHandle: THandle): Boolean;
var
  LSA: TSecurityAttributes;
  LStdinReadChild: THandle;
  LStdoutWriteChild: THandle;
  LSI: TStartupInfoW;
  LPI: TProcessInformation;
  LCmdLine: UnicodeString;
  LWorkDirPW: PWideChar;
begin
  Result := False;
  AStdinWrite := INVALID_HANDLE_VALUE;
  AStdoutRead := INVALID_HANDLE_VALUE;
  AProcessHandle := INVALID_HANDLE_VALUE;
  AThreadHandle := INVALID_HANDLE_VALUE;
  LStdinReadChild := INVALID_HANDLE_VALUE;
  LStdoutWriteChild := INVALID_HANDLE_VALUE;

  // Set up security attributes for inheritable handles
  LSA.nLength := SizeOf(TSecurityAttributes);
  LSA.bInheritHandle := True;
  LSA.lpSecurityDescriptor := nil;

  // Create pipe for child's stdin (parent writes, child reads)
  if not CreatePipe(LStdinReadChild, AStdinWrite, @LSA, 0) then
    Exit;

  // Create pipe for child's stdout (child writes, parent reads)
  if not CreatePipe(AStdoutRead, LStdoutWriteChild, @LSA, 0) then
  begin
    CloseHandle(LStdinReadChild);
    CloseHandle(AStdinWrite);
    AStdinWrite := INVALID_HANDLE_VALUE;
    Exit;
  end;

  // Ensure parent-side handles are NOT inherited by the child
  SetHandleInformation(AStdinWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(AStdoutRead, HANDLE_FLAG_INHERIT, 0);

  // Set up startup info with redirected standard handles
  ZeroMemory(@LSI, SizeOf(LSI));
  LSI.cb := SizeOf(LSI);
  LSI.hStdInput := LStdinReadChild;
  LSI.hStdOutput := LStdoutWriteChild;
  LSI.hStdError := LStdoutWriteChild;
  LSI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  LSI.wShowWindow := SW_HIDE;

  // Build command line
  if AParams <> '' then
    LCmdLine := '"' + AExe + '" ' + AParams
  else
    LCmdLine := '"' + AExe + '"';
  UniqueString(LCmdLine);

  if AWorkDir <> '' then
    LWorkDirPW := PWideChar(AWorkDir)
  else
    LWorkDirPW := nil;

  ZeroMemory(@LPI, SizeOf(LPI));

  if not CreateProcessW(
    nil,
    PWideChar(LCmdLine),
    nil,
    nil,
    True,
    CREATE_UNICODE_ENVIRONMENT or CREATE_NO_WINDOW,
    nil,
    LWorkDirPW,
    LSI,
    LPI
  ) then
  begin
    CloseHandle(LStdinReadChild);
    CloseHandle(LStdoutWriteChild);
    CloseHandle(AStdinWrite);
    CloseHandle(AStdoutRead);
    AStdinWrite := INVALID_HANDLE_VALUE;
    AStdoutRead := INVALID_HANDLE_VALUE;
    Exit;
  end;

  // Close child-side pipe handles (child process has its own copies)
  CloseHandle(LStdinReadChild);
  CloseHandle(LStdoutWriteChild);

  AProcessHandle := LPI.hProcess;
  AThreadHandle := LPI.hThread;
  Result := True;
end;

class function TUtils.CreateDirInPath(const AFilename: string): Boolean;
var
  LPath: string;
  LResolved: string;
begin
  LResolved := TUtils.ResolvePath(AFilename);
  // If AFilename is a directory, use it directly; otherwise extract its directory part
  if TPath.HasExtension(LResolved) then
    LPath := TPath.GetDirectoryName(LResolved)
  else
    LPath := LResolved;

  if LPath.IsEmpty then
    Exit(False);

  if not TDirectory.Exists(LPath) then
    TDirectory.CreateDirectory(LPath);

  Result := True;
end;

class procedure TUtils.CopyFilePreservingEncoding(const ASourceFile, ADestFile: string);
var
  LSourceBytes: TBytes;
begin
  // Validate source file exists
  if not TFile.Exists(ASourceFile) then
    raise Exception.CreateFmt('CopyFilePreservingEncoding: Source file not found: %s', [ASourceFile]);

  // Ensure destination directory exists
  CreateDirInPath(ADestFile);

  // Read all bytes from source file
  LSourceBytes := TFile.ReadAllBytes(ASourceFile);

  // Write bytes to destination - this preserves EVERYTHING including BOM
  TFile.WriteAllBytes(ADestFile, LSourceBytes);
end;

class function TUtils.DetectFileEncoding(const AFilePath: string): TEncoding;
var
  LBytes: TBytes;
  LEncoding: TEncoding;
begin
  // Validate file exists
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('DetectFileEncoding: File not found: %s', [AFilePath]);

  // Read a sample of bytes (first 4KB should be enough for BOM detection)
  LBytes := TFile.ReadAllBytes(AFilePath);

  if Length(LBytes) = 0 then
    Exit(TEncoding.Default);

  // Let TEncoding detect the encoding from BOM
  LEncoding := nil;
  TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.Default);

  Result := LEncoding;
end;

class function TUtils.EnsureBOM(const AText: string): string;
const
  UTF16_BOM = #$FEFF;
begin
  Result := AText;
  if (Length(Result) = 0) or (Result[1] <> UTF16_BOM) then
    Result := UTF16_BOM + Result;
end;

class function TUtils.EscapeString(const AText: string): string;
var
  LI: Integer;
  LChar: Char;
  LNextChar: Char;
begin
  Result := '';
  LI := 1;

  while LI <= Length(AText) do
  begin
    LChar := AText[LI];

    case LChar of
      #13: // Carriage return
        begin
          Result := Result + '\r';
          Inc(LI);
        end;
      #10: // Line feed
        begin
          Result := Result + '\n';
          Inc(LI);
        end;
      #9: // Tab
        begin
          Result := Result + '\t';
          Inc(LI);
        end;
      '"': // Quote
        begin
          Result := Result + '\"';
          Inc(LI);
        end;
      '\': // Backslash - requires look-ahead
        begin
          if LI < Length(AText) then
          begin
            LNextChar := AText[LI + 1];

            // Preserve valid C++ escape sequences: \x (hex), \n, \r, \t, \", \\
            if CharInSet(LNextChar, ['x', 'n', 'r', 't', '"', '\']) then
              Result := Result + '\'  // Valid C++ escape sequence - preserve the backslash
            else
              Result := Result + '\\'; // Not a recognized escape - escape the backslash
          end
          else
            Result := Result + '\\'; // Backslash at end of string - escape it

          Inc(LI);
        end;
    else
      // Regular character - append as-is
      Result := Result + LChar;
      Inc(LI);
    end;
  end;
end;

class function TUtils.StripAnsi(const AText: string): string;
var
  LResult: TStringBuilder;
  LIdx: Integer;
  LLen: Integer;
  LInEscape: Boolean;
begin
  LResult := TStringBuilder.Create();
  try
    LLen := Length(AText);
    LIdx := 1;
    LInEscape := False;
    while LIdx <= LLen do
    begin
      if LInEscape then
      begin
        if CharInSet(AText[LIdx], ['A'..'Z', 'a'..'z', '~']) then
          LInEscape := False;
      end
      else if AText[LIdx] = #27 then
        LInEscape := True
      else
        LResult.Append(AText[LIdx]);
      Inc(LIdx);
    end;
    Result := LResult.ToString();
  finally
    LResult.Free();
  end;
end;

class function TUtils.ExtractAnsiCodes(const AText: string): string;
var
  LResult: TStringBuilder;
  LIdx: Integer;
  LLen: Integer;
  LInEscape: Boolean;
begin
  LResult := TStringBuilder.Create();
  try
    LLen := Length(AText);
    LIdx := 1;
    LInEscape := False;
    while LIdx <= LLen do
    begin
      if LInEscape then
      begin
        LResult.Append(AText[LIdx]);
        if CharInSet(AText[LIdx], ['A'..'Z', 'a'..'z', '~']) then
          LInEscape := False;
      end
      else if AText[LIdx] = #27 then
      begin
        LInEscape := True;
        LResult.Append(AText[LIdx]);
      end;
      Inc(LIdx);
    end;
    Result := LResult.ToString();
  finally
    LResult.Free();
  end;
end;

class function TUtils.GetVersionInfo(out AVersionInfo: TVersionInfo; const AFilePath: string): Boolean;
var
  LFileName: string;
  LInfoSize: DWORD;
  LHandle: DWORD;
  LBuffer: Pointer;
  LFileInfo: PVSFixedFileInfo;
  LLen: UINT;
  LStrValue: PChar;
  LStrLen: UINT;
  LTranslation: Pointer;
  LTransLen: UINT;
  LCodePage: string;

  function ReadStringValue(const AKey: string): string;
  begin
    Result := '';
    if VerQueryValue(LBuffer,
       PChar('\StringFileInfo\' + LCodePage + '\' + AKey),
       Pointer(LStrValue), LStrLen) and (LStrLen > 0) then
      Result := LStrValue;
  end;

begin
  // Initialize output
  AVersionInfo.Major := 0;
  AVersionInfo.Minor := 0;
  AVersionInfo.Patch := 0;
  AVersionInfo.Build := 0;
  AVersionInfo.VersionString := '';
  AVersionInfo.ProductName := '';
  AVersionInfo.CompanyName := '';
  AVersionInfo.Copyright := '';
  AVersionInfo.Description := '';
  AVersionInfo.URL := '';

  // Determine which file to query
  if AFilePath = '' then
    LFileName := ParamStr(0)
  else
    LFileName := AFilePath;

  // Get version info size
  LInfoSize := GetFileVersionInfoSize(PChar(LFileName), LHandle);
  if LInfoSize = 0 then
    Exit(False);

  // Allocate buffer and get version info
  GetMem(LBuffer, LInfoSize);
  try
    if not GetFileVersionInfo(PChar(LFileName), LHandle, LInfoSize, LBuffer) then
      Exit(False);

    // Query fixed file info
    if not VerQueryValue(LBuffer, '\', Pointer(LFileInfo), LLen) then
      Exit(False);

    // Extract version components
    AVersionInfo.Major := HiWord(LFileInfo.dwFileVersionMS);
    AVersionInfo.Minor := LoWord(LFileInfo.dwFileVersionMS);
    AVersionInfo.Patch := HiWord(LFileInfo.dwFileVersionLS);
    AVersionInfo.Build := LoWord(LFileInfo.dwFileVersionLS);

    // Detect language/codepage from translation table
    LCodePage := '040904B0'; // fallback
    if VerQueryValue(LBuffer, '\VarFileInfo\Translation', LTranslation, LTransLen) and
       (LTransLen >= 4) then
      LCodePage := Format('%.4x%.4x', [PWordArray(LTranslation)[0], PWordArray(LTranslation)[1]]);

    // Format version string (Major.Minor.Patch)
    AVersionInfo.VersionString := Format('%d.%d.%d', [AVersionInfo.Major, AVersionInfo.Minor, AVersionInfo.Patch]);

    // Read string table entries
    AVersionInfo.ProductName := ReadStringValue('ProductName');
    AVersionInfo.CompanyName := ReadStringValue('CompanyName');
    AVersionInfo.Copyright := ReadStringValue('LegalCopyright');
    AVersionInfo.Description := ReadStringValue('FileDescription');
    AVersionInfo.URL := ReadStringValue('Comments');

    Result := True;
  finally
    FreeMem(LBuffer);
  end;
end;

class function TUtils.GetModuleVersionString(const AModule: HMODULE): string;
var
  LPath: array[0..MAX_PATH] of Char;
  LInfo: TVersionInfo;
begin
  if (GetModuleFileName(AModule, LPath, MAX_PATH + 1) > 0) and
     GetVersionInfo(LInfo, LPath) then
    Result := LInfo.VersionString
  else
    Result := '0.0.0';
end;

class function TUtils.IsValidWin64PE(const AFilePath: string): Boolean;
var
  LFile: TFileStream;
  LDosHeader: TImageDosHeader;
  LPEHeaderOffset: DWORD;
  LPEHeaderSignature: DWORD;
  LFileHeader: TImageFileHeader;
begin
  Result := False;

  if not FileExists(AFilePath) then
    Exit;

  LFile := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    // Check if file is large enough for DOS header
    if LFile.Size < SizeOf(TImageDosHeader) then
      Exit;

    // Read DOS header
    LFile.ReadBuffer(LDosHeader, SizeOf(TImageDosHeader));

    // Check DOS signature
    if LDosHeader.e_magic <> IMAGE_DOS_SIGNATURE then
      Exit;

    // Validate PE header offset
    LPEHeaderOffset := LDosHeader._lfanew;
    if LFile.Size < LPEHeaderOffset + SizeOf(DWORD) + SizeOf(TImageFileHeader) then
      Exit;

    // Seek to the PE header
    LFile.Position := LPEHeaderOffset;

    // Read and validate the PE signature
    LFile.ReadBuffer(LPEHeaderSignature, SizeOf(DWORD));
    if LPEHeaderSignature <> IMAGE_NT_SIGNATURE then
      Exit;

    // Read the file header
    LFile.ReadBuffer(LFileHeader, SizeOf(TImageFileHeader));

    // Check if it is a 64-bit executable
    if LFileHeader.Machine <> IMAGE_FILE_MACHINE_AMD64 then
      Exit;

    // All checks passed
    Result := True;
  finally
    LFile.Free();
  end;
end;

class procedure TUtils.UpdateIconResource(const AExeFilePath, AIconFilePath: string);
type
  TIconDir = packed record
    idReserved: Word;
    idType: Word;
    idCount: Word;
  end;
  PIconDir = ^TIconDir;

  TGroupIconDirEntry = packed record
    bWidth: Byte;
    bHeight: Byte;
    bColorCount: Byte;
    bReserved: Byte;
    wPlanes: Word;
    wBitCount: Word;
    dwBytesInRes: Cardinal;
    nID: Word;
  end;

  TIconResInfo = packed record
    bWidth: Byte;
    bHeight: Byte;
    bColorCount: Byte;
    bReserved: Byte;
    wPlanes: Word;
    wBitCount: Word;
    dwBytesInRes: Cardinal;
    dwImageOffset: Cardinal;
  end;
  PIconResInfo = ^TIconResInfo;

var
  LUpdateHandle: THandle;
  LIconStream: TMemoryStream;
  LIconDir: PIconDir;
  LIconGroup: TMemoryStream;
  LIconRes: PByte;
  LIconID: Word;
  LI: Integer;
  LGroupEntry: TGroupIconDirEntry;
begin
  if not FileExists(AExeFilePath) then
    raise Exception.Create('The specified executable file does not exist.');

  if not FileExists(AIconFilePath) then
    raise Exception.Create('The specified icon file does not exist.');

  LIconStream := TMemoryStream.Create();
  LIconGroup := TMemoryStream.Create();
  try
    // Load the icon file
    LIconStream.LoadFromFile(AIconFilePath);

    // Read the ICONDIR structure from the icon file
    LIconDir := PIconDir(LIconStream.Memory);
    if LIconDir^.idReserved <> 0 then
      raise Exception.Create('Invalid icon file format.');

    // Begin updating the executable's resources
    LUpdateHandle := BeginUpdateResource(PChar(AExeFilePath), False);
    if LUpdateHandle = 0 then
      raise Exception.Create('Failed to begin resource update.');

    try
      // Process each icon image in the .ico file
      LIconRes := PByte(LIconStream.Memory) + SizeOf(TIconDir);
      for LI := 0 to LIconDir^.idCount - 1 do
      begin
        // Assign a unique resource ID for the RT_ICON
        LIconID := LI + 1;

        // Add the icon image data as an RT_ICON resource
        if not UpdateResource(LUpdateHandle, RT_ICON, PChar(LIconID), LANG_NEUTRAL,
          Pointer(PByte(LIconStream.Memory) + PIconResInfo(LIconRes)^.dwImageOffset),
          PIconResInfo(LIconRes)^.dwBytesInRes) then
          raise Exception.CreateFmt('Failed to add RT_ICON resource for image %d.', [LI]);

        // Move to the next icon entry
        Inc(LIconRes, SizeOf(TIconResInfo));
      end;

      // Create the GROUP_ICON resource
      LIconGroup.Clear();
      LIconGroup.Write(LIconDir^, SizeOf(TIconDir));

      LIconRes := PByte(LIconStream.Memory) + SizeOf(TIconDir);
      // Write each GROUP_ICON entry
      for LI := 0 to LIconDir^.idCount - 1 do
      begin
        LGroupEntry.bWidth := PIconResInfo(LIconRes)^.bWidth;
        LGroupEntry.bHeight := PIconResInfo(LIconRes)^.bHeight;
        LGroupEntry.bColorCount := PIconResInfo(LIconRes)^.bColorCount;
        LGroupEntry.bReserved := 0;
        LGroupEntry.wPlanes := PIconResInfo(LIconRes)^.wPlanes;
        LGroupEntry.wBitCount := PIconResInfo(LIconRes)^.wBitCount;
        LGroupEntry.dwBytesInRes := PIconResInfo(LIconRes)^.dwBytesInRes;
        LGroupEntry.nID := LI + 1;

        LIconGroup.Write(LGroupEntry, SizeOf(TGroupIconDirEntry));

        Inc(LIconRes, SizeOf(TIconResInfo));
      end;

      // Add the GROUP_ICON resource to the executable
      if not UpdateResource(LUpdateHandle, RT_GROUP_ICON, 'MAINICON', LANG_NEUTRAL,
        LIconGroup.Memory, LIconGroup.Size) then
        raise Exception.Create('Failed to add RT_GROUP_ICON resource.');

      // Commit the resource updates
      if not EndUpdateResource(LUpdateHandle, False) then
        raise Exception.Create('Failed to commit resource updates.');
    except
      EndUpdateResource(LUpdateHandle, True); // Discard changes on failure
      raise;
    end;
  finally
    LIconStream.Free();
    LIconGroup.Free();
  end;
end;

class procedure TUtils.UpdateVersionInfoResource(const PEFilePath: string; const AMajor, AMinor, APatch: Word; const AProductName, ADescription, AFilename, ACompanyName, ACopyright: string; const AURL: string);
type
  TVSFixedFileInfo = packed record
    dwSignature: DWORD;
    dwStrucVersion: DWORD;
    dwFileVersionMS: DWORD;
    dwFileVersionLS: DWORD;
    dwProductVersionMS: DWORD;
    dwProductVersionLS: DWORD;
    dwFileFlagsMask: DWORD;
    dwFileFlags: DWORD;
    dwFileOS: DWORD;
    dwFileType: DWORD;
    dwFileSubtype: DWORD;
    dwFileDateMS: DWORD;
    dwFileDateLS: DWORD;
  end;

  TCbrStringPair = record
    Key: string;
    Value: string;
  end;

var
  LHandleUpdate: THandle;
  LVersionInfoStream: TMemoryStream;
  LFixedInfo: TVSFixedFileInfo;
  LDataPtr: Pointer;
  LDataSize: Integer;
  LStringFileInfoStart: Int64;
  LStringTableStart: Int64;
  LVarFileInfoStart: Int64;
  LStringPairs: array of TCbrStringPair;
  LVersion: string;
  LMajor: Word;
  LMinor: Word;
  LPatch: Word;
  LVSVersionInfoStart: Int64;
  LPair: TCbrStringPair;
  LStringInfoEnd: Int64;
  LStringStart: Int64;
  LStringEnd: Int64;
  LFinalPos: Int64;
  LTranslationStart: Int64;

  procedure AlignStream(const AStream: TMemoryStream; const AAlignment: Integer);
  var
    LPadding: Integer;
    LPadByte: Byte;
  begin
    LPadding := (AAlignment - (AStream.Position mod AAlignment)) mod AAlignment;
    LPadByte := 0;
    while LPadding > 0 do
    begin
      AStream.WriteBuffer(LPadByte, 1);
      Dec(LPadding);
    end;
  end;

  procedure WriteWideString(const AStream: TMemoryStream; const AText: string);
  var
    LWideText: WideString;
  begin
    LWideText := WideString(AText);
    AStream.WriteBuffer(PWideChar(LWideText)^, (Length(LWideText) + 1) * SizeOf(WideChar));
  end;

  procedure SetFileVersionFromString(const AVersion: string; out AFileVersionMS, AFileVersionLS: DWORD);
  var
    LVersionParts: TArray<string>;
    LVerMajor: Word;
    LVerMinor: Word;
    LVerBuild: Word;
    LVerRevision: Word;
  begin
    LVersionParts := AVersion.Split(['.']);
    if Length(LVersionParts) <> 4 then
      raise Exception.Create('Invalid version string format. Expected "Major.Minor.Build.Revision".');

    LVerMajor    := StrToIntDef(LVersionParts[0], 0);
    LVerMinor    := StrToIntDef(LVersionParts[1], 0);
    LVerBuild    := StrToIntDef(LVersionParts[2], 0);
    LVerRevision := StrToIntDef(LVersionParts[3], 0);

    AFileVersionMS := (DWORD(LVerMajor) shl 16) or DWORD(LVerMinor);
    AFileVersionLS := (DWORD(LVerBuild) shl 16) or DWORD(LVerRevision);
  end;

begin
  LMajor := EnsureRange(AMajor, 0, MaxWord);
  LMinor := EnsureRange(AMinor, 0, MaxWord);
  LPatch := EnsureRange(APatch, 0, MaxWord);
  LVersion := Format('%d.%d.%d.0', [LMajor, LMinor, LPatch]);

  SetLength(LStringPairs, 9);
  LStringPairs[0].Key := 'Comments';         LStringPairs[0].Value := AURL;
  LStringPairs[1].Key := 'CompanyName';      LStringPairs[1].Value := ACompanyName;
  LStringPairs[2].Key := 'FileDescription';  LStringPairs[2].Value := ADescription;
  LStringPairs[3].Key := 'FileVersion';      LStringPairs[3].Value := LVersion;
  LStringPairs[4].Key := 'InternalName';     LStringPairs[4].Value := ADescription;
  LStringPairs[5].Key := 'LegalCopyright';   LStringPairs[5].Value := ACopyright;
  LStringPairs[6].Key := 'OriginalFilename'; LStringPairs[6].Value := AFilename;
  LStringPairs[7].Key := 'ProductName';      LStringPairs[7].Value := AProductName;
  LStringPairs[8].Key := 'ProductVersion';   LStringPairs[8].Value := LVersion;

  // Initialize fixed info structure
  FillChar(LFixedInfo, SizeOf(LFixedInfo), 0);
  LFixedInfo.dwSignature       := $FEEF04BD;
  LFixedInfo.dwStrucVersion    := $00010000;
  LFixedInfo.dwFileVersionMS   := $00010000;
  LFixedInfo.dwFileVersionLS   := $00000000;
  LFixedInfo.dwProductVersionMS:= $00010000;
  LFixedInfo.dwProductVersionLS:= $00000000;
  LFixedInfo.dwFileFlagsMask   := $3F;
  LFixedInfo.dwFileFlags       := 0;
  LFixedInfo.dwFileOS          := VOS_NT_WINDOWS32;
  LFixedInfo.dwFileType        := VFT_APP;
  LFixedInfo.dwFileSubtype     := 0;
  LFixedInfo.dwFileDateMS      := 0;
  LFixedInfo.dwFileDateLS      := 0;

  SetFileVersionFromString(LVersion, LFixedInfo.dwFileVersionMS,    LFixedInfo.dwFileVersionLS);
  SetFileVersionFromString(LVersion, LFixedInfo.dwProductVersionMS, LFixedInfo.dwProductVersionLS);

  LVersionInfoStream := TMemoryStream.Create();
  try
    // VS_VERSION_INFO
    LVSVersionInfoStart := LVersionInfoStream.Position;

    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(SizeOf(TVSFixedFileInfo));
    LVersionInfoStream.WriteData<Word>(0);
    WriteWideString(LVersionInfoStream, 'VS_VERSION_INFO');
    AlignStream(LVersionInfoStream, 4);

    // VS_FIXEDFILEINFO
    LVersionInfoStream.WriteBuffer(LFixedInfo, SizeOf(TVSFixedFileInfo));
    AlignStream(LVersionInfoStream, 4);

    // StringFileInfo
    LStringFileInfoStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, 'StringFileInfo');
    AlignStream(LVersionInfoStream, 4);

    // StringTable
    LStringTableStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, '040904B0'); // Match Delphi's default code page
    AlignStream(LVersionInfoStream, 4);

    // Write string pairs
    for LPair in LStringPairs do
    begin
      LStringStart := LVersionInfoStream.Position;

      LVersionInfoStream.WriteData<Word>(0);
      LVersionInfoStream.WriteData<Word>((Length(LPair.Value) + 1) * 2);
      LVersionInfoStream.WriteData<Word>(1);
      WriteWideString(LVersionInfoStream, LPair.Key);
      AlignStream(LVersionInfoStream, 4);
      WriteWideString(LVersionInfoStream, LPair.Value);
      AlignStream(LVersionInfoStream, 4);

      LStringEnd := LVersionInfoStream.Position;
      LVersionInfoStream.Position := LStringStart;
      LVersionInfoStream.WriteData<Word>(LStringEnd - LStringStart);
      LVersionInfoStream.Position := LStringEnd;
    end;

    LStringInfoEnd := LVersionInfoStream.Position;

    // Write StringTable length
    LVersionInfoStream.Position := LStringTableStart;
    LVersionInfoStream.WriteData<Word>(LStringInfoEnd - LStringTableStart);

    // Write StringFileInfo length
    LVersionInfoStream.Position := LStringFileInfoStart;
    LVersionInfoStream.WriteData<Word>(LStringInfoEnd - LStringFileInfoStart);

    // Start VarFileInfo where StringFileInfo ended
    LVarFileInfoStart := LStringInfoEnd;
    LVersionInfoStream.Position := LVarFileInfoStart;

    // VarFileInfo header
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, 'VarFileInfo');
    AlignStream(LVersionInfoStream, 4);

    // Translation value block
    LTranslationStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(4);
    LVersionInfoStream.WriteData<Word>(0);
    WriteWideString(LVersionInfoStream, 'Translation');
    AlignStream(LVersionInfoStream, 4);

    // Write translation value
    LVersionInfoStream.WriteData<Word>($0409); // Language ID (US English)
    LVersionInfoStream.WriteData<Word>($04B0); // Unicode code page

    LFinalPos := LVersionInfoStream.Position;

    // Update VarFileInfo block length
    LVersionInfoStream.Position := LVarFileInfoStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos - LVarFileInfoStart);

    // Update translation block length
    LVersionInfoStream.Position := LTranslationStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos - LTranslationStart);

    // Update total version info length
    LVersionInfoStream.Position := LVSVersionInfoStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos);

    LDataPtr := LVersionInfoStream.Memory;
    LDataSize := LVersionInfoStream.Size;

    // Update the resource
    LHandleUpdate := BeginUpdateResource(PChar(PEFilePath), False);
    if LHandleUpdate = 0 then
      RaiseLastOSError();

    try
      if not UpdateResourceW(LHandleUpdate, RT_VERSION, MAKEINTRESOURCE(1),
         MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), LDataPtr, LDataSize) then
        RaiseLastOSError();

      if not EndUpdateResource(LHandleUpdate, False) then
        RaiseLastOSError();
    except
      EndUpdateResource(LHandleUpdate, True);
      raise;
    end;
  finally
    LVersionInfoStream.Free();
  end;
end;

class function TUtils.ResourceExist(const AResName: string): Boolean;
begin
  Result := Boolean((FindResource(HInstance, PChar(AResName), RT_RCDATA) <> 0));
end;

class function TUtils.AddResManifestFromResource(const AResName: string; const AModuleFile: string; ALanguage: Integer): Boolean;
var
  LHandle: THandle;
  LManifestStream: TResourceStream;
begin
  Result := False;

  if not ResourceExist(AResName) then Exit;
  if not TFile.Exists(AModuleFile) then Exit;

  LManifestStream := TResourceStream.Create(HInstance, AResName, RT_RCDATA);
  try
    LHandle := WinAPI.Windows.BeginUpdateResourceW(System.PWideChar(AModuleFile), LongBool(False));

    if LHandle <> 0 then
    begin
      Result := WinAPI.Windows.UpdateResourceW(LHandle, RT_MANIFEST, CREATEPROCESS_MANIFEST_RESOURCE_ID, ALanguage, LManifestStream.Memory, LManifestStream.Size);
      WinAPI.Windows.EndUpdateResourceW(LHandle, False);
    end;
  finally
    FreeAndNil(LManifestStream);
  end;
end;

class procedure TUtils.UpdateRCDataResource(const AExeFilePath: string;
  const AResourceName: string; const AData: TStream);
var
  LHandleUpdate: THandle;
  LBuffer: TMemoryStream;
begin
  // Copy stream data to a memory buffer for UpdateResource
  LBuffer := TMemoryStream.Create();
  try
    AData.Position := 0;
    LBuffer.CopyFrom(AData, AData.Size);

    LHandleUpdate := BeginUpdateResource(PChar(AExeFilePath), False);
    if LHandleUpdate = 0 then
      RaiseLastOSError();

    try
      if not UpdateResourceW(LHandleUpdate, RT_RCDATA,
         PChar(AResourceName), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL),
         LBuffer.Memory, LBuffer.Size) then
        RaiseLastOSError();

      if not EndUpdateResource(LHandleUpdate, False) then
        RaiseLastOSError();
    except
      EndUpdateResource(LHandleUpdate, True);
      raise;
    end;
  finally
    LBuffer.Free();
  end;
end;

class function TUtils.GetFileSHA256(const APath: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(APath).ToLower();
end;

class function TUtils.GetRelativePath(const ABasePath, AFullPath: string): string;
var
  LBasePath: string;
  LFullPath: string;
  LBaseLen: Integer;
begin
  LBasePath := ABasePath.Replace('\', '/');
  LFullPath := AFullPath.Replace('\', '/');

  // Ensure base path ends with /
  if (LBasePath <> '') and not LBasePath.EndsWith('/') then
    LBasePath := LBasePath + '/';

  // If paths share a common prefix, strip it
  if LFullPath.ToLower().StartsWith(LBasePath.ToLower()) then
  begin
    LBaseLen := Length(LBasePath);
    Result := Copy(LFullPath, LBaseLen + 1, Length(LFullPath) - LBaseLen);
  end
  else
    Result := LFullPath; // Can't make relative, return with forward slashes
end;

class function TUtils.NormalizePath(const APath: string): string;
begin
  Result := APath.Replace(PathDelim, '/');
end;

class function TUtils.DisplayPath(const APath: string): string;
begin
  Result := TPath.GetFullPath(APath).Replace('\', '/');
end;

{ ResolvePath }
class function TUtils.ResolvePath(const APath: string;
  const ABaseDir: string): string;
var
  LPath: string;
  LBase: string;
begin
  LPath := APath.Trim();
  if LPath.IsEmpty() then
    Exit('');

  LBase := ABaseDir;

  // An explicit prefix overrides the caller-supplied contextual base.
  // Matched at position 1 only, so a path merely containing '$P:' further
  // along is left alone.
  if LPath.StartsWith(PATH_PREFIX_PROCESS, True) then
  begin
    LPath := LPath.Substring(Length(PATH_PREFIX_PROCESS));
    LBase := TPath.GetDirectoryName(ParamStr(0));
  end
  else if LPath.StartsWith(PATH_PREFIX_CURRENT, True) then
  begin
    LPath := LPath.Substring(Length(PATH_PREFIX_CURRENT));
    LBase := TDirectory.GetCurrentDirectory();
  end
  else if LPath.StartsWith(PATH_PREFIX_SOURCE, True) then
  begin
    // Explicit spelling of the default: keep the caller-supplied base.
    LPath := LPath.Substring(Length(PATH_PREFIX_SOURCE));
  end;

  LPath := LPath.Trim();
  if LPath.IsEmpty() then
    Exit('');

  // Already absolute after the prefix strip. This is what makes the
  // routine idempotent and safe to call on an already-resolved path.
  if TPath.IsPathRooted(LPath) then
    Exit(NormalizePath(TPath.GetFullPath(LPath)));

  if LBase.IsEmpty() then
    LBase := TDirectory.GetCurrentDirectory();

  Result := NormalizePath(TPath.GetFullPath(TPath.Combine(LBase, LPath)));
end;

class function TUtils.GetEnv(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
end;

class procedure TUtils.SetEnv(const AName: string; const AValue: string);
begin
  SetEnvironmentVariable(PChar(AName), PChar(AValue));
end;

class function TUtils.HasEnv(const AName: string): Boolean;
begin
  Result := not GetEnv(AName).IsEmpty();
end;

class function TUtils.RunFromIDE(): Boolean;
begin
  Result := HasEnv('BDS');
end;

class function TUtils.CountLines(
  const APath, APattern: string;
  const ARecursive: Boolean): Int64;
var
  LFiles: TArray<string>;
  LLines: TArray<string>;
  LSearchOpt: TSearchOption;
  LI: Integer;
begin
  Result := 0;
  if not TDirectory.Exists(APath) then
    Exit;
  if ARecursive then
    LSearchOpt := TSearchOption.soAllDirectories
  else
    LSearchOpt := TSearchOption.soTopDirectoryOnly;
  LFiles := TDirectory.GetFiles(APath, APattern, LSearchOpt);
  for LI := 0 to High(LFiles) do
  begin
    LLines := TFile.ReadAllLines(LFiles[LI]);
    Result := Result + Length(LLines);
  end;
end;

class function TUtils.GetAppType(): TAppType;
var
  LBase: PByte;
  LDosHeader: PImageDosHeader;
  LNtHeaders: PImageNtHeaders;
begin
  Result := atUnknown;
  try
    LBase := PByte(GetModuleHandle(nil));
    if LBase = nil then
      Exit;
    LDosHeader := PImageDosHeader(LBase);
    LNtHeaders := PImageNtHeaders(LBase + LDosHeader._lfanew);
    if LNtHeaders.OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_CUI then
      Result := atConsole
    else if LNtHeaders.OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_GUI then
      Result := atGUI;
  except
    // PE header read failed — return matUnknown
  end;
end;


{ TCbrCommandBuilder }

constructor TCommandBuilder.Create();
begin
  inherited;

  FParams := TStringList.Create();
  FParams.Delimiter := ' ';
  FParams.StrictDelimiter := True;
end;

destructor TCommandBuilder.Destroy();
begin
  FreeAndNil(FParams);

  inherited;
end;

procedure TCommandBuilder.Clear();
begin
  FParams.Clear();
end;

procedure TCommandBuilder.AddParam(const AParam: string);
begin
  if AParam <> '' then
    FParams.Add(AParam);
end;

procedure TCommandBuilder.AddParam(const AFlag, AValue: string);
begin
  if AFlag <> '' then
  begin
    if AValue <> '' then
      FParams.Add(AFlag + AValue)
    else
      FParams.Add(AFlag);
  end
  else if AValue <> '' then
    FParams.Add(AValue);
end;

procedure TCommandBuilder.AddQuotedParam(const AFlag, AValue: string);
begin
  if AValue = '' then
    Exit;

  if AFlag <> '' then
    FParams.Add(AFlag + ' "' + AValue + '"')
  else
    FParams.Add('"' + AValue + '"');
end;

procedure TCommandBuilder.AddQuotedParam(const AValue: string);
begin
  AddQuotedParam('', AValue);
end;

procedure TCommandBuilder.AddFlag(const AFlag: string);
begin
  if AFlag <> '' then
    FParams.Add(AFlag);
end;

function TCommandBuilder.Dump(const AId: Integer): string;
var
  LI: Integer;
begin
  if FParams.Count = 0 then
  begin
    Result := '';
    Exit;
  end;

  // Manually join with spaces to avoid TStringList.DelimitedText auto-quoting
  Result := FParams[0];
  for LI := 1 to FParams.Count - 1 do
    Result := Result + ' ' + FParams[LI];
end;

function TCommandBuilder.GetParamCount(): Integer;
begin
  Result := FParams.Count;
end;

// ===========================================================================

procedure Startup();
begin
  ReportMemoryLeaksOnShutdown := True;
  TUtils.InitConsole();
end;

procedure Shutdown();
begin
end;

initialization
begin
  Startup();
end;

finalization
begin
  Shutdown();
end;

end.
