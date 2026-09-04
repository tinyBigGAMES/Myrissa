{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Console.Menu - Interactive console menu system

  Fluent-API menu builder for console applications. Supports nested
  submenus, color customization, multi-column layout, separator items,
  and automatic integration with TTestCase and TTestDemo classes.

  Key types:
  - TConsoleMenu: Menu builder with fluent configuration (Title, colors,
    layout), Add/AddSeparator/AddSubmenu, AddTestCase/AddTestDemo for
    automatic test registration, and Run for the interactive loop
  - TMenuItem / TMenuItemKind: Menu entry record (Action, Separator, Submenu)

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Console,
    StdApp.TestCase, StdApp.TestDemo
===============================================================================}

unit StdApp.Console.Menu;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console,
  StdApp.TestCase,
  StdApp.TestDemo;

type

  TConsoleMenu = class;

  { TMenuCallback }
  TMenuCallback = reference to procedure;

  { TMenuItemKind }
  TMenuItemKind = (
    Action,
    Separator,
    Submenu,
    TestCase,
    TestDemo
  );

  { TMenuItem }
  TMenuItem = record
    ItemName:      string;
    Callback:      TMenuCallback;
    SubMenu:       TConsoleMenu;
    Kind:          TMenuItemKind;
    TestCaseClass: TTestCaseClass;
    TestDemoClass: TTestDemoClass;
  end;

  { TConsoleMenu }
  TConsoleMenu = class(TBaseObject)
  private
    FTitle:           string;
    FExitLabel:       string;
    FItems:           TList<TMenuItem>;
    FChildren:        TObjectList<TConsoleMenu>;
    FIsRoot:          Boolean;
    FTitleColor:      string;
    FItemColor:       string;
    FItemNumberColor: string;
    FExitColor:       string;
    FErrorColor:      string;
    FPromptColor:     string;
    FSeparatorColor:  string;
    FPromptText:      string;
    FPause:           Boolean;
    FMaxRows:         Integer;
    FColumnGap:       Integer;
    FCurrentCategory: string;
    FCurrentCategorySub: TConsoleMenu;
    // Propagate color settings to a child menu
    procedure PropagateColors(const AChild: TConsoleMenu);
    procedure DoShowCLIHelp();
    procedure CollectTestCases(const AList: TList<TTestCaseClass>);
  public
    property Pause: Boolean read FPause write FPause;
    property IsRoot: Boolean read FIsRoot write FIsRoot;

    constructor Create(); override;
    destructor Destroy(); override;

    // Configuration (fluent - returns Self)
    function Title(const ATitle: string): TConsoleMenu;
    function ExitLabel(const ALabel: string): TConsoleMenu;
    function PromptText(const AText: string): TConsoleMenu;
    function TitleColor(const AColor: string): TConsoleMenu;
    function ItemColor(const AColor: string): TConsoleMenu;
    function ItemNumberColor(const AColor: string): TConsoleMenu;
    function ExitColor(const AColor: string): TConsoleMenu;
    function ErrorColor(const AColor: string): TConsoleMenu;
    function PromptColor(const AColor: string): TConsoleMenu;
    function SeparatorColor(const AColor: string): TConsoleMenu;
    function MaxRows(const AValue: Integer): TConsoleMenu;
    function ColumnGap(const AValue: Integer): TConsoleMenu;

    // Add items
    function Add(const AItemName: string;
      const ACallback: TMenuCallback): TConsoleMenu;
    function AddSeparator(): TConsoleMenu;
    function AddSubmenu(const ATitle: string): TConsoleMenu; overload;
    function AddSubmenu(const AConsoleMenu: TConsoleMenu; const ATitle: string): TConsoleMenu; overload;

    // Add a test case class as a submenu with Run All + individual tests
    function AddTestCase(const ATestClass: TTestCaseClass): TConsoleMenu;

    // Add a test demo class as a single menu item
    function AddTestDemo(const ADemoClass: TTestDemoClass): TConsoleMenu;

    // Run the menu loop (blocks until user selects exit/return)
    procedure Run();

    // CLI mode: parse command-line args, run matching tests headless.
    // Returns False if no args (caller should open menu). Returns True
    // if CLI mode was entered (caller should skip menu).
    function CLI(): Boolean;

    // Clear all items
    procedure Clear();

    // Item count (excluding separators)
    function ActionCount(): Integer;

    // Category grouping: items registered after SetCategory go into
    // a submenu with that name, with a "Run All" at the top.
    procedure SetCategory(const ACategory: string);
    procedure ClearCategory();
  end;

