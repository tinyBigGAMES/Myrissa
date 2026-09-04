{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.ResCompiler - Windows resource (.res) compiler and reader

  Creates and parses standard Windows .res files from in-memory data.
  Used to embed DLLs, icons, manifests, version info, and other binary
  resources into executables at build time without requiring the
  Windows SDK resource compiler (rc.exe).

  Key types:
  - TResourceCompiler: Builds .res files from TResourceEntry records --
    AddResource, AddResourceFromFile, Compile, CompileToFile
  - TResourceReader: Parses .res files back into TResourceEntry records --
    LoadFromFile, LoadFromBytes, GetEntry, EntryCount
  - TResourceEntry: Record holding type, name, language, and raw data

  Dependencies: StdApp.Base
===============================================================================}

unit StdApp.ResCompiler;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base;

const
  RES_RT_CURSOR = 1;
  RES_RT_BITMAP = 2;
  RES_RT_ICON = 3;
  RES_RT_MENU = 4;
  RES_RT_RCDATA = 10;
  RES_RT_GROUP_ICON = 14;
  RES_RT_VERSION = 16;
  RES_RT_MANIFEST = 24;
  RES_MEMORY_FLAGS = $0030;  // MOVEABLE | PURE

type
  { TResourceEntry }
  // A single resource entry: type, name, language, and raw data bytes
  TResourceEntry = record
    ResType: Word;
    ResName: string;
    LanguageId: Word;
    Data: TBytes;
  end;

  { TResourceCompiler }
  // Creates .res files from in-memory resource entries.
  // Usage:
  //   LCompiler := TMyrResourceCompiler.Create();
  //   LCompiler.AddResource(RES_RT_RCDATA, 'my_dll_data', LDllBytes);
  //   LCompiler.CompileToFile('output.res');
  //   LCompiler.Free();
  TResourceCompiler = class(TBaseObject)
  private
    FEntries: TList<TResourceEntry>;

    // Write a resource entry header to the stream
    procedure WriteResHeader(const AStream: TMemoryStream;
      const ADataSize: Cardinal; const ATypeOrdinal: Word;
      const AName: string; const ALanguageId: Word;
      const AMemoryFlags: Word = RES_MEMORY_FLAGS);

    // Pad stream to DWORD alignment
    procedure AlignStream(const AStream: TMemoryStream);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Add a resource entry from raw bytes
    procedure AddResource(const ATypeOrdinal: Word; const AName: string;
      const AData: TBytes; const ALanguageId: Word = 0);

    // Add a resource entry by reading a file from disk
    procedure AddResourceFromFile(const ATypeOrdinal: Word; const AName: string;
      const AFilePath: string; const ALanguageId: Word = 0);

    // Compile all entries into .res bytes
    function Compile(): TBytes;

    // Compile and write to disk
    procedure CompileToFile(const AOutputPath: string);

    // Number of entries
    function EntryCount(): Integer;

    // Clear all entries
    procedure Clear();
  end;

  { TResourceReader }
  // Parses .res files back into TMyrResourceEntry records.
  // Usage:
  //   LReader := TMyrResourceReader.Create();
  //   LReader.LoadFromFile('input.res');
  //   for LI := 0 to LReader.EntryCount() - 1 do
  //     ProcessEntry(LReader.GetEntry(LI));
  //   LReader.Free();
  TResourceReader = class(TBaseObject)
  private
    FEntries: TList<TResourceEntry>;

    // Read a type or name field (ordinal or string) from stream
    function ReadTypeOrName(const AStream: TMemoryStream;
      out AOrdinal: Word; out AName: string): Boolean;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Load entries from .res bytes
    procedure LoadFromBytes(const AData: TBytes);

    // Load entries from a .res file on disk
    procedure LoadFromFile(const AFilePath: string);

    // Access parsed entries
    function EntryCount(): Integer;
    function GetEntry(const AIndex: Integer): TResourceEntry;

    // Clear loaded entries
    procedure Clear();
  end;

implementation


{ TResourceCompiler }

constructor TResourceCompiler.Create();
begin
  inherited Create();
  FEntries := TList<TResourceEntry>.Create();
end;

destructor TResourceCompiler.Destroy();
begin
  FEntries.Free();
  inherited Destroy();
end;

procedure TResourceCompiler.AlignStream(const AStream: TMemoryStream);
var
  LPad: Integer;
begin
  LPad := AStream.Size mod 4;
  if LPad > 0 then
  begin
    LPad := 4 - LPad;
    while LPad > 0 do
    begin
      AStream.WriteData(Byte(0));
      Dec(LPad);
    end;
  end;
end;

procedure TResourceCompiler.WriteResHeader(const AStream: TMemoryStream;
  const ADataSize: Cardinal; const ATypeOrdinal: Word;
  const AName: string; const ALanguageId: Word;
  const AMemoryFlags: Word);
