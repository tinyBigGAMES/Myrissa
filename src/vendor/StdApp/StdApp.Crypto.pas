{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Crypto - Cryptographic primitives and minisign-compatible signing

  Pure-Delphi Blake2b-512 (streaming) and Ed25519 (TweetNaCl port, public
  domain reference), secure random via BCryptGenRandom, and TMinisign: a
  minisign-compatible file signing layer ("ED" prehashed format). Signatures
  and public keys produced here verify with stock minisign. Secret keys use
  an AppPacker-specific UNENCRYPTED format (tag "T1") and are never compatible
  with (nor readable by) minisign itself.

  Key types:
  - TBlake2b: streaming 512-bit Blake2b (Init/Update/Finish + static helpers)
  - TEd25519: static keygen/sign/verify (detached, RFC 8032 semantics)
  - TSecureRandom: BCryptGenRandom wrapper
  - TMiniKeyPair: key id + public key + optional secret key
  - TMinisign: key file I/O, .minisig emission, verification

  Dependencies: StdApp.Base, StdApp.Resources
  Notes: x86/x64 little-endian only. Overflow/range checks intentionally off.
===============================================================================}

unit StdApp.Crypto;

{$I StdApp.Defines.inc}
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.Hash,
  System.NetEncoding,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Resources;

const
  { ERR_CRY_RANDOM }
  ERR_CRY_RANDOM = 'CRY001';

  { ERR_CRY_KEYFORMAT }
  ERR_CRY_KEYFORMAT = 'CRY002';

  { ERR_CRY_SIGFORMAT }
  ERR_CRY_SIGFORMAT = 'CRY003';

  { ERR_CRY_KEYID }
  ERR_CRY_KEYID = 'CRY004';

  { ERR_CRY_VERIFY }
  ERR_CRY_VERIFY = 'CRY005';

  { ERR_CRY_FILEIO }
  ERR_CRY_FILEIO = 'CRY006';

type
  { TBlake2b }
  TBlake2b = record
  private
    FH: array[0..7] of UInt64;
    FT: array[0..1] of UInt64;
    FBuf: array[0..127] of Byte;
    FBufLen: Integer;
    procedure DoIncCounter(const AAmount: UInt64);
    procedure DoCompress(const ALast: Boolean);
  public
    // Begin a new unkeyed 512-bit hash
    procedure Init();
    // Absorb ALength bytes from AData
    procedure Update(const AData: PByte; const ALength: NativeInt); overload;
    procedure Update(const AData: TBytes); overload;
    // Finalize and return the 64-byte digest
    function Finish(): TBytes;
    // One-shot helpers
    class function HashBytes(const AData: TBytes): TBytes; static;
    class function HashFile(const AFilename: string; out ADigest: TBytes): Boolean; static;
  end;

  { TEd25519 }
  TEd25519 = class
  public
    // ASeed must be 32 bytes. ASecretKey = seed || public (64 bytes).
    class procedure GenerateKeyPair(const ASeed: TBytes; out APublicKey: TBytes; out ASecretKey: TBytes); static;
    // Detached 64-byte signature over AMessage using 64-byte ASecretKey
    class function Sign(const AMessage: TBytes; const ASecretKey: TBytes): TBytes; static;
    // Verify detached signature
    class function Verify(const AMessage: TBytes; const ASignature: TBytes; const APublicKey: TBytes): Boolean; static;
  end;

  { TSecureRandom }
  TSecureRandom = class
  public
    class function Fill(const ABuffer: PByte; const ACount: Integer): Boolean; static;
    class function GetBytes(const ACount: Integer; out ABytes: TBytes): Boolean; static;
  end;

  { TMiniKeyPair }
  TMiniKeyPair = record
    KeyId: TBytes;      // 8 bytes
    PublicKey: TBytes;  // 32 bytes
    SecretKey: TBytes;  // 64 bytes (seed || public); empty for public-only
    function HasSecret(): Boolean;
    procedure Clear();
  end;

  { TMinisign }
  TMinisign = class(TBaseObject)
  private
    function DoEncodeB64(const AData: TBytes): string;
    function DoDecodeB64(const AText: string; out AData: TBytes): Boolean;
    function DoParsePublicBlob(const ABlob: TBytes; out AKeyPair: TMiniKeyPair;
      const ASourceName: string): Boolean;
    function DoReadKeyLines(const AFilename: string; out ABlob: TBytes): Boolean;
    function DoKeyIdHex(const AKeyId: TBytes): string;
    function DoDefaultTrustedComment(const AFilename: string): string;
  public
    // Fresh Ed25519 keypair with random 8-byte key id
    function GenerateKeyPair(out AKeyPair: TMiniKeyPair): Boolean;
    // AppPacker secret key file (tag T1, UNENCRYPTED)
    function SaveSecretKey(const AFilename: string; const AKeyPair: TMiniKeyPair): Boolean;
    function LoadSecretKey(const AFilename: string; out AKeyPair: TMiniKeyPair): Boolean;
    // minisign-format public key file / string ("Ed" || key_id || pk, 42 bytes b64)
    function SavePublicKey(const AFilename: string; const AKeyPair: TMiniKeyPair): Boolean;
    function LoadPublicKey(const AFilename: string; out AKeyPair: TMiniKeyPair): Boolean;
    function LoadPublicKeyString(const AKeyText: string; out AKeyPair: TMiniKeyPair): Boolean;
    function PublicKeyString(const AKeyPair: TMiniKeyPair): string;
    function KeyIdString(const AKeyPair: TMiniKeyPair): string;
    // Sign AFilename -> AFilename + '.minisig' (minisign "ED" prehashed format)
    function SignFile(const AFilename: string; const AKeyPair: TMiniKeyPair;
      const ATrustedComment: string = ''; const AUntrustedComment: string = ''): Boolean;
    // Verify AFilename against ASigFilename (default AFilename + '.minisig')
    function VerifyFile(const AFilename: string; const AKeyPair: TMiniKeyPair;
      const ASigFilename: string = ''): Boolean;
  end;