implementation

{ TConsoleMenu }

constructor TConsoleMenu.Create();
begin
  inherited;
  FItems := TList<TMenuItem>.Create();
  FChildren := TObjectList<TConsoleMenu>.Create(True);
  FTitle := 'Menu';
  FExitLabel := 'Quit';
  FPromptText := 'Choose> ';
  FTitleColor := COLOR_CYAN + COLOR_BOLD;
  FItemColor := COLOR_WHITE;
  FItemNumberColor := COLOR_YELLOW;
  FExitColor := COLOR_WHITE;
  FErrorColor := COLOR_RED;
  FPromptColor := COLOR_GREEN;
  FSeparatorColor := COLOR_WHITE;
  FIsRoot := True;
  FPause := False;
  FMaxRows := 20;
  FColumnGap := 3;
  FCurrentCategory := '';
  FCurrentCategorySub := nil;
end;

destructor TConsoleMenu.Destroy();
begin
  FChildren.Free();
  FItems.Free();
  inherited;
end;

procedure TConsoleMenu.PropagateColors(const AChild: TConsoleMenu);
begin
  AChild.FTitleColor := FTitleColor;
  AChild.FItemColor := FItemColor;
  AChild.FItemNumberColor := FItemNumberColor;
  AChild.FExitColor := FExitColor;
  AChild.FErrorColor := FErrorColor;
  AChild.FPromptColor := FPromptColor;
  AChild.FSeparatorColor := FSeparatorColor;
  AChild.FPromptText := FPromptText;
  AChild.FPause := FPause;
  AChild.FMaxRows := FMaxRows;
  AChild.FColumnGap := FColumnGap;
end;

function TConsoleMenu.Title(const ATitle: string): TConsoleMenu;
begin
  FTitle := ATitle;
  Result := Self;
end;

function TConsoleMenu.ExitLabel(const ALabel: string): TConsoleMenu;
begin
  FExitLabel := ALabel;
  Result := Self;
end;

function TConsoleMenu.PromptText(const AText: string): TConsoleMenu;
begin
  FPromptText := AText;
  Result := Self;
end;

function TConsoleMenu.TitleColor(const AColor: string): TConsoleMenu;
begin
  FTitleColor := AColor;
  Result := Self;
end;

function TConsoleMenu.ItemColor(const AColor: string): TConsoleMenu;
begin
  FItemColor := AColor;
  Result := Self;
end;

function TConsoleMenu.ItemNumberColor(const AColor: string): TConsoleMenu;
begin
  FItemNumberColor := AColor;
  Result := Self;
end;

function TConsoleMenu.ExitColor(const AColor: string): TConsoleMenu;
begin
  FExitColor := AColor;
  Result := Self;
end;

function TConsoleMenu.ErrorColor(const AColor: string): TConsoleMenu;
begin
  FErrorColor := AColor;
  Result := Self;
end;

function TConsoleMenu.PromptColor(const AColor: string): TConsoleMenu;
begin
  FPromptColor := AColor;
  Result := Self;
end;

function TConsoleMenu.SeparatorColor(const AColor: string): TConsoleMenu;
begin
  FSeparatorColor := AColor;
  Result := Self;
end;

function TConsoleMenu.MaxRows(const AValue: Integer): TConsoleMenu;
begin
  FMaxRows := AValue;
  Result := Self;
