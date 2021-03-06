unit KM_Log;
{$I KaM_Remake.inc}
interface
uses
  SysUtils, Classes, KM_Utils;


type
  //Logging system
  TKMLog = class
  private
    fl: textfile;
    fLogPath: UnicodeString;
    fFirstTick: cardinal;
    fPreviousTick: cardinal;
    fPreviousDate: TDateTime;
    procedure AddLineTime(const aText: UnicodeString);
    procedure AddLineNoTime(const aText: UnicodeString);
  public
    constructor Create(const aPath: UnicodeString);
    // AppendLog adds the line to Log along with time passed since previous line added
    procedure AddTime(const aText: UnicodeString); overload;
    procedure AddTime(const aText: UnicodeString; num: Integer); overload;
    procedure AddTime(const aText: UnicodeString; num: Single); overload;
    procedure AddTime(num: Integer; const aText: UnicodeString); overload;
    procedure AddTime(const aText: UnicodeString; Res: boolean); overload;
    procedure AddTime(a, b: integer); overload;
    // Add line if TestValue=false
    procedure AddAssert(const aMessageText: UnicodeString);
    // AddToLog simply adds the text
    procedure AddNoTime(const aText: UnicodeString);
    procedure DeleteOldLogs;
    property LogPath: UnicodeString read fLogPath; //Used by dedicated server
  end;

var
  gLog: TKMLog;


implementation
uses
  KM_Defaults;


//New thread, in which old logs are deleted (used internally)
type
  TKMOldLogsDeleter = class(TThread)
  private
    fPathToLogs: UnicodeString;
  public
    constructor Create(const aPathToLogs: UnicodeString);
    procedure Execute; override;
  end;


{ TKMOldLogsDeleter }
constructor TKMOldLogsDeleter.Create(const aPathToLogs: UnicodeString);
begin
  //Thread isn't started until all constructors have run to completion
  //so Create(False) may be put in front as well
  inherited Create(False);

  //Must set these values BEFORE starting the thread
  FreeOnTerminate := True; //object can be automatically removed after its termination
  fPathToLogs := aPathToLogs;
end;


procedure TKMOldLogsDeleter.Execute;
var
  SearchRec: TSearchRec;
  fileDateTime: TDateTime;
begin
  if not DirectoryExists(fPathToLogs) then Exit;

  if FindFirst(fPathToLogs + 'KaM*.log', faAnyFile - faDirectory, SearchRec) = 0 then
  repeat
    Assert(FileAge(fPathToLogs + SearchRec.Name, fileDateTime), 'How is that it does not exists any more?');

    if (Abs(Now - fileDateTime) > DEL_LOGS_OLDER_THAN) then
      DeleteFile(fPathToLogs + SearchRec.Name);
  until (FindNext(SearchRec) <> 0);
  FindClose(SearchRec);
end;


{ TKMLog }
constructor TKMLog.Create(const aPath: UnicodeString);
begin
  inherited Create;
  fLogPath := aPath;
  fFirstTick := TimeGet;
  fPreviousTick := TimeGet;
  ForceDirectories(ExtractFilePath((aPath)));

  AssignFile(fl, fLogPath);
  Rewrite(fl);
  //           hh:nn:ss.zzz 12345.678s 1234567ms     text-text-text
  WriteLn(fl, '   Timestamp    Elapsed     Delta     Description');
  CloseFile(fl);

  AddLineTime('Log is up and running. Game version: ' + GAME_VERSION);
end;


//Run thread to delete old logs.
procedure TKMLog.DeleteOldLogs;
begin
  if Self = nil then Exit;

  //No need to remember the instance, it's set to FreeOnTerminate
  TKMOldLogsDeleter.Create(ExtractFilePath(fLogPath));
end;


//Lines are timestamped, each line invokes file open/close for writing,
//meaning that no lines will be lost if Remake crashes
procedure TKMLog.AddLineTime(const aText: UnicodeString);
begin
  AssignFile(fl, fLogPath);
  Append(fl);
  //Write a line when the day changed since last time (useful for dedicated server logs that could be over months)
  if Abs(Trunc(fPreviousDate) - Trunc(Now)) >= 1 then
  begin
    WriteLn(fl, '========================');
    WriteLn(fl, '    Date: ' + FormatDateTime('yyyy/mm/dd', Now));
    WriteLn(fl, '========================');
  end;
  WriteLn(fl, Format('%12s %9.3fs %7dms     %s', [
                FormatDateTime('hh:nn:ss.zzz', Now),
                GetTimeSince(fFirstTick) / 1000,
                GetTimeSince(fPreviousTick),
                aText]));
  CloseFile(fl);
  fPreviousTick := TimeGet;
  fPreviousDate := Now;
end;


{Same line but without timestamp}
procedure TKMLog.AddLineNoTime(const aText: UnicodeString);
begin
  AssignFile(fl, fLogPath);
  Append(fl);
  WriteLn(fl, '                                      ' + aText);
  CloseFile(fl);
end;


procedure TKMLog.AddTime(const aText: UnicodeString);
begin
  if Self = nil then Exit;

  AddLineTime(aText);
end;


procedure TKMLog.AddTime(const aText: UnicodeString; num: integer);
begin
  if Self = nil then Exit;

  AddLineTime(aText + ' ' + inttostr(num));
end;


procedure TKMLog.AddTime(const aText: UnicodeString; num: single);
begin
  if Self = nil then Exit;

  AddLineTime(aText + ' ' + floattostr(num));
end;


procedure TKMLog.AddTime(num: integer; const aText: UnicodeString);
begin
  if Self = nil then Exit;

  AddLineTime(inttostr(num) + ' ' + aText);
end;


procedure TKMLog.AddTime(const aText: UnicodeString; Res: boolean);
var
  s: UnicodeString;
begin
  if Self = nil then Exit;

  if Res then
    s := 'done'
  else
    s := 'fail';
  AddLineTime(aText + ' ... ' + s);
end;


procedure TKMLog.AddTime(A, B: integer);
begin
  if Self = nil then Exit;

  AddLineTime(inttostr(A) + ' : ' + inttostr(B));
end;


procedure TKMLog.AddAssert(const aMessageText: UnicodeString);
begin
  if Self = nil then Exit;

  AddLineNoTime('ASSERTION FAILED! Msg: ' + aMessageText);
  Assert(False, 'ASSERTION FAILED! Msg: ' + aMessageText);
end;


procedure TKMLog.AddNoTime(const aText: UnicodeString);
begin
  if Self = nil then Exit;

  AddLineNoTime(aText);
end;


end.
