{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Packer - Manifest-driven release zip builder (AppPacker core)

  Builds release archives from a small YAML-subset manifest. All relative
  paths in the manifest (source paths, output, seckey) resolve against the
  MANIFEST FILE's directory, so invocation CWD is irrelevant. Supports the
  legacy flat form (root:/include:/exclude:) and the multi-source form
  (sources: list with per-source path/prefix/include/exclude). Optional
  .sha256 checksum emission and native minisign-compatible signing via
  StdApp.Crypto. Refuses (fatal) to archive the configured secret key file.

  Key types:
  - TPackSource: one source tree (path, archive prefix, include/exclude)
  - TSignConfig: signing settings from the sign: block
  - TPackEntry: resolved file -> archive path mapping
  - TPacker: LoadManifest / DiscoverFiles / Build

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Crypto, StdApp.Resources
===============================================================================}

unit StdApp.Packer;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Masks,
  System.Zip,
  System.Generics.Collections,
  System.Generics.Defaults,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Crypto,
  StdApp.Resources;

const
  { ERR_PAK_MANIFEST }
  ERR_PAK_MANIFEST = 'PAK001';

  { ERR_PAK_NOFILES }
  ERR_PAK_NOFILES = 'PAK002';

  { ERR_PAK_ZIP }
  ERR_PAK_ZIP = 'PAK003';

  { ERR_PAK_SECKEY }
  ERR_PAK_SECKEY = 'PAK004';

  { ERR_PAK_SIGN }
  ERR_PAK_SIGN = 'PAK005';

  { ERR_PAK_PARSE }
  ERR_PAK_PARSE = 'PAK006';

  { ERR_PAK_CHECKSUM }
  ERR_PAK_CHECKSUM = 'PAK007';

type
  { TPackSource }
  TPackSource = record
    SourcePath: string;            // resolved absolute directory
    Prefix: string;                // archive path prefix ('' = none)
    IncludeGlobs: TArray<string>;
    ExcludeGlobs: TArray<string>;  // per-source extras; global excludes also apply
  end;

  { TSignConfig }
  TSignConfig = record
    Enabled: Boolean;
    SecretKeyFile: string;         // resolved absolute
    TrustedComment: string;        // optional; {name}/{version} expanded
    UntrustedComment: string;      // optional
  end;

  { TPackEntry }
  TPackEntry = record
    FullPath: string;
    ArchivePath: string;
  end;

  { TPacker }
  TPacker = class(TBaseObject)
  private
    FManifestDir: string;
    FPackName: string;
    FVersion: string;
    FOutput: string;
    FRootValue: string;
    FSources: TList<TPackSource>;
    FGlobalExclude: TArray<string>;
    FTopInclude: TArray<string>;
    FStoreExts: TArray<string>;
    FChecksum: Boolean;
    FVerbose: Boolean;
    FSign: TSignConfig;
    FEntries: TList<TPackEntry>;
    // manifest parsing
    function DoIndentOf(const ALine: string): Integer;
    function DoTrimComment(const ALine: string): string;
    function DoUnquote(const AText: string): string;
    function DoSplitKeyValue(const AText: string; out AKey, AValue: string): Boolean;
    function DoParseBool(const AValue: string): Boolean;
    function DoParseManifest(const ALines: TArray<string>): Boolean;
    function DoExpandPlaceholders(const AText: string): string;
    function DoResolvePath(const APath: string): string;
    procedure DoResolve();
    // discovery
    function DoNormalizeGlob(const APattern: string): string;
    function DoRelativePath(const ABaseDir, AFullPath: string): string;
    function DoMatchesAny(const ABaseDir, AFullPath: string; const AGlobs: TArray<string>): Boolean;
    procedure DoCollectGlob(const ABaseDir, APattern: string; const AFound: TList<string>);
    function DoGuardSecretKey(): Boolean;
    // build
    function DoStoreUncompressed(const APath: string): Boolean;
    function DoBuildZip(): Boolean;
    function DoWriteChecksum(): Boolean;
    function DoSignOutput(): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function LoadManifest(const AFilename: string): Boolean;
    function DiscoverFiles(): Boolean;
    function Build(): Boolean;
    function FileCount(): Integer;
    property PackName: string read FPackName;
    property Version: string read FVersion;
    property Output: string read FOutput;
    property Verbose: Boolean read FVerbose write FVerbose;
  end;

implementation