end;

function TConsoleMenu.ColumnGap(const AValue: Integer): TConsoleMenu;
begin
  FColumnGap := AValue;
  Result := Self;
end;

function TConsoleMenu.Add(const AItemName: string;
  const ACallback: TMenuCallback): TConsoleMenu;
var
  LItem: TMenuItem;
begin
  if FCurrentCategorySub <> nil then
  begin
    Result := FCurrentCategorySub.Add(AItemName, ACallback);
    Exit;
  end;
  LItem.ItemName := AItemName;
  LItem.Callback := ACallback;
  LItem.SubMenu  := nil;
  LItem.Kind     := TMenuItemKind.Action;
  FItems.Add(LItem);
  Result := Self;
end;

function TConsoleMenu.AddSeparator(): TConsoleMenu;
var
  LItem: TMenuItem;
begin
  if FCurrentCategorySub <> nil then
  begin
    Result := FCurrentCategorySub.AddSeparator();
    Exit;
  end;
  LItem.ItemName := '';
  LItem.Callback := nil;
  LItem.SubMenu  := nil;
  LItem.Kind     := TMenuItemKind.Separator;
  FItems.Add(LItem);
  Result := Self;
end;

function TConsoleMenu.AddSubmenu(const ATitle: string): TConsoleMenu;
var
  LItem:  TMenuItem;
  LChild: TConsoleMenu;
begin
  LChild := TConsoleMenu.Create();
  LChild.FIsRoot := False;
  LChild.FTitle := ATitle;
  LChild.FExitLabel := 'Return';
  PropagateColors(LChild);
  FChildren.Add(LChild);

  LItem.ItemName := ATitle;
  LItem.Callback := nil;
  LItem.SubMenu  := LChild;
  LItem.Kind     := TMenuItemKind.Submenu;
  FItems.Add(LItem);

  Result := LChild;
end;

function TConsoleMenu.AddSubmenu(const AConsoleMenu: TConsoleMenu; const ATitle: string): TConsoleMenu;
var
  LItem: TMenuItem;
begin
  AConsoleMenu.FIsRoot := False;
  AConsoleMenu.FTitle := ATitle;
  AConsoleMenu.FExitLabel := 'Return';
  PropagateColors(AConsoleMenu);
  FChildren.Add(AConsoleMenu);

  LItem.ItemName := ATitle;
  LItem.Callback := nil;
  LItem.SubMenu  := AConsoleMenu;
  LItem.Kind     := TMenuItemKind.Submenu;
  FItems.Add(LItem);

  Result := AConsoleMenu;
end;

{ TConsoleMenu.AddTestCase }

function TConsoleMenu.AddTestCase(const ATestClass: TTestCaseClass): TConsoleMenu;

  // Nested helpers to safely capture values for closures
  function MakeRunAll(const AClass: TTestCaseClass): TMenuCallback;
  begin
    Result := procedure
    begin
      TTestCase.Run(AClass);
    end;
  end;

  function MakeRunOne(const AClass: TTestCaseClass;
    const AName: string): TMenuCallback;
  begin
    Result := procedure
    begin
      TTestCase.RunTest(AClass, AName);
    end;
  end;

var
  LTemp: TTestCase;
  LNames: TArray<string>;
  LI: Integer;
  LSub: TConsoleMenu;
  LItem: TMenuItem;
begin
  if FCurrentCategorySub <> nil then
  begin
    Result := FCurrentCategorySub.AddTestCase(ATestClass);
    Exit;
  end;
  // Create a temp instance to read registered test names and title
  LTemp := ATestClass.Create();
  try
    LNames := LTemp.GetTestNames();
    LSub := AddSubmenu(LTemp.Title);

    // Tag the submenu item with the test case class for CLI discovery
    LItem := FItems[FItems.Count - 1];
    LItem.Kind := TMenuItemKind.TestCase;
    LItem.TestCaseClass := ATestClass;
    FItems[FItems.Count - 1] := LItem;

    // First item: Run All
    LSub.Add('Run All', MakeRunAll(ATestClass));
    LSub.AddSeparator();

    // Individual tests
    for LI := 0 to High(LNames) do
      LSub.Add(LNames[LI], MakeRunOne(ATestClass, LNames[LI]));
  finally
    LTemp.Free();
  end;

  Result := Self;
