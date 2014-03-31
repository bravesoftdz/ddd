program ddd;

{$APPTYPE CONSOLE}

uses
  Windows, StrUtils, SysUtils, Classes, WindowsVersion;

//------------------------------------------------------------------------------

type

  ByteArray =   array[0..65535] of Byte;
  ByteArray2 =  array[0..262143] of Byte;

  TDiskGeometry = packed record
    Cylinders:          Int64;
    MediaType:          Integer;
    TracksPerCylinder:  DWORD;
    SectorsPerTrack:    DWORD;
    BytesPerSector:     Integer; // wichtig f�r die Reservierung des Buffer-Speichers
  end;

  TRawDrive = record
    DiskGeometry:       TDiskGeometry;
    Handle:             THandle;
  end;


  TIDERegs = packed record
    bFeaturesReg:       BYTE; // Used for specifying SMART ""commands"".
    bSectorCountReg:    BYTE; // IDE sector count register
    bSectorNumberReg:   BYTE; // IDE sector number register
    bCylLowReg:         BYTE; // IDE low order cylinder value
    bCylHighReg:        BYTE; // IDE high order cylinder value
    bDriveHeadReg:      BYTE; // IDE drive/head register
    bCommandReg:        BYTE; // Actual IDE command.
    bReserved:          BYTE; // reserved for future use.  Must be zero.
  end;

  TSendCmdInParams = packed record
    cBufferSize:        DWORD; // Buffer size in bytes
    irDriveRegs:        TIDERegs; // Structure with drive register values.
    bDriveNumber:       BYTE; // Physical drive number to send command to (0,1,2,3).
    bReserved:          array[0..2] of Byte;
    dwReserved:         array[0..3] of DWORD;
    bBuffer:            array[0..0] of Byte; // Input buffer.
  end;

  TIdSector = packed record
    wGenConfig:         Word;
    wNumCyls:           Word;
    wReserved:          Word;
    wNumHeads:          Word;
    wBytesPerTrack:     Word;
    wBytesPerSector:    Word;
    wSectorsPerTrack:   Word;
    wVendorUnique:      array[0..2] of Word;
    sSerialNumber:      array[0..19] of CHAR;
    wBufferType:        Word;
    wBufferSize:        Word;
    wECCSize:           Word;
    sFirmwareRev:       array[0..7] of Char;
    sModelNumber:       array[0..39] of Char;
    wMoreVendorUnique:  Word;
    wDoubleWordIO:      Word;
    wCapabilities:      Word;
    wReserved1:         Word;
    wPIOTiming:         Word;
    wDMATiming:         Word;
    wBS: Word;
    wNumCurrentCyls:    Word;
    wNumCurrentHeads:   Word;
    wNumCurrentSectorsPerTrack: Word;
    ulCurrentSectorCapacity:    DWORD;
    wMultSectorStuff:   Word;
    ulTotalAddressableSectors:  DWORD;
    wSingleWordDMA:     Word;
    wMultiWordDMA:      Word;
    bReserved:          array[0..127] of BYTE;
  end;

  PIdSector = ^TIdSector;
  TDriverStatus = packed record
    bDriverError:       Byte; // Error code from driver, or 0 if no error.
    bIDEStatus:         Byte; // Contents of IDE Error register. Only valid when bDriverError is SMART_IDE_ERROR.
    bReserved:          array[0..1] of Byte;
    dwReserved:         array[0..1] of DWORD;
  end;

  TSendCmdOutParams = packed record
    cBufferSize:        DWORD; // Size of bBuffer in bytes
    DriverStatus:       TDriverStatus; // Driver status structure.
    bBuffer:            array[0..0] of BYTE; // Buffer of arbitrary length in which to store the data read from the drive.
  end;

//------------------------------------------------------------------------------

const
  //Versionsinfo
  VERSIONINFO: String =#201+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#187+#13+#10+
                       #186+' DigiCorder Disk Dump V1.6 '+#186+#13+#10+
                       #200+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#205+#188;

  //Copyright
  COPYRIGHT: String   ='� 2006-2012 by Lostech';

  //Homepage Adresse
  HOMEPAGE: String    ='www.lostech.de.vu';

  //Beschreibung
  DESCRIPTION: String ='Disk dumping tool for TechniSat�'+#13+#10+'* DigiCorder S1'+#13+#10+'* DigiCorder T1'+#13+#10+'* DigiCorder S2'+#13+#10+'* DigiCorder K2'+#13+#10+'* DigiCorder HD S2'+#13+#10+'* DigiCorder HD K2'+#13+#10+'and compatible devices with TSD filesystem.'+#13+#10;

  //Warnung
  WARNING: String     ='Use at own risk! Removing HDD from Receiver/TV results in losing warranty!';

  //Betriebssystem Konstanten
  cOsUnknown  =-1;
  cOsWin95    =0;
  cOsWin98    =1;
  cOsWin98SE  =2;
  cOsWinME    =3;
  cOsWinNT    =4;
  cOsWin2000  =5;
  cOsXP       =6;

  //Disk Raw Zugriff Konstanten
  IOCTL_DISK_GET_DRIVE_GEOMETRY=  $00070000;
  IDENTIFY_BUFFER_SIZE=           512;

  //Konstanten f�r Farben in der Konsole definieren
  YellowOnBlue    =FOREGROUND_GREEN OR FOREGROUND_RED OR FOREGROUND_INTENSITY OR BACKGROUND_BLUE;
  WhiteOnBlue     =FOREGROUND_BLUE OR FOREGROUND_GREEN OR FOREGROUND_RED OR FOREGROUND_INTENSITY OR BACKGROUND_BLUE;
  BlueOnWhite     =BACKGROUND_BLUE OR BACKGROUND_GREEN OR BACKGROUND_RED OR BACKGROUND_INTENSITY OR FOREGROUND_BLUE;
  RedOnWhite      =FOREGROUND_RED OR FOREGROUND_INTENSITY OR BACKGROUND_RED OR BACKGROUND_GREEN OR BACKGROUND_BLUE OR BACKGROUND_INTENSITY;
  WhiteOnRed      =BACKGROUND_RED OR BACKGROUND_INTENSITY OR FOREGROUND_RED OR FOREGROUND_GREEN OR FOREGROUND_BLUE OR FOREGROUND_INTENSITY;
  ConsoleStandard =FOREGROUND_BLUE OR FOREGROUND_GREEN OR FOREGROUND_RED;

//------------------------------------------------------------------------------

var
  //Laufwerke (PhysicalDrive)
  PVR_Drive:            String;
  PVR_Drive2:           String;
  PVR_Size:             Int64;
  PVR_Size2:            Int64;

  //Image Datei
  PVR_Image:            String;

  //Argumente/Optionen in Main
  POS1:                 Integer;
  CounterMain:          Integer;
  ParameterstringMain:  String;
  CmdLineError:         Boolean;
  ColorMain:            Word;

  //zus�tzliche Variablen
  Buffer:               String;

  //globaler Event
  GlobalEvent:          String;

  //globale Abbruch Variable
  Globalbreak:          Boolean;

  //Handle to console window
  ConHandle:            THandle;

  //To store/set screen position
  Coord:                TCoord;

  //To store max window size
  MaxX, MaxY:           Word;
  CCI:                  TConsoleCursorInfo;

  //To store results of some functions
  NOAW:                 Cardinal;

  //ignoriere Fehler beim auslesen
  IgnoreErrors:         Boolean;

//------------------------------------------------------------------------------

procedure ChangeByteOrder(var Data; Size: Integer);
//Byte Reihenfolge tauschen
var
  ptr: PChar;
  i: Integer;
  c: Char;

begin
  ptr := @Data;
  for i := 0 to (Size shr 1) - 1 do
  begin
    c := ptr^;
    ptr^ := (ptr + 1)^;
    (ptr + 1)^ := c;
    Inc(ptr, 2);
  end;
end;

function GetConInputHandle : THandle;
//Get handle to console input
begin
 Result := GetStdHandle(STD_INPUT_HANDLE)
end;

function GetConOutputHandle : THandle;
//Get handle to console output
begin
 Result := GetStdHandle(STD_OUTPUT_HANDLE)
end;

function ReadKey: Char;
//Tastendruck abfragen
var
  NumRead: Cardinal;
  InputRec: TInputRecord;
begin
  while ((not ReadConsoleInput(GetStdHandle(STD_INPUT_HANDLE), InputRec, 1, NumRead)) or (InputRec.EventType <> KEY_EVENT)) do ;
  Result := InputRec.Event.KeyEvent.AsciiChar;
end;

function WhereX: integer;
//X Position in der Konsole abfragen
var
  cbi: TConsoleScreenBufferInfo;
begin
  getConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), cbi);
  result := tcoord(cbi.dwCursorPosition).x + 1
end;

function WhereY: integer;
//Y Position in der Konsole abfragen
var
  cbi: TConsoleScreenBufferInfo;
begin
  getConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), cbi);
  result := tcoord(cbi.dwCursorPosition).y + 1
end;