const
  { CDefaultStoreExts }
  CDefaultStoreExts: array[0..6] of string = (
    '.png', '.jpg', '.jpeg', '.zip', '.ogg', '.mp3', '.mp4');

type
  { TManifestSection }
  TManifestSection = (
    msTop,
    msTopList,
    msSources,
    msSourceList,
    msSign
  );

{ TPacker }

constructor TPacker.Create();
var
  LIndex: Integer;
begin
  inherited Create();
  FSources := TList<TPackSource>.Create();
  FEntries := TList<TPackEntry>.Create();
  FChecksum := False;
  FVerbose := False;
  FSign := Default(TSignConfig);
  FRootValue := '.';
  SetLength(FStoreExts, Length(CDefaultStoreExts));
  for LIndex := 0 to High(CDefaultStoreExts) do
    FStoreExts[LIndex] := CDefaultStoreExts[LIndex];
end;

destructor TPacker.Destroy();
begin
  FEntries.Free();
  FSources.Free();
  inherited Destroy();
end;

function TPacker.DoIndentOf(const ALine: string): Integer;
var
  LIndex: Integer;
begin
  Result := 0;
  for LIndex := 1 to Length(ALine) do
  begin
    if ALine[LIndex] = ' ' then
      Inc(Result)
    else
      Break;
  end;
end;

function TPacker.DoTrimComment(const ALine: string): string;
var
  LPos: Integer;
  LInQuote: Boolean;
  LIndex: Integer;