end;

{ TConsoleMenu.AddTestDemo }

function TConsoleMenu.AddTestDemo(const ADemoClass: TTestDemoClass): TConsoleMenu;

  function MakeRunner(const AClass: TTestDemoClass): TMenuCallback;
  begin
    Result := procedure
    begin
      TTestDemo.Run(AClass);
    end;
  end;

var
  LTemp: TTestDemo;
  LTitle: string;
  LItem: TMenuItem;
begin
  if FCurrentCategorySub <> nil then
  begin
    Result := FCurrentCategorySub.AddTestDemo(ADemoClass);
    Exit;
  end;
  // Create a temp instance to read its title
  LTemp := ADemoClass.Create();
  try
    LTitle := LTemp.Title;
  finally
    LTemp.Free();
  end;

  Add(LTitle, MakeRunner(ADemoClass));

  // Tag the item with the demo class for CLI discovery
  LItem := FItems[FItems.Count - 1];
  LItem.Kind := TMenuItemKind.TestDemo;
  LItem.TestDemoClass := ADemoClass;
  FItems[FItems.Count - 1] := LItem;

  Result := Self;
end;

procedure TConsoleMenu.Clear();
begin
  FItems.Clear();
  FChildren.Clear();
end;

function TConsoleMenu.ActionCount(): Integer;
var
  LI: Integer;
begin
  Result := 0;
  for LI := 0 to FItems.Count - 1 do
  begin
    if FItems[LI].Kind <> TMenuItemKind.Separator then
      Inc(Result);
  end;
end;

{ TConsoleMenu.SetCategory }

procedure TConsoleMenu.SetCategory(const ACategory: string);
var
  LSub: TConsoleMenu;
begin
  if ACategory = '' then
  begin
    ClearCategory();
    Exit;
  end;
  FCurrentCategory := ACategory;
  LSub := AddSubmenu(ACategory);
  FCurrentCategorySub := LSub;

  // "Run All" iterates the submenu's live item list at execution time,
  // so items added after this call are included.
  LSub.Add('Run All', procedure
  var
    LI: Integer;
    LItem: TMenuItem;
    LTemp: TTestCase;
  begin
    for LI := 0 to LSub.FItems.Count - 1 do
    begin
      LItem := LSub.FItems[LI];
      case LItem.Kind of
        TMenuItemKind.Action:
          if (LItem.ItemName <> 'Run All') and Assigned(LItem.Callback) then
            LItem.Callback();
        TMenuItemKind.TestCase:
          if LItem.TestCaseClass <> nil then
          begin
            LTemp := LItem.TestCaseClass.Create();
            try
              LTemp.Pause := False;
              LTemp.Execute();
            finally
              LTemp.Free();
            end;
          end;
        TMenuItemKind.TestDemo:
          if LItem.TestDemoClass <> nil then
            TTestDemo.Run(LItem.TestDemoClass);
      end;
    end;
    TConsole.Pause();
  end);
  LSub.AddSeparator();
end;

{ TConsoleMenu.ClearCategory }

procedure TConsoleMenu.ClearCategory();
begin
  FCurrentCategory := '';
  FCurrentCategorySub := nil;
end;

procedure TConsoleMenu.Run();
var
  LInput:          string;
  LChoice:         Integer;
  LI:              Integer;
  LRow:            Integer;
  LCol:            Integer;
  LIdx:            Integer;
  LNumber:         Integer;
  LRowCount:       Integer;
  LNumCols:        Integer;
  LDisplayCount:   Integer;
  LMaxRowsEff:     Integer;
  LHasContent:     Boolean;
  LActionMap:      TList<Integer>;
  LDisplayNumbers: TArray<Integer>;
  LItem:           TMenuItem;
  LColWidths:      TArray<Integer>;
  LLine:           string;
  LPadded:         string;
