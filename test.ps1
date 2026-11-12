
#requires -Version 5.1
<#
    PC Hardware Inspector
    Windows 10 / Windows 11
    Generates an HTML hardware inventory report.

    Recommended: Run PowerShell as Administrator.
#>

$ErrorActionPreference = "SilentlyContinue"

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

$OutputDirectory = Join-Path ([Environment]::GetFolderPath("Desktop")) "PC-Hardware-Reports"

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportPath = Join-Path $OutputDirectory "PC-Report-$Timestamp.html"
$BatteryReportPath = Join-Path $OutputDirectory "Battery-Report-$Timestamp.html"

# ------------------------------------------------------------
# HELPER FUNCTIONS
# ------------------------------------------------------------

function Get-CimData {
    param(
        [string]$Class,
        [string]$Namespace = "root/cimv2"
    )

    try {
        return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Format-Bytes {
    param($Bytes)

    if ($null -eq $Bytes -or $Bytes -eq 0) {
        return "N/A"
    }

    $GB = [math]::Round(([double]$Bytes / 1GB), 2)
    return "$GB GB"
}

function Format-Date {
    param($Value)

    if (-not $Value) { return "N/A" }

    try {
        return ([datetime]$Value).ToString("yyyy-MM-dd")
    }
    catch {
        return "$Value"
    }
}

function Get-Value {
    param(
        $Object,
        [string]$Property,
        $Default = "N/A"
    )

    if ($null -ne $Object -and
        $null -ne $Object.$Property -and
        "$($Object.$Property)" -ne "") {
        return $Object.$Property
    }

    return $Default
}

function Get-MonitorText {
    param($Value)

    if ($null -eq $Value) { return "N/A" }

    try {
        $Result = -join ($Value | Where-Object { $_ -ne 0 } |
            ForEach-Object { [char]$_ })

        if ($Result.Trim()) { return $Result.Trim() }
    }
    catch {}

    return "N/A"
}

function ConvertTo-HtmlTable {
    param(
        [string]$Title,
        $Data
    )

    if ($null -eq $Data -or @($Data).Count -eq 0) {
        return "<h2>$Title</h2><p class='muted'>No information available.</p>"
    }

    $Table = $Data | ConvertTo-Html -Fragment | Out-String

    return @"
<section class="panel">
    <h2>$Title</h2>
    $Table
</section>
"@
}

# ------------------------------------------------------------
# 1. SYSTEM INFORMATION
# ------------------------------------------------------------

$Computer = Get-CimData "Win32_ComputerSystem" | Select-Object -First 1
$OS = Get-CimData "Win32_OperatingSystem" | Select-Object -First 1
$BIOS = Get-CimData "Win32_BIOS" | Select-Object -First 1
$Board = Get-CimData "Win32_BaseBoard" | Select-Object -First 1

$SystemInfo = @(
    [pscustomobject]@{
        Property = "Manufacturer"
        Value = Get-Value $Computer "Manufacturer"
    }
    [pscustomobject]@{
        Property = "Model"
        Value = Get-Value $Computer "Model"
    }
    [pscustomobject]@{
        Property = "System Type"
        Value = Get-Value $Computer "SystemType"
    }
    [pscustomobject]@{
        Property = "Computer Name"
        Value = $env:COMPUTERNAME
    }
    [pscustomobject]@{
        Property = "Operating System"
        Value = Get-Value $OS "Caption"
    }
    [pscustomobject]@{
        Property = "OS Version"
        Value = Get-Value $OS "Version"
    }
    [pscustomobject]@{
        Property = "Build Number"
        Value = Get-Value $OS "BuildNumber"
    }
    [pscustomobject]@{
        Property = "Architecture"
        Value = Get-Value $OS "OSArchitecture"
    }
    [pscustomobject]@{
        Property = "Installation Date"
        Value = Format-Date $OS.InstallDate
    }
    [pscustomobject]@{
        Property = "Last Boot"
        Value = Get-Value $OS "LastBootUpTime"
    }
    [pscustomobject]@{
        Property = "BIOS Version"
        Value = Get-Value $BIOS "SMBIOSBIOSVersion"
    }
    [pscustomobject]@{
        Property = "BIOS Manufacturer"
        Value = Get-Value $BIOS "Manufacturer"
    }
    [pscustomobject]@{
        Property = "BIOS Release Date"
        Value = Format-Date $BIOS.ReleaseDate
    }
    [pscustomobject]@{
        Property = "Motherboard"
        Value = Get-Value $Board "Product"
    }
    [pscustomobject]@{
        Property = "Motherboard Manufacturer"
        Value = Get-Value $Board "Manufacturer"
    }
    [pscustomobject]@{
        Property = "Motherboard Version"
        Value = Get-Value $Board "Version"
    }
)

# ------------------------------------------------------------
# 2. PROCESSOR
# ------------------------------------------------------------

$CPU = Get-CimData "Win32_Processor"

$CPUInfo = foreach ($Processor in $CPU) {
    [pscustomobject]@{
        Name = $Processor.Name.Trim()
        Manufacturer = $Processor.Manufacturer
        Cores = $Processor.NumberOfCores
        Threads = $Processor.NumberOfLogicalProcessors
        MaxClockMHz = $Processor.MaxClockSpeed
        Socket = $Processor.SocketDesignation
        L2CacheKB = $Processor.L2CacheSize
        L3CacheKB = $Processor.L3CacheSize
    }
}

# ------------------------------------------------------------
# 3. RAM
# ------------------------------------------------------------

$RAM = Get-CimData "Win32_PhysicalMemory"

$RAMInfo = foreach ($Module in $RAM) {
    [pscustomobject]@{
        Manufacturer = $Module.Manufacturer
        PartNumber = $Module.PartNumber.Trim()
        Capacity = Format-Bytes $Module.Capacity
        SpeedMHz = $Module.Speed
        ConfiguredSpeedMHz = $Module.ConfiguredClockSpeed
        Slot = $Module.DeviceLocator
        Bank = $Module.BankLabel
        MemoryTypeCode = $Module.SMBIOSMemoryType
    }
}

$RAMTotal = ($RAM | Measure-Object -Property Capacity -Sum).Sum

$RAMArrays = Get-CimData "Win32_PhysicalMemoryArray"

$RAMSlots = ($RAMArrays | Measure-Object -Property MemoryDevices -Sum).Sum
$RAMUsed = @($RAM).Count

$RAMSummary = @(
    [pscustomobject]@{
        Property = "Total Installed RAM"
        Value = Format-Bytes $RAMTotal
    }
    [pscustomobject]@{
        Property = "Installed Modules"
        Value = $RAMUsed
    }
    [pscustomobject]@{
        Property = "Reported Memory Slots"
        Value = if ($RAMSlots) { $RAMSlots } else { "N/A" }
    }
    [pscustomobject]@{
        Property = "Free Slots (Estimated)"
        Value = if ($RAMSlots -ge $RAMUsed) { $RAMSlots - $RAMUsed } else { "N/A" }
    }
)

# ------------------------------------------------------------
# 4. STORAGE / SSD / HDD
# ------------------------------------------------------------

$Disks = Get-CimData "Win32_DiskDrive"

$DiskInfo = foreach ($Disk in $Disks) {
    [pscustomobject]@{
        Model = $Disk.Model
        Size = Format-Bytes $Disk.Size
        MediaType = $Disk.MediaType
        Interface = $Disk.InterfaceType
        Firmware = $Disk.FirmwareRevision
        SerialNumber = $Disk.SerialNumber.Trim()
        Status = $Disk.Status
        DeviceID = $Disk.DeviceID
    }
}

$PhysicalDisks = @()

try {
    $PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
}
catch {}

$PhysicalDiskInfo = foreach ($Disk in $PhysicalDisks) {
    [pscustomobject]@{
        Model = $Disk.FriendlyName
        MediaType = $Disk.MediaType
        BusType = $Disk.BusType
        Size = Format-Bytes $Disk.Size
        HealthStatus = $Disk.HealthStatus
        OperationalStatus = ($Disk.OperationalStatus -join ", ")
        Firmware = $Disk.FirmwareVersion
        SerialNumber = $Disk.SerialNumber
    }
}

$ReliabilityInfo = foreach ($Disk in $PhysicalDisks) {
    try {
        $Reliability = Get-StorageReliabilityCounter -PhysicalDisk $Disk -ErrorAction Stop

        if ($Reliability) {
            [pscustomobject]@{
                Disk = $Disk.FriendlyName
                TemperatureC = $Reliability.Temperature
                TemperatureMaxC = $Reliability.TemperatureMax
                PowerOnHours = $Reliability.PowerOnHours
                Wear = $Reliability.Wear
                ReadErrorsTotal = $Reliability.ReadErrorsTotal
                WriteErrorsTotal = $Reliability.WriteErrorsTotal
                ReadErrorsUncorrected = $Reliability.ReadErrorsUncorrected
                WriteErrorsUncorrected = $Reliability.WriteErrorsUncorrected
            }
        }
    }
    catch {}
}

$Volumes = Get-CimData "Win32_LogicalDisk" | Where-Object { $_.DriveType -eq 3 }

$VolumeInfo = foreach ($Volume in $Volumes) {
    [pscustomobject]@{
        Drive = $Volume.DeviceID
        Label = $Volume.VolumeName
        FileSystem = $Volume.FileSystem
        TotalSize = Format-Bytes $Volume.Size
        FreeSpace = Format-Bytes $Volume.FreeSpace
        FreePercent = if ($Volume.Size -gt 0) {
            [math]::Round(($Volume.FreeSpace / $Volume.Size) * 100, 1)
        } else { "N/A" }
    }
}

# ------------------------------------------------------------
# 5. BATTERY
# ------------------------------------------------------------

$Batteries = Get-CimData "Win32_Battery"

$BatteryStatic = Get-CimData "BatteryStaticData" "root/wmi"
$BatteryFull = Get-CimData "BatteryFullChargedCapacity" "root/wmi"
$BatteryCycles = Get-CimData "BatteryCycleCount" "root/wmi"

$BatteryInfo = @()

foreach ($Battery in $Batteries) {

    $DesignCapacity = $null
    $FullCapacity = $null
    $Cycles = $null

    if ($BatteryStatic.Count -gt 0) {
        $DesignCapacity = $BatteryStatic[0].DesignedCapacity
    }

    if ($BatteryFull.Count -gt 0) {
        $FullCapacity = $BatteryFull[0].FullChargedCapacity
    }

    if ($BatteryCycles.Count -gt 0) {
        $Cycles = $BatteryCycles[0].CycleCount
    }

    $Wear = "N/A"

    if ($DesignCapacity -gt 0 -and $FullCapacity -gt 0) {
        $Wear = [math]::Round(
            (1 - ($FullCapacity / $DesignCapacity)) * 100, 1
        )
    }

    $BatteryInfo += [pscustomobject]@{
        Name = $Battery.Name
        Manufacturer = $Battery.Manufacturer
        Chemistry = $Battery.Chemistry
        EstimatedCharge = "$($Battery.EstimatedChargeRemaining)%"
        DesignCapacity_mWh = $DesignCapacity
        FullChargeCapacity_mWh = $FullCapacity
        CycleCount = if ($null -ne $Cycles) { $Cycles } else { "N/A" }
        EstimatedWearPercent = if ($Wear -ne "N/A") { "$Wear%" } else { "N/A" }
        Status = $Battery.Status
    }
}

# Generate Windows battery report separately
$BatteryReportGenerated = $false

if ($Batteries.Count -gt 0) {
    try {
        powercfg /batteryreport /output "$BatteryReportPath" | Out-Null

        if (Test-Path $BatteryReportPath) {
            $BatteryReportGenerated = $true
        }
    }
    catch {}
}

# ------------------------------------------------------------
# 6. GPU
# ------------------------------------------------------------

$GPUs = Get-CimData "Win32_VideoController"

$GPUInfo = foreach ($GPU in $GPUs) {
    [pscustomobject]@{
        Name = $GPU.Name
        AdapterRAM = Format-Bytes $GPU.AdapterRAM
        DriverVersion = $GPU.DriverVersion
        DriverDate = Format-Date $GPU.DriverDate
        VideoProcessor = $GPU.VideoProcessor
        Resolution = $GPU.VideoModeDescription
        RefreshRateHz = $GPU.CurrentRefreshRate
        Status = $GPU.Status
    }
}

# ------------------------------------------------------------
# 7. MONITORS
# ------------------------------------------------------------

$Monitors = Get-CimData "WmiMonitorID" "root/wmi"

$MonitorInfo = foreach ($Monitor in $Monitors) {
    [pscustomobject]@{
        Manufacturer = Get-MonitorText $Monitor.ManufacturerName
        Model = Get-MonitorText $Monitor.UserFriendlyName
        SerialNumber = Get-MonitorText $Monitor.SerialNumberID
        Active = $Monitor.Active
    }
}

# ------------------------------------------------------------
# 8. USB CONTROLLERS AND DEVICES
# ------------------------------------------------------------

$USBControllers = Get-CimData "Win32_USBController"

$USBControllerInfo = foreach ($Controller in $USBControllers) {
    [pscustomobject]@{
        Name = $Controller.Name
        Manufacturer = $Controller.Manufacturer
        Status = $Controller.Status
        PNPDeviceID = $Controller.PNPDeviceID
    }
}

$USBDevices = @()

try {
    $USBDevices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object {
            $_.InstanceId -match '^(USB|USBSTOR)\\'
        })
}
catch {}

$USBDeviceInfo = foreach ($Device in $USBDevices) {
    [pscustomobject]@{
        Name = $Device.FriendlyName
        Class = $Device.Class
        Status = $Device.Status
        InstanceId = $Device.InstanceId
    }
}

# ------------------------------------------------------------
# 9. NETWORK ADAPTERS
# ------------------------------------------------------------

$NetworkAdapters = Get-CimData "Win32_NetworkAdapter" |
    Where-Object { $_.PhysicalAdapter -eq $true }

$NetworkInfo = foreach ($Adapter in $NetworkAdapters) {
    [pscustomobject]@{
        Name = $Adapter.Name
        Manufacturer = $Adapter.Manufacturer
        MAC = $Adapter.MACAddress
        Speed = if ($Adapter.Speed) {
            "$([math]::Round($Adapter.Speed / 1MB, 0)) Mbps"
        } else { "N/A" }
        AdapterType = $Adapter.AdapterType
        NetEnabled = $Adapter.NetEnabled
        Status = $Adapter.NetConnectionStatus
    }
}

# ------------------------------------------------------------
# 10. PNP DEVICES / HARDWARE ERRORS
# ------------------------------------------------------------

$ProblemDevices = @()

try {
    $ProblemDevices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object {
            $_.Status -ne "OK"
        } |
        Select-Object Class, FriendlyName, Status, InstanceId)
}
catch {}