begin
  // Strip a trailing # comment that is not inside quotes
  LPos := 0;
  LInQuote := False;
  for LIndex := 1 to Length(ALine) do
  begin
    if (ALine[LIndex] = '"') or (ALine[LIndex] = '''') then
      LInQuote := not LInQuote
    else if (ALine[LIndex] = '#') and (not LInQuote) then
    begin
      LPos := LIndex;
      Break;
    end;
  end;
  if LPos > 0 then
    Result := Copy(ALine, 1, LPos - 1).Trim()
  else
    Result := ALine.Trim();
end;

function TPacker.DoUnquote(const AText: string): string;
begin
  Result := AText.Trim();
  if (Length(Result) >= 2) and
     (((Result[1] = '"') and (Result[Length(Result)] = '"')) or
      ((Result[1] = '''') and (Result[Length(Result)] = ''''))) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function TPacker.DoSplitKeyValue(const AText: string; out AKey, AValue: string): Boolean;
var
  LPos: Integer;
begin
  LPos := Pos(':', AText);
  Result := LPos > 0;
  if Result then
  begin
    AKey := Copy(AText, 1, LPos - 1).Trim().ToLower();
    AValue := DoUnquote(Copy(AText, LPos + 1, MaxInt).Trim());
  end
  else
  begin
    AKey := '';
    AValue := '';
  end;
end;

function TPacker.DoParseBool(const AValue: string): Boolean;
begin
  Result := SameText(AValue, 'true') or SameText(AValue, 'yes') or (AValue = '1');
end;

function TPacker.DoParseManifest(const ALines: TArray<string>): Boolean;
var
  LSection: TManifestSection;
  LListKey: string;
  LSrcListKey: string;
  LDashIndent: Integer;
  LLineNo: Integer;
  LRaw: string;
  LText: string;
  LIndent: Integer;
  LKey: string;
  LValue: string;
  LCur: TPackSource;
  LInSource: Boolean;
  LTopIncl: TList<string>;
  LTopExcl: TList<string>;
  LStore: TList<string>;
  LSrcIncl: TList<string>;
  LSrcExcl: TList<string>;
  LRest: string;

  procedure DoCloseSource();
  begin
    if LInSource then
    begin
      LCur.IncludeGlobs := LSrcIncl.ToArray();
      LCur.ExcludeGlobs := LSrcExcl.ToArray();
      FSources.Add(LCur);
      LSrcIncl.Clear();
      LSrcExcl.Clear();
      LInSource := False;
    end;
  end;

  procedure DoApplySourceKey();
  begin
    if LKey = 'path' then
    begin
      LCur.SourcePath := LValue;
      LSection := msSources;
    end
    else if LKey = 'prefix' then
    begin
      LCur.Prefix := LValue;
      LSection := msSources;
    end
    else if (LKey = 'include') and (LValue = '') then
    begin
      LSrcListKey := 'include';
      LSection := msSourceList;
    end
    else if (LKey = 'exclude') and (LValue = '') then
    begin
      LSrcListKey := 'exclude';
      LSection := msSourceList;
    end;
  end;

begin
  Result := False;
  LSection := msTop;
  LListKey := '';
  LSrcListKey := '';
  LDashIndent := -1;
  LInSource := False;
  LCur := Default(TPackSource);
  LTopIncl := TList<string>.Create();
  LTopExcl := TList<string>.Create();
  LStore := TList<string>.Create();
  LSrcIncl := TList<string>.Create();
  LSrcExcl := TList<string>.Create();
  try
    for LLineNo := 0 to High(ALines) do
    begin
      LRaw := ALines[LLineNo];
      LText := DoTrimComment(LRaw);
      if LText = '' then
        Continue;
      LIndent := DoIndentOf(LRaw);

      if LIndent = 0 then
      begin
        // Top-level line always terminates any open source entry
        DoCloseSource();
        if not DoSplitKeyValue(LText, LKey, LValue) then
        begin
          FErrors.Add(esError, ERR_PAK_PARSE, RSPakParseError, [LLineNo + 1, LText]);
          Exit;
        end;
        if LValue = '' then
        begin
          if LKey = 'sources' then
          begin
            LSection := msSources;
            LDashIndent := -1;
          end
          else if LKey = 'sign' then
          begin
            LSection := msSign;
            FSign.Enabled := True;
          end
          else
          begin
            LSection := msTopList;
            LListKey := LKey;
          end;
        end
        else
        begin
          LSection := msTop;
          if LKey = 'name' then
            FPackName := LValue
          else if LKey = 'version' then
            FVersion := LValue
          else if LKey = 'root' then
            FRootValue := LValue
          else if LKey = 'output' then
            FOutput := LValue
          else if LKey = 'verbose' then
            FVerbose := DoParseBool(LValue)
          else if LKey = 'checksum' then
            FChecksum := DoParseBool(LValue);
          // Unknown scalar keys are ignored (forward compatible)
        end;
      end
      else
      begin
        case LSection of
          msTopList:
          begin
            if LText.StartsWith('-') then
            begin
              LValue := DoUnquote(Copy(LText, 2, MaxInt).Trim());
              if LListKey = 'include' then
                LTopIncl.Add(LValue)
              else if LListKey = 'exclude' then
                LTopExcl.Add(LValue)
              else if LListKey = 'store_exts' then
                LStore.Add(LValue.ToLower());
            end;
          end;

          msSign:
          begin
            if DoSplitKeyValue(LText, LKey, LValue) then
            begin
              if LKey = 'seckey' then
                FSign.SecretKeyFile := LValue
              else if LKey = 'trusted_comment' then
                FSign.TrustedComment := LValue
              else if LKey = 'untrusted_comment' then
                FSign.UntrustedComment := LValue
              else if LKey = 'enabled' then
                FSign.Enabled := DoParseBool(LValue);
            end;
          end;

          msSources, msSourceList:
          begin
            if LText.StartsWith('-') then
            begin
              // The FIRST dash fixes the source-entry indent level. Dashes at
              // that level start a new source; deeper dashes are list items of
              // the currently open per-source include/exclude list.
              if LDashIndent < 0 then
                LDashIndent := LIndent;
              if LIndent = LDashIndent then
              begin
                DoCloseSource();
                LCur := Default(TPackSource);
                LCur.SourcePath := '.';
                LInSource := True;
                LSrcListKey := '';
                LSection := msSources;
                LRest := Copy(LText, 2, MaxInt).Trim();
                if LRest <> '' then
                begin
                  if DoSplitKeyValue(LRest, LKey, LValue) then
                    DoApplySourceKey()
                  else
                  begin
                    FErrors.Add(esError, ERR_PAK_PARSE, RSPakParseError, [LLineNo + 1, LText]);
                    Exit;
                  end;
                end;
              end
              else
              begin
                LValue := DoUnquote(Copy(LText, 2, MaxInt).Trim());
                if LSrcListKey = 'include' then
                  LSrcIncl.Add(LValue)
                else if LSrcListKey = 'exclude' then
                  LSrcExcl.Add(LValue);
              end;
            end
            else
            begin
              if not LInSource then
              begin
                FErrors.Add(esError, ERR_PAK_PARSE, RSPakParseError, [LLineNo + 1, LText]);
                Exit;
              end;
              if DoSplitKeyValue(LText, LKey, LValue) then
                DoApplySourceKey();
            end;
          end;
        else
          // Indented content under a scalar top-level key: ignore
        end;
      end;
    end;
    DoCloseSource();
    FTopInclude := LTopIncl.ToArray();
    FGlobalExclude := LTopExcl.ToArray();
    if LStore.Count > 0 then
      FStoreExts := LStore.ToArray();
    Result := True;
  finally
    LSrcExcl.Free();
    LSrcIncl.Free();
    LStore.Free();
    LTopExcl.Free();
    LTopIncl.Free();
  end;
end;

function TPacker.DoExpandPlaceholders(const AText: string): string;
begin
  Result := AText.Replace('{name}', FPackName, [rfReplaceAll]);
  Result := Result.Replace('{version}', FVersion, [rfReplaceAll]);
end;

function TPacker.DoResolvePath(const APath: string): string;
begin
  if TPath.IsPathRooted(APath) then
    Result := TPath.GetFullPath(APath)
  else
    Result := TPath.GetFullPath(TPath.Combine(FManifestDir, APath));
end;

procedure TPacker.DoResolve();
var
  LIndex: Integer;
  LSource: TPackSource;
begin
  for LIndex := 0 to FSources.Count - 1 do
  begin
    LSource := FSources[LIndex];
    LSource.SourcePath := DoResolvePath(DoExpandPlaceholders(LSource.SourcePath));
    FSources[LIndex] := LSource;
  end;
  FOutput := DoResolvePath(DoExpandPlaceholders(FOutput));
  if FSign.Enabled and (FSign.SecretKeyFile <> '') then
    FSign.SecretKeyFile := DoResolvePath(DoExpandPlaceholders(FSign.SecretKeyFile));
end;

function TPacker.LoadManifest(const AFilename: string): Boolean;
var
  LFull: string;
  LLines: TArray<string>;
  LFlat: TPackSource;
begin
  Result := False;
  LFull := TPath.GetFullPath(AFilename);
  if not TFile.Exists(LFull) then
  begin
    FErrors.Add(esError, ERR_PAK_MANIFEST, RSPakManifestNotFound, [LFull]);
    Exit;
  end;
  FManifestDir := TPath.GetDirectoryName(LFull);
  try
    LLines := TFile.ReadAllLines(LFull, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, ERR_PAK_MANIFEST, RSPakManifestNotFound, [E.Message]);
      Exit;
    end;
  end;
  FSources.Clear();
  FEntries.Clear();
  if not DoParseManifest(LLines) then
    Exit;
  if FOutput = '' then
  begin
    FErrors.Add(esError, ERR_PAK_MANIFEST, RSPakNoOutput);
    Exit;
  end;
  // Legacy flat form: no sources: block -> synthesize one source from
  // root:/include: with no prefix. checkpoint.yml MUST behave identically.
  if FSources.Count = 0 then
  begin
    LFlat := Default(TPackSource);
    LFlat.SourcePath := FRootValue;
    LFlat.Prefix := '';
    LFlat.IncludeGlobs := FTopInclude;
    FSources.Add(LFlat);
  end;
  DoResolve();
  Result := True;
end;

function TPacker.DoNormalizeGlob(const APattern: string): string;
begin
  Result := StringReplace(APattern, '**', '*', [rfReplaceAll]);
end;

function TPacker.DoRelativePath(const ABaseDir, AFullPath: string): string;
var
  LBase: string;
begin
  // Strict prefix strip (port of UTigerPack.GetRelativePathStrict): returns
  // '' when AFullPath is not under ABaseDir; forward-slash separators.
  LBase := IncludeTrailingPathDelimiter(TPath.GetFullPath(ABaseDir));
  Result := TPath.GetFullPath(AFullPath);
  if Result.StartsWith(LBase, True) then
    Result := Copy(Result, Length(LBase) + 1, MaxInt).Replace('\', '/')
  else
    Result := '';
end;

function TPacker.DoMatchesAny(const ABaseDir, AFullPath: string; const AGlobs: TArray<string>): Boolean;
var
  LRel: string;
  LFileName: string;
  LIndex: Integer;
  LMask: string;
begin
  Result := False;
  if Length(AGlobs) = 0 then
    Exit;
  LRel := DoRelativePath(ABaseDir, AFullPath);
  LFileName := TPath.GetFileName(AFullPath);
  for LIndex := 0 to High(AGlobs) do
  begin
    LMask := DoNormalizeGlob(AGlobs[LIndex].Replace('\', '/'));
    if MatchesMask(LRel, LMask) or MatchesMask(LFileName, LMask) then
      Exit(True);
  end;
end;

procedure TPacker.DoCollectGlob(const ABaseDir, APattern: string; const AFound: TList<string>);
var
  LPattern: string;
  LSlash: Integer;
  LDirPart: string;
  LFilePart: string;
  LMask: string;
  LRecursive: Boolean;
  LSegments: TArray<string>;
  LHead: string;
  LIndex: Integer;
  LStartDir: string;
  LStack: TStack<string>;
  LDir: string;
  LFile: string;
  LSub: string;
begin
  LPattern := APattern.Replace('\', '/');
  LSlash := LPattern.LastIndexOf('/');
  if LSlash >= 0 then
  begin
    LDirPart := LPattern.Substring(0, LSlash);
    LFilePart := LPattern.Substring(LSlash + 1);
  end
  else
  begin
    LDirPart := '';
    LFilePart := LPattern;
  end;
  LRecursive := LPattern.Contains('**');
  // Start directory = base + leading non-wildcard segments of the dir part
  LHead := '';
  if LDirPart <> '' then
  begin
    LSegments := LDirPart.Split(['/']);
    for LIndex := 0 to High(LSegments) do
    begin
      if LSegments[LIndex].Contains('*') then
        Break;
      if LHead = '' then
        LHead := LSegments[LIndex]
      else
        LHead := LHead + '\' + LSegments[LIndex];
    end;
  end;
  if LHead = '' then
    LStartDir := ABaseDir
  else
    LStartDir := TPath.GetFullPath(TPath.Combine(ABaseDir, LHead));
  if not TDirectory.Exists(LStartDir) then
    Exit;
  LMask := DoNormalizeGlob(LFilePart);
  if LMask = '' then
    LMask := '*';
  if LRecursive then
  begin
    // Iterative subtree walk; matches the original stack-based traversal
    LStack := TStack<string>.Create();
    try
      LStack.Push(LStartDir);
      while LStack.Count > 0 do
      begin
        LDir := LStack.Pop();
        for LFile in TDirectory.GetFiles(LDir) do
        begin
          if MatchesMask(TPath.GetFileName(LFile), LMask) then
            AFound.Add(LFile);
        end;
        for LSub in TDirectory.GetDirectories(LDir) do
          LStack.Push(LSub);
      end;
    finally
      LStack.Free();
    end;
  end
  else
  begin
    for LFile in TDirectory.GetFiles(LStartDir) do
    begin
      if MatchesMask(TPath.GetFileName(LFile), LMask) then
        AFound.Add(LFile);
    end;
  end;
end;

function TPacker.DoGuardSecretKey(): Boolean;
var
  LEntry: TPackEntry;
begin
  Result := True;
  if (not FSign.Enabled) or (FSign.SecretKeyFile = '') then
    Exit;
  for LEntry in FEntries do
  begin
    if SameFileName(LEntry.FullPath, FSign.SecretKeyFile) then
    begin
      FErrors.Add(esFatal, ERR_PAK_SECKEY, RSPakSecKeyInArchive, [LEntry.FullPath]);
      Exit(False);
    end;
  end;
end;

function TPacker.DiscoverFiles(): Boolean;
var
  LSource: TPackSource;
  LFound: TList<string>;
  LSeen: TDictionary<string, Boolean>;
  LEntry: TPackEntry;
  LFile: string;
  LGlob: string;
  LRel: string;
  LPrefix: string;
begin
  Result := False;
  FEntries.Clear();
  LFound := TList<string>.Create();
  LSeen := TDictionary<string, Boolean>.Create();
  try
    for LSource in FSources do
    begin
      Status(FVerbose, RSPakSourceScan, [LSource.SourcePath, LSource.Prefix]);
      if not TDirectory.Exists(LSource.SourcePath) then
      begin
        FErrors.Add(esError, ERR_PAK_MANIFEST, RSPakSourceMissing, [LSource.SourcePath]);
        Exit;
      end;
      LFound.Clear();
      for LGlob in LSource.IncludeGlobs do
        DoCollectGlob(LSource.SourcePath, LGlob, LFound);
      LPrefix := LSource.Prefix.Replace('\', '/');
      while LPrefix.EndsWith('/') do
        LPrefix := LPrefix.Substring(0, Length(LPrefix) - 1);
      for LFile in LFound do
      begin
        if DoMatchesAny(LSource.SourcePath, LFile, LSource.ExcludeGlobs) then
          Continue;
        if DoMatchesAny(LSource.SourcePath, LFile, FGlobalExclude) then
          Continue;
        LRel := DoRelativePath(LSource.SourcePath, LFile);
        if LRel = '' then
          Continue;
        LEntry.FullPath := LFile;
        if LPrefix <> '' then
          LEntry.ArchivePath := LPrefix + '/' + LRel
        else
          LEntry.ArchivePath := LRel;
        if LSeen.ContainsKey(LEntry.ArchivePath.ToLower()) then
          Continue;
        LSeen.Add(LEntry.ArchivePath.ToLower(), True);
        FEntries.Add(LEntry);
      end;
    end;
    if FEntries.Count = 0 then
    begin
      FErrors.Add(esError, ERR_PAK_NOFILES, RSPakNoFiles);
      Exit;
    end;
    // Deterministic archive ordering
    FEntries.Sort(TComparer<TPackEntry>.Construct(
      function(const ALeft, ARight: TPackEntry): Integer
      begin
        Result := CompareText(ALeft.ArchivePath, ARight.ArchivePath);
      end));
    if not DoGuardSecretKey() then
      Exit;
    Status(FVerbose, RSPakMatched, [FEntries.Count]);
    Result := True;
  finally
    LSeen.Free();
    LFound.Free();
  end;
end;

function TPacker.DoStoreUncompressed(const APath: string): Boolean;
var
  LExt: string;
  LIndex: Integer;
begin
  Result := False;
  LExt := TPath.GetExtension(APath).ToLower();
  for LIndex := 0 to High(FStoreExts) do
  begin
    if FStoreExts[LIndex] = LExt then
      Exit(True);
  end;
end;

function TPacker.DoBuildZip(): Boolean;
var
  LZip: TZipFile;
  LEntry: TPackEntry;
  LComp: TZipCompression;
begin
  Result := False;
  try
    TUtils.CreateDirInPath(FOutput);
    if TFile.Exists(FOutput) then
      TFile.Delete(FOutput);
    LZip := TZipFile.Create();
    try
      LZip.Open(FOutput, zmWrite);
      for LEntry in FEntries do
      begin
        if DoStoreUncompressed(LEntry.FullPath) then
          LComp := TZipCompression.zcStored
        else
          LComp := TZipCompression.zcDeflate;
        Status(FVerbose, RSPakAdd, [LEntry.ArchivePath]);
        LZip.Add(LEntry.FullPath, LEntry.ArchivePath, LComp);
      end;
      LZip.Close();
    finally
      LZip.Free();
    end;
    Status(True, RSPakDone, [FEntries.Count, FOutput]);
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, ERR_PAK_ZIP, RSPakZipError, [E.Message]);
  end;
end;

function TPacker.DoWriteChecksum(): Boolean;
var
  LHash: string;
begin
  Result := False;
  try
    // sha256sum-compatible: '<lowercase hex>  <filename>' + LF
    LHash := TUtils.GetFileSHA256(FOutput).ToLower();
    TFile.WriteAllText(FOutput + '.sha256',
      LHash + '  ' + TPath.GetFileName(FOutput) + #10, TEncoding.UTF8);
    Status(True, RSPakChecksum, [FOutput + '.sha256']);
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, ERR_PAK_CHECKSUM, RSPakZipError, [E.Message]);
  end;
end;

function TPacker.DoSignOutput(): Boolean;
var
  LMini: TMinisign;
  LPair: TMiniKeyPair;
begin
  Result := False;
  if FSign.SecretKeyFile = '' then
  begin
    FErrors.Add(esError, ERR_PAK_SIGN, RSPakNoSecKey);
    Exit;
  end;
  LMini := TMinisign.Create();
  try
    // Share the error sink so crypto errors surface through the packer.
    // SetErrors borrows (no ownership transfer) -- verified in StdApp.Base.
    LMini.SetErrors(FErrors);
    if not LMini.LoadSecretKey(FSign.SecretKeyFile, LPair) then
      Exit;
    if not LMini.SignFile(FOutput, LPair,
      DoExpandPlaceholders(FSign.TrustedComment),
      DoExpandPlaceholders(FSign.UntrustedComment)) then
      Exit;
    Status(True, RSPakSigned, [FOutput + '.minisig']);
    Result := True;
  finally
    LMini.Free();
  end;
end;

function TPacker.Build(): Boolean;
begin
  Result := DoBuildZip();
  if Result and FChecksum then
    Result := DoWriteChecksum();
  if Result and FSign.Enabled then
    Result := DoSignOutput();
end;

function TPacker.FileCount(): Integer;
begin
  Result := FEntries.Count;
end;

end.