var
  LHeaderStart: Int64;
  LHeaderSize: Cardinal;
  LWideChar: Word;
  LI: Integer;
begin
  // DataSize
  AStream.WriteData(ADataSize);

  // HeaderSize placeholder -- we'll patch this after writing the header
  LHeaderStart := AStream.Position;
  AStream.WriteData(Cardinal(0));

  // Type (ordinal): $FFFF followed by the type word
  AStream.WriteData(Word($FFFF));
  AStream.WriteData(ATypeOrdinal);

  // Name: if empty, write ordinal 0; otherwise write UTF-16 null-terminated string
  // Names are uppercased to match Windows convention (brcc32 behavior)
  if AName = '' then
  begin
    AStream.WriteData(Word($FFFF));
    AStream.WriteData(Word(0));
  end
  else
  begin
    for LI := 1 to Length(AName) do
    begin
      LWideChar := Word(UpCase(AName[LI]));
      AStream.WriteData(LWideChar);
    end;
    AStream.WriteData(Word(0));  // null terminator
  end;

  // Pad to DWORD alignment after type+name
  AlignStream(AStream);

  // DataVersion
  AStream.WriteData(Cardinal(0));

  // MemoryFlags
  AStream.WriteData(AMemoryFlags);

  // LanguageId
  AStream.WriteData(ALanguageId);

  // Version
  AStream.WriteData(Cardinal(0));

  // Characteristics
  AStream.WriteData(Cardinal(0));

  // Patch HeaderSize: distance from start of DataSize field to end of header
  LHeaderSize := Cardinal(AStream.Position - (LHeaderStart - 4));
  AStream.Position := LHeaderStart;
  AStream.WriteData(LHeaderSize);
  AStream.Position := AStream.Size;  // seek back to end
end;

procedure TResourceCompiler.AddResource(const ATypeOrdinal: Word;
  const AName: string; const AData: TBytes; const ALanguageId: Word);
var
  LEntry: TResourceEntry;
begin
  LEntry.ResType := ATypeOrdinal;
  LEntry.ResName := AName;
  LEntry.LanguageId := ALanguageId;
  LEntry.Data := Copy(AData);
  FEntries.Add(LEntry);
end;

procedure TResourceCompiler.AddResourceFromFile(const ATypeOrdinal: Word;
  const AName: string; const AFilePath: string; const ALanguageId: Word);
var
  LData: TBytes;
begin
  if not TFile.Exists(AFilePath) then
  begin
    FErrors.Add(esError, 'R0001', 'Resource file not found: %s', [AFilePath], nil);
    Exit;
  end;

  try
    LData := TFile.ReadAllBytes(AFilePath);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, 'R0002', 'Failed to read resource file: %s', [E.Message], nil);
      Exit;
    end;
  end;

  AddResource(ATypeOrdinal, AName, LData, ALanguageId);
end;

function TResourceCompiler.Compile(): TBytes;
var
  LStream: TMemoryStream;
  LI: Integer;
begin
  Result := nil;

  LStream := TMemoryStream.Create();
  try
    // Mandatory dummy first entry (type=0, name=0, data=0, flags=0)
    WriteResHeader(LStream, 0, 0, '', 0, 0);

    // Write each resource entry
    for LI := 0 to FEntries.Count - 1 do
    begin
      // Write header
      WriteResHeader(LStream, Cardinal(Length(FEntries[LI].Data)),
        FEntries[LI].ResType, FEntries[LI].ResName, FEntries[LI].LanguageId);

      // Write raw data
      if Length(FEntries[LI].Data) > 0 then
        LStream.WriteBuffer(FEntries[LI].Data[0], Length(FEntries[LI].Data));

      // Pad data to DWORD alignment
      AlignStream(LStream);
    end;

    // Copy to result
    SetLength(Result, LStream.Size);
    if LStream.Size > 0 then
    begin
      LStream.Position := 0;
      LStream.ReadBuffer(Result[0], LStream.Size);
    end;
  finally
    LStream.Free();
  end;
end;

procedure TResourceCompiler.CompileToFile(const AOutputPath: string);
var
  LData: TBytes;
begin
  LData := Compile();
  if Length(LData) = 0 then
    Exit;

  try
    TFile.WriteAllBytes(AOutputPath, LData);
  except
    on E: Exception do
      FErrors.Add(esError, 'R0003', 'Failed to write .res file: %s', [E.Message], nil);
  end;
end;

function TResourceCompiler.EntryCount(): Integer;
begin
  Result := FEntries.Count;
end;

procedure TResourceCompiler.Clear();
begin
  FEntries.Clear();
end;

//==============================================================================
// TMyrResourceReader
//==============================================================================

{ TMyrResourceReader }