implementation

{ ===== Internal helpers and constants ===== }

type
  { TGf }
  // Field element, radix 2^16, 16 signed 64-bit limbs (TweetNaCl representation)
  TGf = array[0..15] of Int64;

  { TGePoint }
  // Extended Edwards point (X, Y, Z, T)
  TGePoint = array[0..3] of TGf;

  { TInt64x64 }
  TInt64x64 = array[0..63] of Int64;

const
  { CGf0 }
  CGf0: TGf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

  { CGf1 }
  CGf1: TGf = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

  { CGfD }
  CGfD: TGf = ($78a3, $1359, $4dca, $75eb, $d8ab, $4141, $0a4d, $0070,
               $e898, $7779, $4079, $8cc7, $fe73, $2b6f, $6cee, $5203);

  { CGfD2 }
  CGfD2: TGf = ($f159, $26b2, $9b94, $ebd6, $b156, $8283, $149a, $00e0,
                $d130, $eef3, $80f2, $198e, $fce7, $56df, $d9dc, $2406);

  { CGfX }
  CGfX: TGf = ($d51a, $8f25, $2d60, $c956, $a7b2, $9525, $c760, $692c,
               $dc5c, $fdd6, $e231, $c0a4, $53fe, $cd6e, $36d3, $2169);

  { CGfY }
  CGfY: TGf = ($6658, $6666, $6666, $6666, $6666, $6666, $6666, $6666,
               $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666);

  { CGfI }
  CGfI: TGf = ($a0b0, $4a0e, $1b27, $c4ee, $e478, $ad2f, $1806, $2f43,
               $d7a7, $3dfb, $0099, $2b4d, $df0b, $4fc1, $2480, $2b83);

  { CL }
  // Group order L as 32 bytes (little-endian), values held in Int64 for modL math
  CL: array[0..31] of Int64 = (
    $ed, $d3, $f5, $5c, $1a, $63, $12, $58,
    $d6, $9c, $f7, $a2, $de, $f9, $de, $14,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, $10);

  { CBlake2bIV }
  CBlake2bIV: array[0..7] of UInt64 = (
    UInt64($6A09E667F3BCC908), UInt64($BB67AE8584CAA73B),
    UInt64($3C6EF372FE94F82B), UInt64($A54FF53A5F1D36F1),
    UInt64($510E527FADE682D1), UInt64($9B05688C2B3E6C1F),
    UInt64($1F83D9ABFB41BD6B), UInt64($5BE0CD19137E2179));

  { CBlake2bSigma }
  CBlake2bSigma: array[0..11, 0..15] of Byte = (
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    (14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3),
    (11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4),
    (7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8),
    (9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13),
    (2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9),
    (12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11),
    (13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10),
    (6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5),
    (10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0),
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    (14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3));

  { CMiniSecTag }
  CMiniSecTag: array[0..1] of Byte = (Ord('T'), Ord('1'));

  { CMiniPubAlg }
  CMiniPubAlg: array[0..1] of Byte = (Ord('E'), Ord('d'));

  { CMiniSigAlg }
  // Prehashed signature algorithm tag ("ED")
  CMiniSigAlg: array[0..1] of Byte = (Ord('E'), Ord('D'));

  { BCRYPT_USE_SYSTEM_PREFERRED_RNG }
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

{ BCryptGenRandom }
function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: PByte; cbBuffer: ULONG;
  dwFlags: ULONG): Integer; stdcall; external 'bcrypt.dll';

{ Sar64 }
// Arithmetic right shift on Int64. Delphi shr is logical; TweetNaCl needs
// sign-propagating shifts on negative limbs. Do NOT replace with shr or div.
function Sar64(const AValue: Int64; const AShift: Integer): Int64; inline;
begin
  if AValue >= 0 then
    Result := AValue shr AShift
  else
    Result := not ((not AValue) shr AShift);
end;

{ Ror64 }
function Ror64(const AValue: UInt64; const ABits: Integer): UInt64; inline;
begin
  Result := (AValue shr ABits) or (AValue shl (64 - ABits));
end;

{ Sha512Parts }
// SHA-512 over the concatenation of all parts (RTL implementation)
function Sha512Parts(const AParts: array of TBytes): TBytes;
var
  LHash: THashSHA2;
  LIndex: Integer;
begin
  LHash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  for LIndex := 0 to High(AParts) do
  begin
    if Length(AParts[LIndex]) > 0 then
      LHash.Update(AParts[LIndex]);
  end;
  Result := LHash.HashAsBytes;
end;

{ ===== TBlake2b ===== }

procedure TBlake2b.Init();
var
  LI: Integer;
begin
  for LI := 0 to 7 do
    FH[LI] := CBlake2bIV[LI];
  // Parameter word: digest length 64, key length 0, fanout 1, depth 1
  FH[0] := FH[0] xor UInt64($01010040);
  FT[0] := 0;
  FT[1] := 0;
  FBufLen := 0;
  FillChar(FBuf, SizeOf(FBuf), 0);
end;

procedure TBlake2b.DoIncCounter(const AAmount: UInt64);
begin
  FT[0] := FT[0] + AAmount;
  if FT[0] < AAmount then
    FT[1] := FT[1] + 1;
end;

procedure TBlake2b.DoCompress(const ALast: Boolean);
var
  LV: array[0..15] of UInt64;
  LM: array[0..15] of UInt64;
  LI: Integer;
  LR: Integer;

  procedure DoMix(const AA, AB, AC, AD: Integer; const AX, AY: UInt64);
  begin
    LV[AA] := LV[AA] + LV[AB] + AX;
    LV[AD] := Ror64(LV[AD] xor LV[AA], 32);
    LV[AC] := LV[AC] + LV[AD];
    LV[AB] := Ror64(LV[AB] xor LV[AC], 24);
    LV[AA] := LV[AA] + LV[AB] + AY;
    LV[AD] := Ror64(LV[AD] xor LV[AA], 16);
    LV[AC] := LV[AC] + LV[AD];
    LV[AB] := Ror64(LV[AB] xor LV[AC], 63);
  end;