# ------------------------------------------------------------
# 11. SUMMARY CARDS
# ------------------------------------------------------------

$CPUName = if ($CPU.Count -gt 0) { $CPU[0].Name.Trim() } else { "N/A" }
$GPUName = if ($GPUs.Count -gt 0) { $GPUs[0].Name } else { "N/A" }

$DiskCount = @($Disks).Count

$SummaryCards = @(
    [pscustomobject]@{
        Label = "PROCESSOR"
        Value = $CPUName
    }
    [pscustomobject]@{
        Label = "INSTALLED RAM"
        Value = Format-Bytes $RAMTotal
    }
    [pscustomobject]@{
        Label = "STORAGE DEVICES"
        Value = "$DiskCount"
    }
    [pscustomobject]@{
        Label = "GRAPHICS"
        Value = $GPUName
    }
    [pscustomobject]@{
        Label = "USB DEVICES"
        Value = "$($USBDevices.Count)"
    }
    [pscustomobject]@{
        Label = "BATTERIES"
        Value = "$($Batteries.Count)"
    }
)

# ------------------------------------------------------------
# 12. BUILD HTML REPORT
# ------------------------------------------------------------

$Sections = @(
    @{ Title = "System Information"; Data = $SystemInfo }
    @{ Title = "Processor"; Data = $CPUInfo }
    @{ Title = "RAM Summary"; Data = $RAMSummary }
    @{ Title = "RAM Modules"; Data = $RAMInfo }
    @{ Title = "Storage Devices (CIM)"; Data = $DiskInfo }
    @{ Title = "Physical Disks"; Data = $PhysicalDiskInfo }
    @{ Title = "Disk Reliability / SMART Counters"; Data = $ReliabilityInfo }
    @{ Title = "Logical Volumes"; Data = $VolumeInfo }
    @{ Title = "Battery Information"; Data = $BatteryInfo }
    @{ Title = "Graphics"; Data = $GPUInfo }
    @{ Title = "Monitors"; Data = $MonitorInfo }
    @{ Title = "USB Controllers"; Data = $USBControllerInfo }
    @{ Title = "Connected USB Devices"; Data = $USBDeviceInfo }
    @{ Title = "Network Adapters"; Data = $NetworkInfo }
    @{ Title = "Hardware Problems"; Data = $ProblemDevices }
)