begin
  // CLI mode: if command-line args present, run headless and exit
  if CLI() then
    Exit;

  LActionMap := TList<Integer>.Create();
  try
    // Guard: MaxRows must be at least 1.
    LMaxRowsEff := FMaxRows;
    if LMaxRowsEff < 1 then
      LMaxRowsEff := 20;

    while True do
    begin
      // Build action map and display numbers.
      // Display list = all FItems (including separators).
      // Actions get sequential numbers; separators get 0.
      LActionMap.Clear();
      LDisplayCount := FItems.Count;
      SetLength(LDisplayNumbers, LDisplayCount);
      LNumber := 0;
      for LI := 0 to FItems.Count - 1 do
      begin
        if FItems[LI].Kind = TMenuItemKind.Separator then
          LDisplayNumbers[LI] := 0
        else
        begin
          Inc(LNumber);
          LDisplayNumbers[LI] := LNumber;
          LActionMap.Add(LI);
        end;
      end;

      // Calculate column layout (separators count as rows).
      if LDisplayCount > LMaxRowsEff then
        LNumCols := (LDisplayCount + LMaxRowsEff - 1) div LMaxRowsEff
      else
        LNumCols := 1;

      if LDisplayCount <= LMaxRowsEff then
        LRowCount := LDisplayCount
      else
        LRowCount := LMaxRowsEff;

      // Pass 1: max item name width per column (separators contribute 0).
      SetLength(LColWidths, LNumCols);
      for LCol := 0 to LNumCols - 1 do
      begin
        LColWidths[LCol] := 0;
        for LRow := 0 to LRowCount - 1 do
        begin
          LIdx := LCol * LMaxRowsEff + LRow;
          if LIdx >= LDisplayCount then
            Break;
          if FItems[LIdx].Kind <> TMenuItemKind.Separator then
          begin
            if FItems[LIdx].ItemName.Length > LColWidths[LCol] then
              LColWidths[LCol] := FItems[LIdx].ItemName.Length;
          end;
        end;
      end;

      // Clear screen.
      TConsole.ClearScreen();

      // Title.
      TConsole.PrintLn('');
      TConsole.PrintLn(FTitleColor + '  [ ' + FTitle + ' ]');
      TConsole.PrintLn('');

      // Pass 2: display row by row, column by column.
      for LRow := 0 to LRowCount - 1 do
      begin
        LLine := '  ';
        LHasContent := False;
        for LCol := 0 to LNumCols - 1 do
        begin
          LIdx := LCol * LMaxRowsEff + LRow;
          if LIdx >= LDisplayCount then
            Break;
          LHasContent := True;
          if FItems[LIdx].Kind = TMenuItemKind.Separator then
          begin
            // Blank space matching [NNN] (6 chars) + column name width.
            LLine := LLine + StringOfChar(' ', 6 + LColWidths[LCol]);
          end
          else
          begin
            LPadded := FItems[LIdx].ItemName;
            while LPadded.Length < LColWidths[LCol] do
              LPadded := LPadded + ' ';
            LLine := LLine + FItemNumberColor +
              Format('[%.3d] ', [LDisplayNumbers[LIdx]]) + FItemColor + LPadded;
          end;
          if LCol < LNumCols - 1 then
            LLine := LLine + StringOfChar(' ', FColumnGap);
        end;
        if LHasContent then
          TConsole.PrintLn(LLine);
      end;

      // Exit/return option.
      TConsole.PrintLn('');
      TConsole.PrintLn('  ' + FItemNumberColor + '[000] ' +
        FExitColor + '%s', [FExitLabel]);
      TConsole.PrintLn('');

      // Prompt.
      TConsole.Print(FPromptColor + '  ' + FPromptText);
      ReadLn(LInput);

      LChoice := StrToIntDef(LInput.Trim(), -1);

      // Exit/Return.
      if LChoice = 0 then
        Break;

      // Execute action or enter submenu.
      if (LChoice >= 1) and (LChoice <= LActionMap.Count) then
      begin
        LItem := FItems[LActionMap[LChoice - 1]];

        if LItem.Kind in [TMenuItemKind.Submenu, TMenuItemKind.TestCase,
          TMenuItemKind.TestDemo] then
        begin
          if LItem.SubMenu <> nil then
            LItem.SubMenu.Run();
        end
        else if Assigned(LItem.Callback) then
        begin
          TConsole.ClearScreen();
          LItem.Callback();
          if FPause then
            TConsole.Pause();
        end;
      end
      else
        TConsole.PrintLn(FErrorColor + '  Invalid choice.');
    end;
  finally
    LActionMap.Free();
  end;
