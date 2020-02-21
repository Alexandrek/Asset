<#
.NAME
    Collect-SwitchConfig.ps1

.DESCRIPTION
    This Script pulls Cisco or Schneider Switch configurations for every switch listed in the specified file.
    It then proceeds to compare it with the previous version of the configuration stored to see if any changes have been made.
    If new changes are present it will save a new copy of the config and raise an event ID 9 to be alerted on.  

.EXAMPLE
    Collect-SwitchConfig.ps1 -SwitchListPath "C:\Scripts\CiscoSwichList.txt" -ConfigDirectory "C:\Scripts\Logs" -SwitchType Cisco -SwitchCredUser test -SwitchCredPass pass

.PARAMETER SwitchesListPath
    The parameter SwitchesListPath is used to define the full path to the list of switches

.PARAMETER ConfigsDirectory
        The parameter ConfigsDirectory is used to define the path to store the switch configurations

.PARAMETER SwitchCredUser
    The parameter ConfigsDirectory is used to set the Username used for the switches

.PARAMETER SwitchCredPass
    The parameter SwitchCredPass is used to set the Password used for the switches

.PARAMETER SwitchType
    The parameter SwitchType is used to confirm whether these are Cisco or Schneider switches

.NOTES
    Author: Alex Kirby
    Email: Alexandre.kirby@hotmail.co.uk
    Date: 21/02/2020
    Version: 0.3
    Version history:
    0.1: - 13/02/2020
         - first draft
    0.2: - 17/02/2020
         - Setup as a Function 
         - Added Ability to select between Cisco and Schneider
         - script Name changed from cisco config to Collect-SwitchConfig
         - Added error checking
         - Added ability to pass in credentials
    0.3 - 21/02/2020
        - Added SSH test prior to running telnet with the use of Posh-SSH -version 1.7.7
        - Resolved issues with incorrect Config file creation



    Custom even log source was created prior to using this script with the below command;
        New-EventLog –LogName Application –Source “BaseRock”

    SSH requires the use of the Posh-SSH 1.7.7 module, this can be added using the below script
        Install-Module -Name Posh-SSH -RequiredVersion 1.7.7
        
#>

#Requires -module Posh-SSH -version 1.7.7


Function Collect-SwitchConfig{
    Param(
       [Parameter(Position=0,Mandatory=$true)]
       [ValidateScript({$_ | Test-Path})]
       [string]$SwitchListPath,
       [Parameter(Position=1,Mandatory=$true)]
       [ValidateScript({$_ | Test-Path})]
       [string]$ConfigDirectory,
       [Parameter(Position=2,Mandatory=$true)]
       [ValidateSet("Cisco",'Schneider')]
       [String[]]$SwitchType,
       [Parameter(Position=3,Mandatory=$true)]
       [string]$SwitchCredUser,
       [Parameter(Position=4,Mandatory=$true)]
       [string]$SwitchCredPass

    )#End Param
    
        ##Global Setup Variables 
        $Date = Get-Date -Format dd_MM_yyyy@HH_mm
        $ErrorActionPreference = "silentlycontinue"

        If (!!(Get-EventLog -LogName Application -Source BaseRock)){
    
            $Switches = Get-Content $SwitchListPath
             
            Foreach($Switch in $Switches){

                If(!!(Test-Connection $Switch -Count 2 -Quiet)){

                    $LogName = $Switch + "_" + $Date + ".txt"

                    If (!($ConfigDirectory.EndsWith('\'))){
                        $ConfigDirectory += "\"

                    }
                    $LogPath = $ConfigDirectory + $LogName

                    New-Item -ItemType File -Path $LogPath
                    Sleep 5

                   ##SSH
                    if((Test-NetConnection $Switch -Port 22).TcpTestSucceeded -and ($SwitchType -eq 'Cisco')){
                        
                        Sleep 8
                        $password = ConvertTo-SecureString $SwitchCredPass -AsPlainText -Force
                        $SSHCred = New-Object System.Management.Automation.PSCredential ($SwitchCredUser, $password)

                         $SSHSession = New-SSHSession -ComputerName $Switch -Credential $SSHCred -AcceptKey

                        $SSHRun =  Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "sh run"

                        Add-Content -Value $SSHRun.Output -Path $LogPath

                    }
    
                    ##Telnet 
                    Elseif(Test-NetConnection $Switch -Port 23){          
                       
                       Sleep 8 
                       $wshell = New-Object -Com wscript.shell
                        Start-Process telnet -ArgumentList "$Switch -f $LogPath"
                        sleep 2

                        If($SwitchType -eq 'Cisco'){
                            $command = "$SwitchCredUser{ENTER}$SwitchCredPass{ENTER}terminal length 0{ENTER}sh run{ENTER}"
                            sleep 1
                            $wshell.SendKeys("$command")
                            sleep 6
                            $wshell.SendKeys("quit{ENTER}")


                        }
                        Elseif($SwitchType -eq 'Schneider'){
                            $command = "$SwitchCredUser{ENTER}$SwitchCredPass{ENTER}en{ENTER}sh run{ENTER}logout{ENTER}"
                            sleep 1
                            $wshell.SendKeys("$command")
                            sleep 2

                        }
        
                        sleep 7
                        $wshell.SendKeys("{ENTER}") 
                        
                    }       
            


                ##Check if comaprison needed
                    If (Get-ChildItem -Path $ConfigDirectory -Filter "$Switch*Live*" | Test-Path ){
                            
                        $Latest = Get-ChildItem -Recurse -Path $ConfigDirectory -Filter "$Switch*Live*"
                        $Live = Get-Content $Latest.FullName
                        $PresentOutput = Get-Content $LogPath
       
        
                    
                        If(Compare-Object -ReferenceObject $Live -DifferenceObject $PresentOutput){ ##Files are different

                           Rename-Item $Latest.FullName -NewName ($latest.FullName -replace ".{8}$",".txt")
         
                           Rename-Item $LogPath -NewName ($LogPath -replace ".txt","Live.txt")

                           ##Create Event ID 9
                           $Modifications  = Compare-Object -ReferenceObject $Live -DifferenceObject $telnetoutput -PassThru
                           $Message = "
                               Switch IP : $Switch
           
                               New configuration changes have been made ;
               
                               NEW - OLD
                               $Modifications
                           "
                           Write-EventLog -EventId 9  -LogName Application -EntryType Warning -Source "BaseRock" -Message $Message
                        }Else { ##Files are the same
        
                            Remove-Item $LogPath

                            ##Create Event Id 8
                            Write-EventLog -EventId 8  -LogName Application -EntryType Information -Source "BaseRock" -Message "No new changes to config on $Switch"
        
                        }
                    }Else{
                            Rename-Item $LogPath -NewName ($LogPath -replace ".txt","Live.txt")
                    }
                      
                }Else{
           
                    Write-EventLog -EventId 11  -LogName Application -EntryType Error -Source "BaseRock" -Message "Switch $Switch Not Reachable"

                }#End If Alive



            }#End Foreach Loop
        }Else{

            Write-EventLog -EventId 10  -LogName 'Windows PowerShell' -EntryType Error -Source "Powershell" -Message "The event source 'Baserock' has not been created"

        }
        
}#End Function

Collect-SwitchConfig