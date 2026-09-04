{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.IATHook - Import Address Table hooking

  Provides functionality to intercept Windows API calls made by a loaded
  DLL by patching its Import Address Table (IAT). This allows redirection
  of file I/O operations to serve content from embedded resources or
  custom handlers.

  Key types:
  - TIATHook: Static class -- HookImport, UnhookImport, GetOriginalProc,
    UnhookAll, IsHooked
  - TIATHookEntry: Record storing hook state (original/hook proc, IAT address)

  Usage:
    1. Load target DLL (e.g., via StdApp.DllLoader)
    2. Call HookImport() to redirect specific API calls
    3. Your hook function receives calls, can delegate to original
    4. Call UnhookImport() or UnhookAll() when done

  Dependencies: none (WinApi and System units only)
===============================================================================}
unit StdApp.IATHook;

{$I StdApp.Defines.inc}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections;

type
  { Record storing information about a single IAT hook }
  TIATHookEntry = record
    DllBase: Pointer;
    TargetDll: string;
    FunctionName: string;
    OriginalProc: Pointer;
    HookProc: Pointer;
    IATEntryAddr: PPointer;
  end;

  { Static class providing IAT hooking functionality }
  TIATHook = class
  private class var
    FHooks: TList<TIATHookEntry>;
    class function GetImageNtHeaders(const ABase: Pointer): PImageNtHeaders64; static;
    class function GetImportDescriptor(const ABase: Pointer;
      const ATargetDll: string): PImageImportDescriptor; static;
    class function FindIATEntry(const ABase: Pointer;
      const AImportDesc: PImageImportDescriptor;
      const AFunctionName: string;
      out AOriginalProc: Pointer): PPointer; static;
    class function PatchPointer(const ATarget: PPointer;
      const ANewValue: Pointer): Boolean; static;
    class procedure EnsureHookList(); static;
  public
    { Install a hook for a specific import }
    class function HookImport(const ADllBase: Pointer;
      const ATargetDll: string;
      const AFunctionName: string;
      const AHookProc: Pointer): Boolean; static;

    { Remove a specific hook }
    class function UnhookImport(const ADllBase: Pointer;
      const ATargetDll: string;
      const AFunctionName: string): Boolean; static;

    { Get the original procedure address (before hooking or from saved hook) }
    class function GetOriginalProc(const ADllBase: Pointer;
      const ATargetDll: string;
      const AFunctionName: string): Pointer; static;

    { Remove all installed hooks }
    class procedure UnhookAll(); static;

    { Check if a specific function is hooked }
    class function IsHooked(const ADllBase: Pointer;
      const ATargetDll: string;
      const AFunctionName: string): Boolean; static;

    { Cleanup - call on application shutdown }
    class procedure Finalize(); static;
  end;

implementation

{ TIATHook }

class procedure TIATHook.EnsureHookList();
begin
  if FHooks = nil then
    FHooks := TList<TIATHookEntry>.Create();
end;

class function TIATHook.GetImageNtHeaders(const ABase: Pointer): PImageNtHeaders64;
var
  LDosHeader: PImageDosHeader;
begin
  Result := nil;
  if ABase = nil then
    Exit;

  LDosHeader := PImageDosHeader(ABase);
  if LDosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    Exit;

  Result := PImageNtHeaders64(PByte(ABase) + LDosHeader^._lfanew);
  if Result^.Signature <> IMAGE_NT_SIGNATURE then
    Result := nil;
end;

class function TIATHook.GetImportDescriptor(const ABase: Pointer;
  const ATargetDll: string): PImageImportDescriptor;
var
  LNtHeaders: PImageNtHeaders64;
  LImportDir: TImageDataDirectory;
  LImportDesc: PImageImportDescriptor;
  LDllName: PAnsiChar;
  LDllNameStr: string;
