{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  UTestCase.Script - Script engine test cases

  End-to-end tests for TMyrScriptEngine: full pipeline from source string
  through lex, parse, semantics, and interpret. Tests exercise writeln
  capture, variable declarations, control flow, user routines, builtin
  registration, and error reporting.

  Dependencies: StdApp.TestCase, Myrissa.Script
===============================================================================}

unit UTestCase.Script;

interface

uses
  StdApp.TestCase;

type

  { TCPScriptTests }
  TCPScriptTests = class(TTestCase)
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Rtti,
  StdApp.Base,
  Myrissa.Common,
  Myrissa.Frontend,
  Myrissa.Script;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type
  TOutputCapture = record
    Lines: TArray<string>;
    procedure Reset();
    procedure Add(const AText: string; const ANewLine: Boolean);
    function Text(): string;
  end;

procedure TOutputCapture.Reset();
begin
  Lines := [];
end;

procedure TOutputCapture.Add(const AText: string; const ANewLine: Boolean);
begin
  Lines := Lines + [AText];
end;

function TOutputCapture.Text(): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Lines) do
  begin
    if I > 0 then
      Result := Result + #10;
    Result := Result + Lines[I];
  end;
end;

// ---------------------------------------------------------------------------
// Constructor -- register all tests
// ---------------------------------------------------------------------------