begin
  // Little-endian load of the 128-byte block into 16 words
  for LI := 0 to 15 do
    LM[LI] := PUInt64(@FBuf[LI * 8])^;

  for LI := 0 to 7 do
    LV[LI] := FH[LI];
  for LI := 0 to 7 do
    LV[LI + 8] := CBlake2bIV[LI];

  LV[12] := LV[12] xor FT[0];
  LV[13] := LV[13] xor FT[1];
  if ALast then
    LV[14] := not LV[14];

  for LR := 0 to 11 do
  begin
    DoMix(0, 4, 8, 12, LM[CBlake2bSigma[LR, 0]], LM[CBlake2bSigma[LR, 1]]);
    DoMix(1, 5, 9, 13, LM[CBlake2bSigma[LR, 2]], LM[CBlake2bSigma[LR, 3]]);
    DoMix(2, 6, 10, 14, LM[CBlake2bSigma[LR, 4]], LM[CBlake2bSigma[LR, 5]]);
    DoMix(3, 7, 11, 15, LM[CBlake2bSigma[LR, 6]], LM[CBlake2bSigma[LR, 7]]);
    DoMix(0, 5, 10, 15, LM[CBlake2bSigma[LR, 8]], LM[CBlake2bSigma[LR, 9]]);
    DoMix(1, 6, 11, 12, LM[CBlake2bSigma[LR, 10]], LM[CBlake2bSigma[LR, 11]]);
    DoMix(2, 7, 8, 13, LM[CBlake2bSigma[LR, 12]], LM[CBlake2bSigma[LR, 13]]);
    DoMix(3, 4, 9, 14, LM[CBlake2bSigma[LR, 14]], LM[CBlake2bSigma[LR, 15]]);
  end;

  for LI := 0 to 7 do
    FH[LI] := FH[LI] xor LV[LI] xor LV[LI + 8];
end;

procedure TBlake2b.Update(const AData: PByte; const ALength: NativeInt);
var
  LOffset: NativeInt;
  LTake: NativeInt;
begin
  LOffset := 0;
  while LOffset < ALength do
  begin
    // Only compress a full buffer when MORE input exists; the final block
    // must be compressed by Finish() with the last-block flag set.
    if FBufLen = 128 then
    begin
      DoIncCounter(128);
      DoCompress(False);
      FBufLen := 0;
    end;
    LTake := 128 - FBufLen;
    if LTake > ALength - LOffset then
      LTake := ALength - LOffset;
    Move(AData[LOffset], FBuf[FBufLen], LTake);
    FBufLen := FBufLen + LTake;
    LOffset := LOffset + LTake;
  end;
end;

procedure TBlake2b.Update(const AData: TBytes);
begin
  if Length(AData) > 0 then
    Update(@AData[0], Length(AData));
end;

function TBlake2b.Finish(): TBytes;
begin
  DoIncCounter(UInt64(FBufLen));
  if FBufLen < 128 then
    FillChar(FBuf[FBufLen], 128 - FBufLen, 0);
  DoCompress(True);
  SetLength(Result, 64);
  Move(FH[0], Result[0], 64);
end;

class function TBlake2b.HashBytes(const AData: TBytes): TBytes;
var
  LState: TBlake2b;
begin
  LState.Init();
  LState.Update(AData);
  Result := LState.Finish();
end;

class function TBlake2b.HashFile(const AFilename: string; out ADigest: TBytes): Boolean;
var
  LState: TBlake2b;
  LStream: TFileStream;
  LBuffer: TBytes;
  LRead: Integer;
begin
  Result := False;
  ADigest := nil;
  if not TFile.Exists(AFilename) then
    Exit;
  try
    LStream := TFileStream.Create(AFilename, fmOpenRead or fmShareDenyWrite);
    try
      LState.Init();
      SetLength(LBuffer, 64 * 1024);
      repeat
        LRead := LStream.Read(LBuffer[0], Length(LBuffer));
        if LRead > 0 then
          LState.Update(@LBuffer[0], LRead);
      until LRead <= 0;
      ADigest := LState.Finish();
      Result := True;
    finally
      LStream.Free;
    end;
  except
    Result := False;
  end;
end;

{ ===== Ed25519 field and point operations (TweetNaCl port) ===== }

{ Set25519 }
procedure Set25519(var AR: TGf; const AA: TGf);
var
  LI: Integer;
begin
  for LI := 0 to 15 do
    AR[LI] := AA[LI];
end;

{ Car25519 }
procedure Car25519(var AO: TGf);
var
  LI: Integer;
  LC: Int64;
begin
  for LI := 0 to 15 do
  begin
    AO[LI] := AO[LI] + (Int64(1) shl 16);
    LC := Sar64(AO[LI], 16);
    if LI < 15 then
      AO[LI + 1] := AO[LI + 1] + (LC - 1)
    else
      AO[0] := AO[0] + (LC - 1) + 37 * (LC - 1);
    AO[LI] := AO[LI] - (LC shl 16);
  end;
end;

{ Sel25519 }
// Constant-time conditional swap of two field elements (AB is 0 or 1)
procedure Sel25519(var AP, AQ: TGf; const AB: Int64);
var
  LT: Int64;
  LC: Int64;
  LI: Integer;
begin
  LC := not (AB - 1);
  for LI := 0 to 15 do
  begin
    LT := LC and (AP[LI] xor AQ[LI]);
    AP[LI] := AP[LI] xor LT;
    AQ[LI] := AQ[LI] xor LT;
  end;
end;

{ Pack25519 }
procedure Pack25519(const AO: PByte; const AN: TGf);
var
  LI: Integer;
  LJ: Integer;
  LB: Int64;
  LM: TGf;
  LT: TGf;