end;

{ TConsoleMenu.DoShowCLIHelp }

{ TConsoleMenu.CollectTestCases }

procedure TConsoleMenu.CollectTestCases(const AList: TList<TTestCaseClass>);
var
  LI: Integer;
  LItem: TMenuItem;
begin
  for LI := 0 to FItems.Count - 1 do
  begin
    LItem := FItems[LI];
    if (LItem.Kind = TMenuItemKind.TestCase) and (LItem.TestCaseClass <> nil) then
      AList.Add(LItem.TestCaseClass);
    // Recurse into submenus (including TestCase submenus and plain Submenus)
    if (LItem.SubMenu <> nil) then
      LItem.SubMenu.CollectTestCases(AList);
  end;
end;

procedure TConsoleMenu.DoShowCLIHelp();
begin
  TConsole.PrintLn('Usage: <exe> [selectors] [options]');
  TConsole.PrintLn('');
  TConsole.PrintLn('Selectors (combinable):');
  TConsole.PrintLn('  -all                 Run all registered test cases');
  TConsole.PrintLn('  TestName             Run a specific test by name');
  TConsole.PrintLn('  CaseName.TestName    Run a specific test within a case');
  TConsole.PrintLn('');
  TConsole.PrintLn('Options:');
  //TConsole.PrintLn('  -q                   Quiet mode (failures only)');
  TConsole.PrintLn('  -list                List all test cases and tests');
  TConsole.PrintLn('  -h, --help           Show this help');
end;

{ TConsoleMenu.CLI }

function TConsoleMenu.CLI(): Boolean;
var
  LI: Integer;
  LJ: Integer;
  LK: Integer;
  LFlag: string;
  LSelectors: TList<string>;
  LAllCases: TList<TTestCaseClass>;
  //LQuiet: Boolean;
  LRunAll: Boolean;
  LTemp: TTestCase;
  LNames: TArray<string>;
  LTitle: string;
  LPassCount: Integer;
  LFailCount: Integer;
  LTotalCount: Integer;
  LPassed: Boolean;
  LSel: string;
  LCaseName: string;
  LTestName: string;
  LDotPos: Integer;
