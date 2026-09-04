{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Http - HTTP/HTTPS client utilities

  Thin wrapper over Delphi's THTTPClient providing simple GET requests
  and file downloads with progress reporting. Handles HTTPS, automatic
  redirect following, and safe file downloads via atomic rename.

  Key types:
  - THttpResponse: Status code + body record from GET requests
  - THttpProgressCallback: Progress function for file downloads
    (return False to abort)
  - THttp: Static utility class with Get() and DownloadFile()

  Dependencies: StdApp.Utils (for CreateDirInPath)
  Notes: Downloads write to a .tmp file first and rename on completion,
    so partial downloads never produce a valid output file.
===============================================================================}

unit StdApp.Http;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Net.HttpClient,
  System.Net.URLClient;

type
  { THttpProgressCallback }
  // Progress callback for file downloads.
  // ABytesReceived: total bytes received so far.
  // ABytesTotal: total content length (-1 if unknown).
  // Return True to continue, False to abort the download.
  THttpProgressCallback = reference to function(
    const ABytesReceived: Int64;
    const ABytesTotal: Int64;
    const AUserData: Pointer): Boolean;

  { THttpResponse }
  // Result of an HTTP GET request.
  THttpResponse = record
    StatusCode: Integer;
    Body: string;
    function IsOk(): Boolean;
  end;

  { THttp }
  // Static HTTP utility class. Handles HTTPS, redirects, and chunked
  // downloads with progress callbacks.
  THttp = class
  private type
    { TDownloadHelper }
    // Internal helper bridging THTTPClient's OnReceiveData (of object)
    // to the reference-based THttpProgressCallback.
    TDownloadHelper = class
    private
      FCallback: THttpProgressCallback;
      FUserData: Pointer;
      FAborted: Boolean;
      procedure HandleReceiveData(const ASender: TObject;
        AContentLength: Int64; AReadCount: Int64;
        var AAbort: Boolean);
    end;
  public
    // Perform an HTTP GET request. Returns status code and body.
    // Raises on network-level errors (DNS failure, timeout, etc.).
    class function Get(const AUrl: string): THttpResponse; static;

    // Download a file from AUrl to ADestPath with optional progress.
    // Downloads to a .tmp file first, renames atomically on success.
    // Returns True on success, False on HTTP error or cancellation.
    // Cleans up partial downloads on failure.
    class function DownloadFile(const AUrl: string;
      const ADestPath: string;
      const ACallback: THttpProgressCallback = nil;
      const AUserData: Pointer = nil): Boolean; static;

    // Perform an HTTP POST with a string body. Returns status code and body.
    class function Post(const AUrl: string;
      const ABody: string;
      const AContentType: string = 'application/json'): THttpResponse; static;

    // POST to a URL, writing the response to AStream as chunks arrive.
    // Used for SSE streaming: pass a custom TStream that processes data
    // in its Write() override. Returns the HTTP status code.
    class function PostToStream(const AUrl: string;
      const ABody: string;
      const AStream: TStream;
      const AContentType: string = 'application/json'): Integer; static;
  end;

implementation

uses
  StdApp.Utils;

{ THttpResponse }

function THttpResponse.IsOk(): Boolean;
begin
  Result := (StatusCode >= 200) and (StatusCode < 300);
end;

{ THttp.TDownloadHelper }

procedure THttp.TDownloadHelper.HandleReceiveData(
  const ASender: TObject; AContentLength: Int64; AReadCount: Int64;
  var AAbort: Boolean);
begin
  if Assigned(FCallback) then
  begin
    if not FCallback(AReadCount, AContentLength, FUserData) then
    begin
      AAbort := True;
      FAborted := True;
    end;
  end;
end;

{ THttp }

class function THttp.Get(const AUrl: string): THttpResponse;
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
begin
  Result.StatusCode := 0;
  Result.Body := '';

  LClient := THTTPClient.Create;
  try
    LResponse := LClient.Get(AUrl);
    Result.StatusCode := LResponse.StatusCode;
    Result.Body := LResponse.ContentAsString();
  finally
    LClient.Free();
  end;
end;

class function THttp.DownloadFile(const AUrl: string;
  const ADestPath: string;
  const ACallback: THttpProgressCallback;
  const AUserData: Pointer): Boolean;
var
  LClient: THTTPClient;
  LHelper: TDownloadHelper;
  LStream: TFileStream;
  LResponse: IHTTPResponse;
  LTmpPath: string;
begin
  Result := False;
  LTmpPath := ADestPath + '.tmp';

  // Ensure destination directory exists
  TUtils.CreateDirInPath(ADestPath);

  LHelper := TDownloadHelper.Create();
  try
    LHelper.FCallback := ACallback;
    LHelper.FUserData := AUserData;
    LHelper.FAborted := False;

    LClient := THTTPClient.Create;
    try
      LClient.OnReceiveData := LHelper.HandleReceiveData;

      try
        LStream := TFileStream.Create(LTmpPath, fmCreate);
        try
          LResponse := LClient.Get(AUrl, LStream);
        finally
          LStream.Free();
        end;
      except
        // Network error: clean up partial download
        if TFile.Exists(LTmpPath) then
          TFile.Delete(LTmpPath);
        Exit;
      end;

      // Aborted by user callback
      if LHelper.FAborted then
      begin
        if TFile.Exists(LTmpPath) then
          TFile.Delete(LTmpPath);
        Exit;
      end;

      // HTTP error (non-2xx status)
      if (LResponse.StatusCode < 200) or (LResponse.StatusCode >= 300) then
      begin
        if TFile.Exists(LTmpPath) then
          TFile.Delete(LTmpPath);
        Exit;
      end;

      // Success: atomic rename tmp -> final
      if TFile.Exists(ADestPath) then
        TFile.Delete(ADestPath);
      TFile.Move(LTmpPath, ADestPath);
      Result := True;

    finally
      LClient.Free();
    end;
  finally
    LHelper.Free();
  end;
end;

class function THttp.Post(const AUrl: string;
  const ABody: string;
  const AContentType: string): THttpResponse;
var
  LClient: THTTPClient;
  LSource: TStringStream;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
begin
  Result.StatusCode := 0;
  Result.Body := '';

  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 30000;
    LClient.ResponseTimeout := 300000;

    LSource := TStringStream.Create(ABody, TEncoding.UTF8);
    try
      SetLength(LHeaders, 1);
      LHeaders[0] := TNameValuePair.Create('Content-Type', AContentType);
      LResponse := LClient.Post(AUrl, LSource, nil, LHeaders);
      Result.StatusCode := LResponse.StatusCode;
      Result.Body := LResponse.ContentAsString();
    finally
      LSource.Free();
    end;
  finally
    LClient.Free();
  end;
end;

class function THttp.PostToStream(const AUrl: string;
  const ABody: string;
  const AStream: TStream;
  const AContentType: string): Integer;
var
  LClient: THTTPClient;
  LSource: TStringStream;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
begin
  LClient := THTTPClient.Create;
  try
    // Long timeout for model loading + streaming inference
    LClient.ConnectionTimeout := 30000;
    LClient.ResponseTimeout := 300000;

    LSource := TStringStream.Create(ABody, TEncoding.UTF8);
    try
      SetLength(LHeaders, 1);
      LHeaders[0] := TNameValuePair.Create('Content-Type', AContentType);
      LResponse := LClient.Post(AUrl, LSource, AStream, LHeaders);
      Result := LResponse.StatusCode;
    finally
      LSource.Free();
    end;
  finally
    LClient.Free();
  end;
end;

end.