$CardsHTML = foreach ($Card in $SummaryCards) {
    $SafeValue = [System.Net.WebUtility]::HtmlEncode([string]$Card.Value)

    @"
<div class="summary-card">
    <div class="summary-label">$($Card.Label)</div>
    <div class="summary-value">$SafeValue</div>
</div>
"@
}

$SectionsHTML = foreach ($Section in $Sections) {
    ConvertTo-HtmlTable -Title $Section.Title -Data $Section.Data
}

$BatteryLink = if ($BatteryReportGenerated) {
    "<p><a href='$(Split-Path $BatteryReportPath -Leaf)'>Open detailed Windows Battery Report</a></p>"
} else {
    "<p class='muted'>Windows battery report unavailable or no battery detected.</p>"
}

$ReportHTML = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>PC Hardware Inspector</title>

<style>
* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 30px;
    background: #101827;
    color: #e5e7eb;
    font-family: "Segoe UI", Arial, sans-serif;
}

.container {
    max-width: 1450px;
    margin: auto;
}

.header {
    background: linear-gradient(120deg, #1e3a5f, #172554);
    padding: 30px;
    border-radius: 14px;
    margin-bottom: 25px;
    border: 1px solid #334155;
}

.header h1 {
    margin: 0 0 10px 0;
    font-size: 30px;
}

.header p {
    margin: 5px 0;
    color: #cbd5e1;
}

.summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 15px;
    margin-bottom: 25px;
}

