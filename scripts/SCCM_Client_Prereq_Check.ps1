<#
.SYNOPSIS
	This script is used to verify the prereqs for the SCCM client.

.DESCRIPTION
	This script will check if the device is joined to the correct domains and a ConfigMgr certificate is enrolled and not expired.

.PARAMETER

.EXAMPLE

.NOTES
	Created on:   03-04-2024
	Modified:     05-22-2026
	Author:       Brian Cheng
	Version:      1.1
	Mail:         

	Changelog:
	----------
	03-04-2024 - v1.0 - The Creation date of this script
	05-22-2026 - v1.1 - Added management point server checks

.LINK
	
#>

#Execute script as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
$ProgressPreference = 'SilentlyContinue'

#Verifying the computer is joined to Esri.com or UC.esri.com domain
$domain = (gwmi win32_computersystem).domain
write-host "Verifying domain join:"
if (($domain -eq "esri.com") -or ($domain -eq "uc.esri.com")) {
    write-host -fore green "  Device is joined to $domain"
} else {
    write-host -fore red "  Device is NOT joined to esri.com nor uc.esri.com!"
}
write-host ""
write-host ""

#Verifying the computer has a ConfigMgr certificate enrolled
$templateName = 'ConfigMgr Client Certificate'
$sccmcert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object{ $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq 'Certificate Template Information') -and ($_.Format(0) -match $templateName) }}
write-host "Verifying ConfigMgr certificate:"
if ($sccmcert -ne $null) {
    if ($sccmcert.NotAfter -gt (Get-Date)) {
        write-host -fore green "  Device has a valid ConfigMgr computer certificate"
    } else {
        $sccmcertdate = $sccmcert.NotAfter
        write-host -fore red "  Device has a ConfigMgr computer certificate BUT the certificate is expired! ($sccmcertdate)"
    }
} else {
    write-host -fore red "  Device does NOT have the correct computer certificate!"
    write-host -fore red "  Please run certlm.msc and ensure the correct certificate is enrolled"
}
write-host ""
write-host ""

#Verifying the computer has access to SCCM servers
$CMGServer = "esricmg.esri.com"
$SCCMServer = "red-inf-sccm-p2.esri.com"
write-host "Verifying access to Cloud Management Gateway or internal SCCM server:"
$CMGServerConnection = Test-NetConnection -ComputerName $CMGServer -Port 443 -InformationLevel quiet
$SCCMServerConnection = Test-NetConnection -ComputerName $SCCMServer -Port 443 -InformationLevel quiet
write-host "  Device access to CMG is $CMGServerConnection"
write-host "  Device access to SCCM server is $SCCMServerConnection"

write-host ""
write-host ""

pause
