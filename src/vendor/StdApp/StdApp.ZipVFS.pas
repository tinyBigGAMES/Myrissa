{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.ZipVFS - Virtual file system for embedded ZIP resources

  Intercepts file I/O calls from a loaded DLL (e.g., libtcc.dll) and
  redirects them to serve content from an embedded ZIP archive. Uses
  IAT hooking (StdApp.IATHook) to transparently replace CreateFileW,
  ReadFile, CloseHandle, and other Win32 file APIs so the DLL reads
  from the ZIP without any source modifications.

  Key types:
  - TZipVFS: Static class -- Initialize (hooks the DLL's IAT),
    Finalize (unhooks and cleans up)
  - TZipManager: ZIP archive manager -- LoadFromResource/File,
    OpenFile/CloseFile/ReadFile/SeekFile/GetFileSize with virtual
    handle allocation

  Usage:
    1. Embed ZIP as resource (RT_RCDATA)
    2. Load target DLL via StdApp.DllLoader
    3. Call TZipVFS.Initialize(DllBase, 'RESOURCE_NAME')
    4. DLL file operations transparently serve from ZIP
    5. Call TZipVFS.Finalize() on shutdown

  Dependencies: StdApp.IATHook
===============================================================================}
unit StdApp.ZipVFS;

{$I StdApp.Defines.inc}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Zip,
  System.Generics.Collections,
  StdApp.IATHook;

const
  { Base for virtual handles - high value to avoid collision with real handles }
  VHANDLE_BASE = $10000000;
  INVALID_VHANDLE = -1;

type

  { TZipManager }
  TZipManager = class
  private
    FZipFile: TZipFile;
    FHandleCounter: Integer;
    FResourceStream: TResourceStream;
    FZipStreams: TDictionary<THandle, TMemoryStream>;
    FBasePath: string;
  public
    constructor Create();
    destructor Destroy(); override;

    function LoadFromResource(const AResName: string; const AResType: PChar = RT_RCDATA): Boolean;
    function LoadFromFile(const AFilename: string): Boolean;

    function ContainsFile(const APath: string): Boolean;
    function OpenFile(const APath: string): THandle;
    procedure CloseFile(const AHandle: THandle);
    function ReadFile(const AHandle: THandle; const ABuffer: Pointer; const ACount: Cardinal): Integer;
    function SeekFile(const AHandle: THandle; const AOffset: Int64; const AOrigin: Integer): Int64;
    function GetFileSize(const AHandle: THandle): Int64;

    function IsVirtualHandle(const AHandle: THandle): Boolean;

    property BasePath: string read FBasePath write FBasePath;
    property ZipFile: TZipFile read FZipFile;
  end;

  { TZipVFS }
  TZipVFS = class
  private class var
    FZipManager: TZipManager;
    FDllBase: Pointer;
    FInitialized: Boolean;
    FBasePath: string;

    { Original function pointers }
    FOriginalCreateFileW: Pointer;
    FOriginalReadFile: Pointer;
    FOriginalCloseHandle: Pointer;
    FOriginalSetFilePointerEx: Pointer;
    FOriginalGetFileSizeEx: Pointer;
    FOriginalGetFileType: Pointer;
    FOriginalGetFileAttributesExW: Pointer;

    class function NormalizePath(const APath: string): string; static;
    class function StripBasePath(const APath: string): string; static;
  public
    class function Initialize(const ADllBase: Pointer;
      const AResourceName: string;
      const ABasePath: string = ''): Boolean; overload; static;
    class function Initialize(const ADllBase: Pointer;
      const AZipFilename: string;
      const ABasePath: string;
      const AFromFile: Boolean): Boolean; overload; static;

    class procedure Finalize(); static;

    class property ZipManager: TZipManager read FZipManager;
    class property Initialized: Boolean read FInitialized;
    class property BasePath: string read FBasePath;

    { Original function accessors for hook implementations }
    { Extract a file from the ZIP archive to disk }
    class function ExtractFile(const AZipPath: string; const ADestPath: string;
      const AOverwrite: Boolean = True): Boolean; static;

    { Extract a file from the ZIP archive to a byte array }
    class function ExtractFileToBytes(const AZipPath: string;
      out ABytes: TBytes): Boolean; static;

    { Check if a file exists in the ZIP archive }
    class function FileExists(const AZipPath: string): Boolean; static;

    { List all files in the ZIP archive }
    class function ListFiles(): TArray<string>; static;

    class property OriginalCreateFileW: Pointer read FOriginalCreateFileW;
    class property OriginalReadFile: Pointer read FOriginalReadFile;
    class property OriginalCloseHandle: Pointer read FOriginalCloseHandle;
    class property OriginalSetFilePointerEx: Pointer read FOriginalSetFilePointerEx;
    class property OriginalGetFileSizeEx: Pointer read FOriginalGetFileSizeEx;
    class property OriginalGetFileType: Pointer read FOriginalGetFileType;
    class property OriginalGetFileAttributesExW: Pointer read FOriginalGetFileAttributesExW;
  end;

{ Hook function types matching Windows API signatures }
type
  TCreateFileW = function(lpFileName: LPCWSTR;
    dwDesiredAccess: DWORD;
    dwShareMode: DWORD;
    lpSecurityAttributes: PSecurityAttributes;
    dwCreationDisposition: DWORD;
    dwFlagsAndAttributes: DWORD;
    hTemplateFile: THandle): THandle; stdcall;

  TReadFile = function(hFile: THandle;
    lpBuffer: Pointer;
    nNumberOfBytesToRead: DWORD;
    lpNumberOfBytesRead: PDWORD;
    lpOverlapped: POverlapped): BOOL; stdcall;

  TCloseHandle = function(hObject: THandle): BOOL; stdcall;

  TSetFilePointerEx = function(hFile: THandle;
    liDistanceToMove: LARGE_INTEGER;
    lpNewFilePointer: PLargeInteger;
    dwMoveMethod: DWORD): BOOL; stdcall;

  TGetFileSizeEx = function(hFile: THandle;
    lpFileSize: PLargeInteger): BOOL; stdcall;

  TGetFileType = function(hFile: THandle): DWORD; stdcall;

  TGetFileAttributesExW = function(lpFileName: LPCWSTR;
    fInfoLevelId: DWORD;
    lpFileInformation: Pointer): BOOL; stdcall;


implementation

{ Hook implementations - these are the actual hook functions }

function Hook_CreateFileW(lpFileName: LPCWSTR;
  dwDesiredAccess: DWORD;
  dwShareMode: DWORD;
  lpSecurityAttributes: PSecurityAttributes;
  dwCreationDisposition: DWORD;
  dwFlagsAndAttributes: DWORD;
  hTemplateFile: THandle): THandle; stdcall;
var
  LFilename: string;
  LNormalized: string;
  LStripped: string;
begin
  if (lpFileName <> nil) and TZipVFS.Initialized then
  begin
    LFilename := string(lpFileName);
    LNormalized := TZipVFS.NormalizePath(LFilename);
    LStripped := TZipVFS.StripBasePath(LNormalized);

    { Check if file exists in ZIP }
    if TZipVFS.ZipManager.ContainsFile(LStripped) then
    begin
      Result := TZipVFS.ZipManager.OpenFile(LStripped);
      Exit;
    end;
  end;

  { Fall through to original }
  Result := TCreateFileW(TZipVFS.OriginalCreateFileW)(
    lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes,
    dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
end;

function Hook_ReadFile(hFile: THandle;
  lpBuffer: Pointer;
  nNumberOfBytesToRead: DWORD;
  lpNumberOfBytesRead: PDWORD;
  lpOverlapped: POverlapped): BOOL; stdcall;
var
  LBytesRead: Integer;
begin
  { Check ZipVFS }
  if TZipVFS.Initialized and TZipVFS.ZipManager.IsVirtualHandle(hFile) then
  begin
    LBytesRead := TZipVFS.ZipManager.ReadFile(hFile, lpBuffer, nNumberOfBytesToRead);
    if LBytesRead >= 0 then
    begin
      if lpNumberOfBytesRead <> nil then
        lpNumberOfBytesRead^ := Cardinal(LBytesRead);
      Result := True;
    end
    else
      Result := False;
    Exit;
  end;

  { Fall through to original }
  Result := TReadFile(TZipVFS.OriginalReadFile)(
    hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesRead, lpOverlapped);
end;

function Hook_CloseHandle(hObject: THandle): BOOL; stdcall;
begin
  { Check ZipVFS }
  if TZipVFS.Initialized and TZipVFS.ZipManager.IsVirtualHandle(hObject) then
  begin
    TZipVFS.ZipManager.CloseFile(hObject);
    Result := True;
    Exit;
  end;

  { Fall through to original }
  Result := TCloseHandle(TZipVFS.OriginalCloseHandle)(hObject);
end;

function Hook_SetFilePointerEx(hFile: THandle;
  liDistanceToMove: LARGE_INTEGER;
  lpNewFilePointer: PLargeInteger;
  dwMoveMethod: DWORD): BOOL; stdcall;
var
  LNewPos: Int64;
  LOrigin: Integer;
begin
  { Map Windows move method to TSeekOrigin }
  case dwMoveMethod of
    FILE_BEGIN:   LOrigin := soFromBeginning;
    FILE_CURRENT: LOrigin := soFromCurrent;
    FILE_END:     LOrigin := soFromEnd;
  else
    LOrigin := soFromBeginning;
  end;

  { Check ZipVFS }
  if TZipVFS.Initialized and TZipVFS.ZipManager.IsVirtualHandle(hFile) then
  begin
    LNewPos := TZipVFS.ZipManager.SeekFile(hFile, liDistanceToMove.QuadPart, LOrigin);
    if LNewPos >= 0 then
    begin
      if lpNewFilePointer <> nil then
        lpNewFilePointer^ := LNewPos;
      Result := True;
    end
    else
      Result := False;
    Exit;
  end;

  { Fall through to original }
  Result := TSetFilePointerEx(TZipVFS.OriginalSetFilePointerEx)(
    hFile, liDistanceToMove, lpNewFilePointer, dwMoveMethod);
end;

function Hook_GetFileSizeEx(hFile: THandle;
  lpFileSize: PLargeInteger): BOOL; stdcall;
var
  LSize: Int64;
begin
  { Check ZipVFS }
  if TZipVFS.Initialized and TZipVFS.ZipManager.IsVirtualHandle(hFile) then
  begin
    LSize := TZipVFS.ZipManager.GetFileSize(hFile);
    if LSize >= 0 then
    begin
      if lpFileSize <> nil then
        lpFileSize^ := LSize;
      Result := True;
    end
    else
      Result := False;
    Exit;
  end;

  { Fall through to original }
  Result := TGetFileSizeEx(TZipVFS.OriginalGetFileSizeEx)(hFile, lpFileSize);
end;

function Hook_GetFileType(hFile: THandle): DWORD; stdcall;
const
  FILE_TYPE_DISK = 1;
begin
  { Return FILE_TYPE_DISK for virtual handles so CRT accepts them }
  if TZipVFS.Initialized and TZipVFS.ZipManager.IsVirtualHandle(hFile) then
  begin
    Result := FILE_TYPE_DISK;
    Exit;
  end;

  { Fall through to original }
  Result := TGetFileType(TZipVFS.OriginalGetFileType)(hFile);
end;

function Hook_GetFileAttributesExW(lpFileName: LPCWSTR;
  fInfoLevelId: DWORD;
  lpFileInformation: Pointer): BOOL; stdcall;
var
  LFilename: string;
  LNormalized: string;
  LStripped: string;
  LFileAttrData: PWin32FileAttributeData;
begin
  if (lpFileName <> nil) and TZipVFS.Initialized then
  begin
    LFilename := string(lpFileName);
    LNormalized := TZipVFS.NormalizePath(LFilename);
    LStripped := TZipVFS.StripBasePath(LNormalized);

    { Check if file exists in ZIP }
    if TZipVFS.ZipManager.ContainsFile(LStripped) then
    begin
      { Fill in file attribute data if requested }
      if (fInfoLevelId = 0) and (lpFileInformation <> nil) then
      begin
        LFileAttrData := PWin32FileAttributeData(lpFileInformation);
        LFileAttrData^.dwFileAttributes := FILE_ATTRIBUTE_READONLY or FILE_ATTRIBUTE_NORMAL;
        LFileAttrData^.ftCreationTime.dwLowDateTime := 0;
        LFileAttrData^.ftCreationTime.dwHighDateTime := 0;
        LFileAttrData^.ftLastAccessTime.dwLowDateTime := 0;
        LFileAttrData^.ftLastAccessTime.dwHighDateTime := 0;
        LFileAttrData^.ftLastWriteTime.dwLowDateTime := 0;
        LFileAttrData^.ftLastWriteTime.dwHighDateTime := 0;
        LFileAttrData^.nFileSizeHigh := 0;
        LFileAttrData^.nFileSizeLow := 0;
      end;
      Result := True;
      Exit;
    end;
  end;

  { Fall through to original }
  Result := TGetFileAttributesExW(TZipVFS.OriginalGetFileAttributesExW)(
    lpFileName, fInfoLevelId, lpFileInformation);
end;

{ TZipManager }

constructor TZipManager.Create();
begin
  inherited Create();
  FZipFile := TZipFile.Create();
  FZipStreams := TDictionary<THandle, TMemoryStream>.Create();
  FHandleCounter := 0;
  FResourceStream := nil;
  FBasePath := '';
end;

destructor TZipManager.Destroy();
var
  LStream: TMemoryStream;
begin
  for LStream in FZipStreams.Values do
    LStream.Free();

  FZipStreams.Free();
  FZipFile.Free();

  if Assigned(FResourceStream) then
    FResourceStream.Free();

  inherited Destroy();
end;

function TZipManager.LoadFromResource(const AResName: string;
  const AResType: PChar): Boolean;
begin
  Result := False;

  { Close any currently open ZIP }
  if FZipFile.Mode <> zmClosed then
    FZipFile.Close();

  try
    FResourceStream := TResourceStream.Create(HInstance, AResName, AResType);
    FZipFile.Open(FResourceStream, zmRead);
    Result := True;
  except
    FreeAndNil(FResourceStream);
  end;
end;

function TZipManager.LoadFromFile(const AFilename: string): Boolean;
begin
  Result := False;

  if not TFile.Exists(AFilename) then
    Exit;

  { Close any currently open ZIP }
  if FZipFile.Mode <> zmClosed then
    FZipFile.Close();

  try
    FZipFile.Open(AFilename, zmRead);
    Result := True;
  except
    { Swallow exception, return False }
  end;
end;

function TZipManager.ContainsFile(const APath: string): Boolean;
begin
  Result := FZipFile.IndexOf(APath) >= 0;
end;

function TZipManager.OpenFile(const APath: string): THandle;
var
  LStream: TMemoryStream;
  LBytes: TBytes;
  LFileIndex: Integer;
begin
  Result := INVALID_HANDLE_VALUE;

  LFileIndex := FZipFile.IndexOf(APath);
  if LFileIndex < 0 then
    Exit;

  try
    FZipFile.Read(LFileIndex, LBytes);
    LStream := TMemoryStream.Create();
    try
      if Length(LBytes) > 0 then
        LStream.WriteBuffer(LBytes[0], Length(LBytes));
      LStream.Position := 0;

      Inc(FHandleCounter);
      Result := THandle(VHANDLE_BASE + FHandleCounter);
      FZipStreams.Add(Result, LStream);
    except
      LStream.Free();
      raise;
    end;
  except
    Result := INVALID_HANDLE_VALUE;
  end;
end;

procedure TZipManager.CloseFile(const AHandle: THandle);
var
  LStream: TMemoryStream;
begin
  if FZipStreams.TryGetValue(AHandle, LStream) then
  begin
    LStream.Free();
    FZipStreams.Remove(AHandle);
  end;
end;

function TZipManager.ReadFile(const AHandle: THandle;
  const ABuffer: Pointer;
  const ACount: Cardinal): Integer;
var
  LStream: TMemoryStream;
begin
  Result := -1;

  if FZipStreams.TryGetValue(AHandle, LStream) then
    Result := LStream.Read(ABuffer^, ACount);
end;

function TZipManager.SeekFile(const AHandle: THandle;
  const AOffset: Int64;
  const AOrigin: Integer): Int64;
var
  LStream: TMemoryStream;
begin
  Result := -1;

  if FZipStreams.TryGetValue(AHandle, LStream) then
    Result := LStream.Seek(AOffset, TSeekOrigin(AOrigin));
end;

function TZipManager.GetFileSize(const AHandle: THandle): Int64;
var
  LStream: TMemoryStream;
begin
  Result := -1;

  if FZipStreams.TryGetValue(AHandle, LStream) then
    Result := LStream.Size;
end;

function TZipManager.IsVirtualHandle(const AHandle: THandle): Boolean;
begin
  Result := FZipStreams.ContainsKey(AHandle);
end;

{ TZipVFS }

class function TZipVFS.NormalizePath(const APath: string): string;
var
  LSegments: TArray<string>;
  LStack: TStack<string>;
  LSegment: string;
begin
  LStack := TStack<string>.Create();
  try
    { Normalize slashes to backslash and split }
    LSegments := APath.Replace('/', '\').Split(['\']);

    for LSegment in LSegments do
    begin
      if LSegment = '..' then
      begin
        if LStack.Count > 0 then
          LStack.Pop();
      end
      else if (LSegment <> '.') and (LSegment <> '') then
        LStack.Push(LSegment);
    end;

    { Rebuild path with backslashes }
    Result := '';
    while LStack.Count > 0 do
    begin
      if Result = '' then
        Result := LStack.Pop()
      else
        Result := LStack.Pop() + '\' + Result;
    end;
  finally
    LStack.Free();
  end;
end;

class function TZipVFS.StripBasePath(const APath: string): string;
var
  LPath: string;
  LBase: string;
begin
  LPath := APath.Replace('/', '\');
  LBase := FBasePath.Replace('/', '\');

  { Remove trailing backslash from base }
  if LBase.EndsWith('\') then
    LBase := LBase.Substring(0, LBase.Length - 1);

  { Case-insensitive prefix removal }
  if (LBase <> '') and LPath.ToLower().StartsWith(LBase.ToLower() + '\') then
    Result := LPath.Substring(LBase.Length + 1)
  else if (LBase <> '') and LPath.ToLower().StartsWith(LBase.ToLower()) then
    Result := LPath.Substring(LBase.Length)
  else
    Result := LPath;

  { Remove leading backslash if present }
  if Result.StartsWith('\') then
    Result := Result.Substring(1);
end;

class function TZipVFS.Initialize(const ADllBase: Pointer;
  const AResourceName: string;
  const ABasePath: string): Boolean;
begin
  Result := False;

  if FInitialized then
    Exit;

  { Create ZIP manager }
  FZipManager := TZipManager.Create();

  { Load ZIP from resource }
  if not FZipManager.LoadFromResource(AResourceName) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  FDllBase := ADllBase;
  FBasePath := ABasePath;
  if FBasePath = '' then
    FBasePath := TPath.GetDirectoryName(ParamStr(0));

  { Get original function pointers before hooking }
  FOriginalCreateFileW := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'CreateFileW');
  FOriginalReadFile := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'ReadFile');
  FOriginalCloseHandle := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'CloseHandle');
  FOriginalSetFilePointerEx := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
  FOriginalGetFileSizeEx := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
  FOriginalGetFileType := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileType');
  FOriginalGetFileAttributesExW := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileAttributesExW');

  { Verify we got all originals }
  if (FOriginalCreateFileW = nil) or
     (FOriginalReadFile = nil) or
     (FOriginalCloseHandle = nil) or
     (FOriginalSetFilePointerEx = nil) or
     (FOriginalGetFileType = nil) or
     (FOriginalGetFileAttributesExW = nil) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  { Install hooks }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW', @Hook_CreateFileW) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'ReadFile', @Hook_ReadFile) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle', @Hook_CloseHandle) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx', @Hook_SetFilePointerEx) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    FreeAndNil(FZipManager);
    Exit;
  end;

  { GetFileSizeEx is optional - TCC might not use it }
  if FOriginalGetFileSizeEx <> nil then
    TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx', @Hook_GetFileSizeEx);

  { Hook GetFileType - CRT calls this to validate handles }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileType', @Hook_GetFileType) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
    FreeAndNil(FZipManager);
    Exit;
  end;

  { Hook GetFileAttributesExW - TCC checks if file exists before opening }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileAttributesExW', @Hook_GetFileAttributesExW) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileType');
    FreeAndNil(FZipManager);
    Exit;
  end;

  FInitialized := True;
  Result := True;
end;

class function TZipVFS.Initialize(const ADllBase: Pointer;
  const AZipFilename: string;
  const ABasePath: string;
  const AFromFile: Boolean): Boolean;
begin
  Result := False;

  if FInitialized then
    Exit;

  if not AFromFile then
  begin
    Result := Initialize(ADllBase, AZipFilename, ABasePath);
    Exit;
  end;

  { Create ZIP manager }
  FZipManager := TZipManager.Create();

  { Load ZIP from file }
  if not FZipManager.LoadFromFile(AZipFilename) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  FDllBase := ADllBase;
  FBasePath := ABasePath;
  if FBasePath = '' then
    FBasePath := TPath.GetDirectoryName(ParamStr(0));

  { Get original function pointers before hooking }
  FOriginalCreateFileW := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'CreateFileW');
  FOriginalReadFile := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'ReadFile');
  FOriginalCloseHandle := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'CloseHandle');
  FOriginalSetFilePointerEx := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
  FOriginalGetFileSizeEx := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
  FOriginalGetFileType := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileType');
  FOriginalGetFileAttributesExW := TIATHook.GetOriginalProc(ADllBase, 'KERNEL32.dll', 'GetFileAttributesExW');

  { Verify we got all originals }
  if (FOriginalCreateFileW = nil) or
     (FOriginalReadFile = nil) or
     (FOriginalCloseHandle = nil) or
     (FOriginalSetFilePointerEx = nil) or
     (FOriginalGetFileType = nil) or
     (FOriginalGetFileAttributesExW = nil) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  { Install hooks }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW', @Hook_CreateFileW) then
  begin
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'ReadFile', @Hook_ReadFile) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle', @Hook_CloseHandle) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    FreeAndNil(FZipManager);
    Exit;
  end;

  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx', @Hook_SetFilePointerEx) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    FreeAndNil(FZipManager);
    Exit;
  end;

  { GetFileSizeEx is optional - TCC might not use it }
  if FOriginalGetFileSizeEx <> nil then
    TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx', @Hook_GetFileSizeEx);

  { Hook GetFileType - CRT calls this to validate handles }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileType', @Hook_GetFileType) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
    FreeAndNil(FZipManager);
    Exit;
  end;

  { Hook GetFileAttributesExW - TCC checks if file exists before opening }
  if not TIATHook.HookImport(ADllBase, 'KERNEL32.dll', 'GetFileAttributesExW', @Hook_GetFileAttributesExW) then
  begin
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CreateFileW');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'ReadFile');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'CloseHandle');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'SetFilePointerEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileSizeEx');
    TIATHook.UnhookImport(ADllBase, 'KERNEL32.dll', 'GetFileType');
    FreeAndNil(FZipManager);
    Exit;
  end;

  FInitialized := True;
  Result := True;