.summary-card {
    background: #1e293b;
    padding: 20px;
    border-radius: 12px;
    border: 1px solid #334155;
    min-width: 0;
}

.summary-label {
    color: #94a3b8;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 1px;
    margin-bottom: 12px;
}

.summary-value {
    font-size: 18px;
    font-weight: 600;
    overflow-wrap: anywhere;
}

.panel {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 22px;
    margin-bottom: 20px;
    overflow-x: auto;
}

h2 {
    color: #60a5fa;
    margin-top: 0;
    font-size: 20px;
}

table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
}

th {
    background: #273449;
    color: #93c5fd;
    text-align: left;
    padding: 12px;
    white-space: nowrap;
}

td {
    padding: 11px 12px;
    border-bottom: 1px solid #334155;
    color: #e2e8f0;
    overflow-wrap: anywhere;
}

tr:hover td {
    background: #29384d;
}

tr:last-child td {
    border-bottom: none;
}

.muted {
    color: #94a3b8;
}

.footer {
    color: #64748b;
    font-size: 12px;
    text-align: center;
    margin-top: 30px;
}

a {
    color: #60a5fa;
}

@media(max-width: 600px) {
    body {
        padding: 12px;
    }

    .header {
        padding: 20px;
    }

    .header h1 {
        font-size: 23px;
    }
}