begin
  Set25519(LT, AN);
  Car25519(LT);
  Car25519(LT);
  Car25519(LT);
  for LJ := 0 to 1 do
  begin
    LM[0] := LT[0] - $FFED;
    for LI := 1 to 14 do
    begin
      LM[LI] := LT[LI] - $FFFF - (Sar64(LM[LI - 1], 16) and 1);
      LM[LI - 1] := LM[LI - 1] and $FFFF;
    end;
    LM[15] := LT[15] - $7FFF - (Sar64(LM[14], 16) and 1);
    LB := Sar64(LM[15], 16) and 1;
    LM[14] := LM[14] and $FFFF;
    Sel25519(LT, LM, 1 - LB);
  end;
  for LI := 0 to 15 do
  begin
    AO[2 * LI] := Byte(LT[LI] and $FF);
    AO[2 * LI + 1] := Byte((LT[LI] shr 8) and $FF);
  end;
end;

{ CryptoVerify32 }
// Constant-time compare; 0 if equal, -1 if different
function CryptoVerify32(const AX, AY: PByte): Integer;
var
  LD: Cardinal;
  LI: Integer;
begin
  LD := 0;
  for LI := 0 to 31 do
    LD := LD or Cardinal(AX[LI] xor AY[LI]);
  Result := Integer(1 and ((LD - 1) shr 8)) - 1;
end;

{ Neq25519 }
function Neq25519(const AA, AB: TGf): Integer;
var
  LC: array[0..31] of Byte;
  LD: array[0..31] of Byte;
begin
  Pack25519(@LC[0], AA);
  Pack25519(@LD[0], AB);
  Result := CryptoVerify32(@LC[0], @LD[0]);
end;

{ Par25519 }
function Par25519(const AA: TGf): Byte;
var
  LD: array[0..31] of Byte;
begin
  Pack25519(@LD[0], AA);
  Result := LD[0] and 1;
end;

{ Unpack25519 }
procedure Unpack25519(var AO: TGf; const AN: PByte);
var
  LI: Integer;
begin
  for LI := 0 to 15 do
    AO[LI] := Int64(AN[2 * LI]) + (Int64(AN[2 * LI + 1]) shl 8);
  AO[15] := AO[15] and $7FFF;
end;

{ AddGf }
procedure AddGf(var AO: TGf; const AA, AB: TGf);
var
  LI: Integer;
begin
  for LI := 0 to 15 do
    AO[LI] := AA[LI] + AB[LI];
end;

{ SubGf }
procedure SubGf(var AO: TGf; const AA, AB: TGf);
var
  LI: Integer;
begin
  for LI := 0 to 15 do
    AO[LI] := AA[LI] - AB[LI];
end;

{ MulGf }
// Field multiplication; accumulates into a local 31-limb temp, so output
// aliasing with either input is safe (matches TweetNaCl M)
procedure MulGf(var AO: TGf; const AA, AB: TGf);
var
  LT: array[0..30] of Int64;
  LI: Integer;
  LJ: Integer;
begin
  FillChar(LT, SizeOf(LT), 0);
  for LI := 0 to 15 do
    for LJ := 0 to 15 do
      LT[LI + LJ] := LT[LI + LJ] + AA[LI] * AB[LJ];
  for LI := 0 to 14 do
    LT[LI] := LT[LI] + 38 * LT[LI + 16];
  for LI := 0 to 15 do
    AO[LI] := LT[LI];
  Car25519(AO);
  Car25519(AO);
end;

{ SqrGf }
procedure SqrGf(var AO: TGf; const AA: TGf);
begin
  MulGf(AO, AA, AA);
end;

{ Inv25519 }
procedure Inv25519(var AO: TGf; const AI: TGf);
var
  LC: TGf;
  LA: Integer;
begin
  Set25519(LC, AI);
  for LA := 253 downto 0 do
  begin
    SqrGf(LC, LC);
    if (LA <> 2) and (LA <> 4) then
      MulGf(LC, LC, AI);
  end;
  Set25519(AO, LC);
end;

{ Pow2523 }
procedure Pow2523(var AO: TGf; const AI: TGf);
var
  LC: TGf;
  LA: Integer;
begin
  Set25519(LC, AI);
  for LA := 250 downto 0 do
  begin
    SqrGf(LC, LC);
    if LA <> 1 then
      MulGf(LC, LC, AI);
  end;
  Set25519(AO, LC);
end;

{ AddPoint }
// Extended Edwards point addition; all reads complete before writes, so
// AddPoint(P, P) (doubling) is safe (matches TweetNaCl add)
procedure AddPoint(var AP: TGePoint; const AQ: TGePoint);
var
  LA: TGf;
  LB: TGf;
  LC: TGf;
  LD: TGf;
  LT: TGf;
  LE: TGf;
  LF: TGf;
  LG: TGf;
  LH: TGf;
begin
  SubGf(LA, AP[1], AP[0]);
  SubGf(LT, AQ[1], AQ[0]);
  MulGf(LA, LA, LT);
  AddGf(LB, AP[0], AP[1]);
  AddGf(LT, AQ[0], AQ[1]);
  MulGf(LB, LB, LT);
  MulGf(LC, AP[3], AQ[3]);
  MulGf(LC, LC, CGfD2);
  MulGf(LD, AP[2], AQ[2]);
  AddGf(LD, LD, LD);
  SubGf(LE, LB, LA);
  SubGf(LF, LD, LC);
  AddGf(LG, LD, LC);
  AddGf(LH, LB, LA);
  MulGf(AP[0], LE, LF);
  MulGf(AP[1], LH, LG);
  MulGf(AP[2], LG, LF);
  MulGf(AP[3], LE, LH);
end;

{ CSwap }
procedure CSwap(var AP, AQ: TGePoint; const AB: Int64);
var
  LI: Integer;
begin
  for LI := 0 to 3 do
    Sel25519(AP[LI], AQ[LI], AB);
end;

{ PackPoint }
procedure PackPoint(const AR: PByte; const AP: TGePoint);
var
  LTx: TGf;
  LTy: TGf;
  LZi: TGf;
begin
  Inv25519(LZi, AP[2]);
  MulGf(LTx, AP[0], LZi);
  MulGf(LTy, AP[1], LZi);
  Pack25519(AR, LTy);
  AR[31] := AR[31] xor (Par25519(LTx) shl 7);
