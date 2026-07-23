[Setup]
AppName=KATIYA Station
AppVersion=1.2.0
DefaultDirName={autopf}\KATIYA Station
DefaultGroupName=KATIYA Station
OutputDir=Output
OutputBaseFilename=KATIYA_Station_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\KATIYA Station"; Filename: "{app}\katiya_station_rms.exe"
Name: "{autodesktop}\KATIYA Station"; Filename: "{app}\katiya_station_rms.exe"

[Run]
Filename: "{app}\katiya_station_rms.exe"; Description: "Launch KATIYA Station"; Flags: nowait postinstall skipifsilent