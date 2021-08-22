+++
title = "PowerShell NetApp SnapMirror Destination Migration"
date = "2021-08-22"
description = "PowerShell based Migration of NetApp SnapMirror destination systems."
featured = true
tags = [
    "Robin Beismann"
]
categories = [
    "NetApp"
    "SnapMirror"
    "Migration"
]
series = [""]
aliases = ["test"]
thumbnail = "post/20210822_NetAppSnapmirrorPoShMigration/NetAppLogo.png"
+++
This article shows how to use PowerShell and the NetApp PowerShell Module to migrate all NetApp SnapVault/SnapMirror relationships to a new system.
The script also builds the SVM Relationships and does the cutovers of the relationships on the source ONTAP Systems. 
<!--more-->

# Introduction
If you ever had to migrate a SnapMirror Destination ONTAP System to a new one, you probably already faced the struggle to migrate Volume by Volume and SnapMirror by SnapMirror to keep all Snapshots.

The good news: You don't have to do this manually as NetApp has a great PowerShell integration for both, ONTAP and 7-Mode Systems.

# The magic
Since I had to migrate multiple SnapMirror Destination ONTAP Clusters to new ones and realized how much effort this is per volume, I came up with this PowerShell script to automate this process.

What this script does is:
- SVM Peering
- Volume creation
- Intermediate SnapMirror Relationship and Initialization
- Cutover on the Source Systems from the old SnapMirror Destination over to new SnapMirror Destination (keeping the existing policy, schedule and settings)
- Break-up off the existing SnapMirror from Source Systems to the old Destination System

Prerequisites:
- Credentials for all involved ONTAP Systems
- Cluster Peering between old destination system and new destination system
- Cluster Peering between source systems and new destination systems
- SnapMirror Policies, Schedules and Snapshot Labels from all source storages pre-created on the new destination system (the script will not create them)

# How to use it
To use the script, simply fill in the variables at the start of the script, please make sure to cross check all information you enter.
On the first run, it will ask you for credentials for both, the old and the new destination system. After that, it will create the SVM Peerings (if not existent), the volumes and the SnapMirrors between the old and new destination system and initialize them.

It will take some time (hours to weeks) to transfer the data in those volumes between the old destination and the new destination systems depending on both systems performance and the amount of data. 

You can check the status on the new destination system by executing `snapmirror show` and verifying that the status is `snapmirrored` and `idle`. 

As soon as that's the case, run the script once more. It will start by fetching the status then quiescing, breaking and deleting the mirrors to the old backup system and ask you for credentials to all involved source systems. After entering the credentials, it will start to build the SnapMirror Relationships from the source system to the new destination system, invoke a resync and release the SnapMirror to the old backup system.

# The script
````PowerShell
#region Variables
$oldIP = "<Management IP of old destination storage>"
$newIP = "<Management IP of new destination storage>"

[array]$svms = @(
    @{
        Old = "<SVM Name on old destination storage>"
        New = "<SVM Name on new destination storage>"
    }
    <#
        Add as many SVMs as required
        @{
            Old = "<SVM Name on old destination storage>"
            New = "<SVM Name on new destination storage>"
        }
    #>
)
#endregion

#region Code below

if(!$oldCreds){
    $oldCreds = Get-Credential -Message "Old System"
}
if(!$newCreds){
    $newCreds = Get-Credential -Message "New System"
}

$oldCluster = Connect-NcController -HTTPS -Credential $oldCreds -Name $oldIP
$newCluster = Connect-NcController -HTTPS -Credential $newCreds -Name $newIP

$oldClusterName = (Get-NcCluster -Controller $oldCluster).ClusterName
$newClusterName = (Get-NcCluster -Controller $newCluster).ClusterName

if(!$CredentialTable){
    $CredentialTable = @{}
}
if(!$IPTable){
    $IPTable = @{}
}
if(!$ClusterTable){
    $ClusterTable = @{}
}

if(!($calculatedBlacklist)){
    $calculatedBlacklist = @()
}