end;

{ ScalarMult }
procedure ScalarMult(var AP: TGePoint; var AQ: TGePoint; const AScalar: PByte);
var
  LI: Integer;
  LB: Int64;
begin
  Set25519(AP[0], CGf0);
  Set25519(AP[1], CGf1);
  Set25519(AP[2], CGf1);
  Set25519(AP[3], CGf0);
  for LI := 255 downto 0 do
  begin
    LB := (AScalar[LI shr 3] shr (LI and 7)) and 1;
    CSwap(AP, AQ, LB);
    AddPoint(AQ, AP);
    AddPoint(AP, AP);
    CSwap(AP, AQ, LB);
  end;
end;

{ ScalarBase }
procedure ScalarBase(var AP: TGePoint; const AScalar: PByte);
var
  LQ: TGePoint;
begin
  Set25519(LQ[0], CGfX);
  Set25519(LQ[1], CGfY);
  Set25519(LQ[2], CGf1);
  MulGf(LQ[3], CGfX, CGfY);
  ScalarMult(AP, LQ, AScalar);
end;

{ ModL }
// Reduce a 64-limb intermediate modulo the group order L (TweetNaCl modL).
// NOTE: the inner loop's exit index is reused (x[j] += carry); Delphi for-loop
// variables are undefined after the loop, hence the explicit while loop.
procedure ModL(const AR: PByte; var AX: TInt64x64);
var
  LCarry: Int64;
  LI: Integer;
  LJ: Integer;
begin
  for LI := 63 downto 32 do
  begin
    LCarry := 0;
    LJ := LI - 32;
    while LJ < LI - 12 do
    begin
      AX[LJ] := AX[LJ] + LCarry - 16 * AX[LI] * CL[LJ - (LI - 32)];
      LCarry := Sar64(AX[LJ] + 128, 8);
      AX[LJ] := AX[LJ] - (LCarry shl 8);
      Inc(LJ);
    end;
    AX[LJ] := AX[LJ] + LCarry;
    AX[LI] := 0;
  end;
  LCarry := 0;
  for LJ := 0 to 31 do
  begin
    AX[LJ] := AX[LJ] + LCarry - Sar64(AX[31], 4) * CL[LJ];
    LCarry := Sar64(AX[LJ], 8);
    AX[LJ] := AX[LJ] and 255;
  end;
  for LJ := 0 to 31 do
    AX[LJ] := AX[LJ] - LCarry * CL[LJ];
  for LI := 0 to 31 do
  begin
    AX[LI + 1] := AX[LI + 1] + Sar64(AX[LI], 8);
    AR[LI] := Byte(AX[LI] and 255);
  end;
end;

{ Reduce }
// Reduce a 64-byte hash to a scalar; first 32 bytes of AR are the result
procedure Reduce(var AR: TBytes);
var
  LX: TInt64x64;
  LI: Integer;
begin
  for LI := 0 to 63 do
    LX[LI] := Int64(AR[LI]);
  for LI := 0 to 63 do
    AR[LI] := 0;
  ModL(@AR[0], LX);
end;

{ UnpackNeg }
// Decode a public key into the NEGATED point (TweetNaCl unpackneg); 0 = ok
function UnpackNeg(var AR: TGePoint; const AP: PByte): Integer;
var
  LT: TGf;
  LChk: TGf;
  LNum: TGf;
  LDen: TGf;
  LDen2: TGf;
  LDen4: TGf;
  LDen6: TGf;
begin
  Set25519(AR[2], CGf1);
  Unpack25519(AR[1], AP);
  SqrGf(LNum, AR[1]);
  MulGf(LDen, LNum, CGfD);
  SubGf(LNum, LNum, AR[2]);
  AddGf(LDen, AR[2], LDen);
  SqrGf(LDen2, LDen);
  SqrGf(LDen4, LDen2);
  MulGf(LDen6, LDen4, LDen2);
  MulGf(LT, LDen6, LNum);
  MulGf(LT, LT, LDen);
  Pow2523(LT, LT);
  MulGf(LT, LT, LNum);
  MulGf(LT, LT, LDen);
  MulGf(LT, LT, LDen);
  MulGf(AR[0], LT, LDen);
  SqrGf(LChk, AR[0]);
  MulGf(LChk, LChk, LDen);
  if Neq25519(LChk, LNum) <> 0 then
    MulGf(AR[0], AR[0], CGfI);
  SqrGf(LChk, AR[0]);
  MulGf(LChk, LChk, LDen);
  if Neq25519(LChk, LNum) <> 0 then
    Exit(-1);
  if Par25519(AR[0]) = (AP[31] shr 7) then
    SubGf(AR[0], CGf0, AR[0]);
  MulGf(AR[3], AR[0], AR[1]);
  Result := 0;
end;

{ ===== TEd25519 ===== }

class procedure TEd25519.GenerateKeyPair(const ASeed: TBytes; out APublicKey: TBytes; out ASecretKey: TBytes);
var
  LD: TBytes;
  LP: TGePoint;
begin
  APublicKey := nil;
  ASecretKey := nil;
  if Length(ASeed) <> 32 then
    Exit;
  LD := Sha512Parts([ASeed]);
  LD[0] := LD[0] and 248;
  LD[31] := (LD[31] and 127) or 64;
  ScalarBase(LP, @LD[0]);
  SetLength(APublicKey, 32);
  PackPoint(@APublicKey[0], LP);
  SetLength(ASecretKey, 64);
  Move(ASeed[0], ASecretKey[0], 32);
  Move(APublicKey[0], ASecretKey[32], 32);
end;

class function TEd25519.Sign(const AMessage: TBytes; const ASecretKey: TBytes): TBytes;
var
  LD: TBytes;
  LR: TBytes;
  LH: TBytes;
  LRPart: TBytes;
  LPub: TBytes;
  LP: TGePoint;
  LX: TInt64x64;
  LI: Integer;
  LJ: Integer;