end;

class function TZipVFS.ExtractFile(const AZipPath: string;
  const ADestPath: string;
  const AOverwrite: Boolean): Boolean;
var
  LBytes: TBytes;
  LDestDir: string;
  LFileStream: TFileStream;
begin
  Result := False;

  { Check if initialized }
  if not FInitialized or (FZipManager = nil) then
    Exit;

  { Check if file exists in ZIP }
  if not FZipManager.ContainsFile(AZipPath) then
    Exit;

  { Check if destination already exists }
  if TFile.Exists(ADestPath) then
  begin
    if not AOverwrite then
      Exit;
    { Delete existing file }
    try
      TFile.Delete(ADestPath);
    except
      Exit;
    end;
  end;

  { Create destination directory if needed }
  LDestDir := TPath.GetDirectoryName(ADestPath);
  if (LDestDir <> '') and not TDirectory.Exists(LDestDir) then
  begin
    try
      TDirectory.CreateDirectory(LDestDir);
    except
      Exit;
    end;
  end;

  { Extract file contents }
  if not ExtractFileToBytes(AZipPath, LBytes) then
    Exit;

  { Write to destination }
  try
    LFileStream := TFileStream.Create(ADestPath, fmCreate);
    try
      if Length(LBytes) > 0 then
        LFileStream.WriteBuffer(LBytes[0], Length(LBytes));
      Result := True;
    finally
      LFileStream.Free();
    end;
  except
    Result := False;
  end;