procedure GotoXY(X, Y : Word);
//zur X/Y Position in der Konsole springen
begin
 Coord.X := X; Coord.Y := Y;
 SetConsoleCursorPosition(ConHandle, Coord);
end;

procedure CLS;
//Clear Screen - Bildschirm mit Leerzeichen �berschreiben
begin
 Coord.X := 0; Coord.Y := 0;
 FillConsoleOutputCharacter(ConHandle, ' ', MaxX*MaxY, Coord, NOAW);
 GotoXY(0, 0);
end;

procedure ShowCursor(Show : Bool);
//Cursor ein-/ausblenden
begin
 CCI.bVisible := Show;
 SetConsoleCursorInfo(ConHandle, CCI);
end;

procedure Init;
//Globale Konsolen Variablen initialisieren
begin
  //Get console output handle
  ConHandle := GetConOutputHandle;

  //Get max window size
  Coord := GetLargestConsoleWindowSize(ConHandle);
  MaxX := Coord.X;
  MaxY := Coord.Y;
end;

procedure StatusLine(S : String);
//Statuszeile schreiben
begin
  Coord.X := 0;
  Coord.Y := 0;
  WriteConsoleOutputCharacter(ConHandle, PChar(S),   Length(S)+1, Coord, NOAW);
  FillConsoleOutputAttribute (ConHandle, WhiteOnRed, Length(S),   Coord, NOAW);
end;

procedure ClearStatusLine;
//Statuszeile l�schen
var
  S : String;

begin
  Coord.X := 0;
  Coord.Y := 0;
  S:=StringOfChar(' ',79);
  WriteConsoleOutputCharacter(ConHandle, PChar(S),   Length(S)+1, Coord, NOAW);
  FillConsoleOutputAttribute (ConHandle, WhiteOnBlue, Length(S),   Coord, NOAW);
end;

procedure NewLine(S: String; Color: Integer);
//Neue Zeile schreiben
begin
  Coord.X := WhereX-1;
  Coord.Y := WhereY;
  S:=S+StringOfChar(' ',80-Length(S));
  WriteConsoleOutputCharacter(ConHandle, PChar(S),   Length(S)+1, Coord, NOAW);
  FillConsoleOutputAttribute (ConHandle, Color, Length(S),   Coord, NOAW);
  GotoXY(WhereX-1,WhereY+1);
end;

function ConProc(CtrlType : DWord) : Bool; stdcall; far;
//Console Event Handler z.B. f�r STRG+C abfragen
var
 S : String;

begin
  //Event Typ auswerten
  case CtrlType of
    CTRL_C_EVENT        : S := 'CTRL_C_EVENT';
    CTRL_BREAK_EVENT    : S := 'CTRL_BREAK_EVENT';
    CTRL_CLOSE_EVENT    : S := 'CTRL_CLOSE_EVENT';
    CTRL_LOGOFF_EVENT   : S := 'CTRL_LOGOFF_EVENT';
    CTRL_SHUTDOWN_EVENT : S := 'CTRL_SHUTDOWN_EVENT';
  else
    S := 'UNKNOWN_EVENT';
  end;

 //Abbruch
 StatusLine('[ Warning: '+S+' received ]');
 GlobalBreak:=true;
 GlobalEvent:=S;
 Result := True;
end;

procedure RestoreConsole;
//Farbe der Konsole wieder herstellen
begin
  //Abbruchmeldung
  if GlobalBreak=true then
    begin
      sleep(100);
      ClearStatusLine;
      NewLine('Program abort due to a '+GlobalEvent,BlueOnWhite);
    end;

  //Farbe der Console wieder auf Standard zur�cksetzen
  ColorMain:=ConsoleStandard;
  FillConsoleOutputAttribute(ConHandle, ColorMain, MaxX*MaxY, Coord, NOAW);
  SetConsoleTextAttribute(ConHandle,ColorMain);
  ShowCursor(true);

  //Abbruchbedingung melden
  if GlobalBreak=true then
    ExitCode:=10;
end;

function DriveSize(Drive: String): Int64;
//Laufwerksgr��e in Bytes auslesen
var
  hDevice:  Cardinal;
  RawDrive: TRawDrive;
  BytesReturned: Cardinal;