begin
  Result := nil;

  LNtHeaders := GetImageNtHeaders(ABase);
  if LNtHeaders = nil then
    Exit;

  { Get import directory from optional header }
  LImportDir := LNtHeaders^.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if LImportDir.VirtualAddress = 0 then
    Exit;

  { Walk import descriptors }
  LImportDesc := PImageImportDescriptor(PByte(ABase) + LImportDir.VirtualAddress);

  while LImportDesc^.Name <> 0 do
  begin
    LDllName := PAnsiChar(PByte(ABase) + LImportDesc^.Name);
    LDllNameStr := string(LDllName);

    if SameText(LDllNameStr, ATargetDll) then
    begin
      Result := LImportDesc;
      Exit;
    end;

    Inc(LImportDesc);
  end;
end;

class function TIATHook.FindIATEntry(const ABase: Pointer;
  const AImportDesc: PImageImportDescriptor;
  const AFunctionName: string;
  out AOriginalProc: Pointer): PPointer;
var
  LOriginalThunk: PImageThunkData64;
  LBoundThunk: PImageThunkData64;
  LImportByName: PImageImportByName;
  LFuncName: string;
begin
  Result := nil;
  AOriginalProc := nil;

  if (ABase = nil) or (AImportDesc = nil) then
    Exit;

  { OriginalFirstThunk points to hint/name table (INT) }
  { FirstThunk points to address table (IAT) }
  if AImportDesc^.OriginalFirstThunk <> 0 then
    LOriginalThunk := PImageThunkData64(PByte(ABase) + AImportDesc^.OriginalFirstThunk)
  else
    LOriginalThunk := PImageThunkData64(PByte(ABase) + AImportDesc^.FirstThunk);

  LBoundThunk := PImageThunkData64(PByte(ABase) + AImportDesc^.FirstThunk);

  { Walk thunks looking for our function }
  while LOriginalThunk^.AddressOfData <> 0 do
  begin
    { Check if import is by ordinal }
    if (LOriginalThunk^.Ordinal and IMAGE_ORDINAL_FLAG64) = 0 then
    begin
      { Import by name }
      LImportByName := PImageImportByName(PByte(ABase) + LOriginalThunk^.AddressOfData);
      LFuncName := string(PAnsiChar(@LImportByName^.Name[0]));

      if SameText(LFuncName, AFunctionName) then
      begin
        Result := PPointer(@LBoundThunk^.Ordinal);
        AOriginalProc := Pointer(LBoundThunk^.Ordinal);
        Exit;
      end;
    end;

    Inc(LOriginalThunk);
    Inc(LBoundThunk);
  end;
end;

class function TIATHook.PatchPointer(const ATarget: PPointer;
  const ANewValue: Pointer): Boolean;
var
  LOldProtect: DWORD;
begin
  Result := False;

  if ATarget = nil then
    Exit;

  { Make IAT entry writable }
  if not VirtualProtect(ATarget, SizeOf(Pointer), PAGE_EXECUTE_READWRITE, @LOldProtect) then
    Exit;

  try
    { Patch the pointer }
    ATarget^ := ANewValue;
    Result := True;
  finally
    { Restore original protection }
    VirtualProtect(ATarget, SizeOf(Pointer), LOldProtect, @LOldProtect);
  end;
end;

class function TIATHook.HookImport(const ADllBase: Pointer;
  const ATargetDll: string;
  const AFunctionName: string;
  const AHookProc: Pointer): Boolean;
var
  LImportDesc: PImageImportDescriptor;
  LIATEntry: PPointer;
  LOriginalProc: Pointer;
  LHookEntry: TIATHookEntry;
  I: Integer;
