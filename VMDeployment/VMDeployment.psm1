
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

Function Find-DiskExistence {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMDisk,
        [Parameter(Mandatory=$true)]
        [String]$VirtualizationServerName
    )

    Process {
        $DiskList = Invoke-Command -ScriptBlock {ls -Path "C:\EasyCloud\VirtualMachines\Disk\" | Select-Object Name | Where-Object Name -like "$VMDisk"} -ComputerName $VirtualizationServerName

        If($DiskList) {
            Return "NA"
        }

        Else {
            Write-Host "Deployment of a new virtual machine started..." -ForegroundColor Cyan
            Return $VMDisk
        }
    }
}

Function Save-Configuration {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMName,
        [Parameter(Mandatory=$true)]
        [String]$VMId,
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
            Id = $VMId
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
        $ConfigPath = "$Path"+"Configuration\VirtualMachines" + "\$VMName"
        $VMLocation = '"'+$VMLocation+'"'

        $VMConfig | ConvertTo-Json -Depth 2 | Out-File $ConfigPath

        Write-Host "(i) Configuration file have been saved in the following folder " -ForegroundColor Cyan -NoNewline
        Write-Host "$ConfigPath" -BackgroundColor White -ForegroundColor Black
    }
}

Function Get-AvailableIso {
        $shareServer = (hostname).ToUpper()
        $IsoList = @{}

        $i = 0

        ((ls -Path "\\$shareServer\Isofiles").Name) | ForEach-Object {
            $i++
            $item = "Item$i"
            $IsoList.$item += @{
                "Folder" = $shareServer 
                "Filename" = "$_" }
        }

        $IsoList = ConvertTo-Json -InputObject $IsoList

        Return $IsoList      
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
            $VMDisk = "$VMName" + ".vhdx"
            $VMDiskPath = "C:\EasyCloud\VirtualMachines\Disk\$VMDisk"
            $DiskChecker = Find-DiskExistence -VMDisk $VMDisk -VirtualizationServerName $VirtualizationServer
            $VMPath = "C:\EasyCloud\VirtualMachines\VM\$VMName"
            $VMGeneration = 1
            $VMSwitchName = "InternalSwitch"
            $MachineCores = (Get-WmiObject Win32_processor -ComputerName $VirtualizationServer | Select-Object NumberOfLogicalProcessors)

            If($DiskChecker -eq "NA") {
                Write-Error "Disk with same name already exist"
                Write-Host "(x) Deployment failed" -ForegroundColor Red
                Break;
            }

            If($VMProcessor -gt $MachineCores.NumberOfLogicalProcessors) {
                Write-Error "Number of virtual cores attributed are outpassing physical server number"
                Write-Host "(x) Deployment failed" -ForegroundColor Red
                Break;
            }

            If(Get-VMSwitch -ComputerName $VirtualizationServer | Where-Object Name -like InternalSwitch) {
                Write-Host "InternalSwitch exist" -ForegroundColor Green
            } Else {
                New-VMSwitch -name 'InternalSwitch' -NetAdapterName Ethernet -AllowManagementOS $true -ComputerName $VirtualizationServer
            }

            $Command = "New-VM -Name $VMName -ComputerName $VirtualizationServer -MemoryStartupBytes $VMRam -NewVHDPath '$VMDiskPath' -NewVHDSizeBytes $VMDiskSize -Path "+ "'$VMPath' " + "-Generation $VMGeneration -SwitchName '$VMSwitchName'"

            Invoke-Expression $Command

            Try {
                Add-VMDvdDrive -VMName $VMName -Path "$VMOS" -ComputerName $VirtualizationServer
                Set-VMProcessor $VMName -Count $VMProcessor -ComputerName $VirtualizationServer
                Write-Host "(/) Sucessful verification" -ForegroundColor Green
            } 
            
            Catch {
                Write-Warning "(x) Verification failed"
                Break;
            }

            Write-Host "(/) Sucessful deployment" -ForegroundColor Green

            $VMId = (Get-VM -Name $VMName -ComputerName $VirtualizationServer | Select-Object -Property Id).Id.Guid
            
            Try {
                $Save = 'Save-Configuration -VMName $VMName -VMId $VMId -VMRam $VMRam -VMDisk "$VMDiskPath" -VMDiskSize $VMDiskSize -VMLocation "$VMPath" -VMGeneration $VMGeneration -VMIso $VMOS -VMSwitchName $VMSwitchName -VirtualizationServer $VirtualizationServer'
                Invoke-Expression $Save
                Write-Host " "
            } Catch {
                Write-Warning "The configuration haven't been saved "
            }
        } 
        
        Catch {
            Write-Warning "An error occured in the execution"
            Write-Host "(x) Deployment failed" -ForegroundColor Red
        }

        Return $VMId
    }
}

Function Uninstall-VM {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$VMId,
        [Parameter(Mandatory=$true)]
        [String]$VirtulizationServer
    )

    Process {
        Try {
            $VMToDelete = (Get-VM -Id $VMId -ComputerName $VirtulizationServer)

            $VMName = $VMToDelete.Name

            $VMDisk = "C:\EasyCloud\VirtualMachines\Disk\" + "$VMName"+".vhdx"

            Invoke-Command -ScriptBlock {Remove-Item -Path $Using:VMDisk} -ComputerName $VirtulizationServer

            $VMToDelete | Remove-VM -Force

            If((Get-VM -Id $VMId -ComputerName $VirtulizationServer)) {
                Write-Error "VM $VMName have not been deleted"
            } Else {
                Write-Host "Virtual machine have been deleted" -ForegroundColor Green
            }
        } Catch {
            Write-Error "A problem occured during the deletion"
        }
    }
}

Export-ModuleMember -Function Add-NewVM, Uninstall-VM, Get-AvailableIso