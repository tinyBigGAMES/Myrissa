{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.VirtualMemory - Virtual memory management with mapped I/O

  Provides page-file-backed and file-backed virtual memory regions via
  Windows CreateFileMapping/MapViewOfFile. Anonymous allocations use
  sparse temp files as backing store, eliminating commit charge limits
  -- the OS handles paging transparently with no upfront cost.

  Key types:
  - TVirtualMemory<T>: Core class -- Allocate (sparse temp file backed),
    Open (file-backed), Close, Grow, Flush, AsStream, CreateView<T>,
    shared memory via OpenShared/CreateShared
  - TVirtualMemoryView<T>: Generic typed view with indexed access,
    stream-style Read/Write, and position tracking
  - TVirtualMemoryStream: TStream adapter over a mapped region
  - TVirtualMemoryMode: Allocate, ReadOnly, ReadWrite, CopyOnWrite,
    AllocateExecute (anonymous read-write-execute region for JIT code)

  Dependencies: StdApp.Base, StdApp.Utils
===============================================================================}

unit StdApp.VirtualMemory;

{$I StdApp.Defines.inc}


interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Defaults,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources;

const
  // Win32 view-access flag missing from Winapi.Windows
  // (SECTION_MAP_EXECUTE_EXPLICIT -- execute access on a mapped view)
  { FILE_MAP_EXECUTE }
  FILE_MAP_EXECUTE = $0020;

  // Error codes for OS-level failures (programmer errors use exceptions).
  VM_ERR_ALLOC_SIZE_ZERO     = 'VM001';
  VM_ERR_ALLOC_MAPPING       = 'VM002';
  VM_ERR_ALLOC_MAPVIEW       = 'VM003';
  VM_ERR_ALLOC_EXCEPTION     = 'VM004';
  VM_ERR_LOAD_ALIGNMENT      = 'VM005';
  VM_ERR_LOAD_EXCEPTION      = 'VM006';
  VM_ERR_OPEN_FAILED         = 'VM007';
  VM_ERR_OPEN_MAPPING        = 'VM008';
  VM_ERR_OPEN_MAPVIEW        = 'VM009';
  VM_ERR_OPEN_EXCEPTION      = 'VM010';
  VM_ERR_OPEN_EMPTY          = 'VM011';
  VM_ERR_GROW_NOT_ANONYMOUS  = 'VM012';
  VM_ERR_GROW_REMAP          = 'VM013';
  VM_ERR_FLUSH_FAILED        = 'VM014';
  VM_ERR_SHARED_NAME_EMPTY   = 'VM015';
  VM_ERR_SHARED_OPEN_FAILED  = 'VM016';
  VM_ERR_SHARED_MAPVIEW      = 'VM017';
  VM_ERR_SHARED_EXCEPTION    = 'VM018';
  VM_ERR_ALLOC_NAME_EXISTS   = 'VM019';