begin
  Result := False;
  EnsureHookList();

  { Check if already hooked }
  for I := 0 to FHooks.Count - 1 do
  begin
    if (FHooks[I].DllBase = ADllBase) and
       SameText(FHooks[I].TargetDll, ATargetDll) and
       SameText(FHooks[I].FunctionName, AFunctionName) then
    begin
      { Already hooked - update hook proc }
      LHookEntry := FHooks[I];
      if PatchPointer(LHookEntry.IATEntryAddr, AHookProc) then
      begin
        LHookEntry.HookProc := AHookProc;
        FHooks[I] := LHookEntry;
        Result := True;
      end;
      Exit;
    end;
  end;

  { Find import descriptor for target DLL }
  LImportDesc := GetImportDescriptor(ADllBase, ATargetDll);
  if LImportDesc = nil then
    Exit;

  { Find IAT entry for function }
  LIATEntry := FindIATEntry(ADllBase, LImportDesc, AFunctionName, LOriginalProc);
  if LIATEntry = nil then
    Exit;

  { Patch IAT entry }
  if not PatchPointer(LIATEntry, AHookProc) then
    Exit;

  { Save hook info }
  LHookEntry.DllBase := ADllBase;
  LHookEntry.TargetDll := ATargetDll;
  LHookEntry.FunctionName := AFunctionName;
  LHookEntry.OriginalProc := LOriginalProc;
  LHookEntry.HookProc := AHookProc;
  LHookEntry.IATEntryAddr := LIATEntry;

  FHooks.Add(LHookEntry);
  Result := True;
end;

class function TIATHook.UnhookImport(const ADllBase: Pointer;
  const ATargetDll: string;
  const AFunctionName: string): Boolean;
var
  I: Integer;
  LEntry: TIATHookEntry;
begin
  Result := False;
  EnsureHookList();

  for I := FHooks.Count - 1 downto 0 do
  begin
    LEntry := FHooks[I];
    if (LEntry.DllBase = ADllBase) and
       SameText(LEntry.TargetDll, ATargetDll) and
       SameText(LEntry.FunctionName, AFunctionName) then
    begin
      { Restore original pointer }
      if PatchPointer(LEntry.IATEntryAddr, LEntry.OriginalProc) then
      begin
        FHooks.Delete(I);
        Result := True;
      end;
      Exit;
    end;
  end;
end;

class function TIATHook.GetOriginalProc(const ADllBase: Pointer;
  const ATargetDll: string;
  const AFunctionName: string): Pointer;
var
  I: Integer;
  LEntry: TIATHookEntry;
  LImportDesc: PImageImportDescriptor;
begin
  Result := nil;
  EnsureHookList();

  { First check if we have it saved from a hook }
  for I := 0 to FHooks.Count - 1 do
  begin
    LEntry := FHooks[I];
    if (LEntry.DllBase = ADllBase) and
       SameText(LEntry.TargetDll, ATargetDll) and
       SameText(LEntry.FunctionName, AFunctionName) then
    begin
      Result := LEntry.OriginalProc;
      Exit;
    end;
  end;

  { Not hooked yet - read directly from IAT }
  LImportDesc := GetImportDescriptor(ADllBase, ATargetDll);
  if LImportDesc = nil then
    Exit;

  FindIATEntry(ADllBase, LImportDesc, AFunctionName, Result);
end;

class procedure TIATHook.UnhookAll();
var
  I: Integer;
  LEntry: TIATHookEntry;
begin
  if FHooks = nil then
    Exit;

  for I := FHooks.Count - 1 downto 0 do
  begin
    LEntry := FHooks[I];
    PatchPointer(LEntry.IATEntryAddr, LEntry.OriginalProc);
  end;

  FHooks.Clear();
end;

class function TIATHook.IsHooked(const ADllBase: Pointer;
  const ATargetDll: string;
  const AFunctionName: string): Boolean;
var
  I: Integer;
  LEntry: TIATHookEntry;
begin
  Result := False;
  EnsureHookList();

  for I := 0 to FHooks.Count - 1 do
  begin
    LEntry := FHooks[I];
    if (LEntry.DllBase = ADllBase) and
       SameText(LEntry.TargetDll, ATargetDll) and
       SameText(LEntry.FunctionName, AFunctionName) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class procedure TIATHook.Finalize();
begin
  UnhookAll();
  FreeAndNil(FHooks);
end;

initialization

finalization
  TIATHook.Finalize();

end.