constructor TResourceReader.Create();
begin
  inherited Create();
  FEntries := TList<TResourceEntry>.Create();
end;

destructor TResourceReader.Destroy();
begin
  FEntries.Free();
  inherited Destroy();
end;

function TResourceReader.ReadTypeOrName(const AStream: TMemoryStream;
  out AOrdinal: Word; out AName: string): Boolean;
var
  LMarker: Word;
  LWideChar: Word;
begin
  Result := True;
  AOrdinal := 0;
  AName := '';

  if AStream.Read(LMarker, 2) <> 2 then
  begin
    Result := False;
    Exit;
  end;

  if LMarker = $FFFF then
  begin
    // Ordinal form
    if AStream.Read(AOrdinal, 2) <> 2 then
    begin
      Result := False;
      Exit;
    end;
  end
  else
  begin
    // String form -- LMarker is the first WideChar
    LWideChar := LMarker;
    while LWideChar <> 0 do
    begin
      AName := AName + Char(LWideChar);
      if AStream.Read(LWideChar, 2) <> 2 then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;
end;

procedure TResourceReader.LoadFromBytes(const AData: TBytes);
var
  LStream: TMemoryStream;
  LDataSize: Cardinal;
  LHeaderSize: Cardinal;
  LTypeOrdinal: Word;
  LTypeName: string;
  LNameOrdinal: Word;
  LNameStr: string;
  LDummy: Cardinal;
  LMemFlags: Word;
  LLangId: Word;
  LEntry: TResourceEntry;
begin
  FEntries.Clear();

  if Length(AData) = 0 then
    Exit;

  LStream := TMemoryStream.Create();
  try
    LStream.WriteBuffer(AData[0], Length(AData));
    LStream.Position := 0;

    while LStream.Position < LStream.Size do
    begin
      // Read DataSize and HeaderSize
      if LStream.Read(LDataSize, 4) <> 4 then
        Break;
      if LStream.Read(LHeaderSize, 4) <> 4 then
        Break;

      // Read Type
      if not ReadTypeOrName(LStream, LTypeOrdinal, LTypeName) then
        Break;

      // Read Name
      if not ReadTypeOrName(LStream, LNameOrdinal, LNameStr) then
        Break;

      // Align to DWORD after type+name
      if (LStream.Position mod 4) <> 0 then
        LStream.Position := LStream.Position + (4 - (LStream.Position mod 4));

      // Read DataVersion (skip)
      LStream.Read(LDummy, 4);

      // Read MemoryFlags
      LStream.Read(LMemFlags, 2);

      // Read LanguageId
      LStream.Read(LLangId, 2);

      // Read Version (skip)
      LStream.Read(LDummy, 4);

      // Read Characteristics (skip)
      LStream.Read(LDummy, 4);

      // Skip the dummy first entry (type=0, name=0)
      if (LTypeOrdinal = 0) and (LTypeName = '') and
         (LNameOrdinal = 0) and (LNameStr = '') and (LDataSize = 0) then
      begin
        // Align after data (even though data is 0 bytes)
        if (LStream.Position mod 4) <> 0 then
          LStream.Position := LStream.Position + (4 - (LStream.Position mod 4));
        Continue;
      end;

      // Build entry
      LEntry.ResType := LTypeOrdinal;
      if LNameStr <> '' then
        LEntry.ResName := LNameStr
      else
        LEntry.ResName := IntToStr(LNameOrdinal);
      LEntry.LanguageId := LLangId;

      // Read raw data
      if LDataSize > 0 then
      begin
        SetLength(LEntry.Data, LDataSize);
        LStream.ReadBuffer(LEntry.Data[0], LDataSize);
      end
      else
        LEntry.Data := nil;

      FEntries.Add(LEntry);

      // Align after data to DWORD
      if (LStream.Position mod 4) <> 0 then
        LStream.Position := LStream.Position + (4 - (LStream.Position mod 4));
    end;
  finally
    LStream.Free();
  end;
end;

procedure TResourceReader.LoadFromFile(const AFilePath: string);
var
  LData: TBytes;
begin
  if not TFile.Exists(AFilePath) then
  begin
    FErrors.Add(esError, 'R0010', 'Resource file not found: %s', [AFilePath], nil);
    Exit;
  end;

  try
    LData := TFile.ReadAllBytes(AFilePath);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, 'R0011', 'Failed to read resource file: %s', [E.Message], nil);
      Exit;
    end;
  end;

  LoadFromBytes(LData);
end;

function TResourceReader.EntryCount(): Integer;
begin
  Result := FEntries.Count;
end;

function TResourceReader.GetEntry(const AIndex: Integer): TResourceEntry;
begin
  Result := FEntries[AIndex];
end;

procedure TResourceReader.Clear();
begin
  FEntries.Clear();
end;

end.
