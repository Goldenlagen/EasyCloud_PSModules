﻿
Function Get-VMDeploymentPath {
    $Path = (Get-Module VMDeployment).Path

    $PathArray = $Path.split('\')

    $basePath = ""

    $PathArray | ForEach-Object {
        If($_ -match 'EasyCloud') {
            For ($i=0; $i -lt $PathArray.IndexOf($_) + 1; $i++) {
                $basePath += $PathArray[$i]+"\"
            }
        }
    } 

    Set-Location $basePath
    Return $basePath
}
﻿
Function Find-DiskExistence {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMDisk
    )

    Process {
        $DiskList = Get-VMHardDiskDrive *

        Foreach($Disk in $DiskList) {
            If($Disk.Path -eq $VMDisk) {
                Return "NA"
            } Else {
                Write-Host "Deployment of a new virtual machine started..." -ForegroundColor Cyan
                Return $VMDisk
            }
        }
    }
}

Function Save-Configuration {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMName,
        [Parameter(Mandatory=$true)]
        [String]$VMRam,
        [Parameter(Mandatory=$true)]
        [String]$VMDisk,
        [Parameter(Mandatory=$true)]
        [String]$VMDiskSize,
        [Parameter(Mandatory=$true)]
        [String]$VMLocation,
        [Parameter(Mandatory=$true)]
        [Int16]$VMGeneration,
        [Parameter(Mandatory=$true)]
        [String]$VMIso,
        [Parameter(Mandatory=$true)]
        [String]$ServerName,
        [Parameter(Mandatory=$true)]
        [String]$VMSwitchName,
        [Parameter(Mandatory=$true)]
        [String]$VirtualizationServer
    )

    Begin {
        $Path = Get-VMDeploymentPath
    }

    Process {
        $VMDisk = $VMDisk.Replace('"', '')
        $VMLocation = $VMLocation.Replace('"', '')
        $VMIso = $VMIso.Replace('"', '')
        $VMSwitchName = $VMSwitchName.Replace('"', '')

        $VMValues = [PSCustomObject]@{
            Name = $VMName
            Ram = $VMRam
            DiskLocation = $VMDisk
            DiskSize = $VMDiskSize
            Location = $VMLocation
            Generation = $VMGeneration
            Iso = $VMIso
            SwitchName = $VMSwitchName
            ServerName = $VirtualizationServer
        }

        $VMConfig = [PSCustomObject]@{
            $VMName = $VMValues
        }

        $VMName = "$VMName"+".json"

        $ConfigPath = "$Path\Configuration\VirtualMachines" + "\$VMName"

        $VMLocation = '"'+$VMLocation+'"'

        $VMConfig | ConvertTo-Json -Depth 2 | Out-File $ConfigPath
    }
}

Function Add-NewVM {
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [String]$VMName,
        [Parameter(Mandatory=$true)]
        [String]$VMRam,
        [Parameter(Mandatory=$true)]
        [String]$VMDiskSize,
        [Parameter(Mandatory=$true)]
        [String]$VMOS,
        [Parameter(Mandatory=$true)]
        [Int]$VMProcessor,
        [Parameter(Mandatory=$true)]
        [String]$VirtualizationServer
    )

    Begin {
        $Path = Get-VMDeploymentPath
    }

    Process {
        Try {
            $VMDisk = "F:\ESTIAM\M1 - ESTIAM\PIM\EasyCloud\VM\Storage\$VMName" + ".vhdx"
            $DiskChecker = Find-DiskExistence -VMDisk $VMDisk
            $VMPath = "F:\ESTIAM\M1 - ESTIAM\PIM\EasyCloud\VM\$VMName"
            $VMGeneration = 1
            $VMSwitchName = "Default Switch"
            $MachineCores = (Get-WmiObject Win32_processor | Select-Object NumberOfLogicalProcessors)

            Write-Host $DiskChecker

            If($DiskChecker -eq "NA") {
                Write-Warning "Disk with same name already exist"
                Write-Host "(x) Deployment failed" -ForegroundColor Red
                Break;
            }

            If($VMProcessor -gt $MachineCores.NumberOfLogicalProcessors) {
                Write-Warning "Number of virtual cores attributed are outpassing physical server number"
                Write-Host "(x) Deployment failed" -ForegroundColor Red
                Break;
            }

            $Command = "New-VM -Name $VMName -ComputerName $VirtualizationServer -MemoryStartupBytes $VMRam -NewVHDPath '$VMDisk' -NewVHDSizeBytes $VMDiskSize -Path "+ "'$VMPath' " + "-Generation $VMGeneration -SwitchName '$VMSwitchName'"

            Invoke-Expression $Command
            
            Try {
                Add-VMDvdDrive -VMName $VMName -Path "$SelectedIsoPath"
                Set-VMProcessor $VMName -Count $VMProcessor
                Write-Host "(/) Sucessful verification" -ForegroundColor Green
            } 
            
            Catch {
                Write-Warning "(x) Verification failed"
                Break;
            }

            Write-Host "(/) Sucessful deployment" -ForegroundColor Green
            
            Try {
                $Save = 'Save-Configuration -VMName $VMName -VMRam $VMRam -VMDisk "$VMDisk" -VMDiskSize $VMDiskSize -VMLocation "$VMPath" -VMGeneration $VMGeneration -VMIso $VMOS -VMSwitchName $VMSwitchName'
                Invoke-Expression $Save
                Write-Host "(i) Configuration file have been saved in the following folder " -ForegroundColor Cyan -NoNewline
                Write-Host "F:\ESTIAM\M1 - ESTIAM\PIM\EasyCloud\VM\Config" -BackgroundColor White -ForegroundColor DarkYellow
                Write-Host " "
            } Catch {
                Write-Warning "The configuration haven't been saved "
            }
            
        } 
        
        Catch {
            Write-Warning "An error occured in the execution"
            Write-Host "(x) Deployment failed" -ForegroundColor Red
        } 
    }
}

Function Uninstall-VM {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMName
    )

    Process {
        Try {
            $VMPathToDelete = ((Get-VM | Where-Object {$_.Name -like $VMName} | Select-Object HardDrives).HardDrives).Path
            Remove-Item -Path $VMPathToDelete
            Write-Host "Virtual machine named $VMName have been deleted" -ForegroundColor Green
        } Catch {
            Write-Error "A problem occured during the deletion"
        }
    }
}

Export-ModuleMember -Function Add-NewVM, Uninstall-VM, Test 