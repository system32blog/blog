+++
title = "PowerShell based PRTG Sensor Discovery"
date = "2021-11-08"
description = "Use PowerShell to discover sensors on systems."
featured = true
tags = [
    "Robin Beismann"
]
categories = [
    "PowerShell"
    "PRTG"
    "Discovery"
]
series = [""]
aliases = [""]
thumbnail = "post/PRTGSensorDiscovery/logo.png"
+++
This article shows a script I made to enhance PRTGs own sensor discovery. The script can be run as scheduled tasks and will use the PrtgApi to find any kind of sensors that you wish to monitor on your systems (such as Windows Services, NetApp Volumes, Cisco UCS Disks and so on)
<!--more-->
````Disclaimer: This content and scripts are provided free of charge and I do not take any responsability for them nor any harm they may cause, it is up to you to review and test them properly before deploying them anywhere.````

# Introduction
Many of you probably already heard about PRTG or are already using it to monitor your network. PRTG has a great builtin sensor discovery that will add sensors for almost everything you'd want to know about on your server.
One downside of this is the fact, that everytime you run this discovery, it adds all sensors once again as it does not check if this sensor is already there.

To workaround this, I've build a PowerShell script that you can run as scheduled job to automatically discover any kind of discoverable sensor.

# How does it work?
The script uses PRTGs inbuilt API and the PowerShell Module "PrtgAPI" (https://github.com/lordmilko/PrtgAPI) to invoke a sensor discovery for a specific sensor on a device or a group of devices.
After that it loops through the existing sensors to detect if there are any that are not explicitly excluded or already existent. 

The script has the following features and attributes per sensor type:
- RawType: The PRTG Name of a sensor, you can find all your PRTG Instance is aware off using the cmdlet ```Get-SensorType```.
- SensorPrefix: The prefix that is used by the sensor when you add them using the PRTG API.
- Group: The PRTG Device Group which the script shall run for this sensor type. If multiple groups with the same name exist (e.g. under different probes), it will run for all of them.
- NameFilter: A wildcard aware filter of devices the script shall run for. Do all your Windows Servers starts with "WSRV"? Great! Enter "WSRV*" into the NameFilter and you'll avoid unnecessary discoveries on not applicable devices. If not, just let the asterix in.
- AttributeName: The attribute name out of which the script shall extract the discovered sensors. This differs per sensor. You can find the correct property by running ```New-SensorParameters``` on a device.
- ExclusionList: An array of occurences to ignore, in the existing sensor types below, you can find some examples. This exclusion list also supports wildcards.
- MaxSensors: A threshhold of how many sensors to discover per device. Exceeding this limit will fire an error message.
- DiscoveryInterval: A limitation of how often this Sensor Type discovery shall run, meaning that even if the script is executed multiple times in a row, if the discovery interval is not yet due again, it will skip this sensor type. An example of this would be disk sensors, discovering them all few days will be more than enough. Windows services however might pop up more often and therefor require a more frequent discovery. The last discovery is saved in the current user registry for each device, if you run the script on another device or under an other user context, it will start fresh.
- NameExtractionSB: An additional scriptblock that's being run against the object ```t``` to extract the individual element name out of a device. This might be required for devices that return inconsistent or badly formatted informations around the actual device name. The ```Cisco UCS Disks``` Sensor Type shows an example of it.

# How to use it
To use the script, you will need to populate the following environment variables before you execute the script:
````PowerShell
# Required
## PRTG server url
$env:PRTGUrl = "https://prtg.internaldomain.com"
## PRTG Username
$env:PRTGUsername = "svc-discovery"
## PRTG Password
$env:PRTGPassword = "bacon"

# Optional
## A teams webhook to sent a summary of discovered sensors to (if any)
$env:TeamsURL = "https://yourtenant.webhook.office.com/webhookb2/.."
## A teams webhook to sent a summary of discovered sensors to (if any) while using VSCode to work on the script
$env:TeamsStagingURL = "https://yourtenant.webhook.office.com/webhookb2/.."
````

Depending on the number of items you got in the specified groups, it will take some time (minutes to hours) to discover the Sensor Types defined below. 

## Predefined Sensor Types
There is already a bunch of sensor types defined in the script, feel free to either keep them or delete them out of the hashtable. Those are the ones I've developed the script for and are actively used in my work environment.
- Cisco UCS Disks: Discover disk of a Cisco UCSC and Cisco UCSB Series using their CIMC Interface
- NetApp System Health: Discover NetApp System Health Sensors for each Controller
- NetApp IO: Discover NetApp IO Sensors for each Controller
- NetApp Aggregates: Discover NetApp Aggregates Sensors for all clusters
- NetApp Lifs: Discover NetApp Lif Sensors for each Controller
- NetApp Physical Disk: Discover NetApp Disk Sensors for each physical disk
- NetApp Interfaces: Discover NetApp Physical Interface Sensors for each 
- NetApp Volumes: Discover NetApp Volume Sensors for each Cluster
- NetApp SnapMirrors: Discover NetApp Snapmirror/SnapVault Relationship Sensors for each Cluster
- Disk Space: Discover any available SNMP Disk Space Sensor (Windows/Linux) for each device
- Windows Services: Discover any running Windows Service via SNMP for each device. This Sensor Type already holds a long list of exclusions of builtin Windows Services in English and German OS. The reference lists are from Server 2019 Installations.

# The script
````PowerShell
#region Variables
# Sensor Types
$SensorTypes = [ordered]@{     
    "Cisco UCS Disks" = @{
        RawType = 'snmpciscoucsphysicaldisk'
        SensorPrefix = "Physical Disk"
        Group = "Management"
        NameFilter = "*CIMC" 
        AttributeName = "serial__check"
        ExclusionList = @(
            ""
        )        
        MaxSensors = 30
        NameExtractionSB = [scriptblock]{
            # Extract the pd-* Disk ID instead, otherwise we can't identify the disk slot
            $t.Properties[2].Split("/")[-1]
        }
        DiscoveryInterval = 168
    }
    "NetApp System Health" = @{
        RawType = 'netappcdotsystem'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp System Health"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "cdotnodename__check"
        ExclusionList = @(
            ""
        )
        MaxSensors = 10
        DiscoveryInterval = 168
    }   
    "NetApp IO" = @{
        RawType = 'netappcdotio'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp I/O"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "cdotnodename__check"
        ExclusionList = @(
            ""
        )
        MaxSensors = 10
        DiscoveryInterval = 168
    }   
    "NetApp Aggregate" = @{
        RawType = 'netappcdotaggr'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp Aggregate"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "netappcdotaggrlist__check"
        ExclusionList = @(
            "*root*"
        )
        MaxSensors = 100
        DiscoveryInterval = 168
    } 
    "NetApp Lif" = @{
        RawType = 'netappcdotlif'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp Lif"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "netappcdotliflist__check"
        ExclusionList = @(
            ""
        )
        MaxSensors = 50
        DiscoveryInterval = 168
    }       
    "NetApp Physical Disk" = @{
        RawType = 'netappcdotdisk'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp Physical Disk"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "netappcdotdisklist__check"
        ExclusionList = @(
            ""
        )
        MaxSensors = 200
        DiscoveryInterval = 168
    }   
    "NetApp Interfaces" = @{
        RawType = 'snmpnetappnetworkinterface'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "Network Interface:"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "interface__check"
        ExclusionList = @(
            ""
        )
        MaxSensors = 50
        DiscoveryInterval = 168
    }        
    "NetApp Volumes" = @{
        RawType = 'netappcdotvolume'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp Volume"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "netappcdotvolumelist__check"
        ExclusionList = @(
            "*root*",
            '*.snapshot*',
            'sdw_*',
            '*/sdw_*',
            '*:vol0',
            '*:sdw_*'
        )
        MaxSensors = 25
        
    }    
    "NetApp SnapMirror" = @{
        RawType = 'netappcdotsnapmirror'
        QueryParameters = @{ 
                                "defaultlogin_" = 1; 
                                "user_" = $null; 
                                "password_" = $null; 
                                "transporttype_" = 1; 
                                "timeout_" = 60; 
                                "port_" = 443 
                            }
        SensorPrefix = "NetApp SnapMirror"
        Group = "Storage"
        NameFilter = "*" 
        AttributeName = "cdotsnapmirrorlist__check"
        MaxSensors = 20
        ExclusionList = @(
            "*root*",
            '*.snapshot*',
            'sdw_*',
            '*/sdw_*',
            '*:vol0',
            '*:sdw_*'
        )        
    }  
    "Disk Space" = @{
        RawType = 'snmpdiskfree'
        QueryParameters =   @{ 
                            }
        SensorPrefix = "Disk Free:"
        Group = "Server"
        NameFilter = "*" 
        AttributeName = "disk__check"
        ExclusionList = @(
            "/run/user/*"
        )
        
    }
    "Windows Services" = @{
        RawType = 'snmpservice'
        QueryParameters =   @{ 
                            }
        SensorPrefix = "Service"
        Group = "Server"
        NameFilter = "*" 
        AttributeName = "service__check"
        MaxSensors = 15
        ExclusionList = @(
            "Power",
            "Server",
            "Themes",
            "SysMain",
            "Netlogon",
            "IP Helper",
            "DNS Client",
            "winlogbeat",
            "DHCP Client",
            "Time Broker",
            "Workstation",
            "SNMP Service",
            "User Manager",
            "Windows Time",
            "CoreMessaging",
            "Plug and Play",
            "SMS Agent Host",
            "Task Scheduler",
            "Message Queuing",
            "Storage Service",
            "CNG Key Isolation",
            "COM+ Event System",
            "COM+-Systemanwendung",
            "IIS Admin Service",
            "Windows Event Log",
            "IPsec Policy Agent",
            "Volume Shadow Copy",
            "Group Policy Client",
            "Network Connections",
            "RPC Endpoint Mapper",
            "Web Account Manager",
            "Apex One NT Listener",
            "Data Sharing Service",
            "Network List Service",
            "System Events Broker",
            "User Profile Service",
            "Base Filtering Engine",
            "Local Session Manager",
            "TCP/IP NetBIOS Helper",
            "Cryptographic Services",
            "Apex One NT WSC Service",
            "Application Information",
            "Certificate Propagation",
            "Diagnostic Service Host",
            "Remote Desktop Services",
            "Net.Tcp Listener Adapter",
            "Shell Hardware Detection",
            "State Repository Service",
            "Apex One NT RealTime Scan",
            "Diagnostic Policy Service",
            "Hyper-V Heartbeat Service",
            "Net.Msmq Listener Adapter",
            "Net.Pipe Listener Adapter",
            "Network Connection Broker",
            "Security Accounts Manager",
            "Windows Defender Firewall",
            "Network Location Awareness",
            "Windows Connection Manager",
            "Windows Font Cache Service",
            "Remote Procedure Call (RPC)",
            "Update Orchestrator Service",
            "User Access Logging Service",
            "DCOM Server Process Launcher",
            "Net.Tcp Port Sharing Service",
            "Remote Desktop Configuration",
            "Windows Update Medic Service",
            "Hyper-V Data Exchange Service",
            "Hyper-V Guest Shutdown Service",
            "Application Host Helper Service",
            "Network Store Interface Service",
            "Windows License Manager Service",
            "Distributed Link Tracking Client",
            "Remote Access Connection Manager",
            "CrowdStrike Falcon Sensor Service",
            "System Event Notification Service",
            "Connected Devices Platform Service",
            "Windows Management Instrumentation",
            "Windows Process Activation Service",
            "Distributed Transaction Coordinator",
            "IKE and AuthIP IPsec Keying Modules",
            "Hyper-V Volume Shadow Copy Requestor",
            "Background Tasks Infrastructure Service",
            "Program Compatibility Assistant Service",
            "Connected User Experiences and Telemetry",
            "Secure Socket Tunneling Protocol Service",
            "WinHTTP Web Proxy Auto-Discovery Service",
            "Windows Push Notifications System Service",
            "Windows Remote Management (WS-Management)",
            "Touch Keyboard and Handwriting Panel Service",
            "Hyper-V Remote Desktop Virtualization Service",
            "Connected Devices Platform User Service_*",
            "Windows Push Notifications User Service_*",
            "Remote Desktop Services UserMode Port Redirector",
            "Windows Update",
            "Windows Installer",
            "Network Setup Service",
            "Diagnostic System Host",
            "Microsoft Policy Platform Processor",
            "Microsoft Policy Platform Local Authority",
            "Print Spooler",
            "Windows Search",
            "Computer Browser",
            "Windows Modules Installer",
            "Extensible Authentication Protocol",
            "Microsoft Software Shadow Copy Provider",
            "CDPUserSvc_*",
            "Geolocation Service",
            "VMware *",
            "SSDP Discovery",
            "Virtual Disk",
            "Windows Firewall",
            "Tile Data model server",
            "Smart Card Device Enumeration Service",
            "Background Intelligent Transfer Service",
            "Windows Driver Foundation - User-mode Driver Framework",
            "Diagnostics Tracking Service",
            "Microsoft Online Services Sign-in Assistant",
            "Messaging",
            "Experience",
            "Diagnostics Tracking Service",
            "Performance Logs & Alerts",
            "Intersite Messaging",
            "dmwappushsvc",
            "Superfetch",
            "Credential Manager",
            "Windows Audio",
            "Application Experience",
            "Windows Internal Database VSS Writer",
            "Application Management",
            "WMI Performance Adapter",
            "Software Protection",
            "Secondary Logon",
            "Device Association Service",
            "Windows Image Acquisition (WIA)",
            "AppX Deployment Service (AppXSVC)",
            "Hyper-V Time Synchronization Service",
            "KDC Proxy Server service (KPS)",
            "Remote Registry",
            "Password Export Server Service",
            "Portable Device Enumerator Service",
            "Adobe Acrobat*",
            "Sync Host_*",
            "Encrypting File System (EFS)",
            "SAPSetup Automatic Workstation Update Service",
            "Telephony",
            "GDMA",
            "Windows Insider Service",
            "Windows Error Reporting Service",
            "AVCTP service",
            "Windows Internal Database*",
            "Microsoft Office Click-to-Run Service",
            "Windows Audio Endpoint builder",
            "Office Software Protection Platform",
            "Designs",
            "DNS-Client",
            "DHCP-Client",
            "Plug & Play",
            "SNMP-Dienst",
            "Anmeldedienst",
            "IP-Hilfsdienst",
            "Aufgabenplanung",
            "Windows Audio*",
            "Device Install Service",
            "Client for NFS",
            "Data Deduplication Volume Shadow Copy Service",
            "WMI Performmance Adapter",
            "Microsoft Account Sign-in Assistant",
            "SNMP Trap",
            "Function Discovery Resource Publication",
            "BITS",
            "W32Time",
            "Device Setup Manager",
            "Windows Security Service",
            "SQL Server CEIP service*",
            "Server",
            "Designs",
            "DNS-Client",
            "winlogbeat",
            "DHCP-Client",
            "Plug \u0026 Play",
            "SNMP-Dienst",
            "Anmeldedienst",
            "IP-Hilfsdienst",
            "SMS Agent Host",
            "Aufgabenplanung",
            "Stromversorgung",
            "Basisfiltermodul",
            "Windows-Firewall",
            "Windows-Zeitgeber",
            "Druckwarteschlange",
            "SQL Server-Browser",
            "COM+-Ereignissystem",
            "Kryptografiedienste",
            "Volumeschattenkopie",
            "Benutzerprofildienst",
            "Netzwerklistendienst",
            "Netzwerkverbindungen",
            "Remotedesktopdienste",
            "Zertifikatverteilung",
            "Arbeitsstationsdienst",
            "RPC-Endpunktzuordnung",
            "Systemereignissebroker",
            "Anwendungsinformationen",
            "Apex One NT WSC Service",
            "CNG-Schlüsselisolation",
            "IPsec-Richtlinien-Agent",
            "DCOM-Server-Prozessstart",
            "Gruppenrichtlinienclient",
            "Lokaler Sitzungs-Manager",
            "Sicherheitskonto-Manager",
            "Apex One NT RealTime Scan",
            "Diagnoserichtliniendienst",
            "Windows-Ereignisprotokoll",
            "Remoteprozeduraufruf (RPC)",
            "TCP/IP-NetBIOS-Hilfsdienst",
            "VMware SVGA Helper Service",
            "Windows-Verbindungs-Manager",
            "Diagnostics Tracking Service",
            "Hyper-V-Datenaustauschdienst",
            "Konfiguration für Remotedesktops",
            "Windows-Verwaltungsinstrumentation",
            "Distributed Transaction Coordinator",
            "Netzwerkspeicher-Schnittstellendienst",
            "Windows-Dienst für Schriftartencache",
            "Hyper-V-Volumeschattenkopie-Anforderer",
            "WinHTTP-Web Proxy Auto-Discovery-Dienst",
            "Hyper-V-Dienst für Zeitsynchronisierung",
            "Windows-Remoteverwaltung (WS-Verwaltung)",
            "Hyper-V-Dienst zum Herunterfahren des Gasts",
            "Hyper-V-Remotedesktopvirtualisierungsdienst",
            "Infrastrukturdienst für Hintergrundaufgaben",
            "Intelligenter Hintergrundübertragungsdienst",
            "Benachrichtigungsdienst für Systemereignisse",
            "Dienst für die Benutzerzugriffsprotokollierung",
            "Überwachung verteilter Verknüpfungen (Client)",
            "IKE- und AuthIP IPsec-Schlüsselerstellungsmodule",
            "Anschlussumleitung für Remotedesktopdienst im Benutzermodus",
            "SMS_SITE_SQL_BACKUP",
            "Data ONTAP VSS Hardware Provider",
            "Microsoft Storage Spaces SMP",
            "App Readiness",
            "CNG-Schlüsselisolation",
            "Hyper-V-Taktdienst",
            "Anschlussumleitung für Remotedesktopdienst im Benutzermodus",
            "NLA (Network Location Awareness)",
            "Konfiguration für Remotedesktops",
            "Windows-Dienst für Schriftartencache",
            "Hyper-V-Dienst für Zeitsynchronisierung",
            "Infrastrukturdienst für Hintergrundaufgaben",
            "Intelligenter Hintergrundübertragungsdienst",
            "Benachrichtigungsdienst für Systemereignisse",
            "Dienst für die Benutzerzugriffsprotokollierung",
            "Überwachung verteilter Verknüpfungen (Client)",
            "IKE- und AuthIP IPsec-Schlüsselerstellungsmodule",
            "Function Discovery Provider Host",
            "Intel(R) PROSet Monitoring Service",
            "KtmRm for Distributed Transaction Coordinator",
            "Network Virtualization Service",
            "Application Identity",
            "Contact Data_*",
            "User Data Access_*",
            "User Data Storage_*",
            "Microsoft Passport*",
            "Client License Service (ClipSVC)",
            "Capability Access Manager Service",
            "Diagnosesystemhost",
            "Microsoft Edge Update Service",
            "Delivery Optimization",
            "Optimize drives",
            "Data Deduplication Service",
            "Clipboard User Service_*",
            "Netzwerkeinrichtungsdienst",
            "Benutzerdienst für die Plattform für verbundene Geräte_*",
            "PrintWorkflow_*",
            "Windows-Pushbenachrichtigungs-Benutzerdienst_*",
            "Contact Data_*",
            "Windows-Lizenz-Manager-Dienst",
            "Verschlüsselndes Dateisystem (EFS)",
            "Übermittlungsoptimierung",
            "Shellhardwareerkennung",
            "Datenfreigabedienst",
            "Bluetooth-Unterstützungsdienst",
            "BITS Compact Server",
            "AVCTP-Dienst",
            "Microsoft Key Distribution Service",
            "CNG-Schlüsselisolation",
            "Konfiguration für Remotedesktops",
            "Windows-Dienst für Schriftartencache",
            "Hyper-V-Dienst für Zeitsynchronisierung",
            "Infrastrukturdienst für Hintergrundaufgaben",
            "Intelligenter Hintergrundübertragungsdienst",
            "Benachrichtigungsdienst für Systemereignisse",
            "Dienst für die Benutzerzugriffsprotokollierung",
            "Überwachung verteilter Verknüpfungen (Client)",
            "IKE- und AuthIP IPsec-Schlüsselerstellungsmodule",
            "Anschlussumleitung für Remotedesktopdienst im Benutzermodus",
            "Anwendungshost-Hilfsdienst",
            "Anmeldeinformationsverwaltung",
            "Windows-Prozessaktivierungsdienst",
            "Windows Store Service (WSService)",
            "Zeitbroker",
            "SSTP-Dienst",
            "Windows-Audio",
            "Speicherdienst",
            "Benutzer-Manager",
            "StateRepository-Dienst",
            "Netzwerkverbindungsbroker",
            "RAS-Verbindungsverwaltung",
            "Plattformdienst für verbundene Geräte",
            "Programmkompatibilitäts-Assistent-Dienst",
            "Windows-Pushbenachrichtigungssystemdienst",
            "Dienst für Bildschirmtastatur und Schreibbereich",
            "Benutzererfahrungen und Telemetrie im verbundenen Modus",
            "Windows Biometric Service",
            "COM+ System Application",
            "Update Orchestrator Service for Windows Update",
            "Windows-Audio-Endpunkterstellung",
            "Microsoft-Softwareschattenkopie-Anbieter",
            "Tracing Service for Search in Exchange",
            "Microsoft Edge Update Service (edgeupdate)",
            "Problem Reports and Solutions Control Panel Support",
			"Remoteregistrierung",
			"Smartcard-Geräteaufzählungsdienst",
            "Update Orchestrator Service for Windows Update",
            "Veeam Agent for Microsoft Windows",
            "AzureAttestService"
            "CsInstallService",
            "ConfigMgr Task Sequence Agent",
            "Diagnosediensthost",
            "Kontaktdaten_*",
            "Benutzerdatenzugriff_*",
            "Benutzerdatenspeicher _*",
            "Radio Management Service",
            "Microsoft Edge-Update-Dienst (edgeupdate)",
            "wuauserv",
            "Tracing Service for Search in Exchange",
            "Windows Defender Antivirus Network Inspection Service",
            "Windows Defender Antivirus Service",
            "Wired AutoConfig",
            "Microsoft-Softwareschattenkopie-Anbieter",
            "Diagnosediensthost",
            "Trend Micro Unauthorized Change Prevention Service",
			"Anwendungserfahrung",
			"Anwendungsverwaltung",
			"Funktionssuchanbieter-Host",
			"Display Policy Service",
			"Device Management Wireless Application Protocol (WAP) Push message Routing Service",
			"WSUS Certificate Server",
            "File Server Storage Reports Manager"
        )
        
    }
}
#endregion

#region Initialization
# Import PRTG Module
if(!(Get-Module -Name "PrtgApi" -ErrorAction SilentlyContinue)){
    Import-Module "$env:workspace\Modules\PrtgApi"
}
# Teams Webhook URL (depending on if it is run in VSCode or as job)
if($env:TERM_PROGRAM -eq 'vscode' -and $env:TeamsStagingURL) {
    $TeamsURL = $env:TeamsStagingURL
}else{
    $TeamsURL = $env:TeamsURL
}
#endregion

#region Functions
function Send-TeamsMessage($facts,$Theme="Healthy"){
    $connectorUri = $TeamsURL
    $Summary = "PRTG Sensor Discovery $(if($env:JOB_NAME){ "(Jenkins Job '$env:JOB_NAME')" } )"
    $body = [ordered]@{
        "@type" = "MessageCard"
        "summary" = $Summary
        "themeColor" = $(
            if($Theme.ToLower().Contains("error")){
                "#eb4034"
            }else{
                "#a6a6a6"
            }
        )
        "sections" = @(
            @{
                activityTitle = $Summary
                facts = $facts          
            }
        )
    }
     
    Invoke-RestMethod -Method post -ContentType 'Application/Json' -Body ($body | ConvertTo-Json -Depth 5) -Uri $connectorUri
}
#endregion

#region Connection and Credentials
try{
    # Check if we're connected
    $null = Get-PrtgStatus
}catch{
    # No, let's connect.
    
    # Get Credentials
    $PRTGUsername = $env:PRTGUsername
    $PRTGPassword = $env:PRTGPassword
    [securestring]$secStringPassword = ConvertTo-SecureString $PRTGPassword -AsPlainText -Force
    [pscredential]$creds = New-Object System.Management.Automation.PSCredential ($PRTGUsername, $secStringPassword)

    # Connect
    $null = Connect-PrtgServer -Server $env:PRTGUrl -Credential $creds -Force
}
#endregion

#region Processing
$addedSensors = @()
$hasError = @()
$RegistryBasePath = "Registry::HKEY_CURRENT_USER\SOFTWARE\PRTGDiscovery"
$RegistryLastDiscovery = "$RegistryBasePath\LastScan"

try{
    $servicesAdded = @()
    $SensorTypes.GetEnumerator() | ForEach-Object {
        try{
            $SensorType = $_
            $ignoredServices = $_.Value.ExclusionList.ToLower()
            
            # Get Services for the device
            $services = Get-Device -Group $SensorType.Value.Group | Where-Object { $_.Name -like $SensorType.Value.NameFilter } | ForEach-Object {
                $device = $_
                $LastDiscoveryInterval = 4

                # Check if the registry hive is there
                if(!(Test-Path -Path $RegistryLastDiscovery -ErrorAction SilentlyContinue)){
                    Write-Host -Object "Creating registry path `"$RegistryLastDiscovery`".."
                    $null = New-Item -ItemType Directory -Path $RegistryLastDiscovery -Force
                }
                $stateName = "$($SensorType.Name) - $($device.Name)"

                # Check if our check is due or if we skip that one
                if(
                    (Get-ItemProperty -Path $RegistryLastDiscovery).$stateName -and
                    ($LastState = Get-ItemPropertyValue -Path $RegistryLastDiscovery -Name $stateName) -and
                    ($LastStateDate = [datetime]::ParseExact($LastState,'yyyyMMddHHmmss',$null)) -and
                    ( (Get-Date) -lt $LastStateDate.AddHours($LastDiscoveryInterval) )                
                ){
                    Write-Host -Object "[$($device.Name) - $($SensorType.Name)] Skipping as last discovery was `"$LastStateDate`" and it is due at `"$($LastStateDate.AddHours($LastDiscoveryThreshold))`".."
                    return;
                }                              

                Write-Host -Object "[$($device.Name) - $($SensorType.Name)] Searching for sensors.."
                try{
                    # Null our previous vars out
                    $sensormeta = $null
                    
                    # Build our parameters dynamically for Splatting
                    $params = @{
                        RawType = $SensorType.Value.RawType
                        ErrorAction = 'Stop'
                    }
                    if($SensorType.Value.QueryParameters){
                        $params.QueryParameters = $SensorType.Value.QueryParameters
                    }

                    # Query the device for SNMP Sensors based on our Template
                    Set-ItemProperty -Path $RegistryLastDiscovery -Name $stateName -Value (Get-Date -Format "yyyyMMddHHmmss")
                    $sensormeta = Get-Device -Id $_.Id | New-SensorParameters @params
                    Write-Host -Object "[$($device.Name) - $($SensorType.Name)] Finished searching for sensors.."
                }catch{
                    Write-Verbose -Message "[$($device.Name) - $($SensorType.Name)] Failed to get SNMP sensors: $_"
                }

                # Filter Services for actual application services
                $servicesToMonitor = @()
                if(
                    $sensormeta -and 
                    $sensormeta.Targets -and
                    ($attr = $SensorType.Value.AttributeName) -and
                    ($sTargets = $sensormeta.Targets.$attr)
                ){
                    # Loop through the sensors
                    $sTargets | Foreach-Object {                        
                        if(!$SensorType.Value.NameExtractionSB){
                            $serviceName = $_.Name.Replace("\\","\").ToLower()
                        }else{
                            # Cast "t" as var for the device to be used in the scriptblock
                            $t = $_
                            
                            # Invoke the scriptblock
                            $serviceName = $SensorType.Value.NameExtractionSB.Invoke()

                            # Overwrite it in the hashtable so we can pass the extracted name
                            $_ | Add-Member -Type NoteProperty -Name "Name" -Value $serviceName -Force
                        }

                        # Get service name with device name prefix so we can exclude based on specific devices
                        $serviceNameWithDeviceName = "$($device.Name)\$($serviceName)".Replace("\\","\").ToLower()

                        # Verify if the sensors are not excluded
                        if(!($ignoredServices | Where-Object {
                                ($serviceName -like $_) -or
                                ($serviceNameWithDeviceName -like $_)
                            }
                           )
                        ){
                            $servicesToMonitor += $_
                        }
                    }
                }else{
                    # This device has no sensors based on our Sensor Type
                    Write-Host -ForegroundColor Yellow -Object "[$($device.Name) - $($SensorType.Name)] Has no SNMP Service sensors."
                }

                # Build the return object 
                [PSCustomObject]@{
                    DeviceID = $device.Id
                    DeviceParentID = $device.ParentId
                    DeviceName = $device.Name
                    Services = $servicesToMonitor
                }
            }
            
            # Look through all detected services and add the sensors
            $services | Where-Object { $_.Services } | ForEach-Object {
                # Get the devices
                $device = Get-Device -Id $_.DeviceId

                # Get the devices' sensors
                $sensors = $device | Get-Sensor

                # Save our current object
                $deviceObj = $_
                
                $servicesToAdd = @()
                # Loop through the services
                $deviceObj.Services | ForEach-Object {
                    # Get the new prefix
                    $sensorPrefix = $SensorType.Value.SensorPrefix
                    $normalizedName = $_.Name.Replace("  "," ").Replace("\\","\")
                    # Build the new sensor name and normalize it so we don't accidently create two sensors just because one messed up at creating
                    $newSensorname = "$sensorPrefix $normalizedName"

                    # Check if the sensor already exists
                    if(
                        $sensors.Name -and
                        ($newSensorname -in $sensors.Name.Replace("  "," "))
                    ){
                        Write-Host -ForegroundColor Green -Object "[$($deviceObj.DeviceName)]: $newSensorname exists."

                    # No it doesn't -> create it
                    }else{
                        Write-Host -ForegroundColor Yellow -Object "[$($deviceObj.DeviceName)]: $newSensorname adding to process table.."
                        $params = @{
                            RawType = $SensorType.Value.RawType
                            ErrorAction = 'Stop'
                            Target = $_
                        }
                        
                        # Check if we got additional QueryParameters and add them to our Splatting
                        if($SensorType.Value.QueryParameters){
                            $params.QueryParameters = $SensorType.Value.QueryParameters
                            # Timeout requires an extra switch, if it is set, set it here also
                            if($SensorType.Value.QueryParameters.'timeout_'){
                                $params.Timeout = $SensorType.Value.QueryParameters.'timeout_'
                            }
                        }
                        try{
                            # Create SensorParameter Object based on device
                            $sParam = $device | New-SensorParameters @params

                            # Dynamically add the timeout once more
                            if($params.Timeout){
                                # Add Timeout Switch if set - there seems to be a bug in the module so it does not inherit the one we set earlier, this would generate errors for NetApp cDOT Sensors 
                                if(
                                    $SensorType.Value.QueryParameters -and
                                    $SensorType.Value.QueryParameters.'timeout_'
                                ){
                                    # We need to unlock the object before adding custom parameters to it
                                    $sParam.Unlock()
                                    # Set the timeout
                                    $sParam.timeout = $SensorType.Value.QueryParameters.'timeout_'
                                    # Lock it again
                                    $sParam.Lock()
                                }
                            }

                            # Add the actual sensor to our process list
                            $servicesToAdd += @{
                                SensorParams = $sParam
                                SensorType = $SensorType.Name
                                SensorDeviceName = $device.Name
                                SensorFriendlyName = "[$($device.Name)] $normalizedName"
                            }
                            Write-Host -ForegroundColor Yellow -Object "[$($deviceObj.DeviceName)]: $newSensorname added to process table."
                        }catch{
                            Write-Host -ForegroundColor Red -Object "[$($deviceObj.DeviceName) - $($SensorType.Name)]: $newSensorname failed to create: $_"
                        }
                    }        
                }

                # Process new sensors
                if($servicesToAdd.Count -gt 0){
                    # Check if we have to add too many sensors
                    $MaxSensors = 10
                    if($SensorType.Value.MaxSensors){
                        $MaxSensors = $SensorType.Value.MaxSensors
                    }

                    if($servicesToAdd.Count -gt $MaxSensors){
                        $lError = "[$($deviceObj.DeviceName)]: has over $MaxSensors Sensors to add, please review - skipping for now."
                        $hasError += $lError
                        Write-Host -ForegroundColor Red -Object $lError
                    }else{
                        Write-Host -ForegroundColor Yellow -Object "[$($deviceObj.DeviceName)]: Processing new Sensors.."
                        $servicesToAdd.GetEnumerator() | ForEach-Object {
                            Write-Host -ForegroundColor Yellow -Object "[$($deviceObj.DeviceName)]: adding $($_.SensorFriendlyName).."
                            try{
                                $null = $_.SensorParams | Add-Sensor -ErrorAction Stop
                                $addedSensors += @{
                                    name = $_.SensorType
                                    value = $_.SensorFriendlyName
                                }
                                $servicesAdded += $_
                            }catch{
                                $lError = "[$($deviceObj.DeviceName)]: Failed adding $($_.SensorFriendlyName): $($_.InvocationInfo.ScriptLineNumber) - $($_.Exception.Message)"
                                Write-Host -ForegroundColor Red -Object $lError
                                $hasError += $lError
                            }
                        }
                    }
                }
            }
        }catch{
            $lError = "Failed at Sensor Type: $($SensorType.Name), Error in line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
            Write-Host -ForegroundColor Red -Object $lError
            $hasError += $lError
        }    
    }
}catch{
    $lError = "Failed to discover! Error in line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Host -ForegroundColor Red -Object $lError
    $hasError += $lError
}finally{
    if(
        $addedSensors -and
        $addedSensors.Count -gt 0
    ){
        Write-Host -ForegroundColor Green -Object "Summary:"
        $servicesAdded.GetEnumerator() | ForEach-Object {
            Write-Host -ForegroundColor Green -Object "[$($_.SensorDeviceName)]: added $($_.SensorFriendlyName).."
        }
        if($TeamsURL){
            Send-TeamsMessage -Facts $addedSensors
        }
    }
    
    # Cleanup orphaned Windows Service sensors, this happens from time to time during service discovery unfortunately
    # Those sensors can be identified by their Name "Service " and their type of snmpservice - however they do not work as they don't get an OID
    try{
        $cleanup = Get-Sensor -Name "Service " | Where-Object { $_.Type.StringValue -eq "snmpservice" -and $_.Name -eq "Service " }
        if($cleanup -and $cleanup.Count -gt 0){
            Write-Host -ForegroundColor Yellow -Object "Cleaning up orphaned SNMP Service sensors.."
            $cleanup | ForEach-Object {
                Write-Host -ForegroundColor Yellow -Object "[$($_.Device)]: Cleaning up orphaned SNMP Service sensors.."
                $_ | Remove-Object -Confirm:$false -Force
            } 
        }        
    }catch{
        Write-Host -ForegroundColor Yellow -Object "Error at cleaning up orphaned SNMP Service sensors! Error: $_"
    }

    if($hasError.Count -gt 0){
        Write-Host -ForegroundColor Red -Object "Errors detected, please review the following lines!"
        $hasError | ForEach-Object {
            Write-Host -ForegroundColor Red -Object $_
        }
        exit 1;
    }
}
#endregion
````