end;

class function TZipVFS.ExtractFileToBytes(const AZipPath: string;
  out ABytes: TBytes): Boolean;
var
  LFileIndex: Integer;
begin
  Result := False;
  SetLength(ABytes, 0);

  { Check if initialized }
  if not FInitialized or (FZipManager = nil) then
    Exit;

  { Find file in ZIP }
  LFileIndex := FZipManager.ZipFile.IndexOf(AZipPath);
  if LFileIndex < 0 then
    Exit;

  { Read file contents }
  try
    FZipManager.ZipFile.Read(LFileIndex, ABytes);
    Result := True;
  except
    SetLength(ABytes, 0);
    Result := False;
  end;
end;

class function TZipVFS.FileExists(const AZipPath: string): Boolean;
begin
  Result := False;

  if not FInitialized or (FZipManager = nil) then
    Exit;

  Result := FZipManager.ContainsFile(AZipPath);
end;

class function TZipVFS.ListFiles(): TArray<string>;
var
  LI: Integer;
begin
  SetLength(Result, 0);

  if not FInitialized or (FZipManager = nil) then
    Exit;

  SetLength(Result, FZipManager.ZipFile.FileCount);
  for LI := 0 to FZipManager.ZipFile.FileCount - 1 do
    Result[LI] := FZipManager.ZipFile.FileName[LI];
end;

class procedure TZipVFS.Finalize();
begin
  if not FInitialized then
    Exit;

  { Remove all hooks }
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'CreateFileW');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'ReadFile');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'CloseHandle');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'SetFilePointerEx');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'GetFileSizeEx');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'GetFileType');
  TIATHook.UnhookImport(FDllBase, 'KERNEL32.dll', 'GetFileAttributesExW');

  FreeAndNil(FZipManager);

  FDllBase := nil;
  FOriginalCreateFileW := nil;
  FOriginalReadFile := nil;
  FOriginalCloseHandle := nil;
  FOriginalSetFilePointerEx := nil;
  FOriginalGetFileSizeEx := nil;
  FOriginalGetFileType := nil;
  FOriginalGetFileAttributesExW := nil;

  FInitialized := False;
end;

initialization

finalization
  TZipVFS.Finalize();

end.