begin
  Result := nil;
  if Length(ASecretKey) <> 64 then
    Exit;
  // d = clamped SHA-512(seed)
  LD := Sha512Parts([Copy(ASecretKey, 0, 32)]);
  LD[0] := LD[0] and 248;
  LD[31] := (LD[31] and 127) or 64;
  // r = reduce(SHA-512(d[32..63] || M))
  LR := Sha512Parts([Copy(LD, 32, 32), AMessage]);
  Reduce(LR);
  // R = r * B
  ScalarBase(LP, @LR[0]);
  SetLength(LRPart, 32);
  PackPoint(@LRPart[0], LP);
  // h = reduce(SHA-512(R || pub || M))
  LPub := Copy(ASecretKey, 32, 32);
  LH := Sha512Parts([LRPart, LPub, AMessage]);
  Reduce(LH);
  // S = (r + h*d) mod L
  FillChar(LX, SizeOf(LX), 0);
  for LI := 0 to 31 do
    LX[LI] := Int64(LR[LI]);
  for LI := 0 to 31 do
    for LJ := 0 to 31 do
      LX[LI + LJ] := LX[LI + LJ] + Int64(LH[LI]) * Int64(LD[LJ]);
  SetLength(Result, 64);
  Move(LRPart[0], Result[0], 32);
  ModL(@Result[32], LX);
end;

class function TEd25519.Verify(const AMessage: TBytes; const ASignature: TBytes; const APublicKey: TBytes): Boolean;
var
  LP: TGePoint;
  LQ: TGePoint;
  LH: TBytes;
  LT: TBytes;
begin
  Result := False;
  if (Length(ASignature) <> 64) or (Length(APublicKey) <> 32) then
    Exit;
  if UnpackNeg(LQ, @APublicKey[0]) <> 0 then
    Exit;
  LH := Sha512Parts([Copy(ASignature, 0, 32), APublicKey, AMessage]);
  Reduce(LH);
  // p = h * (-A); then q = S * B; p = p + q; expect pack(p) = R
  ScalarMult(LP, LQ, @LH[0]);
  ScalarBase(LQ, @ASignature[32]);
  AddPoint(LP, LQ);
  SetLength(LT, 32);
  PackPoint(@LT[0], LP);
  Result := CryptoVerify32(@ASignature[0], @LT[0]) = 0;
end;

{ ===== TSecureRandom ===== }

class function TSecureRandom.Fill(const ABuffer: PByte; const ACount: Integer): Boolean;
begin
  Result := BCryptGenRandom(nil, ABuffer, ULONG(ACount), BCRYPT_USE_SYSTEM_PREFERRED_RNG) = 0;
end;

class function TSecureRandom.GetBytes(const ACount: Integer; out ABytes: TBytes): Boolean;
begin
  SetLength(ABytes, ACount);
  Result := Fill(@ABytes[0], ACount);
  if not Result then
    ABytes := nil;
end;

{ ===== TMiniKeyPair ===== }

function TMiniKeyPair.HasSecret(): Boolean;
begin
  Result := Length(SecretKey) = 64;
end;

procedure TMiniKeyPair.Clear();
begin
  KeyId := nil;
  PublicKey := nil;
  SecretKey := nil;
end;

{ ===== TMinisign ===== }

function TMinisign.DoEncodeB64(const AData: TBytes): string;
var
  LEnc: TBase64Encoding;
begin
  // Line length 0 = no line breaks; the default encoder wraps at 76 chars
  // which corrupts key/signature lines
  LEnc := TBase64Encoding.Create(0);
  try
    Result := LEnc.EncodeBytesToString(AData);
  finally
    LEnc.Free;
  end;
end;

function TMinisign.DoDecodeB64(const AText: string; out AData: TBytes): Boolean;
var
  LEnc: TBase64Encoding;
begin
  AData := nil;
  LEnc := TBase64Encoding.Create(0);
  try
    try
      AData := LEnc.DecodeStringToBytes(AText.Trim());
      Result := Length(AData) > 0;
    except
      Result := False;
    end;
  finally
    LEnc.Free;
  end;
end;

function TMinisign.DoParsePublicBlob(const ABlob: TBytes; out AKeyPair: TMiniKeyPair;
  const ASourceName: string): Boolean;
begin
  Result := False;
  AKeyPair.Clear();
  // 42 bytes: "Ed" || key_id(8) || public_key(32)
  if (Length(ABlob) <> 42) or (ABlob[0] <> CMiniPubAlg[0]) or (ABlob[1] <> CMiniPubAlg[1]) then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryBadKeyFile, [ASourceName]);
    Exit;
  end;
  AKeyPair.KeyId := Copy(ABlob, 2, 8);
  AKeyPair.PublicKey := Copy(ABlob, 10, 32);
  AKeyPair.SecretKey := nil;
  Result := True;
end;

function TMinisign.DoReadKeyLines(const AFilename: string; out ABlob: TBytes): Boolean;
var
  LLines: TArray<string>;
  LIndex: Integer;
  LLine: string;
begin
  Result := False;
  ABlob := nil;
  if not TFile.Exists(AFilename) then
  begin
    FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileNotFound, [AFilename]);
    Exit;
  end;
  try
    LLines := TFile.ReadAllLines(AFilename, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileError, [E.Message]);
      Exit;
    end;
  end;
  // First non-empty, non-comment line is the base64 blob
  for LIndex := 0 to High(LLines) do
  begin
    LLine := LLines[LIndex].Trim();
    if LLine = '' then
      Continue;
    if LLine.StartsWith('untrusted comment:') then
      Continue;
    Exit(DoDecodeB64(LLine, ABlob));
  end;
end;

function TMinisign.DoKeyIdHex(const AKeyId: TBytes): string;
var
  LIndex: Integer;
begin
  Result := '';
  for LIndex := 0 to High(AKeyId) do
    Result := Result + IntToHex(AKeyId[LIndex], 2);
  Result := Result.ToUpper();
end;

function TMinisign.DoDefaultTrustedComment(const AFilename: string): string;
var
  LStamp: Int64;
