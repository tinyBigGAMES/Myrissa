{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.VMM - Zero-dependency size-class free list memory manager

  Fully self-contained Delphi memory manager with NO uses clause.
  All WinAPI functions are declared directly -- no unit dependencies
  means no finalization-order leaks.

  Add this unit FIRST in the .dpr uses clause.

  Architecture:
  - 64 GB pool via CreateFileMapping with SEC_RESERVE (no commit charge
    until pages are touched -- only physical RAM used counts)
  - Pages committed on demand in 1 MB chunks via VirtualAlloc
  - 26 size classes from 16 to 65536 bytes, each with a singly-linked free list
  - GetMem: pop from free list (O(1)) or bump-allocate from pool
  - FreeMem: push onto free list (O(1)) -- real recycling, no coalescing needed
  - ReallocMem: same class = no-op, different = alloc+copy+free
  - Allocations > 64K use multi-slice bump (contiguous 64K slices from pool)
  - No old MM fallback for new allocations -- halts on pool exhaustion

  Edge cases:
  - GetMem(0) returns nil
  - FreeMem(nil) is a no-op
  - ReallocMem(nil, N) acts as GetMem(N)
  - ReallocMem(P, 0) acts as FreeMem(P)
  - Pre-VMM pointers (allocated before this MM was installed) are forwarded
    to the old memory manager for FreeMem/ReallocMem

  Lifecycle:
  - Installed in the initialization section, uninstalled in finalization
  - Stats output uses ExitProcessProc to print after all unit finalization

  Command-line options:
  - --mm-pool <MB>   Set pool size in megabytes (default: 65536)
  - --mm-stats       Print allocation statistics on exit

  Dependencies: none (fully self-contained -- no uses clause)
===============================================================================}

unit StdApp.VMM;

{$I StdApp.Defines.inc}

interface

implementation

// *** NO USES CLAUSE — fully self-contained ***