$svms.GetEnumerator() | ForEach-Object {

    $OldSVM = $_.Old
    $NewSVM = $_.New

    $OldSVMObj = Get-NcVserver -Name $OldSVM -Controller $oldCluster

    # Check if Destination SVM Exists
    if(!($NewSVMObj = Get-NcVserver -Name $newSVM -Controller $newCluster)){
        Write-Host("Creating new vServer $newSVM on $newClusterName")
        $aggr = (Get-NcAggr -Controller $newCluster | Sort-Object -Property Available -Descending)[0].Name
        $null = New-NcVserver   -Name $NewSVM `
                        -RootVolumeAggregate $aggr `
                        -RootVolumeSecurityStyle $oldsvmobj.RootVolumeSecurityStyle `
                        -Language $oldsvmobj.Language `
                        -Controller $newCluster
    }

    # Check if Destination SVM is peered with source vserver
    if(!($peerrelationship = Get-NcVserverPeer -Vserver $OldSVM -PeerVserver $NewSVM -Controller $oldCluster -Application "snapmirror")){
        Write-Host("Creating new vServer Peer Relationship for $($oldClusterName):$($OldSVM) to $($newClusterName):$($NewSVM)")
        $peerrelationship = New-NcVserverPeer -Vserver $OldSVM -PeerVserver $NewSVM -Controller $oldCluster -Application "snapmirror" -PeerCluster $newClusterName
    }
    
    # Check if SVM Peer is unitialized
    if($peerrelationship.PeerState -eq "initiated"){
        Write-Host("Confirming new vServer Peer Relationship for $($oldClusterName):$($OldSVM) to $($newClusterName):$($NewSVM)")
        $null = Confirm-NcVserverPeer -Vserver $NewSVM -PeerVserver $OldSVM -Controller $newCluster
    }
    
    # Get existing volumes
    Write-Host("Getting volumes for $oldSVM on $oldClusterName")
    $vols = @()
    Get-NcVol -Vserver $OldSVM -Controller $oldCluster | Where-Object { $_.Name -notlike "*root*" } | ForEach-Object {
        $vols += @{
            Size = $_.TotalSize
            Language = $_.VolumeLanguageAttributes.LanguageCode
            Name = $_.Name
            Security = $_.VolumeSecurityAttributes.Style
        }
    }
        
    # Run through volumes 
    $vols.GetEnumerator() | Where-Object { 
                                            ($_.Name -notin $calculatedBlacklist) -and 
                                            ($_.Name -notin $volumeBlacklist)
                                         } | ForEach-Object {
        # Create new volume if it doesn't exist
        $aggr = (Get-NcAggr -Controller $newCluster | Sort-Object -Property Available -Descending)[0].Name
        if(!($volume = Get-NcVol -Name $_.Name -Vserver $NewSVM -Controller $newCluster)){
            Write-Host("Creating new volume `"$($_.Name)`" for $newSVM on $newClusterName")
            $null = New-NcVol -Size $_.Size -Name $_.Name -Language $_.Language -SecurityStyle $_.Security -VserverContext $NewSVM -Aggregate $aggr -Type dp -JunctionActive:$false -JunctionPath $null -Controller $newCluster
        }
        
        # Create new snapmirror if it doesn't exist
        if(!($snapmirror = Get-NcSnapmirror -SourceCluster $oldClusterName -SourceVserver $OldSVM -SourceVolume $_.Name -DestinationCluster $newClusterName -DestinationVserver $NewSVM -DestinationVolume $_.Name -Controller $newCluster)){
            Write-Host("Creating new snapmirror from $($oldClusterName):$($OldSVM):$($_.Name) to $($newClusterName):$($NewSVM):$($_.Name)")
            $snapmirror = New-NcSnapmirror -SourceCluster $oldClusterName -SourceVserver $OldSVM -SourceVolume $_.Name -DestinationCluster $newClusterName -DestinationVserver $NewSVM -DestinationVolume $_.Name -Schedule "hourly" -Policy "MirrorAllSnapshots" -Controller $newCluster
        }

        # Initialize new snapmirror if not done yet
        if(
            $snapmirror.MirrorState -eq "uninitialized" -and
            $snapmirror.Status -ne "transferring" -and
            $snapmirror.Status -ne "finalizing"    
        ){
            Write-Host("Initializing new snapmirror from $($oldClusterName):$($OldSVM):$($_.Name) to $($newClusterName):$($NewSVM):$($_.Name)")
            $null = Invoke-NcSnapmirrorInitialize -SourceCluster $oldClusterName -SourceVserver $OldSVM -SourceVolume $_.Name -DestinationCluster $newClusterName -DestinationVserver $NewSVM -DestinationVolume $_.Name -Controller $newCluster
        }

        if(
            ($snapmirror.MirrorState -eq "snapmirrored") -and
            ($snapmirror.status -eq "idle") -and
            ($snapmirror.IsHealthy) -and
            ($oldSnapmirror = Get-NcSnapmirror -DestinationCluster $oldClusterName -Destination $_.Name -Controller $oldCluster) -and
            ($peerVserver = Get-NcVserverPeer -Controller $oldCluster | Where-Object { 
                                                                                        $_.PeerVserverUuid -eq $oldsnapmirror.SourceVserverUuid -and 
                                                                                        $_.VserverUuid -eq $oldsnapmirror.DestinationVserverUuid 
                                                                                     }
            )
        ){
            Write-Host("Found healthy snapmirror for $($oldClusterName):$($OldSVM):$($_.Name), source cluster $($peerVserver.PeerCluster) - ready for cutover.")
            $peerCluster = $peerVserver.PeerCluster
            if(!($IPTable[$peerCluster])){
                $IPTable[$peerCluster] = Read-Host -Prompt "Enter IP for: $peerCluster"
            }
            if(!($CredentialTable[$peerCluster])){
                $CredentialTable[$peerCluster] = Get-Credential -Message "Enter Credentials for: $peerCluster" -UserName "admin"
            }
            if(!($ClusterTable[$peerCluster])){
                $ClusterTable[$peerCluster] = Connect-NcController -HTTPS -Credential $CredentialTable[$peerCluster] -Name $IPTable[$peerCluster]
            }
            
            if(Get-NcVol -Name $oldsnapmirror.SourceVolume -Vserver $oldSnapmirror.SourceVserver -Controller $ClusterTable[$peerCluster]){                          
                Write-Host("Found healthy snapmirror for $($oldClusterName):$($OldSVM):$($_.Name), source cluster $($peerVserver.PeerCluster) - successfully validated volume on source cluster.")
                $curVol = $_
                if(!(Get-NcClusterPeer -Name $peerCluster -Controller $newCluster)){
                    Write-Host -Object "Cluster Peering between $peerCluster and $newClusterName does not exist, please peer first!"
                    break;
                }

                # Check if Destination SVM is peered with source vserver
                if(!($peerrelationship = Get-NcVserverPeer -Vserver $peervserver.PeerVserver -PeerVserver $NewSVM -Controller $ClusterTable[$peerCluster] -Application "snapmirror")){
                    Write-Host("Creating new vServer Peer Relationship for $($peerCluster):$($peervserver.PeerVserver) to $($newClusterName):$($NewSVM)")
                    $peerrelationship = New-NcVserverPeer -Vserver $peervserver.PeerVserver -PeerVserver $NewSVM -Controller $ClusterTable[$peerCluster] -Application "snapmirror" -PeerCluster $newClusterName
                }
    
                # Check if SVM Peer is unitialized
                if($peerrelationship.PeerState -eq "initiated"){
                    Write-Host("Confirming vServer Peer Relationship for $($peerCluster):$($peervserver.PeerVserver) to $($newClusterName):$($NewSVM)")
                    $null = Confirm-NcVserverPeer -Vserver $NewSVM -PeerVserver $peervserver.PeerVserver -Controller $newCluster
                }

                # Stop replicating from source to old cluster
                ## Quiesce Snapmirror on old cluster from source cluster
                Write-Host("Quiscing Snapmirror from $($oldsnapmirror.SourceLocation) to $($oldsnapmirror.DestinationLocation)")
                Invoke-NcSnapmirrorQuiesce -Destination $oldsnapmirror.DestinationLocation -Source $oldsnapmirror.SourceLocation -Controller $oldCluster  

                # Break Relationship new cluster to old cluster                
                ## Quiesce Snapmirror on new cluster from old cluster
                Write-Host("Quiscing Snapmirror from $($snapmirror.SourceLocation) to $($snapmirror.DestinationLocation)")
                Invoke-NcSnapmirrorQuiesce -Destination $snapmirror.DestinationLocation -Source $snapmirror.SourceLocation -Controller $newCluster                
                
                ## Break Snapmirror on new cluster from old cluster
                Write-Host("Break Snapmirror from $($snapmirror.SourceLocation) to $($snapmirror.DestinationLocation)")
                Invoke-NcSnapmirrorBreak -Destination $snapmirror.DestinationLocation -Source $snapmirror.SourceLocation -Controller $newCluster -Confirm:$false
                
                ## Delete Snapmirror on new cluster from old cluster
                Remove-NcSnapmirror -Destination $snapmirror.DestinationLocation -Source $snapmirror.SourceLocation -Controller $newCluster -Confirm:$false
                
                ## Release Snapmirror on old cluster to new cluster
                Invoke-NcSnapmirrorRelease -Source $snapmirror.SourceLocation -Destination $snapmirror.DestinationLocation -Controller $oldCluster -Confirm:$false                             

                # Build Snapmirror to new cluster from source cluster and cleanup
                ## Create new snapmirror
                New-NcSnapmirror -Destination $snapmirror.DestinationLocation -Source $oldsnapmirror.SourceLocation -Schedule $oldsnapmirror.Schedule -Policy $oldsnapmirror.Policy -Controller $newCluster -Type $oldsnapmirror.PolicyType

                ## Resync new snapmirror
                Invoke-NcSnapmirrorResync -Destination $snapmirror.DestinationLocation -Source $oldsnapmirror.SourceLocation -Controller $newCluster -Confirm:$false
                                
                ## Break Snapmirror on old cluster from source cluster
                Invoke-NcSnapmirrorRelease -Destination $oldsnapmirror.DestinationLocation -Source $oldsnapmirror.SourceLocation -Controller $ClusterTable[$peerCluster] -Confirm:$false
                
                ## Delete Snapmirror on old cluster from source cluster
                Remove-NcSnapmirror -Destination $oldsnapmirror.DestinationLocation -Source $oldsnapmirror.SourceLocation -Controller $oldCluster -Confirm:$false

                ## Add Volume to calculated blacklist
                $calculatedBlacklist += $_.Name

                Start-Sleep -Seconds 15
            }
        }
    }
}

#endregion
````