begin
  LStamp := DateTimeToUnix(Now(), False);
  Result := Format('timestamp:%d'#9'file:%s'#9'hashed', [LStamp, TPath.GetFileName(AFilename)]);
end;

function TMinisign.GenerateKeyPair(out AKeyPair: TMiniKeyPair): Boolean;
var
  LSeed: TBytes;
begin
  Result := False;
  AKeyPair.Clear();
  if not TSecureRandom.GetBytes(32, LSeed) then
  begin
    FErrors.Add(esFatal, ERR_CRY_RANDOM, RSCryRandomFailed);
    Exit;
  end;
  if not TSecureRandom.GetBytes(8, AKeyPair.KeyId) then
  begin
    FErrors.Add(esFatal, ERR_CRY_RANDOM, RSCryRandomFailed);
    Exit;
  end;
  TEd25519.GenerateKeyPair(LSeed, AKeyPair.PublicKey, AKeyPair.SecretKey);
  Result := AKeyPair.HasSecret();
end;

function TMinisign.SaveSecretKey(const AFilename: string; const AKeyPair: TMiniKeyPair): Boolean;
var
  LBlob: TBytes;
  LText: string;
begin
  Result := False;
  if not AKeyPair.HasSecret() then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryNoSecretKey);
    Exit;
  end;
  // Blob: 'T1' || key_id(8) || secret_key(64) = 74 bytes, UNENCRYPTED AppPacker format
  SetLength(LBlob, 74);
  LBlob[0] := CMiniSecTag[0];
  LBlob[1] := CMiniSecTag[1];
  Move(AKeyPair.KeyId[0], LBlob[2], 8);
  Move(AKeyPair.SecretKey[0], LBlob[10], 64);
  LText := 'untrusted comment: ' + Format(RSCrySecKeyComment, [DoKeyIdHex(AKeyPair.KeyId)]) + #10 +
    DoEncodeB64(LBlob) + #10;
  // BOM-free UTF-8: minisign-style tooling cannot parse key files with a BOM
  try
    TFile.WriteAllBytes(AFilename, TEncoding.UTF8.GetBytes(LText));
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileError, [E.Message]);
  end;
end;

function TMinisign.LoadSecretKey(const AFilename: string; out AKeyPair: TMiniKeyPair): Boolean;
var
  LBlob: TBytes;
begin
  Result := False;
  AKeyPair.Clear();
  if not DoReadKeyLines(AFilename, LBlob) then
    Exit;
  if (Length(LBlob) <> 74) or (LBlob[0] <> CMiniSecTag[0]) or (LBlob[1] <> CMiniSecTag[1]) then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryBadKeyFile, [AFilename]);
    Exit;
  end;
  AKeyPair.KeyId := Copy(LBlob, 2, 8);
  AKeyPair.SecretKey := Copy(LBlob, 10, 64);
  AKeyPair.PublicKey := Copy(LBlob, 42, 32); // pk = secret_key[32..63]
  Result := True;
end;

function TMinisign.SavePublicKey(const AFilename: string; const AKeyPair: TMiniKeyPair): Boolean;
var
  LText: string;
begin
  Result := False;
  if Length(AKeyPair.PublicKey) <> 32 then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryNoPublicKey);
    Exit;
  end;
  LText := 'untrusted comment: minisign public key ' + DoKeyIdHex(AKeyPair.KeyId) + #10 +
    PublicKeyString(AKeyPair) + #10;
  // BOM-free UTF-8: stock minisign cannot parse key files that start with a BOM
  try
    TFile.WriteAllBytes(AFilename, TEncoding.UTF8.GetBytes(LText));
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileError, [E.Message]);
  end;
end;

function TMinisign.LoadPublicKey(const AFilename: string; out AKeyPair: TMiniKeyPair): Boolean;
var
  LBlob: TBytes;
begin
  Result := False;
  AKeyPair.Clear();
  if not DoReadKeyLines(AFilename, LBlob) then
    Exit;
  Result := DoParsePublicBlob(LBlob, AKeyPair, AFilename);
end;

function TMinisign.LoadPublicKeyString(const AKeyText: string; out AKeyPair: TMiniKeyPair): Boolean;
var
  LBlob: TBytes;
begin
  Result := False;
  AKeyPair.Clear();
  if not DoDecodeB64(AKeyText, LBlob) then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryBadKeyFile, ['<string>']);
    Exit;
  end;
  Result := DoParsePublicBlob(LBlob, AKeyPair, '<string>');
end;

function TMinisign.PublicKeyString(const AKeyPair: TMiniKeyPair): string;
var
  LBlob: TBytes;
begin
  Result := '';
  if (Length(AKeyPair.PublicKey) <> 32) or (Length(AKeyPair.KeyId) <> 8) then
    Exit;
  SetLength(LBlob, 42);
  LBlob[0] := CMiniPubAlg[0];
  LBlob[1] := CMiniPubAlg[1];
  Move(AKeyPair.KeyId[0], LBlob[2], 8);
  Move(AKeyPair.PublicKey[0], LBlob[10], 32);
  Result := DoEncodeB64(LBlob);
end;

function TMinisign.KeyIdString(const AKeyPair: TMiniKeyPair): string;
begin
  Result := DoKeyIdHex(AKeyPair.KeyId);
end;

function TMinisign.SignFile(const AFilename: string; const AKeyPair: TMiniKeyPair;
  const ATrustedComment: string; const AUntrustedComment: string): Boolean;
var
  LDigest: TBytes;
  LSig: TBytes;
  LGlobal: TBytes;
  LGlobalMsg: TBytes;
  LBlob: TBytes;
  LTrustedBytes: TBytes;
  LTrusted: string;
  LUntrusted: string;
  LText: string;