begin
  // Bare invocation: fall through to menu
  if ParamCount() = 0 then
    Exit(False);

  Result := True;
  //LQuiet := False;
  LRunAll := False;
  LSelectors := TList<string>.Create();
  LAllCases := TList<TTestCaseClass>.Create();
  try
    // Collect test cases from the entire menu tree
    CollectTestCases(LAllCases);

    // Parse command line
    LI := 1;
    while LI <= ParamCount() do
    begin
      LFlag := ParamStr(LI).Trim();

      if (LFlag = '-h') or (LFlag = '--help') then
      begin
        DoShowCLIHelp();
        ExitCode := 0;
        Exit(True);
      end
      else if LFlag = '-list' then
      begin
        // List all test cases and their tests
        for LJ := 0 to LAllCases.Count - 1 do
        begin
          LTemp := LAllCases[LJ].Create();
          try
            TConsole.PrintLn(COLOR_CYAN + '%s', [LTemp.Title]);
            LNames := LTemp.GetTestNames();
            for LK := 0 to High(LNames) do
              TConsole.PrintLn('  %s', [LNames[LK]]);
          finally
            LTemp.Free();
          end;
        end;
        ExitCode := 0;
        Exit(True);
      end
      else if LFlag = '-all' then
        LRunAll := True
      //else if LFlag = '-q' then
      //  LQuiet := True
      else if LFlag.StartsWith('-') then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: unknown flag: %s', [LFlag]);
        TConsole.PrintLn('');
        DoShowCLIHelp();
        ExitCode := 2;
        Exit(True);
      end
      else
        LSelectors.Add(LFlag);

      Inc(LI);
    end;

    if (not LRunAll) and (LSelectors.Count = 0) then
    begin
      TConsole.PrintLn(COLOR_RED + 'Error: no selector given.');
      TConsole.PrintLn('');
      DoShowCLIHelp();
      ExitCode := 2;
      Exit(True);
    end;

    LPassCount := 0;
    LFailCount := 0;
    LTotalCount := 0;

    for LJ := 0 to LAllCases.Count - 1 do
    begin
      LTemp := LAllCases[LJ].Create();
      try
        LTemp.Pause := False;
        LTitle := LTemp.Title;
        LNames := LTemp.GetTestNames();

        if LRunAll then
        begin
          // Run all tests in this case
          Inc(LTotalCount, Length(LNames));
          LTemp.Execute();
          if LTemp.AllPassed then
            Inc(LPassCount, Length(LNames))
          else
            Inc(LFailCount);
        end
        else
        begin
          // Match selectors against test case title and test names
          for LSel in LSelectors do
          begin
            LDotPos := Pos('.', LSel);

            if LDotPos > 0 then
            begin
              // CaseName.TestName format
              LCaseName := Copy(LSel, 1, LDotPos - 1);
              LTestName := Copy(LSel, LDotPos + 1, MaxInt);
              if SameText(LCaseName, LTitle) then
              begin
                Inc(LTotalCount);
                LPassed := TTestCase.RunTest(LAllCases[LJ], LTestName);
                if LPassed then
                  Inc(LPassCount)
                else
                  Inc(LFailCount);
              end;
            end
            else
            begin
              // Plain name: match against case title or test names
              if SameText(LSel, LTitle) then
              begin
                // Run entire case
                Inc(LTotalCount, Length(LNames));
                LTemp.Execute();
                if LTemp.AllPassed then
                  Inc(LPassCount, Length(LNames))
                else
                  Inc(LFailCount);
              end
              else
              begin
                // Match against individual test names
                for LK := 0 to High(LNames) do
                begin
                  if SameText(LSel, LNames[LK]) then
                  begin
                    Inc(LTotalCount);
                    LPassed := TTestCase.RunTest(LAllCases[LJ], LNames[LK]);
                    if LPassed then
                      Inc(LPassCount)
                    else
                      Inc(LFailCount);
                  end;
                end;
              end;
            end;
          end;
        end;
      finally
        LTemp.Free();
      end;
    end;

    if LTotalCount = 0 then
    begin
      TConsole.PrintLn(COLOR_RED + 'No tests matched the selection.');
      ExitCode := 1;
      Exit(True);
    end;

    // Summary
    TConsole.PrintLn('');
    if LFailCount = 0 then
      TConsole.PrintLn(COLOR_GREEN + COLOR_BOLD +
        '=== ALL PASSED (%d tests) ===', [LTotalCount])
    else
      TConsole.PrintLn(COLOR_RED + COLOR_BOLD +
        '=== FAILED (%d passed, %d failed of %d) ===',
        [LPassCount, LFailCount, LTotalCount]);

    if LFailCount > 0 then
      ExitCode := 1
    else
      ExitCode := 0;
  finally
    LAllCases.Free();
    LSelectors.Free();
  end;
end;

end.
