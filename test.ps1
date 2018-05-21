################################################
# Configure the variables below
################################################
$LogDataDir = "C:\Users\Administrator\Desktop\Zerto Automation\Logs"
$VPGList = "C:\Users\Administrator\Desktop\Zerto Automation\VPG_Creation-VPGs.csv"
$VMList = "C:\Users\Administrator\Desktop\Zerto Automation\VPG_Creation-VMs.csv"
$ZertoServer = "192.168.111.20"
$ZertoPort = "9669"
$ZertoUser = "administrator@vsphere.local"
$ZertoPassword = "ZertoLabs18!"
$TimeToWaitBetweenVPGCreation = "30"
####################################################################################################
# Nothing to configure below this line - Starting the main function of the script
####################################################################################################

################################################
# Setting log directory and starting transcript logging
################################################
$CurrentMonth = get-date -format MM.yy
$CurrentTime = get-date -format hh.mm.ss
$CurrentLogDataDir = $LogDataDir + $CurrentMonth
$CurrentLogDataFile = $LogDataDir + $CurrentMonth + "\BulkVPGCreationLog-" + $CurrentTime + ".txt"
# Testing path exists to engine logging, if not creating it
$ExportDataDirTestPath = test-path $CurrentLogDataDir
if ($ExportDataDirTestPath -eq $False)
{
New-Item -ItemType Directory -Force -Path $CurrentLogDataDir
}
start-transcript -path $CurrentLogDataFile -NoClobber

################################################
# Setting Cert Policy - required for successful auth with the Zerto API
################################################
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
public bool CheckValidationResult(
ServicePoint srvPoint, X509Certificate certificate,
WebRequest request, int certificateProblem) {
return true;
}
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

################################################
# Building Zerto API string and invoking API
################################################
$baseURL = "https://" + $ZertoServer + ":"+$ZertoPort+"/v1/"
# Authenticating with Zerto APIs
$xZertoSessionURL = $baseURL + "session/add"
$authInfo = ("{0}:{1}" -f $ZertoUser,$ZertoPassword)
$authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
$authInfo = [System.Convert]::ToBase64String($authInfo)
$headers = @{Authorization=("Basic {0}" -f $authInfo)}
$sessionBody = '{"AuthenticationMethod": "1"}'
$TypeJSON = "application/JSON"
$TypeXML = "application/XML"
$xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURL -Headers $headers -Method POST -Body $sessionBody -ContentType $TypeJSON
# Extracting x-zerto-session from the response, and adding it to the actual API
$xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
$zertosessionHeader = @{"x-zerto-session"=$xZertoSession; "Accept"=$TypeJSON }
# URL to create VPG settings
$CreateVPGURL = $BaseURL+"vpgSettings"

################################################
# Importing the CSV of Profiles to use for VM Protection
################################################
$VPGCSVImport = Import-Csv $VPGList
$VMCSVImport = Import-Csv $VMList

