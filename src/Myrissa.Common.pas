{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit Myrissa.Common;

{$I StdApp.Defines.inc}

interface


const
  //============================================================================
  // Version Constants
  //============================================================================
  MYR_MAJOR_VERSION = 0;
  MYR_MINOR_VERSION = 1;
  MYR_PATCH_VERSION = 0;
  MYR_VERSION = (MYR_MAJOR_VERSION * 10000) + (MYR_MINOR_VERSION * 100) + MYR_PATCH_VERSION;
  MYR_VERSION_STR = '0.1.0';

  // File Extensions
  MYR_SRCFILE_EXT = '.myr';
  MYR_DBGFILE_EXT = '.mdbg';
  MYR_DBGFILE_MAGIC = 'MDBG';
  MYR_DBGFILE_VERSION = 2;

  // File paths
  // Prefixed '$P:' -- these are shipped assets that live beside the running
  // executable, never relative to the caller's current directory.
  LIB_PATH_SYSTEM = '$P:res/libs/system';
  MYR_RES_TESTS_DIR = '$P:res/tests';
  MYR_RES_STD_DIR = '$P:res/libs/std';
  MYR_RES_STD_C_DIR = '$P:res/libs/std/c';

type
  { TMyrTargetKind }
  TMyrTargetKind = (
    tgWin64,
    tgLinux64
  );

{ cpTryParseTarget }
function MyrTryParseTarget(const AValue: string; out ATarget: TMyrTargetKind): Boolean;

{ cpSanitizeIdentifier }
function MyrSanitizeIdentifier(const AName: string): string;

{ cpLogStdErr }
procedure MyrLogStdErr(const AMsg: string);

implementation

uses
  System.SysUtils;

{ cpTryParseTarget }
function MyrTryParseTarget(const AValue: string; out ATarget: TMyrTargetKind): Boolean;
var
  LLower: string;
begin
  Result := True;
  LLower := AValue.ToLower();
  if LLower = 'win64' then
    ATarget := tgWin64
  else if LLower = 'linux64' then
    ATarget := tgLinux64
  else
    Result := False;
end;

{ cpSanitizeIdentifier }
function MyrSanitizeIdentifier(const AName: string): string;
var
  I: Integer;
  LChar: Char;
begin
  Result := '';
  for I := 1 to Length(AName) do
  begin
    LChar := AName[I];
    if CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result := Result + LChar
    else
      Result := Result + '_';
  end;
end;

{ cpLogStdErr }
procedure MyrLogStdErr(const AMsg: string);
begin
  WriteLn(ErrOutput, AMsg);
end;

end.