const
  //==========================================================================
  // WinAPI Constants
  //==========================================================================
  PAGE_READWRITE = $04;
  WIN_STD_INPUT  = Cardinal($FFFFFFF6); // STD_INPUT_HANDLE
  WIN_STD_OUTPUT = Cardinal($FFFFFFF5); // STD_OUTPUT_HANDLE
  INVALID_HANDLE = NativeUInt($FFFFFFFFFFFFFFFF); // INVALID_HANDLE_VALUE
  FILE_MAP_ALL   = $000F001F; // FILE_MAP_ALL_ACCESS
  SEC_RESERVE    = $04000000; // Reserve address space only, no commit charge
  MEM_COMMIT     = $00001000; // Commit reserved pages

  //==========================================================================
  // ANSI Color Escape Sequences (raw bytes, no string allocation)
  //==========================================================================
  ESC = AnsiChar(#27);

  //==========================================================================
  // Memory Manager Constants
  //==========================================================================
  // Block header layout (16 bytes): [0..7] NativeUInt requested size,
  // [8] Byte class index, [12..15] UInt32 slice count (4-byte aligned).
  // Slice count MUST be wider than a Byte: oversized blocks use 64K
  // slices, so a Byte caps at 255 slices (~16 MB) and silently truncates
  // larger blocks, corrupting free/realloc/reuse accounting.
  MM_HEADER_SIZE = 16;
  MM_DEFAULT_POOL_SIZE: NativeUInt = $1000000000; // 64 GB (SEC_RESERVE, no commit charge)
  MM_COMMIT_GRANULARITY = $100000; // 1 MB commit chunks
  MM_CLASS_COUNT = 26;
  MM_MAX_POOL_SIZE = 65536;

  { MM_SIZES }
  MM_SIZES: array[0..MM_CLASS_COUNT - 1] of NativeUInt = (
    16, 32, 48, 64, 80, 96, 112, 128,
    192, 256, 384, 512,
    768, 1024, 1536, 2048,
    3072, 4096, 6144, 8192,
    12288, 16384, 24576, 32768, 49152, 65536
  );

//=============================================================================
// WinAPI Function Declarations
//=============================================================================

function CreateFileMappingA(
  hFile: NativeUInt;
  lpAttributes: Pointer;
  flProtect: Cardinal;
  dwMaximumSizeHigh: Cardinal;
  dwMaximumSizeLow: Cardinal;
  lpName: PAnsiChar
): NativeUInt; stdcall; external 'kernel32.dll' name 'CreateFileMappingA';

function MapViewOfFile(
  hFileMappingObject: NativeUInt;
  dwDesiredAccess: Cardinal;
  dwFileOffsetHigh: Cardinal;
  dwFileOffsetLow: Cardinal;
  dwNumberOfBytesToMap: NativeUInt
): Pointer; stdcall; external 'kernel32.dll' name 'MapViewOfFile';

function UnmapViewOfFile(
  lpBaseAddress: Pointer
): LongBool; stdcall; external 'kernel32.dll' name 'UnmapViewOfFile';

function CloseHandle(
  hObject: NativeUInt
): LongBool; stdcall; external 'kernel32.dll' name 'CloseHandle';

function VirtualAlloc(
  lpAddress: Pointer;
  dwSize: NativeUInt;
  flAllocationType: Cardinal;
  flProtect: Cardinal
): Pointer; stdcall; external 'kernel32.dll' name 'VirtualAlloc';

function GetStdHandle(
  nStdHandle: Cardinal
): NativeUInt; stdcall; external 'kernel32.dll' name 'GetStdHandle';

function WriteFile(
  hFile: NativeUInt;
  const lpBuffer;
  nNumberOfBytesToWrite: Cardinal;
  var lpNumberOfBytesWritten: Cardinal;
  lpOverlapped: Pointer
): LongBool; stdcall; external 'kernel32.dll' name 'WriteFile';

function ReadFile(
  hFile: NativeUInt;
  var lpBuffer;
  nNumberOfBytesToRead: Cardinal;
  var lpNumberOfBytesRead: Cardinal;
  lpOverlapped: Pointer
): LongBool; stdcall; external 'kernel32.dll' name 'ReadFile';

function GetCommandLineA(): PAnsiChar; stdcall;
  external 'kernel32.dll' name 'GetCommandLineA';

function IsDebuggerPresent(): LongBool; stdcall;
  external 'kernel32.dll' name 'IsDebuggerPresent';

function GetEnvironmentVariableA(
  lpName: PAnsiChar;
  lpBuffer: PAnsiChar;
  nSize: Cardinal
): Cardinal; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';

type
  { PFreeBlock }
  PFreeBlock = ^TFreeBlock;

  { TFreeBlock }
  TFreeBlock = record
    Next: PFreeBlock;
  end;

var
  // Free lists — one per size class, plus oversized
  GFreeLists: array[0..MM_CLASS_COUNT - 1] of PFreeBlock;
  GOversizedFreeList: PFreeBlock;

  // Direct lookup: 16-byte quantum index → class index
  GClassLookup: array[0..(MM_MAX_POOL_SIZE div 16) - 1] of Byte;

  // The single pool
  GPoolBase: PByte;
  GPoolSize: NativeUInt;
  GBumpPos: NativeUInt;
  GCommittedPos: NativeUInt;
  GMappingHandle: NativeUInt;

  // Saved and custom MM
  GOldMM: TMemoryManagerEx;
  GNewMM: TMemoryManagerEx;

  // Stats
  GAllocCount: NativeUInt;
  GFreeCount: NativeUInt;
  GReuseCount: NativeUInt;
  GBytesAllocated: NativeUInt;
  GBytesFreed: NativeUInt;
  GCurrentUsed: NativeUInt;
  GPeakUsed: NativeUInt;
  GOldMMFreeCount: NativeUInt;

  // Console handle (cached)
  GConsoleHandle: NativeUInt;

  // Options
  GShowStats: Boolean;

  // Saved exit handler
  GOldExitProcessProc: procedure;
  GExitHandlerCalled: Boolean;

//=============================================================================
// Console Output Helpers (stack-based, zero heap allocation)
//=============================================================================

{ RawWrite - write raw bytes to console }
procedure RawWrite(const ABuf: PAnsiChar; ALen: Cardinal);
var
  LWritten: Cardinal;
begin
  WriteFile(GConsoleHandle, ABuf^, ALen, LWritten, nil);
end;

{ RawWriteStr - write null-terminated AnsiChar string }
procedure RawWriteStr(const AStr: PAnsiChar);
var
  LLen: Cardinal;
  LP: PAnsiChar;
begin
  LP := AStr;
  LLen := 0;
  while LP^ <> #0 do
  begin
    Inc(LP);
    Inc(LLen);
  end;
  if LLen > 0 then
    RawWrite(AStr, LLen);
end;

{ RawWriteInt - write integer to console }
procedure RawWriteInt(AValue: NativeUInt);
var
  LBuf: array[0..31] of AnsiChar;
  LPos: Integer;
  LDigit: NativeUInt;
begin
  if AValue = 0 then
  begin
    RawWrite('0', 1);
    Exit;
  end;

  LPos := 31;
  while AValue > 0 do
  begin
    LDigit := AValue mod 10;
    LBuf[LPos] := AnsiChar(Ord('0') + LDigit);
    AValue := AValue div 10;
    Dec(LPos);
  end;
  Inc(LPos);
  RawWrite(@LBuf[LPos], Cardinal(32 - LPos));
end;

{ RawWriteLn - write newline }
procedure RawWriteLn();
begin
  RawWrite(#13#10, 2);
end;

{ RawColor - write ANSI color escape }
procedure RawColor(const ACode: PAnsiChar);
var
  LEsc: AnsiChar;
begin
  LEsc := ESC;
  RawWrite(@LEsc, 1);
  RawWriteStr(ACode);
end;

{ RawReset - reset ANSI color }
procedure RawReset();
begin
  RawColor('[0m');
end;

//=============================================================================
// Size Class Helpers
//=============================================================================

{ InitClassLookup }
procedure InitClassLookup();
var
  LQuantum: Integer;
  LSize: NativeUInt;
  LClass: Integer;
begin
  for LQuantum := 0 to (MM_MAX_POOL_SIZE div 16) - 1 do
  begin
    LSize := NativeUInt(LQuantum + 1) * 16;
    LClass := 0;
    while (LClass < MM_CLASS_COUNT - 1) and (MM_SIZES[LClass] < LSize) do
      Inc(LClass);
    GClassLookup[LQuantum] := Byte(LClass);
  end;
end;

{ SizeToClass }
function SizeToClass(ASize: NativeUInt): Integer; inline;
begin
  if ASize = 0 then
    ASize := 1;
  Result := GClassLookup[(ASize + 15) shr 4 - 1];
end;

{ IsPoolPointer }
function IsPoolPointer(P: Pointer): Boolean; inline;
var
  LAddr: NativeUInt;
begin
  if (P = nil) or (GPoolBase = nil) or (GPoolSize = 0) then
  begin
    Result := False;
    Exit;
  end;
  LAddr := NativeUInt(P);
  Result := (LAddr >= NativeUInt(GPoolBase)) and
            (LAddr < NativeUInt(GPoolBase) + GPoolSize);
end;

//=============================================================================
// Memory Manager Implementation
//=============================================================================

{ PoolExhausted - fatal: print diagnostic and halt }
procedure PoolExhausted(const ARequestedSize: NativeUInt);
begin
  RawWriteLn();
  RawColor('[31m'); // red
  RawWriteStr('  VMM FATAL: pool exhausted');
  RawReset();
  RawWriteLn();
  RawWriteStr('  Pool size: ');
  RawWriteInt(GPoolSize div $100000);
  RawWriteStr(' MB, used: ');
  RawWriteInt(GBumpPos div 1024);
  RawWriteStr(' KB, requested: ');
  RawWriteInt(ARequestedSize);
  RawWriteStr(' bytes');
  RawWriteLn();
  RawWriteStr('  Use --mm-pool <MB> to increase pool size.');
  RawWriteLn();
  Halt(3);
end;

{ EnsureCommitted }
procedure EnsureCommitted(const ANeededPos: NativeUInt);
var
  LCommitSize: NativeUInt;
begin
  if ANeededPos <= GCommittedPos then
    Exit;
  // Round up to commit granularity
  LCommitSize := ((ANeededPos - GCommittedPos) + MM_COMMIT_GRANULARITY - 1)
    and not (MM_COMMIT_GRANULARITY - 1);
  // Clamp to pool boundary
  if GCommittedPos + LCommitSize > GPoolSize then
    LCommitSize := GPoolSize - GCommittedPos;
  if LCommitSize = 0 then
    Exit;
  if VirtualAlloc(GPoolBase + GCommittedPos, LCommitSize,
    MEM_COMMIT, PAGE_READWRITE) = nil then
    PoolExhausted(LCommitSize);
  Inc(GCommittedPos, LCommitSize);
end;

{ VMGetMem }
function VMGetMem(Size: NativeInt): Pointer;
var
  LClass: Integer;
  LClassSize: NativeUInt;
  LBlock: PFreeBlock;
  LBlockStart: NativeUInt;
  LUserStart: NativeUInt;
  LNextPos: NativeUInt;
  LSliceCount: NativeUInt;
  LTotalSize: NativeUInt;
  LSliceStride: NativeUInt;
  LPrev: PFreeBlock;
  LFreeSlices: NativeUInt;
begin
  if Size <= 0 then
  begin
    Result := nil;
    Exit;
  end;

  Inc(GAllocCount);

  // Oversized — multi-slice allocation using 64K slices
  if NativeUInt(Size) > MM_MAX_POOL_SIZE then
  begin
    LClass := MM_CLASS_COUNT - 1; // class 25 = 65536
    LClassSize := MM_SIZES[LClass];
    LSliceCount := (NativeUInt(Size) + LClassSize - 1) div LClassSize;
    LSliceStride := MM_HEADER_SIZE + LClassSize;
    LTotalSize := LSliceCount * LSliceStride;

    // Check oversized free list for a block with enough slices
    LPrev := nil;
    LBlock := GOversizedFreeList;
    while LBlock <> nil do
    begin
      LFreeSlices := PUInt32(PByte(LBlock) - MM_HEADER_SIZE + SizeOf(NativeUInt) + 4)^;
      if LFreeSlices >= LSliceCount then
      begin
        // Remove from oversized free list
        if LPrev = nil then
          GOversizedFreeList := LBlock^.Next
        else
          LPrev^.Next := LBlock^.Next;
        Inc(GReuseCount);
        Inc(GBytesAllocated, LFreeSlices * LClassSize);
        Inc(GCurrentUsed, LFreeSlices * LClassSize);
        if GCurrentUsed > GPeakUsed then
          GPeakUsed := GCurrentUsed;
        // Update header with new size, keep original slice count
        PNativeUInt(PByte(LBlock) - MM_HEADER_SIZE)^ := NativeUInt(Size);
        Result := Pointer(LBlock);
        Exit;
      end;
      LPrev := LBlock;
      LBlock := LBlock^.Next;
    end;

    // No match in free list — bump-allocate contiguous slices
    LBlockStart := (GBumpPos + 15) and not NativeUInt(15);
    LUserStart := LBlockStart + MM_HEADER_SIZE;
    LNextPos := LBlockStart + LTotalSize;

    if LNextPos > GPoolSize then
      PoolExhausted(NativeUInt(Size));

    EnsureCommitted(LNextPos);

    // Write header on first slice only: size, class, slice count
    // (user data spans across remaining slices — no intermediate headers)
    PNativeUInt(GPoolBase + LBlockStart)^ := NativeUInt(Size);
    PByte(GPoolBase + LBlockStart + SizeOf(NativeUInt))^ := Byte(LClass);
    PUInt32(GPoolBase + LBlockStart + SizeOf(NativeUInt) + 4)^ := UInt32(LSliceCount);

    Result := GPoolBase + LUserStart;
    GBumpPos := LNextPos;
    Inc(GBytesAllocated, LSliceCount * LClassSize);
    Inc(GCurrentUsed, LSliceCount * LClassSize);
    if GCurrentUsed > GPeakUsed then
      GPeakUsed := GCurrentUsed;
    Exit;
  end;

  LClass := SizeToClass(NativeUInt(Size));
  LClassSize := MM_SIZES[LClass];

  // Fast path: pop from free list
  LBlock := GFreeLists[LClass];
  if LBlock <> nil then
  begin
    GFreeLists[LClass] := LBlock^.Next;
    Inc(GReuseCount);
    Inc(GBytesAllocated, LClassSize);
    Inc(GCurrentUsed, LClassSize);
    if GCurrentUsed > GPeakUsed then
      GPeakUsed := GCurrentUsed;
    // Write full header — block may be a recycled multi-slice sub-block
    PNativeUInt(PByte(LBlock) - MM_HEADER_SIZE)^ := NativeUInt(Size);
    PByte(PByte(LBlock) - MM_HEADER_SIZE + SizeOf(NativeUInt))^ := Byte(LClass);
    PUInt32(PByte(LBlock) - MM_HEADER_SIZE + SizeOf(NativeUInt) + 4)^ := 1;
    Result := Pointer(LBlock);
    Exit;
  end;

  // Slow path: bump-allocate from pool (all free lists empty)
  LBlockStart := (GBumpPos + 15) and not NativeUInt(15);
  LUserStart := LBlockStart + MM_HEADER_SIZE;
  LNextPos := LUserStart + LClassSize;

  // Pool exhausted — halt
  if LNextPos > GPoolSize then
    PoolExhausted(NativeUInt(Size));

  EnsureCommitted(LNextPos);

  // Write header: [original size][class index][slice count]
  PNativeUInt(GPoolBase + LBlockStart)^ := NativeUInt(Size);
  PByte(GPoolBase + LBlockStart + SizeOf(NativeUInt))^ := Byte(LClass);
  PUInt32(GPoolBase + LBlockStart + SizeOf(NativeUInt) + 4)^ := 1;

  Result := GPoolBase + LUserStart;
  GBumpPos := LNextPos;
  Inc(GBytesAllocated, LClassSize);
  Inc(GCurrentUsed, LClassSize);
  if GCurrentUsed > GPeakUsed then
    GPeakUsed := GCurrentUsed;
end;

{ VMFreeMem }
function VMFreeMem(P: Pointer): Integer;
var
  LClass: Integer;
  LSliceCount: NativeUInt;
  LBlock: PFreeBlock;
begin
  if P = nil then
  begin
    Result := 0;
    Exit;
  end;

  Inc(GFreeCount);

  // Pre-VMM allocation — forward to original MM
  if not IsPoolPointer(P) then
  begin
    Inc(GOldMMFreeCount);
    Result := GOldMM.FreeMem(P);
    Exit;
  end;

  LClass := PByte(PByte(P) - MM_HEADER_SIZE + SizeOf(NativeUInt))^;
  LSliceCount := PUInt32(PByte(P) - MM_HEADER_SIZE + SizeOf(NativeUInt) + 4)^;

  if LSliceCount = 1 then
  begin
    // Single slice — push onto free list
    LBlock := PFreeBlock(P);
    LBlock^.Next := GFreeLists[LClass];
    GFreeLists[LClass] := LBlock;
    Inc(GBytesFreed, MM_SIZES[LClass]);
    Dec(GCurrentUsed, MM_SIZES[LClass]);
  end
  else
  begin
    // Multi-slice — push whole block onto oversized free list
    LBlock := PFreeBlock(P);
    LBlock^.Next := GOversizedFreeList;
    GOversizedFreeList := LBlock;
    Inc(GBytesFreed, LSliceCount * MM_SIZES[LClass]);
    Dec(GCurrentUsed, LSliceCount * MM_SIZES[LClass]);
  end;

  Result := 0;
end;

{ VMReallocMem }
function VMReallocMem(P: Pointer; Size: NativeInt): Pointer;
var
  LOldClass: Integer;
  LOldSliceCount: NativeUInt;
  LNewClass: Integer;
  LOldSize: NativeUInt;
  LOldCapacity: NativeUInt;
  LCopySize: NativeUInt;
begin
  // ReallocMem(nil, Size) = GetMem(Size)
  if P = nil then
  begin
    Result := VMGetMem(Size);
    Exit;
  end;

  // ReallocMem(P, 0) = FreeMem(P) + return nil
  if Size <= 0 then
  begin
    VMFreeMem(P);
    Result := nil;
    Exit;
  end;

  // Pre-VMM allocation — forward to original MM
  if not IsPoolPointer(P) then
  begin
    Result := GOldMM.ReallocMem(P, Size);
    Exit;
  end;

  LOldClass := PByte(PByte(P) - MM_HEADER_SIZE + SizeOf(NativeUInt))^;
  LOldSliceCount := PUInt32(PByte(P) - MM_HEADER_SIZE + SizeOf(NativeUInt) + 4)^;
  LOldSize := PNativeUInt(PByte(P) - MM_HEADER_SIZE)^;
  LOldCapacity := LOldSliceCount * MM_SIZES[LOldClass];

  // Fast path: new size fits in current capacity — update stored size only
  if NativeUInt(Size) <= LOldCapacity then
  begin
    // For single-slice, also check if class changes (downsize frees memory)
    if (LOldSliceCount = 1) and (NativeUInt(Size) <= MM_MAX_POOL_SIZE) then
    begin
      LNewClass := SizeToClass(NativeUInt(Size));
      if LNewClass = LOldClass then
      begin
        PNativeUInt(PByte(P) - MM_HEADER_SIZE)^ := NativeUInt(Size);
        Result := P;
        Exit;
      end;
    end
    else if LOldSliceCount > 1 then
    begin
      // Multi-slice: fits in existing capacity, just update size
      PNativeUInt(PByte(P) - MM_HEADER_SIZE)^ := NativeUInt(Size);
      Result := P;
      Exit;
    end;
  end;

  // Different class or capacity — alloc, copy, free
  Result := VMGetMem(Size);
  if Result <> nil then
  begin
    LCopySize := LOldSize;
    if NativeUInt(Size) < LCopySize then
      LCopySize := NativeUInt(Size);
    Move(P^, Result^, LCopySize);
  end;
  VMFreeMem(P);
end;

{ VMAllocMem }
function VMAllocMem(Size: NativeInt): Pointer;
begin
  Result := VMGetMem(Size);
  if (Result <> nil) and (Size > 0) then
    FillChar(Result^, Size, 0);
end;

{ VMRegisterLeak }
function VMRegisterLeak(P: Pointer): Boolean;
begin
  Result := False;
end;

{ VMUnregisterLeak }
function VMUnregisterLeak(P: Pointer): Boolean;
begin
  Result := False;
end;

//=============================================================================
// Command-Line Parsing (raw, no heap allocation)
//=============================================================================

{ MatchArg - check if PAnsiChar starts with a given null-terminated string }
function MatchArg(const ASrc: PAnsiChar; const AMatch: PAnsiChar): Boolean;
var
  LS: PAnsiChar;
  LM: PAnsiChar;
begin
  LS := ASrc;
  LM := AMatch;
  while (LM^ <> #0) do
  begin
    if LS^ <> LM^ then
    begin
      Result := False;
      Exit;
    end;
    Inc(LS);
    Inc(LM);
  end;
  Result := True;
end;

{ ParseInt - parse decimal integer from PAnsiChar, returns 0 on failure }
function ParseInt(const ASrc: PAnsiChar): NativeUInt;
var
  LP: PAnsiChar;
begin
  Result := 0;
  LP := ASrc;
  while (LP^ >= '0') and (LP^ <= '9') do
  begin
    Result := Result * 10 + NativeUInt(Ord(LP^) - Ord('0'));
    Inc(LP);
  end;
end;

{ ParseCommandLine }
procedure ParseCommandLine();
var
  LP: PAnsiChar;
  LValue: NativeUInt;
begin
  GShowStats := False;
  GPoolSize := MM_DEFAULT_POOL_SIZE;

  LP := GetCommandLineA();
  if LP = nil then
    Exit;

  // Skip past the executable name
  if LP^ = '"' then
  begin
    Inc(LP);
    while (LP^ <> #0) and (LP^ <> '"') do Inc(LP);
    if LP^ = '"' then Inc(LP);
  end
  else
  begin
    while (LP^ <> #0) and (LP^ <> ' ') do Inc(LP);
  end;

  // Scan for --mm-stats and --mm-pool
  while LP^ <> #0 do
  begin
    // Skip whitespace
    while LP^ = ' ' do Inc(LP);
    if LP^ = #0 then Break;

    if MatchArg(LP, '--mm-stats') then
      GShowStats := True
    else if MatchArg(LP, '--mm-pool') then
    begin
      // Skip past '--mm-pool'
      Inc(LP, 9);
      while LP^ = ' ' do Inc(LP);
      LValue := ParseInt(LP);
      if LValue > 0 then
        GPoolSize := LValue * $100000; // megabytes
    end;

    // Skip to next whitespace
    while (LP^ <> #0) and (LP^ <> ' ') do Inc(LP);
  end;
end;

//=============================================================================
// Stats and Lifecycle
//=============================================================================

{ PrintStats }
procedure PrintStats();
var
  I: Integer;
  LFreeListItems: NativeUInt;
  LBlock: PFreeBlock;
  LPoolAllocs: NativeUInt;
  LPoolFrees: NativeUInt;
  LLeakedBytes: NativeUInt;
  LLeakedCount: NativeUInt;
  LReadBuf: AnsiChar;
  LBytesRead: Cardinal;
begin
  {$IFDEF RELEASE}
  if not GShowStats then
    Exit;
  {$ENDIF}

  LFreeListItems := 0;
  for I := 0 to MM_CLASS_COUNT - 1 do
  begin
    LBlock := GFreeLists[I];
    while LBlock <> nil do
    begin
      Inc(LFreeListItems);
      LBlock := LBlock^.Next;
    end;
  end;

  // Count oversized free list items
  LBlock := GOversizedFreeList;
  while LBlock <> nil do
  begin
    Inc(LFreeListItems);
    LBlock := LBlock^.Next;
  end;

  LPoolAllocs := GAllocCount;
  LPoolFrees := GFreeCount - GOldMMFreeCount;
  LLeakedBytes := GBytesAllocated - GBytesFreed;
  LLeakedCount := LPoolAllocs - LPoolFrees;

  RawWriteLn();

  // Header
  RawColor('[36m'); // cyan
  RawWriteStr('  -- StdApp Virtual MM --');
  RawReset();
  RawWriteLn();

  // Pool line
  RawWriteStr('  Pool: ');
  RawColor('[33m'); // yellow
  RawWriteInt(GPoolSize div $100000);
  RawWriteStr(' MB');
  RawReset();
  RawWriteStr(' reserved, ');
  RawColor('[33m');
  RawWriteInt(GCommittedPos div 1024);
  RawWriteStr(' KB');
  RawReset();
  RawWriteStr(' committed');
  RawWriteLn();

  // Current / Peak line
  RawWriteStr('  Current: ');
  RawColor('[32m'); // green
  RawWriteInt(GCurrentUsed div 1024);
  RawWriteStr(' KB');
  RawReset();
  RawWriteStr('  Peak: ');
  RawColor('[33m'); // yellow
  RawWriteInt(GPeakUsed div 1024);
  RawWriteStr(' KB');
  RawReset();
  RawWriteLn();

  // Pool allocs line
  RawWriteStr('  Pool allocs: ');
  RawColor('[32m'); // green
  RawWriteInt(LPoolAllocs);
  RawReset();
  RawWriteStr('  frees: ');
  RawColor('[32m');
  RawWriteInt(LPoolFrees);
  RawReset();
  RawWriteStr('  reused: ');
  RawColor('[32m');
  RawWriteInt(GReuseCount);
  RawReset();
  RawWriteLn();

  // OldMM line
  RawWriteStr('  OldMM frees: ');
  RawColor('[33m');
  RawWriteInt(GOldMMFreeCount);
  RawReset();
  RawWriteLn();

  // Leaks line
  RawWriteStr('  Allocated: ');
  RawColor('[32m');
  RawWriteInt(GBytesAllocated div 1024);
  RawWriteStr(' KB');
  RawReset();
  RawWriteStr('  Freed: ');
  RawColor('[32m');
  RawWriteInt(GBytesFreed div 1024);
  RawWriteStr(' KB');
  RawReset();
  RawWriteStr('  Leaks: ');
  if LLeakedCount > 0 then
    RawColor('[31m')  // red
  else
    RawColor('[32m'); // green

  if LLeakedBytes >= 1024 then
  begin
    RawWriteInt(LLeakedBytes div 1024);
    RawWriteStr(' KB');
  end
  else
  begin
    RawWriteInt(LLeakedBytes);
    RawWriteStr(' bytes');
  end;
  RawWriteStr(' (');
  RawWriteInt(LLeakedCount);
  RawWriteStr(' blocks)');
  RawReset();
  RawWriteLn();

  // Free list line
  RawWriteStr('  Free list items: ');
  RawColor('[33m');
  RawWriteInt(LFreeListItems);
  RawReset();
  RawWriteLn();

  // Pause if running from IDE (BDS environment variable is set)
  if GetEnvironmentVariableA('BDS', nil, 0) > 0 then
  begin
    RawWriteLn();
    RawWriteStr('  Press ENTER to continue...');
    // Use raw ReadFile on stdin — Delphi I/O is finalized at this point
    ReadFile(GetStdHandle(WIN_STD_INPUT), LReadBuf, 1, LBytesRead, nil);
  end;
end;

{ VMMExitHandler - runs after all unit finalization via ExitProcessProc }
procedure VMMExitHandler();
begin
  // Guard against re-entrant calls (runtime errors trigger Halt → ExitProcessProc)
  if GExitHandlerCalled then
    Exit;
  GExitHandlerCalled := True;

  // All frees (including System/SysInit) have completed by now
  SetMemoryManager(GOldMM);
  PrintStats();

  // Release the pool
  if GPoolBase <> nil then
  begin
    UnmapViewOfFile(GPoolBase);
    GPoolBase := nil;
  end;
  if GMappingHandle <> 0 then
  begin
    CloseHandle(GMappingHandle);
    GMappingHandle := 0;
  end;
  GPoolSize := 0;
  GBumpPos := 0;

  // Chain to previous handler
  if Assigned(GOldExitProcessProc) then
    GOldExitProcessProc();
end;

{ Startup }
procedure Startup();
var
  I: Integer;
begin
  // Ensure we are first
  if IsMemoryManagerSet() then
    Halt(1);

  InitClassLookup();
  ParseCommandLine();

  for I := 0 to MM_CLASS_COUNT - 1 do
    GFreeLists[I] := nil;
  GOversizedFreeList := nil;

  GBumpPos := 0;
  GCommittedPos := 0;
  GAllocCount := 0;
  GFreeCount := 0;
  GReuseCount := 0;
  GBytesAllocated := 0;
  GBytesFreed := 0;
  GCurrentUsed := 0;
  GPeakUsed := 0;
  GOldMMFreeCount := 0;
  GExitHandlerCalled := False;

  // Save current MM
  GetMemoryManager(GOldMM);

  // Allocate the pool via CreateFileMapping + MapViewOfFile
  // SEC_RESERVE: reserve address space only, no commit charge upfront
  // Pages are committed on demand via VirtualAlloc in EnsureCommitted
  GMappingHandle := CreateFileMappingA(
    INVALID_HANDLE, nil, PAGE_READWRITE or SEC_RESERVE,
    Cardinal(GPoolSize shr 32),   // high 32 bits of size
    Cardinal(GPoolSize),          // low 32 bits of size
    nil);
  if GMappingHandle = 0 then
    Halt(2);

  GPoolBase := MapViewOfFile(GMappingHandle, FILE_MAP_ALL, 0, 0, 0);
  if GPoolBase = nil then
  begin
    CloseHandle(GMappingHandle);
    Halt(2);
  end;

  // Cache console handle
  GConsoleHandle := GetStdHandle(WIN_STD_OUTPUT);

  // Wire up custom MM
  GNewMM.GetMem := VMGetMem;
  GNewMM.FreeMem := VMFreeMem;
  GNewMM.ReallocMem := VMReallocMem;
  GNewMM.AllocMem := VMAllocMem;
  GNewMM.RegisterExpectedMemoryLeak := VMRegisterLeak;
  GNewMM.UnregisterExpectedMemoryLeak := VMUnregisterLeak;

  // Switch
  SetMemoryManager(GNewMM);

  // Register exit handler — runs after all unit finalization
  GOldExitProcessProc := ExitProcessProc;
  ExitProcessProc := VMMExitHandler;
end;

initialization
  Startup();

end.
