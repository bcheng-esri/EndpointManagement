# Endpoint Management

A PowerShell script repository for Configuration Manager (SCCM/MECM)

## Scripts

| Name | Function |
| --- | --- |
| Install-SCCMClient.ps1 | Installs the SCCM client |
| Uninstall-SCCMClient.ps1 | Uninstalls the SCCM client |
| Reset-WindowsUpdate.ps1 | Fully resets Windows Updates components, files, and settings |
| Reset-WMIRepository.ps1 | [Click here for details](https://github.com/bcheng-esri/Reset-WMIRepository) |
| Invoke-SCCMClientActions.ps1 | [Click here for details](https://github.com/bcheng-esri/Invoke-SCCMClientActions) |


## Requirements

- An **elevated (Administrator)** PowerShell session

## Usage

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/Install-SCCMClient.ps1 | iex
```

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/Uninstall-SCCMClient.ps1 | iex
```

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/Reset-WindowsUpdate.ps1 | iex
```