begin
  DriveSize:=0;
  FillChar(RawDrive, SizeOf(TRawDrive), 0);
  hDevice:=CreateFile(pchar('\\.\'+Drive), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice = INVALID_HANDLE_VALUE then
    begin
      Exit;
    end;
  if DeviceIoControl(hDevice, IOCTL_DISK_GET_DRIVE_GEOMETRY, nil, 0, @RawDrive.DiskGeometry, SizeOf(TDiskGeometry), BytesReturned, nil)=true then
    begin
      DriveSize:=RawDrive.DiskGeometry.Cylinders*RawDrive.DiskGeometry.TracksPerCylinder*RawDrive.DiskGeometry.SectorsPerTrack*RawDrive.DiskGeometry.BytesPerSector;
    end;
  CloseHandle(hDevice);
end;

function GetDosDevice(PhysicalDrive: String): String;
//DOSDeviceName bzw. Symlinks auslesen
var
  Buffer: string;

begin
  SetLength(Buffer,256);
  Buffer:=StringOfChar(#0,Length(Buffer));
  try
  QueryDosDevice(PChar(PhysicalDrive), @Buffer[1], 256);
  except
  Buffer:='';
  end;
  Buffer:=StringReplace(Buffer,#0,'',[rfReplaceAll, rfIgnoreCase]);
  Result:=Trim(Buffer);
end;

procedure DriveInfo(Drive: String);
//Laufwerksinfo anzeigen
var
  Buffer:             String;
  hDevice:            Cardinal;
  RawDrive:           TRawDrive;
  BytesReturned:      Cardinal;
  cbBytesReturned: DWORD;
  SCIP: TSendCmdInParams;
  aIdOutCmd: array[0..(SizeOf(TSendCmdOutParams) + IDENTIFY_BUFFER_SIZE - 1) - 1] of Byte;
  IdOutCmd: TSendCmdOutParams absolute aIdOutCmd;

begin
  //Grundeinstellungen
  hDevice:=CreateFile(pchar('\\.\'+Drive), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice = INVALID_HANDLE_VALUE then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive)>0 then
        writeln('Error:'+#9+'Could not access "'+Drive+'" for reading!')
      else
        writeln('Error:'+#9+'Could not access Drive "'+AnsiReplaceStr(Drive,'\\.\','')+'" for reading!');
      writeln('');
      ExitCode:=5;
      RestoreConsole;
      Exit;
    end;
  if DeviceIoControl(hDevice, IOCTL_DISK_GET_DRIVE_GEOMETRY, nil, 0, @RawDrive.DiskGeometry, SizeOf(TDiskGeometry), BytesReturned, nil)=true then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive)>0 then
        writeln('"'+Drive+'" detailed infos!')
      else
        writeln('Drive "'+AnsiReplaceStr(Drive,'\\.\','')+'" detailed infos!');
      writeln('');
      writeln('       Info        |       Value');
      writeln('-------------------+-------------------');
      FillChar(SCIP, SizeOf(TSendCmdInParams) - 1, #0);
      FillChar(aIdOutCmd, SizeOf(aIdOutCmd), #0);
      cbBytesReturned := 0;
      // Set up data structures for IDENTIFY command.
      with SCIP do
        begin
          cBufferSize := IDENTIFY_BUFFER_SIZE;
          //      bDriveNumber := 0;
          with irDriveRegs do
            begin
              bSectorCountReg := 1;
              bSectorNumberReg := 1;
              //      if Win32Platform=VER_PLATFORM_WIN32_NT then bDriveHeadReg := $A0
              //      else bDriveHeadReg := $A0 or ((bDriveNum and 1) shl 4);
              bDriveHeadReg := $A0;
              bCommandReg := $EC;
            end;
      end;
      if DeviceIoControl(hDevice, $0007C088, @SCIP, SizeOf(TSendCmdInParams) - 1, @aIdOutCmd, SizeOf(aIdOutCmd), cbBytesReturned, nil) then
        begin
          Buffer:='';
          with PIdSector(@IdOutCmd.bBuffer)^ do
            begin
              ChangeByteOrder(sModelNumber, SizeOf(sModelNumber));
              (PChar(@sModelNumber) + SizeOf(sModelNumber))^ := #0;
              Buffer:=PChar(@sModelNumber);
            end;
          writeln(' HDD Model         | '+Buffer);
          Buffer:='';
          with PIdSector(@IdOutCmd.bBuffer)^ do
            begin
              ChangeByteOrder(sFirmwareRev, SizeOf(sFirmwareRev));
              (PChar(@sFirmwareRev) + SizeOf(sFirmwareRev))^ := #0;
              Buffer:=PChar(@sFirmwareRev);
            end;
          writeln(' HDD Firmware      | '+Buffer);
          Buffer:='';
          with PIdSector(@IdOutCmd.bBuffer)^ do
            begin
              ChangeByteOrder(sSerialNumber, SizeOf(sSerialNumber));
              (PChar(@sSerialNumber) + SizeOf(sSerialNumber))^ := #0;
              Buffer:=PChar(@sSerialNumber);
            end;
          writeln(' HDD Serial        | '+Buffer);
        end;
      writeln(' Cylinders         | '+IntToStr(RawDrive.DiskGeometry.Cylinders));
      writeln(' TracksPerCylinder | '+IntToStr(RawDrive.DiskGeometry.TracksPerCylinder));
      writeln(' SectorsPerTrack   | '+IntToStr(RawDrive.DiskGeometry.SectorsPerTrack));
      writeln(' BytesPerSector    | '+IntToStr(RawDrive.DiskGeometry.BytesPerSector));
      writeln(' HDD physical size | '+format('%.2f GB',[RawDrive.DiskGeometry.Cylinders*RawDrive.DiskGeometry.TracksPerCylinder*RawDrive.DiskGeometry.SectorsPerTrack*RawDrive.DiskGeometry.BytesPerSector/1024/1024/1000]));
      Buffer:='';
      Buffer:=GetDosDevice(Drive);
      if Buffer<>'' then
        writeln(' MS-DOS Devicename | '+Buffer);
      writeln('');
    end;
  CloseHandle(hDevice);
end;

function AddPath(FileName: String): String;
//Pfadangabe erg�nzen wenn nur Dateiname und kein Pfad angegeben wurde
begin
  if ExtractFilePath(FileName)='' then
    AddPath:=ExtractFilePath(Paramstr(0))+FileName
  else
    AddPath:=FileName;
end;

{
function GetOperatingSystem: Integer;
//Betriebssystem auswerten
var
  osVerInfo: TOSVersionInfo;
  majorVer, minorVer: Integer;

begin
  //Betriebsystemversion auslesen
  osVerInfo.dwOSVersionInfoSize:=SizeOf(TOSVersionInfo);
  if GetVersionEx(osVerInfo) then
  begin
    //Betriebssystemversion auswerten
    majorVer:=osVerInfo.dwMajorVersion;
    minorVer:=osVerInfo.dwMinorVersion;
    case osVerInfo.dwPlatformId of
      //Windows NT/2000/XP
      VER_PLATFORM_WIN32_NT:
        begin
          if majorVer <= 4 then
            Result:=cOsWinNT
          else if (majorVer = 5) and (minorVer = 0) then
            Result:=cOsWin2000
          else if (majorVer = 5) and (minorVer = 1) then
            Result:=cOsXP
          else
            Result:=cOsUnknown;
        end;
      //Windows 9x/ME
      VER_PLATFORM_WIN32_WINDOWS:
        begin
          if (majorVer = 4) and (minorVer = 0) then
            Result:=cOsWin95
          else if (majorVer = 4) and (minorVer = 10) then
          begin
            if osVerInfo.szCSDVersion[1] = 'A' then
              Result:=cOsWin98SE
            else
              Result:=cOsWin98;
          end
          else if (majorVer = 4) and (minorVer = 90) then
            Result:=cOsWinME
          else
            Result:=cOsUnknown;
        end;
      else
        Result:=cOsUnknown;
    end;
  end
  else
    Result:=cOsUnknown;
end;
}

procedure Version;
//Programm Versionsinfo anzeigen
begin
  writeln('');
  writeln(VERSIONINFO);
  writeln('');
  writeln(DESCRIPTION);
  writeln(WARNING);
  writeln('');
  writeln(COPYRIGHT+'  '+HOMEPAGE);
  writeln('');
end;

procedure Help;
//Hilfe anzeigen
begin
  writeln('Available options:');
  writeln('-di[a..z]        set drive letter for read input (overrides automatic)');
  writeln('-dl[a..z]        show drive letter info');
  writeln('-do[a..z]        set drive letter for write output (without c: see remarks)');
  writeln('-erased[a..z]    erase selected drive by letter (without c: see remarks)');
  writeln('-erasepd[1..19]  erase selected PhysicalDrive');
  writeln('-errorignore     do not stop on read errors');
  writeln('-exitcodes       show list of possible exit codes');
  writeln('-help            show this help page');
  writeln('-i [filename]    set binary input filename');
  writeln('-list            show list of Magic Headers by PhysicalDrive');
  writeln('-list2           show list of Magic Headers by drive letter');
  writeln('-listdetails     show detailed list of PhysicalDrives (only if available)');
  writeln('-listdetails2    show detailed list of drives by letter (only if available)');
  writeln('-noboot          ignore bootsector during erasing or writing');
  writeln('-o [filename]    set binary output filename');
  writeln('-pd[0..19]       show PhysicalDrive info');
  writeln('-pdi[0..19]      set PhysicalDrive for read input (overrides automatic)');
  writeln('-pdo[1..19]      set PhysicalDrive for write output');

  writeln('');
  writeln('');
  writeln('Additional remarks:');
  writeln('1.) PhysicalDrive0 and drive c: are blocked for erasing and writing operations');
  writeln('    due to security reasons because this is normaly the main Windows HDD');
  writeln('2.) Option "-noboot" can only be applied for erasing and writing operations');
  writeln('3.) a program break can be done by pressing [CTRL+C]');
  writeln('4.) Option "-errorignore" may cause that the program does not stop on its own');
  writeln('    to stop it manually press [CTRL+C]');
  writeln('5.) Option "-list" shows all PhyiscalDrives which can be accessed.');
  writeln('    Option "-listdetails" shows instead only PhysicalDrives with available');
  writeln('    detail infos');
  writeln('6.) Option "-list2" shows all Drives by letters which can be accessed.');
  writeln('    Option "-listdetails2" shows instead only Drives by letters with available');
  writeln('    detail infos');
  writeln('7.) "TechniSat FS 1" signalizes a DigiCorder S1/T1 (and compatible) HDD');
  writeln('    "TechniSat FS 2" signalizes a DigiCorder (HD)S2/K2 (and compatible) HDD');


  writeln('');
  writeln('');
  writeln('Usage examples (change PhysicalDrive/Drive letter or file path to your needs):');
  writeln('1.) Dumping a DigiCorder HDD into a file:');
  writeln('    ddd.exe C:/Dumpfile.bin');
  writeln('    ddd.exe -pdi1 -o "C:/Dumpfile.bin"');
  writeln('');
  writeln('2.) Erasing a HDD:');
  writeln('    ddd.exe -erasepd2');
  writeln('    ddd.exe -erasepd2 -noboot');
  writeln('');
  writeln('3.) Writing a dump image to a HDD:');
  writeln('    ddd.exe -pdo1 -i "C:/Dumpfile.bin"');
  writeln('    ddd.exe -pdo1 -i "C:/Dumpfile.bin" -noboot');
  writeln('');
  writeln('4.) Copy a HDD to another HDD:');
  writeln('    ddd.exe -pdi1 -pdo2');
  writeln('    ddd.exe -pdi1 -pdo2 -noboot');
  writeln('');
end;

procedure ExitCodes;
//Exit Codes anzeigen
begin
  writeln('');
  writeln('Code | Meaning');
  writeln('-----+------------------------------------');
  writeln('  0  | no error');
  writeln('  1  | unsupported OS (Windows 9x and NT)');
  writeln('  2  | no commandline options declared');
  writeln('  3  | PVR HDD not found');
  writeln('  4  | no dump image filename declared');
  writeln('  5  | no PhysicalDrive read access');
  writeln('  6  | no PhysicalDrive write access');
  writeln('  7  | no dump image read access');
  writeln('  8  | no dump image write access');
  writeln('  9  | illegal commandline combination');
  writeln(' 10  | program aborted');
  writeln('');
end;

function ReadBlock(Drive: string; Block: LongInt; ChangeEndian: Boolean): ByteArray;
//Block von Festplatte lesen
var
  hDevice:  Cardinal;
  RipArray: ByteArray;
  NewArray: ByteArray;
  BytesRead: Cardinal;
  Counter: Integer;
  Sector: LARGE_INTEGER;

begin
  //einzelnen Block auslesen
  hDevice:=CreateFile(pchar('\\.\'+Drive), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice = INVALID_HANDLE_VALUE then
    begin
      Exit;
    end;
  if (Block>0) then
    Sector.QuadPart:=Block*65536
  else
    Sector.QuadPart:=0;
  SetFilePointer(hDevice,Sector.LowPart,@Sector.HighPart, FILE_BEGIN);
  ReadFile(hDevice, RipArray, SizeOf(RipArray), BytesRead, nil);
  CloseHandle (hDevice);

  //Endian Reihenfolge �ndern
  if ChangeEndian=true then
    begin
      Counter:=0;
      while Counter<SizeOf(RipArray)+1 do
        begin
          NewArray[Counter]:= RipArray[Counter+1];
          NewArray[Counter+1]:=RipArray[Counter];
          Counter:=Counter+2;
        end;
      ReadBlock:=NewArray;
    end
  else
    ReadBlock:=RipArray;
end;

function FindDrive: String;
//DigiCorder Festplatte finden
var
  ReadBlockArray: ByteArray;
  DriveNumber: Integer;

begin
  //20 m�gliche physikalische Laufwerke auf Magic pr�fen und das 1. gefundene Laufwerk melden
  FindDrive:='';
  for DriveNumber:=0 to 19 do
    begin
      ReadBlockArray[0]:=0;
      ReadBlockArray[1]:=0;
      ReadBlockArray[2]:=0;
      ReadBlockArray[3]:=0;
      ReadBlockArray:=ReadBlock('PhysicalDrive'+IntToStr(DriveNumber),0, false);
      //8C A2 76 B9 -> DigiCorder S1/T1
      if (ReadBlockArray[0]=140) and (ReadBlockArray[1]=162) and (ReadBlockArray[2]=118) and (ReadBlockArray[3]=185) then
        begin
          FindDrive:='PhysicalDrive'+IntToStr(DriveNumber);
          break;
        end;
      //B3 6E DB 8A -> DigiCorder S2/K2/HD S2
      if (ReadBlockArray[0]=179) and (ReadBlockArray[1]=110) and (ReadBlockArray[2]=219) and (ReadBlockArray[3]=138) then
        begin
          FindDrive:='PhysicalDrive'+IntToStr(DriveNumber);
          break;
        end;
    end;

  //26 m�gliche Laufwerksbuchstaben auf Magic pr�fen und das 1. gefundene Laufwerk melden
  for DriveNumber:=0 to 25 do
    begin
      ReadBlockArray[0]:=0;
      ReadBlockArray[1]:=0;
      ReadBlockArray[2]:=0;
      ReadBlockArray[3]:=0;
      ReadBlockArray:=ReadBlock('\\.\'+Chr(97+DriveNumber)+':',0, false);
      //8C A2 76 B9 -> DigiCorder S1/T1
      if (ReadBlockArray[0]=140) and (ReadBlockArray[1]=162) and (ReadBlockArray[2]=118) and (ReadBlockArray[3]=185) then
        begin
          FindDrive:='\\.\'+Chr(97+DriveNumber)+':';
          break;
        end;
      //B3 6E DB 8A -> DigiCorder S2/K2/HD S2
      if (ReadBlockArray[0]=179) and (ReadBlockArray[1]=110) and (ReadBlockArray[2]=219) and (ReadBlockArray[3]=138) then
        begin
          FindDrive:='\\.\'+Chr(97+DriveNumber)+':';
          break;
        end;
    end;
end;

procedure ListDrives;
//Festplatten auflisten
var
  ReadBlockArray: ByteArray;
  DriveNumber: Integer;
  DosDevice: String;

begin
  //20 m�gliche physikalische Laufwerke auf Magic pr�fen
  writeln('');
  writeln('     Drive      | MagicHeader |      HDD Type     |      MS-DOS Devicename');
  writeln('----------------+-------------+-------------------+----------------------------');
  for DriveNumber:=0 to 19 do
    begin
      ReadBlockArray[0]:=255;
      ReadBlockArray[1]:=254;
      ReadBlockArray[2]:=253;
      ReadBlockArray[3]:=252;
      ReadBlockArray:=ReadBlock('PhysicalDrive'+IntToStr(DriveNumber),0,false);
      //nur bei echtem Ergebnis eine Ausgabe anzeigen
      if (ReadBlockArray[0]<>255) and (ReadBlockArray[1]<>254) and (ReadBlockArray[2]<>253) and (ReadBlockArray[3]<>252) then
        begin
          DosDevice:=GetDosDevice('PhysicalDrive'+IntToStr(DriveNumber));
          //8C A2 76 B9 -> DigiCorder S1/T1
          if (ReadBlockArray[0]=140) and (ReadBlockArray[1]=162) and (ReadBlockArray[2]=118) and (ReadBlockArray[3]=185) then
            writeln('PhysicalDrive'+IntToStr(DriveNumber)+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | TechniSat FS 1    | '+DosDevice)
          //B3 6E DB 8A -> DigiCorder S2/K2/HD S2/HD K2
          else if (ReadBlockArray[0]=179) and (ReadBlockArray[1]=110) and (ReadBlockArray[2]=219) and (ReadBlockArray[3]=138) then
            writeln('PhysicalDrive'+IntToStr(DriveNumber)+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | TechniSat FS 2    | '+DosDevice)
          else
            writeln('PhysicalDrive'+IntToStr(DriveNumber)+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | unknown HDD       | '+DosDevice)
        end;
    end;
  writeln('');
end;

procedure ListDrivesByDriveLetter;
//Festplatten auflisten
var
  ReadBlockArray: ByteArray;
  DriveNumber: Integer;
  DosDevice: String;

begin
  //26 m�gliche Laufwerke auf Magic pr�fen
  writeln('');
  writeln('     Drive      | MagicHeader |      HDD Type     |      MS-DOS Devicename');
  writeln('----------------+-------------+-------------------+-----------------------------');
  for DriveNumber:=0 to 25 do
    begin
      ReadBlockArray[0]:=255;
      ReadBlockArray[1]:=254;
      ReadBlockArray[2]:=253;
      ReadBlockArray[3]:=252;
      ReadBlockArray:=ReadBlock(Chr(97+DriveNumber)+':',0,false);
      //nur bei echtem Ergebnis eine Ausgabe anzeigen
      if (ReadBlockArray[0]<>255) and (ReadBlockArray[1]<>254) and (ReadBlockArray[2]<>253) and (ReadBlockArray[3]<>252) then
        begin
          DosDevice:=GetDosDevice('PhysicalDrive'+IntToStr(DriveNumber));
          //8C A2 76 B9 -> DigiCorder S1/T1
          if (ReadBlockArray[0]=140) and (ReadBlockArray[1]=162) and (ReadBlockArray[2]=118) and (ReadBlockArray[3]=185) then
            writeln('Drive '+Chr(97+DriveNumber)+':'+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | TechniSat FS 1    | '+DosDevice)
          //B3 6E DB 8A -> DigiCorder S2/K2/HD S2/HD K2  Digit HD8-S/K
          else if (ReadBlockArray[0]=179) and (ReadBlockArray[1]=110) and (ReadBlockArray[2]=219) and (ReadBlockArray[3]=138) then
            writeln('Drive '+Chr(97+DriveNumber)+':'+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | TechniSat FS 2    | '+DosDevice)
          else
            writeln('Drive '+Chr(97+DriveNumber)+':'+#9+'| 0x'+IntToHex(ReadBlockArray[0],2)+IntToHex(ReadBlockArray[1],2)+IntToHex(ReadBlockArray[2],2)+IntToHex(ReadBlockArray[3],2)+'  | unknown HDD       | '+DosDevice)
        end;
    end;
  writeln('');
end;

procedure ListDrivesExtended;
//Festplatten auflisten (Details)
var
  hDevice:            Cardinal;
  DriveNumber:        Integer;

begin
  //20 m�gliche physikalische Laufwerke auf Detailinfos pr�fen
  writeln('');
  for DriveNumber:=0 to 19 do
    begin
    hDevice:=CreateFile(pchar('\\.\'+'PhysicalDrive'+IntToStr(DriveNumber)), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
    if hDevice = INVALID_HANDLE_VALUE then
      begin
        //writeln('');
        //writeln('Error:'+#9+'Could not access "'+'PhysicalDrive'+IntToStr(DriveNumber)+'" for reading!');
        //writeln('');
      end
    else
      begin
        DriveInfo('PhysicalDrive'+IntToStr(DriveNumber));
        CloseHandle(hDevice);
      end;
    end;
  writeln('');
end;

procedure ListDrivesExtendedByDriveLetter;
//Festplatten auflisten (Details)
var
  hDevice:            Cardinal;
  DriveNumber:        Integer;

begin
  //26 m�gliche Laufwerke auf Detailinfos pr�fen
  writeln('');
  for DriveNumber:=0 to 25 do
    begin
    hDevice:=CreateFile(pchar('\\.\'+Chr(97+DriveNumber)+':'), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
    if hDevice = INVALID_HANDLE_VALUE then
      begin
        //writeln('');
        //writeln('Error:'+#9+'Could not access "'+'PhysicalDrive'+IntToStr(DriveNumber)+'" for reading!');
        //writeln('');
      end
    else
      begin
        DriveInfo(Chr(97+DriveNumber)+':');
        CloseHandle(hDevice);
      end;
    end;
  writeln('');
end;

procedure DumpImage(Drive: String; ImageFile: String);
//Dump Image eines Laufwerks anlegen
var
  Percent, PercentOld: Single;
  hDevice, hDevice2:  Cardinal;
  BytesRead, BytesWritten: Cardinal;
  RipArray: ByteArray2;
  Position: LARGE_INTEGER;
  ImageSize: LARGE_INTEGER;

begin
  //Fehler beim auslesen ignorieren
  if IgnoreErrors=true then
    begin
      writeln('');
      writeln('Warning:'+#9+'Read errors will be ignored');
      writeln('Warning:'+#9+'If programm does not stop when source HD end is reached then exit by pressing [CTRL+C]');
      writeln('');
    end;

  //Festplattengr��e auslesen
  PVR_Size:=DriveSize(PVR_Drive);
  writeln('Info:'+#9+'Input HDD physical size'+#9+#9+format('%.2f GB',[PVR_Size/1024/1024/1000]));

  //Grundeinstellungen
  writeln('');
  write('Info:'+#9+'Progress [                    ]   0.0%');
  PercentOld:=0;
  Position.QuadPart:=0;

  //Laufwerk �ffnen
  hDevice:=CreateFile(pchar('\\.\'+Drive), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive)>0 then
        writeln('Error:'+#9+'Could not access "'+Drive+'" for reading!')
      else
        writeln('Error:'+#9+'Could not access Drive "'+AnsiReplaceStr(Drive,'\\.\','')+'" for reading!');
      writeln('');
      ExitCode:=5;
      RestoreConsole;
      Exit;
    end;

  //Dump Image �ffnen
  if FileExists(ImageFile) then
    DeleteFile(ImageFile);
  hDevice2:=CreateFile(pchar(ImageFile), GENERIC_WRITE, FILE_SHARE_WRITE, nil, OPEN_ALWAYS, 0, 0);
  if hDevice2=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      writeln('Error:'+#9+'Could not access "'+ImageFile+'" for writing!');
      writeln('');
      CloseHandle(hDevice);
      ExitCode:=8;
      RestoreConsole;
      Exit;
    end;

  //while (Position.QuadPart div 512)<SuperBlock.SectCount-1 do
  while (Position.QuadPart<PVR_Size-1) and (GlobalBreak=false) do
    begin
      //Daten aus Laufwerk auslesen
      SetFilePointer(hDevice,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      ReadFile(hDevice, RipArray, SizeOf(RipArray), BytesRead, nil);
      if BytesRead=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'End of HDD reached or read error');
          if IgnoreErrors=false then
            break;
        end;

      //Fortschrittsanzeige
      Percent:=(Position.QuadPart/PVR_Size)*100;
      if FormatFloat('000.0', Percent)<>FormatFloat('000.0', PercentOld) then
        begin
          PercentOld:=Percent;
          buffer:='['+StringOfChar(#254,trunc((Percent+0.1)*0.2))+StringOfChar(' ',20-trunc((Percent+0.1)*0.2))+'] '+StringOfChar(' ',3-Length(FormatFloat('000.0', Percent)))+FormatFloat('000.0', Percent)+'%';
          buffer:=StringOfChar(#8, Length(buffer))+buffer;
          buffer:=StringReplace(buffer, ',', '.',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 00', ']   ',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 0', ']  ',[rfReplaceAll, rfIgnoreCase]);
          write(buffer);
        end;

      //Daten in Dump Image schreiben
      SetFilePointer(hDevice2,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      WriteFile(hDevice2, RipArray, SizeOf(RipArray), BytesWritten, nil);

      if BytesWritten=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'Target HDD full or write error');
          break;
        end;
      Position.QuadPart:=Position.QuadPart+(SizeOf(RipArray));
    end;

  //Dump Image Gr��e ermitteln
  ImageSize.LowPart:=GetFileSize(hDevice2,@ImageSize.HighPart);
  writeln('');
  writeln('Info:'+#9+format('%.2f GB',[ImageSize.QuadPart/1024/1024/1000])+' written');

  //aufr�umen
  CloseHandle(hDevice);
  CloseHandle(hDevice2);
end;

procedure WriteImage(PhysicalDrive: String; ImageFile: String; IgnoreBootSector: Boolean);
//Dump Image eines Laufwerks anlegen
var
  Percent, PercentOld: Single;
  hDevice, hDevice2:  Cardinal;
  BytesRead, BytesWritten: Cardinal;
  WriteArray: ByteArray2;
  Position: LARGE_INTEGER;
  ImageSize: LARGE_INTEGER;

begin
  //Grundeinstellungen
  PercentOld:=0;
  if IgnoreBootSector=true then
    begin
      writeln('');
      writeln('Info:'+#9+'Ignore bootsector to be written');
      Position.QuadPart:=512;
    end
  else
    begin
      writeln('');
      writeln('Info:'+#9+'Allow bootsector to be written');
      Position.QuadPart:=0;
    end;

  //Sicherheitsabfrage
  if PhysicalDrive='PhysicalDrive0' then
    begin
      writeln('');
      writeln('Error:'+#9+'"PhysicalDrive0" not allowed for writing access due to safety reasons!');
      writeln('Hint:'+#9+'Try to set up target HDD with an higher drive number like "PhysicalDrive1".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;

  //Laufwerk �ffnen
  hDevice:=CreateFile(pchar('\\.\'+PhysicalDrive), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      writeln('Error:'+#9+'Could not access "'+PhysicalDrive+'" for writing!');
      writeln('');
      ExitCode:=6;
      RestoreConsole;
      Exit;
    end;

  //Dump Image �ffnen
  hDevice2:=CreateFile(pchar(ImageFile), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if hDevice2=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      writeln('Error:'+#9+'Could not access "'+ImageFile+'" for reading!');
      writeln('');
      CloseHandle(hDevice);
      ExitCode:=7;
      RestoreConsole;
      Exit;
    end;

  //Dump Image Gr��e ermitteln
  ImageSize.LowPart:=GetFileSize(hDevice2,@ImageSize.HighPart);
  writeln('Info:'+#9+'Input dump file size'+#9+#9+format('%.2f GB',[ImageSize.QuadPart/1024/1024/1000]));
  PVR_Size:=DriveSize(PhysicalDrive);
  writeln('Info:'+#9+'Output HDD disk size'+#9+#9+format('%.2f GB',[PVR_Size/1024/1024/1000]));
  if ImageSize.QuadPart-SizeOf(WriteArray)>PVR_Size then
    writeln('Info:'+#9+'Source dump image is bigger than target HDD!');
  if ImageSize.QuadPart<PVR_Size then
    writeln('Info:'+#9+'Source dump image is smaller than target HDD!');

  //Dump Image auf Ziellaufwerk schreiben
  writeln('');
  write('Info:'+#9+'Progress [                    ]   0.0%');
  while (Position.QuadPart<ImageSize.QuadPart-(SizeOf(WriteArray))) and (GlobalBreak=false) do
    begin
      //Daten aus Image auslesen
      SetFilePointer(hDevice2,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      ReadFile(hDevice2, WriteArray, SizeOf(WriteArray), BytesRead, nil);
      if BytesRead=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'End of dump image reached or read error');
          break;
        end;

      //Fortschrittsanzeige
      Percent:=(Position.QuadPart/ImageSize.QuadPart)*100;
      if FormatFloat('000.0', Percent)<>FormatFloat('000.0', PercentOld) then
        begin
          PercentOld:=Percent;
          buffer:='['+StringOfChar(#254,trunc((Percent+0.1)*0.2))+StringOfChar(' ',20-trunc((Percent+0.1)*0.2))+'] '+StringOfChar(' ',3-Length(FormatFloat('000.0', Percent)))+FormatFloat('000.0', Percent)+'%';
          buffer:=StringOfChar(#8, Length(buffer))+buffer;
          buffer:=StringReplace(buffer, ',', '.',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 00', ']   ',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 0', ']  ',[rfReplaceAll, rfIgnoreCase]);
          write(buffer);
        end;

      //Daten auf Laufwerk schreiben
      SetFilePointer(hDevice,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      WriteFile(hDevice, WriteArray, SizeOf(WriteArray), BytesWritten, nil);
      if BytesWritten=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'Target HDD full or write error');
          break;
        end;
      Position.QuadPart:=Position.QuadPart+(SizeOf(WriteArray));
    end;

  //meldung �ber die Anzahl der geschriebenen Daten
  writeln('');
  writeln('Info:'+#9+format('%.2f GB',[Position.QuadPart/1024/1024/1000])+' written');

  //aufr�umen
  CloseHandle(hDevice);
  CloseHandle(hDevice2);
end;

procedure CopyDrive(Drive1: String; Drive2: String; IgnoreBootSector: Boolean);
//Laufwerk kopieren
var
  Percent, PercentOld: Single;
  hDevice, hDevice2:  Cardinal;
  BytesRead, BytesWritten: Cardinal;
  WriteArray: ByteArray2;
  Position: LARGE_INTEGER;

begin
  //Grundeinstellungen
  PercentOld:=0;
  if IgnoreBootSector=true then
    begin
      writeln('');
      writeln('Info:'+#9+'Ignore bootsector to be written');
      Position.QuadPart:=512;
    end
  else
    begin
      writeln('');
      writeln('Info:'+#9+'Allow bootsector to be written');
      Position.QuadPart:=0;
    end;

  //Fehler beim auslesen ignorieren
  if IgnoreErrors=true then
    begin
      writeln('');
      writeln('Warning:'+#9+'Read errors will be ignored');
      writeln('Warning:'+#9+'If programm does not stop when source HD end is reached then exit by pressing [CTRL+C]');
      writeln('');
    end;

  //Sicherheitsabfrage
  if Drive1=Drive2 then
    begin
      writeln('');
      writeln('Error:'+#9+'Source and target drive may not be identical!');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;
  if Drive2='PhysicalDrive0' then
    begin
      writeln('');
      writeln('Error:'+#9+'"PhysicalDrive0" not allowed for writing access due to safety reasons!');
      writeln('Hint:'+#9+'Try to set up target HDD with an higher drive number like "PhysicalDrive1".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;
  if Drive2='\\.\c:' then
    begin
      writeln('');
      writeln('Error:'+#9+'Drive "c:" not allowed for writing access due to safety reasons!');
      writeln('Hint:'+#9+'Try to set up target HDD with an another drive letter like "d:".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;

  //Festplattengr��e auslesen
  PVR_Size:=DriveSize(Drive1);
  PVR_Size2:=DriveSize(Drive2);
  writeln('Info:'+#9+'Input  HDD physical size'+#9+format('%.2f GB',[PVR_Size/1024/1024/1000]));
  writeln('Info:'+#9+'Output HDD physical size'+#9+format('%.2f GB',[PVR_Size2/1024/1024/1000]));
  if PVR_Size>PVR_Size2 then
    writeln('Info:'+#9+'Source HDD is bigger than target HDD!');
  if PVR_Size<PVR_Size2 then
    writeln('Info:'+#9+'Source HDD is smaller than target HDD!');

  //Quell-Laufwerk �ffnen
  hDevice:=CreateFile(pchar('\\.\'+Drive1), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive1)>0 then
        writeln('Error:'+#9+'Could not access "'+Drive1+'" for reading!')
      else
        writeln('Error:'+#9+'Could not access Drive "'+AnsiReplaceStr(Drive1,'\\.\','')+'" for reading!');
      writeln('');
      ExitCode:=5;
      RestoreConsole;
      Exit;
    end;

  //Ziel-Laufwerk �ffnen
  hDevice2:=CreateFile(pchar('\\.\'+Drive2), GENERIC_READ Or GENERIC_WRITE, FILE_SHARE_READ OR FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if hDevice2=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive2)>0 then
        writeln('Error:'+#9+'Could not access "'+Drive2+'" for writing!')
      else
        writeln('Error:'+#9+'Could not access Drive "'+AnsiReplaceStr(Drive2,'\\.\','')+'" for writing!');
      writeln('');
      CloseHandle(hDevice);
      ExitCode:=6;
      RestoreConsole;
      Exit;
    end;

  //Dump Image auf Ziellaufwerk schreiben
  writeln('');
  write('Info:'+#9+'Progress [                    ]   0.0%');
  while (Position.QuadPart<PVR_Size-(SizeOf(WriteArray))) and (GlobalBreak=false) do
    begin
      //Daten aus Quell-Laufwerk auslesen
      SetFilePointer(hDevice,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      ReadFile(hDevice, WriteArray, SizeOf(WriteArray), BytesRead, nil);
      if BytesRead=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'End of source HDD reached or read error');
          if IgnoreErrors=false then
            break;
        end;

      //Fortschrittsanzeige
      Percent:=(Position.QuadPart/PVR_Size)*100;
      if FormatFloat('000.0', Percent)<>FormatFloat('000.0', PercentOld) then
        begin
          PercentOld:=Percent;
          buffer:='['+StringOfChar(#254,trunc((Percent+0.1)*0.2))+StringOfChar(' ',20-trunc((Percent+0.1)*0.2))+'] '+StringOfChar(' ',3-Length(FormatFloat('000.0', Percent)))+FormatFloat('000.0', Percent)+'%';
          buffer:=StringOfChar(#8, Length(buffer))+buffer;
          buffer:=StringReplace(buffer, ',', '.',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 00', ']   ',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 0', ']  ',[rfReplaceAll, rfIgnoreCase]);
          write(buffer);
        end;

      //Daten auf Laufwerk schreiben
      SetFilePointer(hDevice2,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      WriteFile(hDevice2, WriteArray, SizeOf(WriteArray), BytesWritten, nil);
      if BytesWritten=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'Target HDD full or write error');
          break;
        end;
      Position.QuadPart:=Position.QuadPart+(SizeOf(WriteArray));
    end;

  //meldung �ber die Anzahl der geschriebenen Daten
  writeln('');
  writeln('Info:'+#9+format('%.2f GB',[Position.QuadPart/1024/1024/1000])+' copied');

  //aufr�umen
  CloseHandle(hDevice);
  CloseHandle(hDevice2);
end;

procedure EraseDrive(Drive: String; IgnoreBootSector: Boolean);
//ein Laufwerk l�schen
var
  hDevice:  Cardinal;
  BytesWritten: Cardinal;
  DelArray: ByteArray2;
  Counter: Integer;
  Position: LARGE_INTEGER;
  Sector: Int64;
  Percent, PercentOld: Single;
  
begin
  //Grundeinstellungen
  if IgnoreBootSector=true then
    begin
      writeln('');
      writeln('Info:'+#9+'Ignore bootsector to be erased');
      Position.QuadPart:=512;
      Sector:=1;
    end
  else
    begin
      writeln('');
      writeln('Info:'+#9+'Allow bootsector to be erased');
      Position.QuadPart:=0;
      Sector:=0;
    end;

  //Sicherheitsabfrage
  if Drive='PhysicalDrive0' then
    begin
      writeln('');
      writeln('Error:'+#9+'"PhysicalDrive0" not allowed for erasing due to safety reasons!');
      writeln('Hint:'+#9+'Try to set up target HDD with an higher drive number like "PhysicalDrive1".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;
  if Drive='\\.\c:' then
    begin
      writeln('');
      writeln('Error:'+#9+'Drive "c:" not allowed for erasing due to safety reasons!');
      writeln('Hint:'+#9+'Try to set up target HDD with an another drive letter like "d:".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;

  //L�sch Array definiert auf 0x00 setzen
  for Counter:=0 to SizeOf(DelArray)-1 do
    begin
      DelArray[Counter]:=0;
    end;

  //Gr��e ermitteln
  PVR_Size:=DriveSize(Drive);
  if PVR_Size>0 then
    PVR_Size:=PVR_Size div 512;

  //Laufwerk �ffnen
  hDevice:=CreateFile(pchar('\\.\'+Drive),GENERIC_WRITE,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
  if hDevice=INVALID_HANDLE_VALUE then
    begin
      writeln('');
      if Pos('PhysicalDrive',Drive)>0 then
        writeln('Error:'+#9+'Could not access "'+Drive+'" for erasing!')
      else
        writeln('Error:'+#9+'Could not access Drive "'+AnsiReplaceStr(Drive,'\\.\','')+'" for erasing!');
      writeln('');
      ExitCode:=6;
      RestoreConsole;
      Exit;
    end;

  //L�schvorgang
  PercentOld:=0;
  writeln('Info:'+#9+'Available sectors'+#9+#9+IntToStr(PVR_Size));
  writeln('');
  write('Info:'+#9+'Progress [                    ]   0.0%');
  while (Sector<PVR_Size-1) and (GlobalBreak=false) do
    begin
      //aktuellen Sektor l�schen
      SetFilePointer(hDevice,Position.LowPart,@Position.HighPart, FILE_BEGIN);
      WriteFile(hDevice, DelArray, SizeOf(DelArray), BytesWritten, nil);
      if BytesWritten=0 then
        begin
          writeln('');
          writeln('Info:'+#9+'End of HDD reached or write error');
          break;
        end;

      //Fortschrittsanzeige
      Percent:=(Sector/PVR_Size)*100;
      if FormatFloat('000.0', Percent)<>FormatFloat('000.0', PercentOld) then
        begin
          PercentOld:=Percent;
          buffer:='['+StringOfChar(#254,trunc((Percent+0.1)*0.2))+StringOfChar(' ',20-trunc((Percent+0.1)*0.2))+'] '+StringOfChar(' ',3-Length(FormatFloat('000.0', Percent)))+FormatFloat('000.0', Percent)+'%';
          buffer:=StringOfChar(#8, Length(buffer))+buffer;
          buffer:=StringReplace(buffer, ',', '.',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 00', ']   ',[rfReplaceAll, rfIgnoreCase]);
          buffer:=StringReplace(buffer, '] 0', ']  ',[rfReplaceAll, rfIgnoreCase]);
          write(buffer);
        end;

      Position.QuadPart:=Position.QuadPart+(SizeOf(DelArray));
      Sector:=Sector+(SizeOf(DelArray) div 512)
    end;

  //aufr�umen
  CloseHandle(hDevice);
  writeln('');
  writeln('Info:'+#9+'Erased sectors'+#9+#9+#9+IntToStr(Sector));
  if GlobalBreak=false then
    begin
      if Pos('PhysicalDrive',Drive)>0 then
        writeln('Info:'+#9+'"'+Drive+'" erased')
      else
        writeln('Info:'+#9+'Drive "'+AnsiReplaceStr(Drive,'\\.\','')+'" erased');
    end;
end;

//Hauptprogramm ("Main")
begin
  //Globale Konsolenvariablen initialisieren
  Init;

  //Event Handler mit eigener Routine abfangen
  SetConsoleCtrlHandler(@ConProc, True);

  //Cursor auf linke obere Ecke setzen und ausblenden
  ShowCursor(false);
  Coord.X := 0; Coord.Y := 0;

  //Farbe der Console setzen
  ColorMain:=WhiteOnBlue;
  FillConsoleOutputAttribute(ConHandle, ColorMain, MaxX*MaxY, Coord, NOAW);
  SetConsoleTextAttribute(ConHandle,ColorMain);
  Cls;

  //Versionsinfo
  Version;
  SetConsoleTitle(PChar('DigiCorder Disk Dump '+COPYRIGHT));
  writeln('');
  
  //Commandline Argumente auswerten
  if ParamCount=0 then
    begin
      writeln('');
      writeln('Error:'+#9+'No commandline option declared! Showing help.');
      writeln('');
      Help;
      ExitCode:=2;
      RestoreConsole;
      Exit;
    end;
  for CounterMain:=1 to ParamCount do
    begin
      ParameterstringMain:=ParameterstringMain+Paramstr(CounterMain)+' ';
    end;

  //ung�ltige Commandline Argumente auswerten
  CmdLineError:=false;
  if (Pos('-pdi', LowerCase(ParameterstringMain))>0) and (Pos('-i', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-pdo', LowerCase(ParameterstringMain))>0) and (Pos('-o', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-pdi', LowerCase(ParameterstringMain))>0) and (Pos('-erase', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-pdo', LowerCase(ParameterstringMain))>0) and (Pos('-erase', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-di', LowerCase(ParameterstringMain))>0) and (Pos('-i', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-do', LowerCase(ParameterstringMain))>0) and (Pos('-o', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-di', LowerCase(ParameterstringMain))>0) and (Pos('-erase', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if (Pos('-do', LowerCase(ParameterstringMain))>0) and (Pos('-erase', LowerCase(ParameterstringMain))>0) then
    CmdLineError:=true;
  if CmdLineError=true then
    begin
      writeln('');
      writeln('Error:'+#9+'Commandline options in this combination not allowed! Try "-help".');
      writeln('');
      ExitCode:=9;
      RestoreConsole;
      Exit;
    end;

  //Betriebssystem �berpr�fen
  Buffer:=GetWinVersion(false);
  writeln('');
  writeln('Info:'+#9+'Running on OS "'+GetWinVersion(true)+'"');
  writeln('');
  if (Buffer='Windows 95') or (Buffer='Windows 98') or (Buffer='Windows ME') then
    begin
      writeln('');
      writeln('Error:'+#9+'DDD can not be used on '+Buffer+'!');
      writeln('');
      ExitCode:=1;
      RestoreConsole;
      Exit;
    end;
  if (Buffer='Windows Vista') then
    begin
      writeln('');
      writeln('Info:'+#9+'DDD has is not intended for newer Windows OS like Windows Vista!');
      writeln('Info:'+#9+'Try starting DDD as "Administrator" if problems occur.');
      writeln('');
    end;

  //Hilfe anzeigen
  if (Pos('-help', LowerCase(ParameterstringMain))>0) or (Pos('/?', LowerCase(ParameterstringMain))>0) then
    begin
      Help;
      RestoreConsole;
      Exit;
    end;

  //Lesefehler ignorieren
  if (Pos('-errorignore', LowerCase(ParameterstringMain))>0) then
    begin
      IgnoreErrors:=true;
    end;

  //Header der m�glichen Laufwerke auflisten (PhysicalDrive)
  if (Pos('-list', LowerCase(ParameterstringMain))>0) and (Pos('-listdetails', LowerCase(ParameterstringMain))=0) and (Pos('-list2', LowerCase(ParameterstringMain))=0) and (Pos('-listdetails2', LowerCase(ParameterstringMain))=0) then
    begin
      writeln('Info:'+#9+'List of PhysicalDrive Magic Headers');
      ListDrives;
      RestoreConsole;
      Exit;
    end;

  //Header der m�glichen Laufwerke auflisten (Laufwerksbuchstabe)
  if (Pos('-list2', LowerCase(ParameterstringMain))>0) then
    begin
      writeln('Info:'+#9+'List of Drive Magic Headers by letter');
      ListDrivesByDriveLetter;
      RestoreConsole;
      Exit;
    end;

  //Details der vorhandenen Laufwerke auflisten (PhysicalDrive)
  if (Pos('-listdetails', LowerCase(ParameterstringMain))>0) and (Pos('-listdetails2', LowerCase(ParameterstringMain))=0)then
    begin
      writeln('Info:'+#9+'Detailed list of PhysicalDrives');
      ListDrivesExtended;
      RestoreConsole;
      Exit;
    end;

  //Details der vorhandenen Laufwerke auflisten (Laufwerksbuchstabe)
  if (Pos('-listdetails2', LowerCase(ParameterstringMain))>0) then
    begin
      writeln('Info:'+#9+'Detailed list of Drives by letter');
      ListDrivesExtendedByDriveLetter;
      RestoreConsole;
      Exit;
    end;

  //Liste der m�glichen Exitcodes anzeigen
  if (Pos('-exitcodes', LowerCase(ParameterstringMain))>0) then
    begin
      writeln('Info:'+#9+'List of possible exitcodes');
      ExitCodes;
      RestoreConsole;
      Exit;
    end;

  //Laufwerk l�schen (PhysicalDrive)
  if (Pos('-erasepd', LowerCase(ParameterstringMain))>0) then
    begin
      POS1:=Pos('-erasepd', LowerCase(ParameterstringMain))+8;
      if (AnsiMidStr(ParameterstringMain,POS1+1,1)=' ') or (AnsiMidStr(ParameterstringMain,POS1+1,1)='') then
        PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,1)
      else
        PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,2);
      if (StrToIntDef(PVR_Drive, 0)<0) or (StrToIntDef(PVR_Drive, 0)>19) then
        begin
          writeln('Error:'+#9+'Unsupported PhysicalDrive setting for erasing HDD!');
        end
      else
        begin
          PVR_Drive:='PhysicalDrive'+IntToStr(StrToIntDef(PVR_Drive, 0));
          writeln('Info:'+#9+'HDD for erasing selected'+#9+PVR_Drive);
        end;
      if (Pos('-noboot', LowerCase(ParameterstringMain))>0) then
        EraseDrive(PVR_Drive,true)
      else
        EraseDrive(PVR_Drive,false);
      RestoreConsole;
      Exit;
    end;

  //Laufwerk l�schen (Laufwerksbuchstabe)
  if (Pos('-erased', LowerCase(ParameterstringMain))>0) then
    begin
      POS1:=Pos('-erased', LowerCase(ParameterstringMain))+7;
      PVR_Drive:=AnsiMidStr(LowerCase(ParameterstringMain),POS1,1);
      if (Ord(PVR_Drive[1])<97) or (Ord(PVR_Drive[1])>123) then
        begin
          writeln('Error:'+#9+'Unsupported Drive letter setting for erasing HDD!');
        end
      else
        begin
          writeln('Info:'+#9+'HDD for erasing selected'+#9+'Drive "'+PVR_Drive+':"');
          PVR_Drive:='\\.\'+PVR_Drive+':';
        end;
      if (Pos('-noboot', LowerCase(ParameterstringMain))>0) then
        EraseDrive(PVR_Drive,true)
      else
        EraseDrive(PVR_Drive,false);
      RestoreConsole;
      Exit;
    end;

  //Laufwerk Info (PhysicalDrive)
  if (Pos('-pd', LowerCase(ParameterstringMain))>0) and not (Pos('-pdi', LowerCase(ParameterstringMain))>0) and not (Pos('-pdo', LowerCase(ParameterstringMain))>0) then
    begin
      POS1:=Pos('-pd', LowerCase(ParameterstringMain))+3;
      if (AnsiMidStr(ParameterstringMain,POS1+1,1)=' ') or (AnsiMidStr(ParameterstringMain,POS1+1,1)='') then
        PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,1)
      else
        PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,2);
      if (StrToIntDef(PVR_Drive, 0)<0) or (StrToIntDef(PVR_Drive, 0)>19) then
        begin
          writeln('Error:'+#9+'Unsupported PhysicalDrive setting for HDD info!');
        end
      else
        begin
          PVR_Drive:='PhysicalDrive'+IntToStr(StrToIntDef(PVR_Drive, 0));
          writeln('Info:'+#9+'HDD for info selected'+#9+PVR_Drive);
          DriveInfo(PVR_Drive);
        end;
      RestoreConsole;
      Exit;
    end;

  //Laufwerk Info (Laufwerksbuchstabe)
  if (Pos('-dl', LowerCase(ParameterstringMain))>0) then
    begin
      POS1:=Pos('-d', LowerCase(ParameterstringMain))+3;
      PVR_Drive:=AnsiMidStr(LowerCase(ParameterstringMain),POS1,1);
      if (Ord(PVR_Drive[1])<97) or (Ord(PVR_Drive[1])>123) then
        begin
          writeln('Error:'+#9+'Unsupported drive letter setting for HDD info!');
        end
      else
        begin
          writeln('Info:'+#9+'HDD for info selected'+#9+'Drive "'+PVR_Drive+':"');
          PVR_Drive:='\\.\'+PVR_Drive+':';
          DriveInfo(PVR_Drive);
        end;
      RestoreConsole;
      Exit;
    end;

  //Ausgabedatei auswerten
  if (Pos('-o', LowerCase(ParameterstringMain))>0) then
    begin
      for CounterMain:=1 to ParamCount do
        begin
          if Paramstr(CounterMain)='-o' then
            begin
              PVR_Image:=AddPath(Paramstr(CounterMain+1));
            end;
        end;
      if PVR_Image<>'' then
        begin
          writeln('Info:'+#9+'Set "'+PVR_Image+'" for output binary');
        end
      else
        begin
          writeln('Error:'+#9+'No output filename declared!');
          ExitCode:=4;
          RestoreConsole;
          Exit;
        end;
    end;
  if (ParamCount=1) and (PVR_Image='') then
    begin
      if LeftStr(Paramstr(1),1)<>'-' then
        begin
          PVR_Image:=AddPath(Paramstr(1));
          writeln('Info:'+#9+'Set "'+PVR_Image+'" for output binary');
        end;
      if (PVR_Image='') then
        begin
          writeln('Error:'+#9+'No output filename declared!');
          ExitCode:=4;
          RestoreConsole;
          Exit;
        end;
    end;

  //Eingabedatei auswerten
  if (Pos('-i', LowerCase(ParameterstringMain))>0) then
    begin
      for CounterMain:=1 to ParamCount do
        begin
          if Paramstr(CounterMain)='-i' then
            begin
              PVR_Image:=AddPath(Paramstr(CounterMain+1));
            end;
        end;
      if PVR_Image<>'' then
        begin
          writeln('Info:'+#9+'Set "'+PVR_Image+'" for input binary');
        end
      else
        begin
          writeln('Error:'+#9+'No input filename declared!');
          ExitCode:=4;
          RestoreConsole;
          Exit;
        end;
    end;

  //Quell-Laufwerk einstellen oder suchen
  if (Pos('-pdi', LowerCase(ParameterstringMain))>0) or (Pos('-di', LowerCase(ParameterstringMain))>0) then
    begin
      //PhysicalDrives
      if (Pos('-pdi', LowerCase(ParameterstringMain))>0) then
        begin
          POS1:=Pos('-pdi', LowerCase(ParameterstringMain))+4;
          if (AnsiMidStr(ParameterstringMain,POS1+1,1)=' ') or (AnsiMidStr(ParameterstringMain,POS1+1,1)='') then
            PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,1)
          else
            PVR_Drive:=AnsiMidStr(ParameterstringMain,POS1,2);
          if (StrToIntDef(PVR_Drive, 0)<0) or (StrToIntDef(PVR_Drive, 0)>19) then
            begin
              writeln('Error:'+#9+'Unsupported PhysicalDrive setting for input PVR HDD!');
            end
          else
            begin
              PVR_Drive:='PhysicalDrive'+IntToStr(StrToIntDef(PVR_Drive, 0));
              writeln('Info:'+#9+'Input PVR HDD selected'+#9+#9+PVR_Drive);
            end;
        end;
      //Laufwerksbuchstaben
      if (Pos('-di', LowerCase(ParameterstringMain))>0) then
        begin
          POS1:=Pos('-di', LowerCase(ParameterstringMain))+3;
          PVR_Drive:=AnsiMidStr(LowerCase(ParameterstringMain),POS1,1);
          if (Ord(PVR_Drive[1])<97) or (Ord(PVR_Drive[1])>123) then
            begin
              writeln('Error:'+#9+'Unsupported drive letter setting for input PVR HDD!');
            end
          else
            begin
              writeln('Info:'+#9+'Input PVR HDD selected'+#9+#9+'Drive "'+PVR_Drive+':"');
              PVR_Drive:='\\.\'+PVR_Drive+':';
            end;
        end;
    end
  else
    begin
      //Automatiksuche f�r Dump
      if (ParamCount=1) and (PVR_Image<>'') then
        begin
          write('Info:'+#9+'Searching for PVR HDD...');
          PVR_Drive:=FindDrive;
          writeln(#9+'done');
          if PVR_Drive<>'' then
            begin
              if Pos('PhysicalDrive',PVR_Drive)>0 then
                writeln('Info:'+#9+'Input PVR HDD found'+#9+#9+PVR_Drive)
              else
                writeln('Info:'+#9+'Input PVR HDD found'+#9+#9+AnsiReplaceStr(PVR_Drive,'\\.\','Drive "')+'"');
            end
          else
            begin
              writeln('Error:'+#9+'No input PVR HDD found!');
              ExitCode:=3;
              RestoreConsole;
              Exit;
            end;
        end;
    end;

  //Ziel-Laufwerk einstellen
  if (Pos('-pdo', LowerCase(ParameterstringMain))>0) or (Pos('-do', LowerCase(ParameterstringMain))>0) then
    begin
      //PhysicalDrive
      if (Pos('-pdo', LowerCase(ParameterstringMain))>0) then
        begin
          POS1:=Pos('-pdo', LowerCase(ParameterstringMain))+4;
          if (AnsiMidStr(ParameterstringMain,POS1+1,1)=' ') or (AnsiMidStr(ParameterstringMain,POS1+1,1)='') then
            PVR_Drive2:=AnsiMidStr(ParameterstringMain,POS1,1)
          else
            PVR_Drive2:=AnsiMidStr(ParameterstringMain,POS1,2);
          if (StrToIntDef(PVR_Drive2, 0)<0) or (StrToIntDef(PVR_Drive2, 0)>19) then
            begin
              writeln('Error:'+#9+'Unsupported PhysicalDrive setting for output HDD!');
            end
          else
            begin
              PVR_Drive2:='PhysicalDrive'+IntToStr(StrToIntDef(PVR_Drive2, 0));
              writeln('Info:'+#9+'Output HDD selected'+#9+#9+PVR_Drive2);
            end;
        end;
      //Laufwerksbuchstaben
      if (Pos('-do', LowerCase(ParameterstringMain))>0) then
        begin
          POS1:=Pos('-do', LowerCase(ParameterstringMain))+3;
          PVR_Drive2:=AnsiMidStr(LowerCase(ParameterstringMain),POS1,1);
          if (Ord(PVR_Drive2[1])<97) or (Ord(PVR_Drive2[1])>123) then
            begin
              writeln('Error:'+#9+'Unsupported drive letter setting for output HDD!');
            end
          else
            begin
              writeln('Info:'+#9+'Output HDD selected'+#9+#9+'Drive "'+PVR_Drive2+':"');
              PVR_Drive2:='\\.\'+PVR_Drive2+':';
            end;
        end;
    end;

  //Dump erzeugen
  if (PVR_Drive<>'') and (PVR_Drive2='') and (PVR_Image<>'') and (Pos('-pdi', LowerCase(ParameterstringMain))>0) and (Pos('-pdo', LowerCase(ParameterstringMain))=0) then
    begin
      DumpImage(PVR_drive,PVR_Image);
    end;
  if (ParamCount=1) and (PVR_Image<>'') and (PVR_Drive<>'') then
    begin
      DumpImage(PVR_drive,PVR_Image);
    end;

  //Dump schreiben
  if (PVR_Drive='') and (PVR_Drive2<>'') and (PVR_Image<>'') and (Pos('-pdo', LowerCase(ParameterstringMain))>0) and (Pos('-pdi', LowerCase(ParameterstringMain))=0) then
    begin
      if (Pos('-noboot', LowerCase(ParameterstringMain))>0) then
        WriteImage(PVR_drive2,PVR_Image,true)
      else
        WriteImage(PVR_drive2,PVR_Image,false);
    end;

  //Laufwerk kopieren (PhysicalDrive)
  if (PVR_Drive<>'') and (PVR_Drive2<>'') and (Pos('-pdo', LowerCase(ParameterstringMain))>0) and (Pos('-pdi', LowerCase(ParameterstringMain))>0) then
    begin
      if (Pos('-noboot', LowerCase(ParameterstringMain))>0) then
        CopyDrive(PVR_drive,PVR_drive2,true)
      else
        CopyDrive(PVR_drive,PVR_drive2,false);
    end;
  //Laufwerk kopieren (Laufwerksbuchstaben)
  if (PVR_Drive<>'') and (PVR_Drive2<>'') and (Pos('-do', LowerCase(ParameterstringMain))>0) and (Pos('-di', LowerCase(ParameterstringMain))>0) then
    begin
      if (Pos('-noboot', LowerCase(ParameterstringMain))>0) then
        CopyDrive(PVR_drive,PVR_drive2,true)
      else
        CopyDrive(PVR_drive,PVR_drive2,false);
    end;

  //Konsole wieder herstellen
  RestoreConsole;

  //Abbruchbedingung melden
  if GlobalBreak=true then
    ExitCode:=10;  
end.
