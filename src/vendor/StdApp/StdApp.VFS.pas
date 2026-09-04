{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.VFS - Virtual file system with custom VPK archive format

  Memory-mapped virtual file system using a custom packed archive
  format (VPK). Built entirely on TVirtualMemory<Byte> from
  StdApp.VirtualMemory -- all memory mapping, file I/O, and buffer
  management are delegated to TVirtualMemory, eliminating raw OS
  handle management. The packer uses sparse-file-backed allocation
  for the archive buffer, allowing large archives with no commit
  charge limits. Archive reading uses file-backed read-only mapping
  for transparent OS paging.

  Key types:
  - TVFS: Archive reader -- Open (memory-maps the VPK), FileExist,
    OpenFile (returns TVirtualMemoryView<Byte>), ListFiles, Close
  - TVFSPackCallback: Progress callback for archive building
  - TVFSHeader / TVFSEntry: On-disk archive structures

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources,
    StdApp.VirtualMemory
===============================================================================}

unit StdApp.VFS;

{$I StdApp.Defines.inc}

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  StdApp.VirtualMemory;

const
  VFS_MAGIC: array[0..3] of AnsiChar = 'VPK0';
  VFS_VERSION = 1;
  VFS_FILE_EXTENSION = 'vpk';

  // VFS Error Codes
  VFS_ERR_OPEN_FILE       = 'VFS01';
  VFS_ERR_INVALID_MAGIC   = 'VFS04';
  VFS_ERR_INVALID_VERSION = 'VFS05';
  VFS_ERR_TRUNCATED       = 'VFS06';
  VFS_ERR_NOT_OPEN        = 'VFS07';
  VFS_ERR_ENTRY_NOT_FOUND = 'VFS08';
  VFS_ERR_SCAN_DIR        = 'VFS10';
  VFS_ERR_EMPTY_DIR       = 'VFS11';
  VFS_ERR_SOURCE_OPEN     = 'VFS13';
  VFS_ERR_EXCEPTION       = 'VFS15';

type

  { TVFSHeader }
  TVFSHeader = packed record
    Magic: array[0..3] of AnsiChar;
    Version: UInt32;
    EntryCount: UInt32;
    DataStartOffset: UInt64;
    Reserved: array[0..31] of Byte;
  end;

  { TVFSEntry }
  TVFSEntry = packed record
    EntryPath: array[0..259] of Char;
    Offset: UInt64;
    EntrySize: UInt64;
    Checksum: UInt32;
    Flags: UInt32;
  end;

  { TVFSPackStatus }
  TVFSPackStatus = (
    cpsStarting,
    cpsFileBegin,
    cpsFileEnd,
    cpsCompleted,
    cpsError
  );

  { TVFSPackInfo }
  TVFSPackInfo = record
    Status: TVFSPackStatus;
    Filename: string;
    EntryPath: string;
    FileIndex: Integer;
    FileCount: Integer;
    FileSize: UInt64;
    BytesWritten: UInt64;
    TotalBytes: UInt64;
    ErrorMessage: string;
  end;

  { TVFSPackCallback }
  TVFSPackCallback = reference to procedure(
    const AInfo: TVFSPackInfo;
    var ACancel: Boolean;
    const AUserData: Pointer
  );

  { TVFS }
  TVFS = class(TBaseObject)
  private
    FArchive: TVirtualMemory<Byte>;
    FHeader: TVFSHeader;
    FEntries: TArray<TVFSEntry>;
    FLookup: TDictionary<string, Integer>;
    FIsOpen: Boolean;
    class function NormalizePath(const APath: string): string; static;
    class function ComputeCRC32(const AData: Pointer;
      const ASize: UInt64): UInt32; static;
    class procedure SetEntryPath(var AEntry: TVFSEntry;
      const APath: string); static;
    class function GetEntryPath(
      const AEntry: TVFSEntry): string; static;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function Open(const AFilename: string): Boolean;
    procedure Close();
    function IsOpen(): Boolean;
    function FileExists(const APath: string): Boolean;
    function OpenFile(
      const APath: string): TVirtualMemoryView<Byte>;
    function GetFileSize(const APath: string): UInt64;
    function EntryCount(): Integer;
    function ListFiles(): TArray<string>; overload;
    function ListFiles(
      const ADirectory: string): TArray<string>; overload;
    function PackDirectory(
      const ASourceDir: string;
      const AOutputFile: string;
      const ACallback: TVFSPackCallback = nil;
      const AUserData: Pointer = nil
    ): Boolean;
  end;

