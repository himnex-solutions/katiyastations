[Setup]
AppName=KATIYA Station
AppVersion=1.6.0
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
; ── Offline Wi-Fi sync (local hub) ─────────────────────────────────────────
; When the internet is down, waiter devices send their orders to this PC over
; the LAN so the till can still bill them. Windows Firewall blocks an inbound
; listen by default, and the prompt appears behind the app where nobody sees
; it — so open the two ports here, at install time, while we have admin rights.
;   TCP 8787 — the hub's HTTP/WebSocket server
;   UDP 8788 — discovery, so waiter devices find this PC with no configuration
; Both are scoped to private networks; the shop's own Wi-Fi, never a public one.
; Kept idempotent by deleting any existing rule of the same name first.
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""KATIYA Station Local Hub (TCP)"""; Flags: runhidden; StatusMsg: "Configuring firewall for offline Wi-Fi sync..."
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""KATIYA Station Local Hub (TCP)"" dir=in action=allow protocol=TCP localport=8787 profile=private program=""{app}\katiya_station_rms.exe"""; Flags: runhidden; StatusMsg: "Configuring firewall for offline Wi-Fi sync..."
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""KATIYA Station Local Hub (UDP)"""; Flags: runhidden; StatusMsg: "Configuring firewall for offline Wi-Fi sync..."
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""KATIYA Station Local Hub (UDP)"" dir=in action=allow protocol=UDP localport=8788 profile=private program=""{app}\katiya_station_rms.exe"""; Flags: runhidden; StatusMsg: "Configuring firewall for offline Wi-Fi sync..."

Filename: "{app}\katiya_station_rms.exe"; Description: "Launch KATIYA Station"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Leave no orphaned firewall holes behind. RunOnceId keeps each rule from being
; deleted repeatedly when more than one version is uninstalled.
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""KATIYA Station Local Hub (TCP)"""; Flags: runhidden; RunOnceId: "DelHubFirewallTCP"
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""KATIYA Station Local Hub (UDP)"""; Flags: runhidden; RunOnceId: "DelHubFirewallUDP"