#Requires -RunAsAdministrator
# fix-wsl-routing.ps1 - let WSL reach the Multipass (Hyper-V) VMs on Windows 10.
#
# WSL 2 and the Hyper-V VMs sit on separate virtual switches and Windows does not
# route between them by default. Turning on forwarding for the vEthernet adapters
# fixes it. Windows resets this at every reboot, so run it again after a restart:
#
#   powershell -ExecutionPolicy Bypass -File .\fix-wsl-routing.ps1

Get-NetIPInterface |
    Where-Object { $_.InterfaceAlias -like 'vEthernet*' } |
    Set-NetIPInterface -Forwarding Enabled

Get-NetIPInterface -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -like 'vEthernet*' } |
    Format-Table InterfaceAlias, Forwarding -AutoSize