################################################
# Running the creation process by VPG, as a VPG can contain multiple VMs
################################################
foreach ($VPG in $VPGCSVImport)
{
$VPGName = $VPG.VPGName
$ReplicationPriority = $VPG.ReplicationPriority
$RecoverySiteName = $VPG.RecoverySiteName
$ClusterName = $VPG.ClusterName
$FailoverNetwork = $VPG.FailoverNetwork
$TestNetwork = $VPG.TestNetwork
$DatastoreName = $VPG.DatastoreName
$JournalDatastore = $VPG.JournalDatastore
$vCenterFolder = $VPG.vCenterFolder
$JournalHistoryInHours = $VPG.JournalHistoryInHours
$RpoAlertInSeconds = $VPG.RpoAlertInSeconds
$TestIntervalInMinutes = $VPG.TestIntervalInMinutes
$JournalHardLimitInMB = $VPG.JournalHardLimitInMB
$JournalWarningThresholdInMB = $VPG.JournalWarningThresholdInMB
# Getting list of VMs for the VPG
$VPGVMs = $VMCSVImport | Where {$_.VPGName -Match "$VPGName"}
$VPGVMNames = $VPGVMs.VMName
# Logging and showing action
write-host "Creating Protection Group:$VPGName for VMs:$VPGVMNames"

################################################
# Getting Identifiers for VPG settings
################################################
# Get SiteIdentifier for getting Local Identifier later in the script
$SiteInfoURL = $BaseURL+"localsite"
$SiteInfoCMD = Invoke-RestMethod -Uri $SiteInfoURL -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$LocalSiteIdentifier = $SiteInfoCMD | Select SiteIdentifier -ExpandProperty SiteIdentifier
# Get SiteIdentifier for getting Identifiers
$TargetSiteInfoURL = $BaseURL+"virtualizationsites"
$TargetSiteInfoCMD = Invoke-RestMethod -Uri $TargetSiteInfoURL -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$TargetSiteIdentifier = $TargetSiteInfoCMD | Where-Object {$_.VirtualizationSiteName -eq $RecoverySiteName} | select SiteIdentifier -ExpandProperty SiteIdentifier
# Get NetworkIdentifiers for API
$VISiteInfoURL1 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/networks"
$VISiteInfoCMD1 = Invoke-RestMethod -Uri $VISiteInfoURL1 -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$FailoverNetworkIdentifier = $VISiteInfoCMD1 | Where-Object {$_.VirtualizationNetworkName -eq $FailoverNetwork} | Select NetworkIdentifier -ExpandProperty NetworkIdentifier
$TestNetworkIdentifier = $VISiteInfoCMD1 | Where-Object {$_.VirtualizationNetworkName -eq $TestNetwork} | Select NetworkIdentifier -ExpandProperty NetworkIdentifier
# Get ClusterIdentifier for API
$VISiteInfoURL2 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/hostclusters"
$VISiteInfoCMD2 = Invoke-RestMethod -Uri $VISiteInfoURL2 -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$ClusterIdentifier = $VISiteInfoCMD2 | Where-Object {$_.VirtualizationClusterName -eq $ClusterName} | Select ClusterIdentifier -ExpandProperty ClusterIdentifier
# Get ServiceProfileIdenfitifer for API
$VISiteServiceProfileURL = $BaseURL+"serviceprofiles"
$VISiteServiceProfileCMD = Invoke-RestMethod -Uri $VISiteServiceProfileURL -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$ServiceProfileIdentifier = $VISiteServiceProfileCMD | Where-Object {$_.Description -eq $ServiceProfile} | Select ServiceProfileIdentifier -ExpandProperty ServiceProfileIdentifier
# Get DatastoreIdentifiers for API
$VISiteInfoURL3 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/datastores"
$VISiteInfoCMD3 = Invoke-RestMethod -Uri $VISiteInfoURL3 -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$DatastoreIdentifier = $VISiteInfoCMD3 | Where-Object {$_.DatastoreName -eq $DatastoreName} | Select DatastoreIdentifier -ExpandProperty DatastoreIdentifier
$JournalDatastoreIdentifier = $VISiteInfoCMD3 | Where-Object {$_.DatastoreName -eq $JournalDatastore} | Select DatastoreIdentifier -ExpandProperty DatastoreIdentifier
# Get Folders for API
$VISiteInfoURL4 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/folders"
$VISiteInfoCMD4 = Invoke-RestMethod -Uri $VISiteInfoURL4 -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$FolderIdentifier = $VISiteInfoCMD4 | Where-Object {$_.FolderName -eq $vCenterFolder} | Select FolderIdentifier -ExpandProperty FolderIdentifier

################################################
# Getting a VM identifier for each VM to be protected and adding it to the VMIDarray
################################################
# Reseting VM identifier list, required for creating multiple protection groups
$VMIdentifierList = $null
$VMIDArray = @()
# Running for each VM operation against the VPG name
foreach ($VMLine in $VPGVMNames)
{
write-host "$VMLine"
$VMInfoURL = $BaseURL+"virtualizationsites/$LocalSiteIdentifier/vms"
$VMInfoCMD = Invoke-RestMethod -Uri $VMInfoURL -TimeoutSec 100 -Headers $zertosessionHeader -ContentType $TypeJSON
$VMIdentifier = $VMInfoCMD | Where-Object {$_.VmName -eq $VMLine} | select VmIdentifier -ExpandProperty VmIdentifier
# Adding VM ID to array
$VMIDArrayLine = new-object PSObject
$VMIDArrayLine | Add-Member -MemberType NoteProperty -Name "VMID" -Value $VMIdentifier
$VMIDArray += $VMIDArrayLine
}

################################################
# Building JSON Request for posting VPG settings to API
################################################
$JSONMain =
"{
""Backup"": null,
""Basic"": {
""JournalHistoryInHours"": ""$JournalHistoryInHours"",
""Name"": ""$VPGName"",
""Priority"": ""$ReplicationPriority"",
""ProtectedSiteIdentifier"": ""$LocalSiteIdentifier"",
""RecoverySiteIdentifier"": ""$TargetSiteIdentifier"",
""RpoInSeconds"": ""$RpoAlertInSeconds"",
""ServiceProfileIdentifier"": null,
""TestIntervalInMinutes"": ""$TestIntervalInMinutes"",
""UseWanCompression"": true,
""ZorgIdentifier"": null
},
""BootGroups"": {
""BootGroups"": [
{
""BootDelayInSeconds"": 0,
""BootGroupIdentifier"": ""00000000-0000-0000-0000-000000000000"",
""Name"": ""Default""
}
]
},
""Journal"": {
""DatastoreClusterIdentifier"":null,
""DatastoreIdentifier"":""$DatastoreIdentifier"",
""Limitation"":{
""HardLimitInMB"":""$JournalHardLimitInMB"",
""HardLimitInPercent"":null,
""WarningThresholdInMB"":""$JournalWarningThresholdInMB"",
""WarningThresholdInPercent"":null
}
},
""Networks"": {
""Failover"":{
""Hypervisor"":{
""DefaultNetworkIdentifier"":""$FailoverNetworkIdentifier""
}
},
""FailoverTest"":{
""Hypervisor"":{
""DefaultNetworkIdentifier"":""$TestNetworkIdentifier""
}
}
},
""Recovery"": {
""DefaultDatastoreIdentifier"":""$DatastoreIdentifier"",
""DefaultFolderIdentifier"":""$FolderIdentifier"",
""DefaultHostClusterIdentifier"":""$ClusterIdentifier"",
""DefaultHostIdentifier"":null,
""ResourcePoolIdentifier"":null
},
""Scripting"": {
""PostBackup"": null,
""PostRecovery"": {
""Command"": null,
""Parameters"": null,
""TimeoutInSeconds"": 0
},
""PreRecovery"": {
""Command"": null,
""Parameters"": null,
""TimeoutInSeconds"": 0
}
},
""Vms"": ["
# Resetting VMs if a previous VPG was created in this run of the script
$JSONVMs = $null
# Creating JSON request per VM using the VM array for all the VMs in the VPG
foreach ($VM in $VMIDArray)
{
$VMID = $VM.VMID
$JSONVMsLine = "{""VmIdentifier"":""$VMID""}"
# Running if statement to check if this is the first VM in the array, if not then a comma is added to string
if ($JSONVMs -ne $null)
{
$JSONVMsLine = "," + $JSONVMsLine
}
$JSONVMs = $JSONVMs + $JSONVMsLine
}
# Creating the end of the JSON request
$JSONEnd = "]
}"
# Putting the JSON request elements together and outputting the request
$JSON = $JSONMain + $JSONVMs + $JSONEnd
write-host "Running JSON request below:
$JSON"

################################################
# Posting the VPG JSON Request to the API
################################################
Try
{
$VPGSettingsIdentifier = Invoke-RestMethod -Method Post -Uri $CreateVPGURL -Body $JSON -ContentType $TypeJSON -Headers $zertosessionHeader
write-host "VPGSettingsIdentifier: $VPGSettingsIdentifier"
}
Catch {
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}

################################################
# Confirming VPG settings from API
################################################
$ConfirmVPGSettingURL = $BaseURL+"vpgSettings/"+"$VPGSettingsIdentifier"
$ConfirmVPGSettingCMD = Invoke-RestMethod -Method Post -Uri $ConfirmVPGSettingURL -Headers $zertosessionHeader -ContentType $TypeJSON

################################################
# Committing the VPG settings to be created
################################################
$CommitVPGSettingURL = $BaseURL+"vpgSettings/"+"$VPGSettingsIdentifier"+"/commit"
write-host "Commiting VPG creation for VPG:$VPGName with URL:
$CommitVPGSettingURL"
Try
{
Invoke-RestMethod -Method Post -Uri $CommitVPGSettingURL -ContentType $TypeJSON -Headers $zertosessionHeader -TimeoutSec 100
}
Catch {
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}

################################################
# Waiting $TimeToWaitBetweenVPGCreation seconds before creating the next VPG
################################################
write-host "Waiting $TimeToWaitBetweenVPGCreation seconds before creating the next VPG or stopping script if on the last VPG"
sleep $TimeToWaitBetweenVPGCreation
#
# End of per VPG actions below
}
# End of per VPG actions above
#

################################################
# Stopping logging
################################################
Stop-Transcript