begin
  Result := False;
  if not AKeyPair.HasSecret() then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryNoSecretKey);
    Exit;
  end;
  if not TBlake2b.HashFile(AFilename, LDigest) then
  begin
    FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileNotFound, [AFilename]);
    Exit;
  end;
  // Prehashed ("ED") signature: Ed25519 over the Blake2b-512 digest
  LSig := TEd25519.Sign(LDigest, AKeyPair.SecretKey);
  LTrusted := ATrustedComment;
  if LTrusted = '' then
    LTrusted := DoDefaultTrustedComment(AFilename);
  LUntrusted := AUntrustedComment;
  if LUntrusted = '' then
    LUntrusted := Format(RSCrySigDefaultComment, [DoKeyIdHex(AKeyPair.KeyId)]);
  // Global signature: Ed25519 over (signature || trusted_comment_utf8)
  LTrustedBytes := TEncoding.UTF8.GetBytes(LTrusted);
  SetLength(LGlobalMsg, 64 + Length(LTrustedBytes));
  Move(LSig[0], LGlobalMsg[0], 64);
  if Length(LTrustedBytes) > 0 then
    Move(LTrustedBytes[0], LGlobalMsg[64], Length(LTrustedBytes));
  LGlobal := TEd25519.Sign(LGlobalMsg, AKeyPair.SecretKey);
  // Signature blob: 'ED' || key_id(8) || signature(64) = 74 bytes
  SetLength(LBlob, 74);
  LBlob[0] := CMiniSigAlg[0];
  LBlob[1] := CMiniSigAlg[1];
  Move(AKeyPair.KeyId[0], LBlob[2], 8);
  Move(LSig[0], LBlob[10], 64);
  // minisign .minisig layout, LF-only line endings, BOM-free UTF-8
  LText := 'untrusted comment: ' + LUntrusted + #10 +
    DoEncodeB64(LBlob) + #10 +
    'trusted comment: ' + LTrusted + #10 +
    DoEncodeB64(LGlobal) + #10;
  try
    TFile.WriteAllBytes(AFilename + '.minisig', TEncoding.UTF8.GetBytes(LText));
    Result := True;
  except
    on E: Exception do
      FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileError, [E.Message]);
  end;
end;

function TMinisign.VerifyFile(const AFilename: string; const AKeyPair: TMiniKeyPair;
  const ASigFilename: string): Boolean;
var
  LSigFile: string;
  LLines: TArray<string>;
  LClean: TArray<string>;
  LIndex: Integer;
  LLine: string;
  LBlob: TBytes;
  LGlobal: TBytes;
  LDigest: TBytes;
  LSig: TBytes;
  LTrusted: string;
  LTrustedBytes: TBytes;
  LGlobalMsg: TBytes;
begin
  Result := False;
  if Length(AKeyPair.PublicKey) <> 32 then
  begin
    FErrors.Add(esError, ERR_CRY_KEYFORMAT, RSCryNoPublicKey);
    Exit;
  end;
  LSigFile := ASigFilename;
  if LSigFile = '' then
    LSigFile := AFilename + '.minisig';
  if not TFile.Exists(LSigFile) then
  begin
    FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileNotFound, [LSigFile]);
    Exit;
  end;
  try
    LLines := TFile.ReadAllLines(LSigFile, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileError, [E.Message]);
      Exit;
    end;
  end;
  // Collect non-empty lines; expect exactly the 4-line minisig layout
  LClean := nil;
  for LIndex := 0 to High(LLines) do
  begin
    LLine := LLines[LIndex].Trim();
    if LLine <> '' then
      LClean := LClean + [LLine];
  end;
  if (Length(LClean) < 4) or
     (not LClean[0].StartsWith('untrusted comment:')) or
     (not LClean[2].StartsWith('trusted comment:')) then
  begin
    FErrors.Add(esError, ERR_CRY_SIGFORMAT, RSCryBadSigFile, [LSigFile]);
    Exit;
  end;
  if (not DoDecodeB64(LClean[1], LBlob)) or (Length(LBlob) <> 74) then
  begin
    FErrors.Add(esError, ERR_CRY_SIGFORMAT, RSCryBadSigFile, [LSigFile]);
    Exit;
  end;
  // Only the modern prehashed format is supported; legacy 'Ed' is rejected
  if (LBlob[0] <> CMiniSigAlg[0]) or (LBlob[1] <> CMiniSigAlg[1]) then
  begin
    FErrors.Add(esError, ERR_CRY_SIGFORMAT, RSCryBadSigFile, [LSigFile]);
    Exit;
  end;
  if not CompareMem(@LBlob[2], @AKeyPair.KeyId[0], 8) then
  begin
    FErrors.Add(esError, ERR_CRY_KEYID, RSCryKeyIdMismatch, [LSigFile]);
    Exit;
  end;
  if (not DoDecodeB64(LClean[3], LGlobal)) or (Length(LGlobal) <> 64) then
  begin
    FErrors.Add(esError, ERR_CRY_SIGFORMAT, RSCryBadSigFile, [LSigFile]);
    Exit;
  end;
  if not TBlake2b.HashFile(AFilename, LDigest) then
  begin
    FErrors.Add(esError, ERR_CRY_FILEIO, RSCryFileNotFound, [AFilename]);
    Exit;
  end;
  LSig := Copy(LBlob, 10, 64);
  if not TEd25519.Verify(LDigest, LSig, AKeyPair.PublicKey) then
  begin
    FErrors.Add(esError, ERR_CRY_VERIFY, RSCryVerifyFailed, [AFilename]);
    Exit;
  end;
  // Verify the trusted comment via the global signature
  LTrusted := LClean[2].Substring(Length('trusted comment:')).TrimLeft();
  LTrustedBytes := TEncoding.UTF8.GetBytes(LTrusted);
  SetLength(LGlobalMsg, 64 + Length(LTrustedBytes));
  Move(LSig[0], LGlobalMsg[0], 64);
  if Length(LTrustedBytes) > 0 then
    Move(LTrustedBytes[0], LGlobalMsg[64], Length(LTrustedBytes));
  if not TEd25519.Verify(LGlobalMsg, LGlobal, AKeyPair.PublicKey) then
  begin
    FErrors.Add(esError, ERR_CRY_VERIFY, RSCryVerifyFailed, [LSigFile]);
    Exit;
  end;
  Result := True;
end;

end.
