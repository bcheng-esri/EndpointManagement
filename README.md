# Endpoint Management

A PowerShell script repository for Configuration Manager (SCCM/MECM)

## Scripts

| Name | Function |
| --- | --- |
| Install_SCCM_Client.ps1 | Installs the SCCM client |
| Uninstall_SCCM_Client.ps1 | Uninstalls the SCCM client |
| WindowsUpdate_Reset.ps1 | Fully resets Windows Updates components, files, and settings |
| Invoke-SCCMClientActions.ps1 | [Click here for details](https://github.com/bcheng-esri/Invoke-SCCMClientActions) |
| Reset-WMIRepository.ps1 | [Click here for details](https://github.com/bcheng-esri/Reset-WMIRepository) |

## Requirements

- An **elevated (Administrator)** PowerShell session

## Usage

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/Install_SCCM_Client.ps1 | iex | iex
```

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/Uninstall_SCCM_Client.ps1 | iex | iex
```

```powershell
irm https://raw.githubusercontent.com/bcheng-esri/EndpointManagement/refs/heads/main/scripts/WindowsUpdate_Reset.ps1 | iex | iex
```
