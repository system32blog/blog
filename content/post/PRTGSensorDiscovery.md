+++
title = "PowerShell based PRTG Sensor Discovery"
date = "2021-11-08"
description = "Use PowerShell to discover sensors on systems."
featured = true
tags = [
    "Robin Beismann"
]
categories = [
    "PowerShell",
    "PRTG",
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

The script is also able to send you a summary of what it discovered and created directly into your Teams Channel (via an Webhook Connector).

# How does it work?
The script uses PRTGs inbuilt API and the PowerShell Module "PrtgApi" (https://github.com/lordmilko/PrtgApi) to invoke a sensor discovery for a specific sensor on a device or a group of devices.
After that it loops through the existing sensors to detect if there are any that are not explicitly excluded or already existent. 

The script has the following features and attributes per sensor type:
- RawType: The PRTG Name of a sensor, you can find all your PRTG Instance is aware off using the cmdlet ```Get-SensorType```.
- SensorPrefix: The prefix that is used by the sensor when you add them using the PRTG API.
- Group: The PRTG Device Group which the script shall run for this sensor type. If multiple groups with the same name exist (e.g. under different probes), it will run for all of them.
- NameFilter: A wildcard aware filter of devices the script shall run for. Do all your Windows Servers starts with "WSRV"? Great! Enter "WSRV*" into the NameFilter and you'll avoid unnecessary discoveries on not applicable devices. If not, just let the asterix in.
- AttributeName: The attribute name out of which the script shall extract the discovered sensors. This differs per sensor. You can find the correct property by running ```New-SensorParameters``` on a device.
- ExclusionList: An array of occurences to ignore, in the existing sensor types below, you can find some examples. This exclusion list also supports wildcards.
- MaxSensors: A threshold of how many sensors to discover per device. Exceeding this limit will fire an error message.
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
You can find the script here: https://github.com/system32blog/blog/blob/master/static/post/PRTGSensorDiscovery/Invoke-PRTGSensorDiscovery.ps1