type

  { TVirtualMemoryMode }
  TVirtualMemoryMode = (
    Allocate,    // Anonymous page-file-backed, read-write
    ReadOnly,    // File-backed, read-only (PAGE_READONLY)
    ReadWrite,   // File-backed, read-write (PAGE_READWRITE), changes persist
    CopyOnWrite,     // File-backed, private writes (PAGE_WRITECOPY), file untouched
    AllocateExecute  // Anonymous page-file-backed, read-write-execute (JIT code)
  );

  { TVirtualMemoryStream }
  TVirtualMemoryStream = class(TStream)
  private
    FMemory: Pointer;
    FSize: Int64;
    FPosition: Int64;
    FIsReadOnly: Boolean;
  protected
    function GetSize(): Int64; override;
  public
    constructor Create(
      const AMemory: Pointer;
      const ASize: Int64;
      const AIsReadOnly: Boolean
    );
    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Write(const ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  { TVirtualMemoryEnumerator<T> }
  TVirtualMemoryEnumerator<T> = class
  private
    type PT = ^T;
  private
    FMemory: Pointer;
    FCapacity: UInt64;
    FIndex: Int64;
    function GetCurrent(): T;
  public
    constructor Create(
      const AMemory: Pointer;
      const ACapacity: UInt64
    );
    destructor Destroy(); override;
    function MoveNext(): Boolean;
    property Current: T read GetCurrent;
  end;

  { TVirtualMemoryView<T> }
  TVirtualMemoryView<T> = class
  private
    type PT = ^T;
  private
    FBaseMemory: Pointer;  // points to start of this view's region
    FSize: UInt64;         // byte size of the view region
    FPosition: UInt64;
    FIsReadOnly: Boolean;
    function GetItem(AIndex: UInt64): T;
    procedure SetItem(AIndex: UInt64; AValue: T);
    function GetCapacity(): UInt64;
    function GetIsOpen(): Boolean;
  public
    constructor Create(
      const ABaseMemory: Pointer;
      const ASize: UInt64;
      const AIsReadOnly: Boolean
    );

    // Stream-style read/write within the view bounds
    function Read(var ABuffer; const ACount: UInt64): UInt64;
    function Write(const ABuffer; const ACount: UInt64): UInt64;

    // Position management
    procedure SetPosition(const AValue: UInt64);
    function Eob(): Boolean;

    // Persistence
    procedure SaveToStream(const AStream: TStream);
    procedure SaveToFile(const AFileName: string);

    function ItemPtr(const AIndex: UInt64): Pointer;

    // Typed indexed access (relative to view start)
    property Item[AIndex: UInt64]: T read GetItem write SetItem; default;

    property IsOpen: Boolean read GetIsOpen;
    property IsReadOnly: Boolean read FIsReadOnly;
    property Memory: Pointer read FBaseMemory;
    property Size: UInt64 read FSize;
    property Capacity: UInt64 read GetCapacity;
    property Position: UInt64 read FPosition write SetPosition;
  end;

  { TVirtualMemory<T> }
  TVirtualMemory<T> = class(TBaseObject)
  private
    type PT = ^T;
  private
    // OS handles
    FFileHandle: THandle;
    FMappingHandle: THandle;
    FMemory: Pointer;

    // State
    FSize: UInt64;
    FPosition: UInt64;
    FMode: TVirtualMemoryMode;
    FFilename: string;
    FMappingName: string;
    FTempFilePath: string;

    // Shared memory (IPC)
    FIsSharedConsumer: Boolean;
    FIsReadOnlyConsumer: Boolean;

    // Auto-grow (anonymous mode only)
    FAutoGrow: Boolean;
    FGrowFactor: Double;

    // Private helpers
    procedure DoClear();

    // Property accessors
    function GetItem(AIndex: UInt64): T;
    procedure SetItem(AIndex: UInt64; AValue: T);
    function GetCapacity(): UInt64;
    function GetIsOpen(): Boolean;
    function GetIsReadOnly(): Boolean;
    function GetIsSharedOwner(): Boolean;
    procedure SetPosition(const AValue: UInt64);

    // Internal write with optional auto-grow
    function DoWrite(const ABuffer: Pointer; const ACount: UInt64): UInt64;

    // Ensure writable mode or raise
    procedure CheckWritable();

  public
    constructor Create(); override;
    destructor Destroy(); override;
    function Allocate(const ASize: UInt64;
      const AMappingName: string = '';
      const AExecutable: Boolean = False): Boolean;

    function OpenShared(const AMappingName: string;
      const ASize: UInt64;
      const AReadOnly: Boolean = False): Boolean;

    function Open(const AFilename: string;
      const AMode: TVirtualMemoryMode = TVirtualMemoryMode.ReadOnly): Boolean;

    procedure Close();

    function Read(var ABuffer; const ACount: UInt64): UInt64; overload;
    function Read(var ABuffer: TBytes;
      const AOffset: UInt64; const ACount: UInt64): UInt64; overload;
    function Write(const ABuffer; const ACount: UInt64): UInt64; overload;
    function Write(const ABuffer: TBytes;
      const AOffset: UInt64; const ACount: UInt64): UInt64; overload;
    function ReadString(): string;
    procedure WriteString(const AValue: string);
    function Seek(const AOffset: Int64;
      const AOrigin: TSeekOrigin): UInt64;
    function Eob(): Boolean;

    procedure SaveToStream(const AStream: TStream);
    procedure SaveToFile(const AFilename: string);
    class function LoadFromFile(const AFilename: string): TVirtualMemory<T>;

    function FlushToDisk(): Boolean;

    // Flush the CPU instruction cache after writing code into an
    // AllocateExecute region -- required before executing newly written code
    procedure FlushInstructionCacheRegion(const AOffset: UInt64 = 0;
      const ASize: UInt64 = 0);

    procedure ZeroMemory();
    procedure CopyFrom(const ASource: Pointer; const ASizeBytes: UInt64);
    procedure Fill(const AValue: T);
    function Contains(const AValue: T): Boolean;
    function IndexOf(const AValue: T): Int64;

    function CreateStream(): TStream;
    function CreateView(const AOffset: UInt64;
      const ACount: UInt64): TVirtualMemoryView<T>;
    function Grow(const ANewSize: UInt64): Boolean;
    function GetEnumerator(): TVirtualMemoryEnumerator<T>;

    function ItemPtr(const AIndex: UInt64): Pointer;

    property Item[AIndex: UInt64]: T read GetItem write SetItem; default;
    property Capacity: UInt64 read GetCapacity;
    property Memory: Pointer read FMemory;
    property Size: UInt64 read FSize;
    property Position: UInt64 read FPosition write SetPosition;
    property IsOpen: Boolean read GetIsOpen;
    property IsReadOnly: Boolean read GetIsReadOnly;
    property IsSharedOwner: Boolean read GetIsSharedOwner;
    property MappingMode: TVirtualMemoryMode read FMode;
    property Filename: string read FFilename;
    property MappingHandle: THandle read FMappingHandle;
    property MappingName: string read FMappingName;
    property AutoGrow: Boolean read FAutoGrow write FAutoGrow;
    property GrowFactor: Double read FGrowFactor write FGrowFactor;
  end;

  { TVirtualBucketState }
  TVirtualBucketState = (
    Empty,
    Occupied,
    Deleted
  );

  { TVirtualDirectoryBucket<TKey, TValue> }
  TVirtualDirectoryBucket<TKey, TValue> = record
    Hash: UInt32;
    Key: TKey;
    Value: TValue;
    State: TVirtualBucketState;
  end;

  { TVirtualDirectory<TKey, TValue> }
  TVirtualDirectory<TKey, TValue> = class
  public type
    TForEachCallback = reference to procedure(const AKey: TKey; const AValue: TValue);
  private
    FBuckets: TVirtualMemory<TVirtualDirectoryBucket<TKey, TValue>>;
    FCount: Integer;
    FCapacity: Integer;
    FComparer: IEqualityComparer<TKey>;

    function FindBucket(const AKey: TKey; const AHash: UInt32;
      out AIndex: Integer): Boolean;
    procedure Rehash(const ANewCapacity: Integer);
    procedure CheckGrow();
    function GetItem(const AKey: TKey): TValue;
    procedure SetItem(const AKey: TKey; const AValue: TValue);
  public
    constructor Create(const AInitialCapacity: Integer = 256);
    destructor Destroy(); override;

    procedure Add(const AKey: TKey; const AValue: TValue);
    function Remove(const AKey: TKey): Boolean;
    function TryGetValue(const AKey: TKey; out AValue: TValue): Boolean;
    function ContainsKey(const AKey: TKey): Boolean;
    procedure Clear();
    procedure ForEach(const ACallback: TForEachCallback);

    property Items[const AKey: TKey]: TValue read GetItem write SetItem; default;
    property Count: Integer read FCount;
    property Capacity: Integer read FCapacity;
  end;

implementation

const
  FSCTL_SET_SPARSE = $000900C4;

{ TVirtualMemoryStream }
constructor TVirtualMemoryStream.Create(
  const AMemory: Pointer;
  const ASize: Int64;
  const AIsReadOnly: Boolean
);
begin
  inherited Create();
  FMemory := AMemory;
  FSize := ASize;
  FPosition := 0;
  FIsReadOnly := AIsReadOnly;
end;

function TVirtualMemoryStream.GetSize(): Int64;
begin
  Result := FSize;
end;

function TVirtualMemoryStream.Read(var ABuffer; ACount: Longint): Longint;
var
  LAvailable: Int64;
begin
  LAvailable := FSize - FPosition;
  if ACount > LAvailable then
    ACount := Longint(LAvailable);
  if ACount <= 0 then
    Exit(0);
  CopyMemory(@ABuffer,
    Pointer(UIntPtr(FMemory) + UIntPtr(FPosition)), ACount);
  Inc(FPosition, ACount);
  Result := ACount;
end;

function TVirtualMemoryStream.Write(const ABuffer; ACount: Longint): Longint;
var
  LAvailable: Int64;
begin
  if FIsReadOnly then
    raise EInvalidOperation.Create('Cannot write to a read-only stream');

  LAvailable := FSize - FPosition;
  if ACount > LAvailable then
    ACount := Longint(LAvailable);
  if ACount <= 0 then
    Exit(0);
  CopyMemory(
    Pointer(UIntPtr(FMemory) + UIntPtr(FPosition)), @ABuffer, ACount);
  Inc(FPosition, ACount);
  Result := ACount;

end;

function TVirtualMemoryStream.Seek(const AOffset: Int64;
  AOrigin: TSeekOrigin): Int64;
var
  LNewPos: Int64;
begin

  if AOrigin = soBeginning then
    LNewPos := AOffset
  else if AOrigin = soCurrent then
    LNewPos := FPosition + AOffset
  else // soEnd
    LNewPos := FSize + AOffset;

  if (LNewPos < 0) or (LNewPos > FSize) then
    raise EArgumentOutOfRangeException.Create(
      'Stream seek position out of bounds');
  FPosition := LNewPos;
  Result := FPosition;

end;

{ TVirtualMemoryEnumerator<T> }
constructor TVirtualMemoryEnumerator<T>.Create(
  const AMemory: Pointer;
  const ACapacity: UInt64
);
begin
  inherited Create();
  FMemory := AMemory;
  FCapacity := ACapacity;
  FIndex := -1;
end;

destructor TVirtualMemoryEnumerator<T>.Destroy();
begin
  inherited;
end;

function TVirtualMemoryEnumerator<T>.MoveNext(): Boolean;
begin
  Inc(FIndex);
  Result := UInt64(FIndex) < FCapacity;
end;

function TVirtualMemoryEnumerator<T>.GetCurrent(): T;
var
  LPtr: Pointer;
begin
  LPtr := Pointer(UIntPtr(FMemory) + UIntPtr(UInt64(FIndex) * UInt64(SizeOf(T))));
  if System.IsManagedType(T) then
    Result := PT(LPtr)^
  else
    CopyMemory(@Result, LPtr, SizeOf(T));
end;

{ TVirtualMemoryView<T> }
constructor TVirtualMemoryView<T>.Create(
  const ABaseMemory: Pointer;
  const ASize: UInt64;
  const AIsReadOnly: Boolean
);
begin
  inherited Create();
  FBaseMemory := ABaseMemory;
  FSize := ASize;
  FPosition := 0;
  FIsReadOnly := AIsReadOnly;
end;

function TVirtualMemoryView<T>.GetIsOpen(): Boolean;
begin
  Result := FBaseMemory <> nil;
end;

function TVirtualMemoryView<T>.GetCapacity(): UInt64;
begin
  Result := FSize div UInt64(SizeOf(T));
end;

function TVirtualMemoryView<T>.GetItem(AIndex: UInt64): T;
var
  LPtr: Pointer;
begin
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('View index out of bounds');
  LPtr := Pointer(UIntPtr(FBaseMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
  if System.IsManagedType(T) then
    Result := PT(LPtr)^
  else
    CopyMemory(@Result, LPtr, SizeOf(T));
end;

procedure TVirtualMemoryView<T>.SetItem(AIndex: UInt64; AValue: T);
var
  LPtr: Pointer;
begin
  if FIsReadOnly then
    raise EInvalidOperation.Create('Cannot write to a read-only view');
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('View index out of bounds');
  LPtr := Pointer(UIntPtr(FBaseMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
  if System.IsManagedType(T) then
    PT(LPtr)^ := AValue
  else
    CopyMemory(LPtr, @AValue, SizeOf(T));
end;

procedure TVirtualMemoryView<T>.SetPosition(const AValue: UInt64);
begin
  if AValue > FSize then
    raise EArgumentOutOfRangeException.Create(
      'View position out of bounds');
  FPosition := AValue;
end;

function TVirtualMemoryView<T>.Read(var ABuffer; const ACount: UInt64): UInt64;
var
  LCount: UInt64;
begin
  LCount := ACount;
  if FPosition + LCount > FSize then
    LCount := FSize - FPosition;
  if LCount > 0 then
    CopyMemory(@ABuffer,
      Pointer(UIntPtr(FBaseMemory) + UIntPtr(FPosition)), LCount);
  Inc(FPosition, LCount);
  Result := LCount;
end;

function TVirtualMemoryView<T>.Write(const ABuffer;
  const ACount: UInt64): UInt64;
begin
  if FIsReadOnly then
    raise EInvalidOperation.Create('Cannot write to a read-only view');

  if FPosition + ACount > FSize then
    Exit(0);
  CopyMemory(
    Pointer(UIntPtr(FBaseMemory) + UIntPtr(FPosition)), @ABuffer, ACount);
  Inc(FPosition, ACount);
  Result := ACount;
end;

function TVirtualMemoryView<T>.Eob(): Boolean;
begin
  Result := FPosition >= FSize;
end;

procedure TVirtualMemoryView<T>.SaveToStream(const AStream: TStream);
begin
  if FSize > 0 then
    AStream.WriteBuffer(FBaseMemory^, FSize);
end;

procedure TVirtualMemoryView<T>.SaveToFile(const AFileName: string);
var
  LStream: TFileStream;
  LResolved: string;
begin
  LResolved := TUtils.ResolvePath(AFileName);
  LStream := TFileStream.Create(LResolved, fmCreate);
  try
    SaveToStream(LStream);
  finally
    LStream.Free();
  end;
end;

function TVirtualMemoryView<T>.ItemPtr(const AIndex: UInt64): Pointer;
begin
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('View index out of bounds');
  Result := Pointer(UIntPtr(FBaseMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
end;


{ TVirtualMemory<T> }
constructor TVirtualMemory<T>.Create();
begin
  inherited Create();

  FFileHandle := INVALID_HANDLE_VALUE;
  FMappingHandle := 0;
  FMemory := nil;
  FSize := 0;
  FPosition := 0;
  FMode := TVirtualMemoryMode.Allocate;
  FFilename := '';
  FMappingName := '';
  FAutoGrow := False;
  FGrowFactor := 2.0;
  FIsSharedConsumer := False;
  FIsReadOnlyConsumer := False;
end;

destructor TVirtualMemory<T>.Destroy();
begin
  DoClear();

  inherited;
end;

function TVirtualMemory<T>.ItemPtr(const AIndex: UInt64): Pointer;
begin
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('Index out of bounds');
  Result := Pointer(UIntPtr(FMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
end;

procedure TVirtualMemory<T>.CheckWritable();
begin
  if GetIsReadOnly() then
    raise EInvalidOperation.Create(
      'Cannot write in read-only mode');
end;

procedure TVirtualMemory<T>.DoClear();
begin
  // Finalize managed fields before releasing the memory
  if System.IsManagedType(T) and (FMemory <> nil) and (FSize > 0) then
    System.FinalizeArray(FMemory, TypeInfo(T), FSize div UInt64(SizeOf(T)));

  if FMemory <> nil then
    UnmapViewOfFile(FMemory);
  if FMappingHandle <> 0 then
    CloseHandle(FMappingHandle);
  if FFileHandle <> INVALID_HANDLE_VALUE then
    CloseHandle(FFileHandle);

  FMemory := nil;
  FMappingHandle := 0;
  FFileHandle := INVALID_HANDLE_VALUE;
  FSize := 0;
  FPosition := 0;
  FFilename := '';
  FMappingName := '';
  FTempFilePath := '';
  FIsSharedConsumer := False;
  FIsReadOnlyConsumer := False;
end;

procedure TVirtualMemory<T>.Close();
begin
  DoClear();
end;

function TVirtualMemory<T>.GetIsOpen(): Boolean;
begin
  Result := FMemory <> nil;
end;

function TVirtualMemory<T>.GetIsReadOnly(): Boolean;
begin
  Result := (FMode = TVirtualMemoryMode.ReadOnly) or FIsReadOnlyConsumer;
end;

function TVirtualMemory<T>.GetIsSharedOwner(): Boolean;
begin
  Result := GetIsOpen() and (not FIsSharedConsumer);
end;

function TVirtualMemory<T>.GetCapacity(): UInt64;
begin
  Result := FSize div UInt64(SizeOf(T));
end;

procedure TVirtualMemory<T>.SetPosition(const AValue: UInt64);
begin
  if AValue > FSize then
    raise EArgumentOutOfRangeException.Create('Position out of bounds');
  FPosition := AValue;
end;

function TVirtualMemory<T>.GetItem(AIndex: UInt64): T;
var
  LPtr: Pointer;
begin
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('Index out of bounds');
  LPtr := Pointer(UIntPtr(FMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
  if System.IsManagedType(T) then
    Result := PT(LPtr)^
  else
    CopyMemory(@Result, LPtr, SizeOf(T));
end;

procedure TVirtualMemory<T>.SetItem(AIndex: UInt64; AValue: T);
var
  LPtr: Pointer;
begin
  CheckWritable();
  if AIndex >= GetCapacity() then
    raise EArgumentOutOfRangeException.Create('Index out of bounds');
  LPtr := Pointer(UIntPtr(FMemory) + UIntPtr(AIndex * UInt64(SizeOf(T))));
  if System.IsManagedType(T) then
    PT(LPtr)^ := AValue
  else
    CopyMemory(LPtr, @AValue, SizeOf(T));
end;

function TVirtualMemory<T>.Allocate(const ASize: UInt64;
  const AMappingName: string = '';
  const AExecutable: Boolean = False): Boolean;
var
  LBytesReturned: DWORD;
  LTotalBytes: UInt64;
  LFileAccess: DWORD;
  LPageProtect: DWORD;
  LMapAccess: DWORD;
begin
  Result := False;

  // Executable regions need EXECUTE rights on the backing file handle,
  // the section protection, and the mapped view
  if AExecutable then
  begin
    LFileAccess := GENERIC_READ or GENERIC_WRITE or GENERIC_EXECUTE;
    LPageProtect := PAGE_EXECUTE_READWRITE;
    LMapAccess := FILE_MAP_ALL_ACCESS or FILE_MAP_EXECUTE;
  end
  else
  begin
    LFileAccess := GENERIC_READ or GENERIC_WRITE;
    LPageProtect := PAGE_READWRITE;
    LMapAccess := FILE_MAP_ALL_ACCESS;
  end;

  if ASize = 0 then
  begin
    FErrors.Add(esError, VM_ERR_ALLOC_SIZE_ZERO,
      RSVMAllocSizeZero, [], nil);
    Exit;
  end;

  // Release any prior mapping
  Close();

  LTotalBytes := UInt64(SizeOf(T)) * ASize;

  // Use caller-supplied name or generate a GUID-based name
  if AMappingName <> '' then
    FMappingName := AMappingName
  else
    FMappingName := TPath.GetGUIDFileName();

  try
    // Create sparse temp file as backing store (no commit charge)
    FTempFilePath := TPath.Combine(TPath.GetTempPath(), FMappingName + '.vmtmp');
    FFileHandle := CreateFile(PChar(FTempFilePath),
      LFileAccess, 0, nil, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL or FILE_FLAG_DELETE_ON_CLOSE, 0);
    if FFileHandle = INVALID_HANDLE_VALUE then
    begin
      FErrors.Add(esError, VM_ERR_ALLOC_MAPPING,
        RSVMCreateMappingFailed, [GetLastError()], nil);
      Exit;
    end;

    // Mark file as sparse (NTFS -- pages only consume disk when written)
    DeviceIoControl(FFileHandle, FSCTL_SET_SPARSE,
      nil, 0, nil, 0, LBytesReturned, nil);

    // Set file size
    SetFilePointerEx(FFileHandle, Int64(LTotalBytes), nil, FILE_BEGIN);
    SetEndOfFile(FFileHandle);

    // Create mapping from the sparse file
    FMappingHandle := CreateFileMapping(FFileHandle, nil,
      LPageProtect, 0, 0, PChar(FMappingName));
    if FMappingHandle = 0 then
    begin
      FErrors.Add(esError, VM_ERR_ALLOC_MAPPING,
        RSVMCreateMappingFailed, [GetLastError()], nil);
      Exit;
    end;

    // If the caller supplied a custom name, reject if the mapping
    // already existed — the producer should own the name exclusively
    if (AMappingName <> '') and (GetLastError() = ERROR_ALREADY_EXISTS) then
    begin
      CloseHandle(FMappingHandle);
      FMappingHandle := 0;
      FErrors.Add(esError, VM_ERR_ALLOC_NAME_EXISTS,
        RSVMMappingNameExists, [AMappingName], nil);
      Exit;
    end;

    FMemory := MapViewOfFile(FMappingHandle, LMapAccess, 0, 0, 0);
    if FMemory = nil then
    begin
      FErrors.Add(esError, VM_ERR_ALLOC_MAPVIEW,
        RSVMMapViewFailed, [GetLastError()], nil);
      CloseHandle(FMappingHandle);
      FMappingHandle := 0;
      Exit;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(esError, VM_ERR_ALLOC_EXCEPTION,
        RSVMAllocException, [E.Message], nil);
      DoClear();
      Exit;
    end;
  end;

  FSize := LTotalBytes;
  FPosition := 0;
  if AExecutable then
    FMode := TVirtualMemoryMode.AllocateExecute
  else
    FMode := TVirtualMemoryMode.Allocate;
  FFilename := '';
  FIsSharedConsumer := False;
  Result := True;
end;

procedure TVirtualMemory<T>.FlushInstructionCacheRegion(const AOffset: UInt64 = 0;
  const ASize: UInt64 = 0);
var
  LSize: UInt64;
begin
  // Only meaningful on a live executable region
  if (FMode <> TVirtualMemoryMode.AllocateExecute) or (FMemory = nil) then
    Exit;

  if AOffset >= FSize then
    Exit;

  // Zero size means flush from offset to end of region; clamp to bounds
  LSize := ASize;
  if (LSize = 0) or (AOffset + LSize > FSize) then
    LSize := FSize - AOffset;

  WinApi.Windows.FlushInstructionCache(GetCurrentProcess(),
    Pointer(UIntPtr(FMemory) + UIntPtr(AOffset)), LSize);
end;

function TVirtualMemory<T>.OpenShared(const AMappingName: string;
  const ASize: UInt64;
  const AReadOnly: Boolean = False): Boolean;
var
  LMapAccess: DWORD;
  LTotalBytes: UInt64;
begin
  Result := False;

  if AMappingName = '' then
  begin
    FErrors.Add(esError, VM_ERR_SHARED_NAME_EMPTY,
      RSVMSharedNameEmpty, [], nil);
    Exit;
  end;

  // Release any prior mapping
  Close();

  LTotalBytes := UInt64(SizeOf(T)) * ASize;

  if AReadOnly then
    LMapAccess := FILE_MAP_READ
  else
    LMapAccess := FILE_MAP_ALL_ACCESS;

  try
    FMappingHandle := OpenFileMapping(LMapAccess, False,
      PChar(AMappingName));
    if FMappingHandle = 0 then
    begin
      FErrors.Add(esError, VM_ERR_SHARED_OPEN_FAILED,
        RSVMOpenMappingFailed,
        [AMappingName, GetLastError()], nil);
      Exit;
    end;

    FMemory := MapViewOfFile(FMappingHandle, LMapAccess, 0, 0, 0);
    if FMemory = nil then
    begin
      FErrors.Add(esError, VM_ERR_SHARED_MAPVIEW,
        RSVMMapViewNamedFailed,
        [AMappingName, GetLastError()], nil);
      CloseHandle(FMappingHandle);
      FMappingHandle := 0;
      Exit;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(esError, VM_ERR_SHARED_EXCEPTION,
        RSVMSharedException, [AMappingName, E.Message], nil);
      DoClear();
      Exit;
    end;
  end;

  FSize := LTotalBytes;
  FPosition := 0;
  FMode := TVirtualMemoryMode.Allocate;
  FFilename := '';
  FMappingName := AMappingName;
  FFileHandle := INVALID_HANDLE_VALUE;
  FIsSharedConsumer := True;
  FIsReadOnlyConsumer := AReadOnly;
  Result := True;
end;

function TVirtualMemory<T>.Open(const AFilename: string;
  const AMode: TVirtualMemoryMode): Boolean;
var
  LFileSizeHigh: DWORD;
  LFileSizeLow: DWORD;
  LTotalSize: UInt64;
  LDesiredAccess: DWORD;
  LPageProtect: DWORD;
  LMapAccess: DWORD;
begin
  Result := False;

  if (AMode = TVirtualMemoryMode.Allocate) or
     (AMode = TVirtualMemoryMode.AllocateExecute) then
  begin
    // Allocate/AllocateExecute are not valid for Open; use Allocate() instead.
    FErrors.Add(esError, VM_ERR_OPEN_FAILED,
      RSVMUseAllocate, [], nil);
    Exit;
  end;

  // Release any prior mapping
  Close();

  // Determine OS flags based on mode
  if AMode = TVirtualMemoryMode.ReadOnly then
  begin
    LDesiredAccess := GENERIC_READ;
    LPageProtect := PAGE_READONLY;
    LMapAccess := FILE_MAP_READ;
  end
  else if AMode = TVirtualMemoryMode.ReadWrite then
  begin
    LDesiredAccess := GENERIC_READ or GENERIC_WRITE;
    LPageProtect := PAGE_READWRITE;
    LMapAccess := FILE_MAP_ALL_ACCESS;
  end
  else // vmCopyOnWrite
  begin
    LDesiredAccess := GENERIC_READ;
    LPageProtect := PAGE_WRITECOPY;
    LMapAccess := FILE_MAP_COPY;
  end;

  try
    FFileHandle := CreateFile(PChar(AFilename),
      LDesiredAccess, FILE_SHARE_READ, nil,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if FFileHandle = INVALID_HANDLE_VALUE then
    begin
      FErrors.Add(esError, VM_ERR_OPEN_FAILED,
        RSVMOpenFileFailed,
        [AFilename, GetLastError()], nil);
      Exit;
    end;

    LFileSizeLow := GetFileSize(FFileHandle, @LFileSizeHigh);
    LTotalSize := (UInt64(LFileSizeHigh) shl 32) or UInt64(LFileSizeLow);

    if LTotalSize = 0 then
    begin
      FErrors.Add(esError, VM_ERR_OPEN_EMPTY,
        RSVMFileEmpty, [AFilename], nil);
      CloseHandle(FFileHandle);
      FFileHandle := INVALID_HANDLE_VALUE;
      Exit;
    end;

    FMappingHandle := CreateFileMapping(FFileHandle, nil,
      LPageProtect, 0, 0, nil);
    if FMappingHandle = 0 then
    begin
      FErrors.Add(esError, VM_ERR_OPEN_MAPPING,
        RSVMCreateMappingNamedFailed,
        [AFilename, GetLastError()], nil);
      CloseHandle(FFileHandle);
      FFileHandle := INVALID_HANDLE_VALUE;
      Exit;
    end;

    FMemory := MapViewOfFile(FMappingHandle, LMapAccess, 0, 0, 0);
    if FMemory = nil then
    begin
      FErrors.Add(esError, VM_ERR_OPEN_MAPVIEW,
        RSVMMapViewNamedFailed,
        [AFilename, GetLastError()], nil);
      CloseHandle(FMappingHandle);
      FMappingHandle := 0;
      CloseHandle(FFileHandle);
      FFileHandle := INVALID_HANDLE_VALUE;
      Exit;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(esError, VM_ERR_OPEN_EXCEPTION,
        RSVMOpenException, [AFilename, E.Message], nil);
      DoClear();
      Exit;
    end;
  end;

  FFilename := AFilename;
  FSize := LTotalSize;
  FPosition := 0;
  FMode := AMode;
  FMappingName := '';
  Result := True;
end;

function TVirtualMemory<T>.Read(var ABuffer; const ACount: UInt64): UInt64;
var
  LCount: UInt64;
begin
  LCount := ACount;
  if FPosition + LCount > FSize then
    LCount := FSize - FPosition;
  if LCount > 0 then
    CopyMemory(@ABuffer,
      Pointer(UIntPtr(FMemory) + UIntPtr(FPosition)), LCount);
  Inc(FPosition, LCount);
  Result := LCount;
end;

function TVirtualMemory<T>.Read(var ABuffer: TBytes;
  const AOffset: UInt64; const ACount: UInt64): UInt64;
var
  LCount: UInt64;
begin
  if (AOffset + ACount > UInt64(Length(ABuffer))) then
    raise EArgumentOutOfRangeException.Create(
      'Buffer overflow in Read');

  LCount := ACount;
  if FPosition + LCount > FSize then
    LCount := FSize - FPosition;
  if LCount > 0 then
    CopyMemory(@ABuffer[AOffset],
      Pointer(UIntPtr(FMemory) + UIntPtr(FPosition)), LCount);
  Inc(FPosition, LCount);
  Result := LCount;
end;

function TVirtualMemory<T>.DoWrite(const ABuffer: Pointer;
  const ACount: UInt64): UInt64;
var
  LNeeded: UInt64;
  LNewSize: UInt64;
begin
  // Check if we need to auto-grow (anonymous mode only)
  LNeeded := FPosition + ACount;
  if LNeeded > FSize then
  begin
    if FAutoGrow and (FMode = TVirtualMemoryMode.Allocate) then
    begin
      // Grow to at least the needed size, or by GrowFactor
      LNewSize := FSize;
      if LNewSize = 0 then
        LNewSize := UInt64(SizeOf(T));
      while LNewSize < LNeeded do
        LNewSize := UInt64(Trunc(Double(LNewSize) * FGrowFactor));
      // Convert bytes to element count for Grow
      if not Grow(LNewSize div UInt64(SizeOf(T))) then
        Exit(0);
    end
    else
      Exit(0);
  end;

  CopyMemory(
    Pointer(UIntPtr(FMemory) + UIntPtr(FPosition)), ABuffer, ACount);
  Inc(FPosition, ACount);
  Result := ACount;
end;

function TVirtualMemory<T>.Write(const ABuffer;
  const ACount: UInt64): UInt64;
begin
  CheckWritable();
  Result := DoWrite(@ABuffer, ACount);
end;

function TVirtualMemory<T>.Write(const ABuffer: TBytes;
  const AOffset: UInt64; const ACount: UInt64): UInt64;
begin
  CheckWritable();

  if (AOffset + ACount > UInt64(Length(ABuffer))) then
    raise EArgumentOutOfRangeException.Create(
      'Buffer overflow in Write');
  Result := DoWrite(@ABuffer[AOffset], ACount);

end;

function TVirtualMemory<T>.ReadString(): string;
var
  LLen: UInt64;
begin
  Read(LLen, SizeOf(LLen));
  SetLength(Result, LLen);
  if LLen > 0 then
    Read(Result[1], LLen * UInt64(SizeOf(Char)));
end;

procedure TVirtualMemory<T>.WriteString(const AValue: string);
var
  LLength: UInt64;
begin
  CheckWritable();

  LLength := Length(AValue);
  DoWrite(@LLength, SizeOf(LLength));
  if LLength > 0 then
    DoWrite(PChar(AValue), LLength * UInt64(SizeOf(Char)));
end;

function TVirtualMemory<T>.Seek(const AOffset: Int64;
  const AOrigin: TSeekOrigin): UInt64;
var
  LNewPos: Int64;
begin
  if AOrigin = soBeginning then
    LNewPos := AOffset
  else if AOrigin = soCurrent then
    LNewPos := Int64(FPosition) + AOffset
  else // soEnd
    LNewPos := Int64(FSize) + AOffset;

  if (LNewPos < 0) or (UInt64(LNewPos) > FSize) then
    raise EArgumentOutOfRangeException.Create(
      'Seek position out of bounds');
  FPosition := UInt64(LNewPos);
  Result := FPosition;
end;

function TVirtualMemory<T>.Eob(): Boolean;
begin
  Result := FPosition >= FSize;
end;

procedure TVirtualMemory<T>.SaveToStream(const AStream: TStream);
begin
  if FSize > 0 then
    AStream.WriteBuffer(FMemory^, FSize);
end;

procedure TVirtualMemory<T>.SaveToFile(const AFilename: string);
var
  LStream: TFileStream;
  LResolved: string;
begin
  LResolved := TUtils.ResolvePath(AFilename);
  LStream := TFileStream.Create(LResolved, fmCreate);
  try
    SaveToStream(LStream);
  finally
    LStream.Free();
  end;
end;

class function TVirtualMemory<T>.LoadFromFile(
  const AFilename: string): TVirtualMemory<T>;
var
  LFileStream: TFileStream;
  LFileSize: Int64;
  LElements: UInt64;
begin
  Result := TVirtualMemory<T>.Create();
  try
    LFileStream := TFileStream.Create(AFilename,
      fmOpenRead or fmShareDenyWrite);
    try
      LFileSize := LFileStream.Size;
      if LFileSize mod SizeOf(T) <> 0 then
      begin
        Result.FErrors.Add(esError, VM_ERR_LOAD_ALIGNMENT,
          RSVMLoadAlignmentFailed,
          [LFileSize, SizeOf(T)], nil);
        Exit;
      end;

      LElements := LFileSize div SizeOf(T);
      if not Result.Allocate(LElements) then
        Exit;

      LFileStream.ReadBuffer(Result.FMemory^, LFileSize);
      Result.FPosition := 0;
    finally
      LFileStream.Free();
    end;
  except
    on E: Exception do
      Result.FErrors.Add(esError, VM_ERR_LOAD_EXCEPTION,
        RSVMLoadException, [AFilename, E.Message], nil);
  end;
end;

function TVirtualMemory<T>.FlushToDisk(): Boolean;
begin
  Result := True;

  // Only meaningful for read-write file-backed mappings
  if FMode <> TVirtualMemoryMode.ReadWrite then
    Exit;

  if (FMemory <> nil) and (FSize > 0) then
  begin
    if not FlushViewOfFile(FMemory, 0) then
    begin
      FErrors.Add(esError, VM_ERR_FLUSH_FAILED,
        RSVMFlushFailed, [GetLastError()], nil);
      Result := False;
    end;
  end;
end;

procedure TVirtualMemory<T>.ZeroMemory();
begin
  CheckWritable();
  if System.IsManagedType(T) and (FMemory <> nil) and (FSize > 0) then
    System.FinalizeArray(FMemory, TypeInfo(T), GetCapacity());
  FillChar(FMemory^, FSize, 0);
end;

procedure TVirtualMemory<T>.CopyFrom(const ASource: Pointer;
  const ASizeBytes: UInt64);
begin
  CheckWritable();

  if ASizeBytes > FSize then
    raise EArgumentOutOfRangeException.Create(
      'Source size exceeds buffer capacity');
  CopyMemory(FMemory, ASource, ASizeBytes);
end;

procedure TVirtualMemory<T>.Fill(const AValue: T);
var
  LIndex: UInt64;
  LCap: UInt64;
  LPtr: Pointer;
begin
  CheckWritable();

  LCap := GetCapacity();
  if System.IsManagedType(T) then
  begin
    for LIndex := 0 to LCap - 1 do
    begin
      LPtr := Pointer(UIntPtr(FMemory) +
        UIntPtr(LIndex * UInt64(SizeOf(T))));
      PT(LPtr)^ := AValue;
    end;
  end
  else
  begin
    LIndex := 0;
    while LIndex < LCap do
    begin
      LPtr := Pointer(UIntPtr(FMemory) +
        UIntPtr(LIndex * UInt64(SizeOf(T))));
      CopyMemory(LPtr, @AValue, SizeOf(T));
      Inc(LIndex);
    end;
  end;
end;

function TVirtualMemory<T>.Contains(const AValue: T): Boolean;
begin
  Result := IndexOf(AValue) >= 0;
end;

function TVirtualMemory<T>.IndexOf(const AValue: T): Int64;
var
  LIndex: UInt64;
  LCap: UInt64;
  LPtr: Pointer;
begin
  Result := -1;

  LCap := GetCapacity();
  LIndex := 0;
  while LIndex < LCap do
  begin
    LPtr := Pointer(UIntPtr(FMemory) +
      UIntPtr(LIndex * UInt64(SizeOf(T))));
    if CompareMem(LPtr, @AValue, SizeOf(T)) then
    begin
      Result := Int64(LIndex);
      Exit;
    end;
    Inc(LIndex);
  end;
end;

function TVirtualMemory<T>.CreateStream(): TStream;
begin
  Result := TVirtualMemoryStream.Create(
    FMemory, Int64(FSize), GetIsReadOnly());
end;

function TVirtualMemory<T>.CreateView(const AOffset: UInt64;
  const ACount: UInt64): TVirtualMemoryView<T>;
var
  LByteOffset: UInt64;
  LByteSize: UInt64;
begin
  LByteOffset := AOffset * UInt64(SizeOf(T));
  LByteSize := ACount * UInt64(SizeOf(T));

  if LByteOffset + LByteSize > FSize then
    raise EArgumentOutOfRangeException.Create(
      'View range exceeds buffer bounds');

  Result := TVirtualMemoryView<T>.Create(
    Pointer(UIntPtr(FMemory) + UIntPtr(LByteOffset)),
    LByteSize, GetIsReadOnly());
end;

function TVirtualMemory<T>.Grow(const ANewSize: UInt64): Boolean;
var
  LNewTotalBytes: UInt64;
  LOldMemory: Pointer;
  LOldSize: UInt64;
  LOldMappingHandle: THandle;
  LOldFileHandle: THandle;
  LBytesReturned: DWORD;
  LNewMappingHandle: THandle;
  LNewFileHandle: THandle;
  LNewMemory: Pointer;
  LNewName: string;
  LNewTempPath: string;
  LFileAccess: DWORD;
  LPageProtect: DWORD;
  LMapAccess: DWORD;
begin
  Result := False;

  if (FMode <> TVirtualMemoryMode.Allocate) and
     (FMode <> TVirtualMemoryMode.AllocateExecute) then
  begin
    FErrors.Add(esError, VM_ERR_GROW_NOT_ANONYMOUS,
      RSVMGrowNotAnonymous, [], nil);
    Exit;
  end;

  if FIsSharedConsumer then
  begin
    FErrors.Add(esError, VM_ERR_GROW_NOT_ANONYMOUS,
      RSVMGrowNotShared, [], nil);
    Exit;
  end;

  LNewTotalBytes := ANewSize * UInt64(SizeOf(T));
  if LNewTotalBytes <= FSize then
  begin
    // Already big enough — no-op success
    Result := True;
    Exit;
  end;


  // Set access flags based on mode
  if FMode = TVirtualMemoryMode.AllocateExecute then
  begin
    LFileAccess := GENERIC_READ or GENERIC_WRITE or GENERIC_EXECUTE;
    LPageProtect := PAGE_EXECUTE_READWRITE;
    LMapAccess := FILE_MAP_ALL_ACCESS or FILE_MAP_EXECUTE;
  end
  else
  begin
    LFileAccess := GENERIC_READ or GENERIC_WRITE;
    LPageProtect := PAGE_READWRITE;
    LMapAccess := FILE_MAP_ALL_ACCESS;
  end;

  LOldMemory := FMemory;
  LOldSize := FSize;
  LOldMappingHandle := FMappingHandle;
  LOldFileHandle := FFileHandle;

  LNewName := TPath.GetGUIDFileName();

  try
    // Create new sparse temp file
    LNewTempPath := TPath.Combine(TPath.GetTempPath(), LNewName + '.vmtmp');
    LNewFileHandle := CreateFile(PChar(LNewTempPath),
      LFileAccess, 0, nil, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL or FILE_FLAG_DELETE_ON_CLOSE, 0);
    if LNewFileHandle = INVALID_HANDLE_VALUE then
    begin
      FErrors.Add(esError, VM_ERR_GROW_REMAP,
        RSVMGrowMappingFailed,
        [GetLastError()], nil);
      Exit;
    end;

    // Mark sparse and set size
    DeviceIoControl(LNewFileHandle, FSCTL_SET_SPARSE,
      nil, 0, nil, 0, LBytesReturned, nil);
    SetFilePointerEx(LNewFileHandle, Int64(LNewTotalBytes), nil, FILE_BEGIN);
    SetEndOfFile(LNewFileHandle);

    LNewMappingHandle := CreateFileMapping(LNewFileHandle,
      nil, LPageProtect, 0, 0, PChar(LNewName));
    if LNewMappingHandle = 0 then
    begin
      FErrors.Add(esError, VM_ERR_GROW_REMAP,
        RSVMGrowMappingFailed,
        [GetLastError()], nil);
      CloseHandle(LNewFileHandle);
      Exit;
    end;

    LNewMemory := MapViewOfFile(LNewMappingHandle,
      LMapAccess, 0, 0, 0);
    if LNewMemory = nil then
    begin
      FErrors.Add(esError, VM_ERR_GROW_REMAP,
        RSVMGrowMapViewFailed,
        [GetLastError()], nil);
      CloseHandle(LNewMappingHandle);
      CloseHandle(LNewFileHandle);
      Exit;
    end;

    // Copy old data into the new mapping
    if (LOldMemory <> nil) and (LOldSize > 0) then
    begin
      if System.IsManagedType(T) then
      begin
        System.CopyArray(LNewMemory, LOldMemory, TypeInfo(T),
          LOldSize div UInt64(SizeOf(T)));
        System.FinalizeArray(LOldMemory, TypeInfo(T),
          LOldSize div UInt64(SizeOf(T)));
      end
      else
        CopyMemory(LNewMemory, LOldMemory, LOldSize);
    end;

    // Release old mapping and file
    if LOldMemory <> nil then
      UnmapViewOfFile(LOldMemory);
    if LOldMappingHandle <> 0 then
      CloseHandle(LOldMappingHandle);
    if LOldFileHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(LOldFileHandle);

    // Swap in the new mapping
    FMemory := LNewMemory;
    FMappingHandle := LNewMappingHandle;
    FFileHandle := LNewFileHandle;
    FMappingName := LNewName;
    FTempFilePath := LNewTempPath;
    FSize := LNewTotalBytes;
    // Position is preserved
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, VM_ERR_GROW_REMAP,
        RSVMGrowException, [E.Message], nil);
  end;

end;

function TVirtualMemory<T>.GetEnumerator(): TVirtualMemoryEnumerator<T>;
begin
  Result := TVirtualMemoryEnumerator<T>.Create(
    FMemory, GetCapacity());
end;

{ TVirtualDirectory<TKey, TValue> }
constructor TVirtualDirectory<TKey, TValue>.Create(const AInitialCapacity: Integer);
begin
  inherited Create();
  FComparer := TEqualityComparer<TKey>.Default();
  FCapacity := AInitialCapacity;
  FCount := 0;
  FBuckets := TVirtualMemory<TVirtualDirectoryBucket<TKey, TValue>>.Create();
  FBuckets.Allocate(UInt64(AInitialCapacity));
  FBuckets.ZeroMemory();
end;

destructor TVirtualDirectory<TKey, TValue>.Destroy();
begin
  FBuckets.Free();
  inherited;
end;

function TVirtualDirectory<TKey, TValue>.FindBucket(const AKey: TKey;
  const AHash: UInt32; out AIndex: Integer): Boolean;
var
  LIdx: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
  LStartIdx: Integer;
  LFirstDeleted: Integer;
begin
  Result := False;
  LFirstDeleted := -1;
  LIdx := Integer(AHash mod UInt32(FCapacity));
  LStartIdx := LIdx;

  repeat
    LBucket := FBuckets[LIdx];

    if LBucket.State = TVirtualBucketState.Empty then
    begin
      // Not found — return first deleted slot if available, otherwise this empty slot
      if LFirstDeleted >= 0 then
        AIndex := LFirstDeleted
      else
        AIndex := LIdx;
      Exit;
    end;

    if LBucket.State = TVirtualBucketState.Deleted then
    begin
      // Track first deleted slot for reuse
      if LFirstDeleted < 0 then
        LFirstDeleted := LIdx;
    end
    else if (LBucket.Hash = AHash) and FComparer.Equals(LBucket.Key, AKey) then
    begin
      AIndex := LIdx;
      Result := True;
      Exit;
    end;

    LIdx := (LIdx + 1) mod FCapacity;
  until LIdx = LStartIdx;

  // Table full (shouldn't happen with proper load factor)
  if LFirstDeleted >= 0 then
    AIndex := LFirstDeleted
  else
    AIndex := -1;
end;

procedure TVirtualDirectory<TKey, TValue>.CheckGrow();
var
  LNewCapacity: Integer;
begin
  // Grow at 75% load factor
  if FCount * 4 >= FCapacity * 3 then
  begin
    LNewCapacity := FCapacity * 2;
    Rehash(LNewCapacity);
  end;
end;

procedure TVirtualDirectory<TKey, TValue>.Rehash(const ANewCapacity: Integer);
var
  LOldBuckets: TVirtualMemory<TVirtualDirectoryBucket<TKey, TValue>>;
  LOldCapacity: Integer;
  I: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
begin
  LOldBuckets := FBuckets;
  LOldCapacity := FCapacity;

  FCapacity := ANewCapacity;
  FCount := 0;
  FBuckets := TVirtualMemory<TVirtualDirectoryBucket<TKey, TValue>>.Create();
  FBuckets.Allocate(UInt64(ANewCapacity));
  FBuckets.ZeroMemory();

  for I := 0 to LOldCapacity - 1 do
  begin
    LBucket := LOldBuckets[I];
    if LBucket.State = TVirtualBucketState.Occupied then
      Add(LBucket.Key, LBucket.Value);
  end;

  LOldBuckets.Free();
end;

procedure TVirtualDirectory<TKey, TValue>.Add(const AKey: TKey;
  const AValue: TValue);
var
  LHash: UInt32;
  LIdx: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
begin
  CheckGrow();

  LHash := UInt32(FComparer.GetHashCode(AKey));
  if FindBucket(AKey, LHash, LIdx) then
    raise EArgumentException.Create('Key already exists in directory');

  if LIdx < 0 then
    raise EInvalidOperation.Create('Directory is full');

  LBucket.Hash := LHash;
  LBucket.Key := AKey;
  LBucket.Value := AValue;
  LBucket.State := TVirtualBucketState.Occupied;
  FBuckets[LIdx] := LBucket;
  Inc(FCount);
end;

function TVirtualDirectory<TKey, TValue>.Remove(const AKey: TKey): Boolean;
var
  LHash: UInt32;
  LIdx: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
begin
  LHash := UInt32(FComparer.GetHashCode(AKey));
  Result := FindBucket(AKey, LHash, LIdx);
  if Result then
  begin
    LBucket := FBuckets[LIdx];
    LBucket.State := TVirtualBucketState.Deleted;
    FBuckets[LIdx] := LBucket;
    Dec(FCount);
  end;
end;

function TVirtualDirectory<TKey, TValue>.TryGetValue(const AKey: TKey;
  out AValue: TValue): Boolean;
var
  LHash: UInt32;
  LIdx: Integer;
begin
  LHash := UInt32(FComparer.GetHashCode(AKey));
  Result := FindBucket(AKey, LHash, LIdx);
  if Result then
    AValue := FBuckets[LIdx].Value;
end;

function TVirtualDirectory<TKey, TValue>.ContainsKey(const AKey: TKey): Boolean;
var
  LHash: UInt32;
  LIdx: Integer;
begin
  LHash := UInt32(FComparer.GetHashCode(AKey));
  Result := FindBucket(AKey, LHash, LIdx);
end;

function TVirtualDirectory<TKey, TValue>.GetItem(const AKey: TKey): TValue;
var
  LHash: UInt32;
  LIdx: Integer;
begin
  LHash := UInt32(FComparer.GetHashCode(AKey));
  if not FindBucket(AKey, LHash, LIdx) then
    raise EArgumentException.Create('Key not found in directory');
  Result := FBuckets[LIdx].Value;
end;

procedure TVirtualDirectory<TKey, TValue>.SetItem(const AKey: TKey;
  const AValue: TValue);
var
  LHash: UInt32;
  LIdx: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
begin
  LHash := UInt32(FComparer.GetHashCode(AKey));
  if FindBucket(AKey, LHash, LIdx) then
  begin
    // Update existing
    LBucket := FBuckets[LIdx];
    LBucket.Value := AValue;
    FBuckets[LIdx] := LBucket;
  end
  else
  begin
    // Insert new
    CheckGrow();
    LHash := UInt32(FComparer.GetHashCode(AKey));
    FindBucket(AKey, LHash, LIdx);
    if LIdx < 0 then
      raise EInvalidOperation.Create('Directory is full');
    LBucket.Hash := LHash;
    LBucket.Key := AKey;
    LBucket.Value := AValue;
    LBucket.State := TVirtualBucketState.Occupied;
    FBuckets[LIdx] := LBucket;
    Inc(FCount);
  end;
end;

procedure TVirtualDirectory<TKey, TValue>.Clear();
begin
  FBuckets.ZeroMemory();
  FCount := 0;
end;

procedure TVirtualDirectory<TKey, TValue>.ForEach(
  const ACallback: TForEachCallback);
var
  LI: Integer;
  LBucket: TVirtualDirectoryBucket<TKey, TValue>;
begin
  for LI := 0 to FCapacity - 1 do
  begin
    LBucket := FBuckets[LI];
    if LBucket.State = TVirtualBucketState.Occupied then
      ACallback(LBucket.Key, LBucket.Value);
  end;
end;

end.