implementation

var
  GCRC32Table: array[0..255] of UInt32;

procedure InitCRC32Table();
var
  LIndex: Integer;
  LBit: Integer;
  LCRC: UInt32;
begin
  for LIndex := 0 to 255 do
  begin
    LCRC := UInt32(LIndex);
    for LBit := 0 to 7 do
    begin
      if (LCRC and 1) <> 0 then
        LCRC := (LCRC shr 1) xor $EDB88320
      else
        LCRC := LCRC shr 1;
    end;
    GCRC32Table[LIndex] := LCRC;
  end;
end;

{ TVFS }

class function TVFS.NormalizePath(const APath: string): string;
begin
  Result := APath.Replace('\', '/').ToLower();
end;

class function TVFS.ComputeCRC32(const AData: Pointer;
  const ASize: UInt64): UInt32;
var
  LPtr: PByte;
  LRemaining: UInt64;
begin
  Result := $FFFFFFFF;
  LPtr := PByte(AData);
  LRemaining := ASize;
  while LRemaining > 0 do
  begin
    Result := GCRC32Table[(Result xor LPtr^) and $FF] xor (Result shr 8);
    Inc(LPtr);
    Dec(LRemaining);
  end;
  Result := Result xor $FFFFFFFF;
end;

class procedure TVFS.SetEntryPath(var AEntry: TVFSEntry;
  const APath: string);
var
  LLen: Integer;
begin
  FillChar(AEntry.EntryPath, SizeOf(AEntry.EntryPath), 0);
  LLen := Length(APath);
  if LLen > 259 then
    LLen := 259;
  if LLen > 0 then
    CopyMemory(@AEntry.EntryPath[0], PChar(APath), LLen * SizeOf(Char));
end;

class function TVFS.GetEntryPath(
  const AEntry: TVFSEntry): string;
var
  LLen: Integer;
begin
  LLen := 0;
  while (LLen < 260) and (AEntry.EntryPath[LLen] <> #0) do
    Inc(LLen);
  SetString(Result, PChar(@AEntry.EntryPath[0]), LLen);
end;

constructor TVFS.Create();
begin
  inherited Create();
  FArchive := TVirtualMemory<Byte>.Create();
  FLookup := TDictionary<string, Integer>.Create();
  FIsOpen := False;
end;

destructor TVFS.Destroy();
begin
  Close();
  FLookup.Free();
  FArchive.Free();
  inherited;
end;

function TVFS.Open(const AFilename: string): Boolean;
var
  LFilename: string;
  LHeaderPtr: Pointer;
  LEntryPtr: Pointer;
  LIndex: Integer;
  LPath: string;
begin
  Result := False;
  Close();

  // Force the canonical extension
  LFilename := TPath.ChangeExtension(AFilename, VFS_FILE_EXTENSION);

  // Open archive as read-only memory-mapped file
  if not FArchive.Open(LFilename, TVirtualMemoryMode.ReadOnly) then
  begin
    GetErrors().Add(esError, VFS_ERR_OPEN_FILE,
      RSVFSOpenFileFailed, [LFilename]);
    Exit;
  end;

  // Validate minimum size for header
  if FArchive.Size < UInt64(SizeOf(TVFSHeader)) then
  begin
    GetErrors().Add(esError, VFS_ERR_TRUNCATED, RSVFSTruncated);
    FArchive.Close();
    Exit;
  end;

  // Read header from mapped memory
  LHeaderPtr := FArchive.Memory;
  CopyMemory(@FHeader, LHeaderPtr, SizeOf(TVFSHeader));

  // Validate magic signature
  if (FHeader.Magic[0] <> VFS_MAGIC[0]) or
     (FHeader.Magic[1] <> VFS_MAGIC[1]) or
     (FHeader.Magic[2] <> VFS_MAGIC[2]) or
     (FHeader.Magic[3] <> VFS_MAGIC[3]) then
  begin
    GetErrors().Add(esError, VFS_ERR_INVALID_MAGIC,
      RSVFSInvalidMagic);
    FArchive.Close();
    Exit;
  end;

  // Validate version
  if FHeader.Version <> VFS_VERSION then
  begin
    GetErrors().Add(esError, VFS_ERR_INVALID_VERSION,
      RSVFSInvalidVersion, [FHeader.Version]);
    FArchive.Close();
    Exit;
  end;

  // Validate file size covers the full directory
  if FArchive.Size < UInt64(SizeOf(TVFSHeader)) +
     (UInt64(FHeader.EntryCount) * UInt64(SizeOf(TVFSEntry))) then
  begin
    GetErrors().Add(esError, VFS_ERR_TRUNCATED, RSVFSTruncated);
    FArchive.Close();
    Exit;
  end;

  // Read directory entries from mapped memory
  SetLength(FEntries, FHeader.EntryCount);
  if FHeader.EntryCount > 0 then
  begin
    LEntryPtr := Pointer(
      UIntPtr(FArchive.Memory) + UIntPtr(SizeOf(TVFSHeader)));
    CopyMemory(@FEntries[0], LEntryPtr,
      UInt64(FHeader.EntryCount) * UInt64(SizeOf(TVFSEntry)));
  end;

  // Build lookup dictionary (paths already normalized from pack)
  FLookup.Clear();
  for LIndex := 0 to Integer(FHeader.EntryCount) - 1 do
  begin
    LPath := GetEntryPath(FEntries[LIndex]);
    FLookup.AddOrSetValue(LPath, LIndex);
  end;

  FIsOpen := True;
  Result := True;
end;

procedure TVFS.Close();
begin
  FLookup.Clear();
  SetLength(FEntries, 0);
  FillChar(FHeader, SizeOf(FHeader), 0);
  FArchive.Close();
  FIsOpen := False;
end;

function TVFS.IsOpen(): Boolean;
begin
  Result := FIsOpen;
end;

function TVFS.FileExists(const APath: string): Boolean;
begin
  Result := FIsOpen and FLookup.ContainsKey(NormalizePath(APath));
end;

function TVFS.OpenFile(
  const APath: string): TVirtualMemoryView<Byte>;
var
  LIndex: Integer;
  LEntry: TVFSEntry;
begin
  if not FIsOpen then
    raise EInvalidOperation.Create('VFS archive is not open');

  if not FLookup.TryGetValue(NormalizePath(APath), LIndex) then
    raise EFileNotFoundException.Create(
      'Entry not found in VFS: ' + APath);

  LEntry := FEntries[LIndex];

  // CreateView with byte offset and byte count (T=Byte, so 1:1)
  Result := FArchive.CreateView(LEntry.Offset, LEntry.EntrySize);
end;

function TVFS.GetFileSize(const APath: string): UInt64;
var
  LIndex: Integer;
begin
  if not FIsOpen then
  begin
    GetErrors().Add(esError, VFS_ERR_NOT_OPEN, RSVFSNotOpen);
    Result := 0;
    Exit;
  end;

  if not FLookup.TryGetValue(NormalizePath(APath), LIndex) then
  begin
    GetErrors().Add(esError, VFS_ERR_ENTRY_NOT_FOUND,
      RSVFSEntryNotFound, [APath]);
    Result := 0;
    Exit;
  end;

  Result := FEntries[LIndex].EntrySize;
end;

function TVFS.EntryCount(): Integer;
begin
  if FIsOpen then
    Result := Integer(FHeader.EntryCount)
  else
    Result := 0;
end;

function TVFS.ListFiles(): TArray<string>;
var
  LIndex: Integer;
begin
  SetLength(Result, Length(FEntries));
  for LIndex := 0 to High(FEntries) do
    Result[LIndex] := GetEntryPath(FEntries[LIndex]);
end;

function TVFS.ListFiles(
  const ADirectory: string): TArray<string>;
var
  LPrefix: string;
  LList: TList<string>;
  LIndex: Integer;
  LPath: string;
begin
  LPrefix := NormalizePath(ADirectory);

  // Ensure prefix ends with /
  if (LPrefix <> '') and (not LPrefix.EndsWith('/')) then
    LPrefix := LPrefix + '/';

  LList := TList<string>.Create();
  try
    for LIndex := 0 to High(FEntries) do
    begin
      LPath := GetEntryPath(FEntries[LIndex]);
      if LPath.StartsWith(LPrefix) then
        LList.Add(LPath);
    end;
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TVFS.PackDirectory(
  const ASourceDir: string;
  const AOutputFile: string;
  const ACallback: TVFSPackCallback;
  const AUserData: Pointer
): Boolean;
var
  LFiles: TArray<string>;
  LFileCount: Integer;
  LTotalDataSize: UInt64;
  LFileSizes: TArray<UInt64>;
  LRelPaths: TArray<string>;
  LIndex: Integer;
  LHeaderSize: UInt64;
  LDirSize: UInt64;
  LDataStart: UInt64;
  LArchiveSize: UInt64;
  LArchive: TVirtualMemory<Byte>;
  LSource: TVirtualMemory<Byte>;
  LHeader: TVFSHeader;
  LEntries: TArray<TVFSEntry>;
  LCurrentOffset: UInt64;
  LBytesWritten: UInt64;
  LInfo: TVFSPackInfo;
  LCancel: Boolean;
  LBaseDir: string;
  LOutputFile: string;
begin
  Result := False;

  try
    // Validate source directory
    if not TDirectory.Exists(ASourceDir) then
    begin
      GetErrors().Add(esError, VFS_ERR_SCAN_DIR,
        RSVFSScanDirFailed, [ASourceDir]);
      Exit;
    end;

    // Force canonical extension on output
    LOutputFile := TPath.ChangeExtension(AOutputFile, VFS_FILE_EXTENSION);

    // Scan all files recursively
    LFiles := TDirectory.GetFiles(ASourceDir, '*',
      TSearchOption.soAllDirectories);
    LFileCount := Length(LFiles);
    if LFileCount = 0 then
    begin
      GetErrors().Add(esError, VFS_ERR_EMPTY_DIR,
        RSVFSEmptyDirectory, [ASourceDir]);
      Exit;
    end;

    // Collect sizes and relative paths
    SetLength(LFileSizes, LFileCount);
    SetLength(LRelPaths, LFileCount);
    LTotalDataSize := 0;
    LBaseDir := IncludeTrailingPathDelimiter(ASourceDir);

    for LIndex := 0 to LFileCount - 1 do
    begin
      LFileSizes[LIndex] := UInt64(TFile.GetSize(LFiles[LIndex]));
      LTotalDataSize := LTotalDataSize + LFileSizes[LIndex];
      LRelPaths[LIndex] := NormalizePath(
        Copy(LFiles[LIndex], Length(LBaseDir) + 1, MaxInt));
    end;

    // Compute layout
    LHeaderSize := UInt64(SizeOf(TVFSHeader));
    LDirSize := UInt64(LFileCount) * UInt64(SizeOf(TVFSEntry));
    LDataStart := LHeaderSize + LDirSize;
    LArchiveSize := LDataStart + LTotalDataSize;

    // Fire cpsStarting callback
    if Assigned(ACallback) then
    begin
      FillChar(LInfo, SizeOf(LInfo), 0);
      LInfo.Status := TVFSPackStatus.cpsStarting;
      LInfo.FileCount := LFileCount;
      LInfo.TotalBytes := LTotalDataSize;
      LCancel := False;
      ACallback(LInfo, LCancel, AUserData);
      if LCancel then
        Exit;
    end;

    // Build directory entries with pre-computed offsets
    SetLength(LEntries, LFileCount);
    LCurrentOffset := LDataStart;
    for LIndex := 0 to LFileCount - 1 do
    begin
      FillChar(LEntries[LIndex], SizeOf(TVFSEntry), 0);
      SetEntryPath(LEntries[LIndex], LRelPaths[LIndex]);
      LEntries[LIndex].Offset := LCurrentOffset;
      LEntries[LIndex].EntrySize := LFileSizes[LIndex];
      LEntries[LIndex].Flags := 0;
      LCurrentOffset := LCurrentOffset + LFileSizes[LIndex];
    end;

    // Allocate the archive buffer via sparse temp file (no commit
    // charge -- pages only consume disk when written)
    LArchive := TVirtualMemory<Byte>.Create();
    try
      LArchive.SetErrors(GetErrors());
      if not LArchive.Allocate(LArchiveSize) then
        Exit;

      // Write header
      FillChar(LHeader, SizeOf(LHeader), 0);
      Move(VFS_MAGIC, LHeader.Magic, SizeOf(LHeader.Magic));
      LHeader.Version := VFS_VERSION;
      LHeader.EntryCount := UInt32(LFileCount);
      LHeader.DataStartOffset := LDataStart;
      CopyMemory(LArchive.Memory, @LHeader, SizeOf(TVFSHeader));

      // Copy file data and compute checksums
      LBytesWritten := 0;
      LSource := TVirtualMemory<Byte>.Create();
      try
        for LIndex := 0 to LFileCount - 1 do
        begin
          // Fire cpsFileBegin
          if Assigned(ACallback) then
          begin
            LInfo.Status := TVFSPackStatus.cpsFileBegin;
            LInfo.Filename := LFiles[LIndex];
            LInfo.EntryPath := LRelPaths[LIndex];
            LInfo.FileIndex := LIndex + 1;
            LInfo.FileCount := LFileCount;
            LInfo.FileSize := LFileSizes[LIndex];
            LInfo.BytesWritten := LBytesWritten;
            LInfo.TotalBytes := LTotalDataSize;
            LInfo.ErrorMessage := '';
            LCancel := False;
            ACallback(LInfo, LCancel, AUserData);
            if LCancel then
              Exit;
          end;

          // Copy file data (skip zero-size files)
          if LFileSizes[LIndex] > 0 then
          begin
            // Memory-map the source file for reading
            if not LSource.Open(LFiles[LIndex],
              TVirtualMemoryMode.ReadOnly) then
            begin
              GetErrors().Add(esError, VFS_ERR_SOURCE_OPEN,
                RSVFSSourceOpenFailed, [LFiles[LIndex]]);
              if Assigned(ACallback) then
              begin
                LInfo.Status := TVFSPackStatus.cpsError;
                LInfo.ErrorMessage :=
                  'Failed to open: ' + LFiles[LIndex];
                LCancel := False;
                ACallback(LInfo, LCancel, AUserData);
              end;
              Exit;
            end;

            // Copy source data into archive buffer
            CopyMemory(
              Pointer(UIntPtr(LArchive.Memory) +
                UIntPtr(LEntries[LIndex].Offset)),
              LSource.Memory,
              LFileSizes[LIndex]);

            // Compute CRC32 checksum from the source data
            LEntries[LIndex].Checksum := ComputeCRC32(
              LSource.Memory, LFileSizes[LIndex]);

            LSource.Close();
          end;

          LBytesWritten := LBytesWritten + LFileSizes[LIndex];

          // Fire cpsFileEnd
          if Assigned(ACallback) then
          begin
            LInfo.Status := TVFSPackStatus.cpsFileEnd;
            LInfo.BytesWritten := LBytesWritten;
            LCancel := False;
            ACallback(LInfo, LCancel, AUserData);
            if LCancel then
              Exit;
          end;
        end;
      finally
        LSource.Free();
      end;

      // Write directory entries (after checksums are computed)
      if LFileCount > 0 then
        CopyMemory(
          Pointer(UIntPtr(LArchive.Memory) +
            UIntPtr(SizeOf(TVFSHeader))),
          @LEntries[0],
          UInt64(LFileCount) * UInt64(SizeOf(TVFSEntry)));

      // Save archive to disk
      LArchive.SaveToFile(LOutputFile);
      Result := True;

      // Fire cpsCompleted
      if Assigned(ACallback) then
      begin
        LInfo.Status := TVFSPackStatus.cpsCompleted;
        LInfo.BytesWritten := LBytesWritten;
        LInfo.ErrorMessage := '';
        LCancel := False;
        ACallback(LInfo, LCancel, AUserData);
      end;
    finally
      LArchive.Free();
    end;
  except
    on E: Exception do
    begin
      GetErrors().Add(esError, VFS_ERR_EXCEPTION,
        RSVFSException, [E.Message]);
    end;
  end;
end;

initialization
  InitCRC32Table();

end.