{ TCPScriptTests }
constructor TCPScriptTests.Create();
begin
  inherited;
  Title := 'Script';

  // -- Basic: writeln through full pipeline --
  RegisterTest('exec_writeln', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource('''
        module script test_writeln;
        begin
          println("hello from script");
        end.
        ''',
        'test_writeln.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = 'hello from script', 'output matches: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Variables and arithmetic --
  RegisterTest('exec_variables', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_vars;
        var
          x: int32;
          y: int32;
        begin
          x := 10;
          y := x + 5;
          println(y);
        end.
        ''',
        'test_vars.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '15', 'y = 15: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- If/else control flow --
  RegisterTest('exec_if_else', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_if;
        var
          x: int32;
        begin
          x := 42;
          if x > 10 then
            println("big");
          else
            println("small");
          end
        end.
        ''',
        'test_if.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = 'big', 'took then branch: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- While loop --
  RegisterTest('exec_while', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_while;
        var
          i: int32;
        begin
          i := 0;
          while i < 3 do
            i := i + 1;
          end
          println(i);
        end.
        ''',
        'test_while.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '3', 'i = 3: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- User-defined function --
  RegisterTest('exec_user_routine', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_func;
        routine double(const x: int32): int32;
        begin
          return x * 2;
        end;
        begin
          println(double(7));
        end.
        ''',
        'test_func.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '14', 'double(7) = 14: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Builtin registration and call --
  RegisterTest('exec_builtin', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
    LBuiltinCalled: Boolean;
  begin
    LCapture.Reset();
    LBuiltinCalled := False;
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LEngine.RegisterGlobalRoutine('routine TestPing()',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          LBuiltinCalled := True;
          Result := TMyrScriptValue.Empty;
        end);
      LEngine.PrintErrors();
      Check(not LEngine.GetErrors().HasErrors(), 'registration succeeded');

      LOk := LEngine.ExecuteSource(
        '''
        module script test_builtin;
        begin
          TestPing();
          println("after ping");
        end.
        ''',
        'test_builtin.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LBuiltinCalled, 'builtin was called');
      Check(LCapture.Text() = 'after ping', 'output after builtin: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Registered routine with parameters --
  RegisterTest('exec_routine_args', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
    LReceived: string;
  begin
    LCapture.Reset();
    LReceived := '';
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LEngine.RegisterGlobalRoutine('routine SetValue(const AValue: string)',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          LReceived := AArgs[0].AsString;
          Result := TMyrScriptValue.Empty;
        end);

      LEngine.RegisterGlobalRoutine('routine AddNums(const A: int32; const B: int32): int32',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<Int64>(AArgs[0].AsInt64 + AArgs[1].AsInt64);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_args;
        begin
          SetValue("hello");
          println(AddNums(3, 7));
        end.
        ''',
        'test_args.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LReceived = 'hello', 'SetValue received: [%s]', [LReceived]);
      Check(LCapture.Text() = '10', 'AddNums(3,7) = 10: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Registered routines with varied param/return types --
  RegisterTest('exec_routine_types', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      // string -> string
      LEngine.RegisterGlobalRoutine('routine Greet(const AName: string): string',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<string>('hello ' + AArgs[0].AsString);
        end);

      // float64 -> float64
      LEngine.RegisterGlobalRoutine('routine Half(const AVal: float64): float64',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<Double>(AArgs[0].AsExtended / 2.0);
        end);

      // boolean -> boolean
      LEngine.RegisterGlobalRoutine('routine Flip(const AFlag: boolean): boolean',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<Boolean>(not AArgs[0].AsBoolean);
        end);

      // int64 -> int64
      LEngine.RegisterGlobalRoutine('routine Square64(const AVal: int64): int64',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<Int64>(AArgs[0].AsInt64 * AArgs[0].AsInt64);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_types;
        var
          s: string;
          f: float64;
          b: boolean;
          n: int64;
        begin
          s := Greet("world");
          println(s);
          f := Half(9.0);
          println(f);
          b := Flip(false);
          println(b);
          n := Square64(12);
          println(n);
        end.
        ''',
        'test_types.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 4, 'got 4 output lines');
      Check(LCapture.Lines[0] = 'hello world', 'string return: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '4.5', 'float64 return: [%s]', [LCapture.Lines[1]]);
      Check(LCapture.Lines[2] = 'true', 'boolean return: [%s]', [LCapture.Lines[2]]);
      Check(LCapture.Lines[3] = '144', 'int64 return: [%s]', [LCapture.Lines[3]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Mixed-type multi-param routines --
  RegisterTest('exec_routine_mixed', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      // string + int32 + boolean -> string
      LEngine.RegisterGlobalRoutine(
        'routine Format3(const ALabel: string; const ACount: int32; const AFlag: boolean): string',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<string>(Format('%s:%d:%s', [
            AArgs[0].AsString, AArgs[1].AsInt64,
            IfThen(AArgs[2].AsBoolean, 'ON', 'OFF')]));
        end);

      // float64 + int32 -> float64
      LEngine.RegisterGlobalRoutine(
        'routine Scale(const AVal: float64; const AFactor: int32): float64',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<Double>(AArgs[0].AsExtended * AArgs[1].AsInt64);
        end);

      // string + string -> string
      LEngine.RegisterGlobalRoutine(
        'routine Join(const A: string; const B: string): string',
        function(const AArgs: TMyrScriptArgs;
          const AInterpreter: TMyrScriptInterpreter;
          const AUserData: Pointer): TMyrScriptValue
        begin
          Result := TMyrScriptValue.From<string>(AArgs[0].AsString + '-' + AArgs[1].AsString);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_mixed;
        var
          s: string;
          f: float64;
        begin
          s := Format3("items", 42, true);
          println(s);
          f := Scale(3.5, 4);
          println(f);
          println(Join("hello", "world"));
        end.
        ''',
        'test_mixed.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 3, 'got 3 output lines');
      Check(LCapture.Lines[0] = 'items:42:ON', 'mixed params: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '14', 'float*int: [%s]', [LCapture.Lines[1]]);
      Check(LCapture.Lines[2] = 'hello-world', 'two strings: [%s]', [LCapture.Lines[2]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Recursion --
  RegisterTest('exec_recursion', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_rec;
        routine factorial(const n: int32): int32;
        begin
          if n <= 1 then
            return 1;
          end
          return n * factorial(n - 1);
        end;
        begin
          println(factorial(6));
        end.
        ''',
        'test_rec.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '720', 'factorial(6) = 720: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- For loop --
  RegisterTest('exec_for', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_for;
        var
          i: int32;
          sum: int32;
        begin
          sum := 0;
          for i := 1 to 5 do
            sum := sum + i;
          end;
          println(sum);
        end.
        ''',
        'test_for.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '15', 'sum 1..5 = 15: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Repeat/until --
  RegisterTest('exec_repeat', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_repeat;
        var
          x: int32;
        begin
          x := 0;
          repeat
            x := x + 1;
          until x = 5;
          println(x);
        end.
        ''',
        'test_repeat.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '5', 'repeat to 5: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Break and continue --
  RegisterTest('exec_break_continue', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_bc;
        var
          i: int32;
          sum: int32;
        begin
          sum := 0;
          for i := 1 to 10 do
            if i = 6 then
              break;
            end
            sum := sum + i;
          end;
          println(sum);
        end.
        ''',
        'test_bc.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '15', 'break at 6, sum 1..5 = 15: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Match/case --
  RegisterTest('exec_match', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_match;
        var
          x: int32;
        begin
          x := 3;
          match x of
            1: println("one");
            2: println("two");
            3: println("three");
          else
            println("other");
          end;
        end.
        ''',
        'test_match.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = 'three', 'matched 3: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Nested control flow --
  RegisterTest('exec_nested', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_nested;
        var
          i: int32;
          j: int32;
          count: int32;
        begin
          count := 0;
          for i := 1 to 3 do
            for j := 1 to 3 do
              if (i + j) > 3 then
                count := count + 1;
              end
            end;
          end;
          println(count);
        end.
        ''',
        'test_nested.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(LCapture.Text() = '6', 'nested loops+if count: [%s]', [LCapture.Text()]);
    finally
      LEngine.Free();
    end;
  end);

  // -- RegisterGlobalData: injected constants --
  RegisterTest('exec_register_data', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LEngine.RegisterGlobalData(
        '''
        const
          MY_VALUE = 42;
          MY_NAME = "hello";
        '''
      );
      Check(not LEngine.GetErrors().HasErrors(), 'RegisterGlobalData succeeded');

      LOk := LEngine.ExecuteSource(
        '''
        module script test_data;
        begin
          println("{}", MY_VALUE);
          println(MY_NAME);
        end.
        ''',
        'test_data.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '42', 'MY_VALUE = 42: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = 'hello', 'MY_NAME = hello: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Syntax error reports failure --
  RegisterTest('exec_error', procedure
  var
    LEngine: TMyrScriptEngine;
    LOk: Boolean;
  begin
    LEngine := TMyrScriptEngine.Create();
    try
      LOk := LEngine.ExecuteSource(
        '''
        module script test_err;
        begin
          this is not valid syntax
        end.
        ''',
        'test_err.cps');

      Check(not LOk, 'ExecuteSource returns false on syntax error');
    finally
      LEngine.Free();
    end;
  end);

  // -- Record literal, field access, field assignment --
  RegisterTest('exec_record', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_record;
        type
          Point = record
            x: int32;
            y: int32;
          end;
        var
          p: Point;
        begin
          p := Point(x: 10, y: 20);
          println(p.x);
          println(p.y);
          p.x := 99;
          println(p.x);
        end.
        ''',
        'test_record.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 3, 'got 3 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '10', 'p.x = 10: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '20', 'p.y = 20: [%s]', [LCapture.Lines[1]]);
      Check(LCapture.Lines[2] = '99', 'p.x after assign = 99: [%s]', [LCapture.Lines[2]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Array indexing and setlength --
  RegisterTest('exec_array', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_array;
        var
          a: array of int32;
        begin
          setlength(a, 3);
          a[0] := 10;
          a[1] := 20;
          a[2] := 30;
          println(a[0]);
          println(a[1]);
          println(a[2]);
          println(len(a));
        end.
        ''',
        'test_array.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 4, 'got 4 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '10', 'a[0] = 10: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '20', 'a[1] = 20: [%s]', [LCapture.Lines[1]]);
      Check(LCapture.Lines[2] = '30', 'a[2] = 30: [%s]', [LCapture.Lines[2]]);
      Check(LCapture.Lines[3] = '3', 'len(a) = 3: [%s]', [LCapture.Lines[3]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Set literal and in operator --
  RegisterTest('exec_set', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_set;
        var
          s: set of int32;
          x: int32;
        begin
          s := [1, 3, 5..7];
          x := 3;
          if x in s then
            println("yes")
          else
            println("no")
          end;
          x := 4;
          if x in s then
            println("yes")
          else
            println("no")
          end;
        end.
        ''',
        'test_set.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = 'yes', '3 in set: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = 'no', '4 not in set: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- ThrowCode and guard with exccode/excmsg --
  RegisterTest('exec_guard_exccode', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_guard;
        begin
          guard
            throwcode(42, "test error");
          except
            println(exccode());
            println(excmsg());
          end;
        end.
        ''',
        'test_guard.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '42', 'exccode = 42: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = 'test error', 'excmsg = test error: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Assert statements --
  RegisterTest('exec_assert_pass', procedure
  var
    LEngine: TMyrScriptEngine;
    LOk: Boolean;
  begin
    LEngine := TMyrScriptEngine.Create();
    try
      LOk := LEngine.ExecuteSource(
        '''
        module script test_assert;
        begin
          assert(true);
          asserttrue(1 = 1);
          assertfalse(1 = 2);
          asserteq(10, 10);
        end.
        ''',
        'test_assert.cps');

      LEngine.PrintErrors();
      Check(LOk, 'all asserts pass');
    finally
      LEngine.Free();
    end;
  end);

  // -- Assert failure --
  RegisterTest('exec_assert_fail', procedure
  var
    LEngine: TMyrScriptEngine;
    LOk: Boolean;
  begin
    LEngine := TMyrScriptEngine.Create();
    try
      LOk := LEngine.ExecuteSource(
        '''
        module script test_assert_fail;
        begin
          asserteq(10, 20);
        end.
        ''',
        'test_assert_fail.cps');

      Check(not LOk, 'asserteq(10,20) fails execution');
    finally
      LEngine.Free();
    end;
  end);

  // -- Choices (enum) dot access --
  RegisterTest('exec_choices', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_choices;
        type
          Color = choices(Red, Green, Blue);
        var
          c: Color;
        begin
          c := Color.Green;
          println(c);
          if c = Color.Green then
            println("green")
          end;
        end.
        ''',
        'test_choices.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '1', 'Color.Green = 1: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = 'green', 'matched green: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Deref through pointer (new/dispose) --
  RegisterTest('exec_new_dispose', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_new;
        type
          Pair = record
            a: int32;
            b: int32;
          end;
          PairPtr = pointer to Pair;
        var
          p: PairPtr;
        begin
          new(p);
          p^.a := 100;
          p^.b := 200;
          println(p^.a);
          println(p^.b);
          dispose(p);
        end.
        ''',
        'test_new.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '100', 'p^.a = 100: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '200', 'p^.b = 200: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- String indexing --
  RegisterTest('exec_string_index', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_stridx;
        var
          s: string;
        begin
          s := "hello";
          println(s[1]);
          println(s[5]);
          println(len(s));
        end.
        ''',
        'test_stridx.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 3, 'got 3 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = 'h', 's[1] = h: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = 'o', 's[5] = o: [%s]', [LCapture.Lines[1]]);
      Check(LCapture.Lines[2] = '5', 'len = 5: [%s]', [LCapture.Lines[2]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- Compound assignment on composites --
  RegisterTest('exec_compound_assign', procedure
  var
    LEngine: TMyrScriptEngine;
    LCapture: TOutputCapture;
    LOk: Boolean;
  begin
    LCapture.Reset();
    LEngine := TMyrScriptEngine.Create();
    try
      LEngine.SetPrintCallback(
        procedure(const AText: string; const ANewLine: Boolean; const AUserData: Pointer)
        begin
          LCapture.Add(AText, ANewLine);
        end);

      LOk := LEngine.ExecuteSource(
        '''
        module script test_compound;
        type
          Counter = record
            value: int32;
          end;
        var
          c: Counter;
          a: array of int32;
        begin
          c := Counter(value: 10);
          c.value += 5;
          println(c.value);
          setlength(a, 2);
          a[0] := 100;
          a[0] += 50;
          println(a[0]);
        end.
        ''',
        'test_compound.cps');

      LEngine.PrintErrors();
      Check(LOk, 'ExecuteSource returns true');
      Check(Length(LCapture.Lines) = 2, 'got 2 output lines: [%d]', [Length(LCapture.Lines)]);
      Check(LCapture.Lines[0] = '15', 'c.value += 5 = 15: [%s]', [LCapture.Lines[0]]);
      Check(LCapture.Lines[1] = '150', 'a[0] += 50 = 150: [%s]', [LCapture.Lines[1]]);
    finally
      LEngine.Free();
    end;
  end);

  // -- C++ block runtime error --
  RegisterTest('exec_cpp_error', procedure
  var
    LEngine: TMyrScriptEngine;
    LOk: Boolean;
  begin
    LEngine := TMyrScriptEngine.Create();
    try
      LOk := LEngine.ExecuteSource(
        '''
        module script test_cpp;
        begin
          cppstart source
            // some c++ code
          cppend;
        end.
        ''',
        'test_cpp.cps');

      Check(not LOk, 'cppstart raises runtime error');
    finally
      LEngine.Free();
    end;
  end);
end;

procedure TCPScriptTests.Run();
begin
  inherited;
end;

end.