@media print {
    body {
        background: white;
        color: black;
    }

    .header, .panel, .summary-card {
        background: white;
        color: black;
        border: 1px solid #ccc;
        break-inside: avoid;
    }

    td {
        color: black;
    }

    th {
        background: #eee;
        color: black;
    }

    h2 {
        color: #1e3a8a;
    }
}
</style>

</head>

<body>
<div class="container">

<div class="header">
    <h1>PC Hardware Inspector</h1>
    <p>Hardware Inventory & System Diagnostics</p>
    <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p><strong>User:</strong> $env:USERNAME</p>
</div>

<div class="summary">
    $($CardsHTML -join "`n")
</div>

$($SectionsHTML -join "`n")

<section class="panel">
    <h2>Additional Battery Report</h2>
    $BatteryLink
</section>

<div class="footer">
    PC Hardware Inspector | Generated using Windows PowerShell
    <br>
    Some hardware information may be unavailable depending on firmware,
    drivers and manufacturer support.
</div>

</div>
</body>
</html>
"@

$ReportHTML | Out-File -FilePath $ReportPath -Encoding UTF8

# ------------------------------------------------------------
# 13. FINISH
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       PC HARDWARE INSPECTOR" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[+] Hardware inventory completed." -ForegroundColor Green
Write-Host "[+] HTML report: $ReportPath" -ForegroundColor Green

if ($BatteryReportGenerated) {
    Write-Host "[+] Battery report: $BatteryReportPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Opening report..." -ForegroundColor Cyan

Start-Process $ReportPath
