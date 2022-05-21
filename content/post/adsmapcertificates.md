+++
title = "AD Authentication Issues 2022-05 May Patches / Mapping Certificates to AD Objects"
date = "2022-05-20"
description = "Use PowerShell to map existing enrolled certificates to User or Computer Accounts for NPS/RAS Authentication"
featured = true
tags = [
    "Robin Beismann"
]
categories = [
    "PowerShell",
    "ADCS",
    "ADDS",
    "NPS",
    "RAS"
]
series = [""]
aliases = [""]
thumbnail = "post/ADCSMapCertificates/ad.png"
+++
This article shows how to use PowerShell to address the issues that come with the new StrongCertificateBindingEnforcement security feature of Active Directory by mapping the existing/already enrolled certificates to their respective AD account (whether computer or user).
<!--more-->
````Disclaimer: This content and scripts are provided free of charge and I do not take any responsability for them nor any harm they may cause, it is up to you to review and test them properly before deploying them anywhere.````

# Introduction
Many organizations were hit a bit unprepared by this months' patchday which introduces a new security feature called "StrongCertificateBindingEnforcement" that ended up breaking authentication on various important Windows roles such as Network Policy Servers (NPS) or Routing and Remote Access Service (RRAS) when authenticating via certificates.

While Microsoft already released hotfixes to address an issue where the AD Object was not properly matched to the Certificate it uses, there are still many users facing issues.

It is possible to disable this new behavior by setting the registry property `HKLM\SYSTEM\CurrentControlSet\Services\Kdc\StrongCertificateBindingEnforcement` to `REG_DWORD:0x00000000`. However this disables the security mitigations that Microsoft introduced during this patch day (for a good reason!).

Mitigating the actual issue will require multiple steps in many environments, therefor please follow the next paragraphs.

# Issue Mitigation Steps
In this post, I will address different topics you should take into account when addressing this issue in your environment.

## 1. Applying the Hotfixes
First off, apply the hotfixes Microsoft released on 2022/05/20 to make sure that you're not walking into the previously introduced bug.

As for the modern operating systems, all you need is to install the following cumulative updates depending on the OS (installation of the previous 2022-05 updates is not required):
- Windows Server 2022: [​KB5015013](https://support.microsoft.com/help/5015013)
- Windows Server version 20H2: ​[KB5015020](https://support.microsoft.com/help/5015020)
- Windows Server 2019: [KB5015018](https://support.microsoft.com/help/5015018)
- Windows Server 2016: ​[KB5015019](https://support.microsoft.com/help/5015019)

On the older OSes which do not follow the modern update pattern with cumulative updates, you will first have to update your OS before applying one of the following hotfixes:
- Windows Server 2012 R2: [KB5014986](https://support.microsoft.com/help/5014986)
- Windows Server 2012: [KB5014991](https://support.microsoft.com/help/5014991)
- Windows Server 2008 R2 SP1: [KB5014987](https://support.microsoft.com/help/5014987)
- Windows Server 2008 SP2: [KB5014990](https://support.microsoft.com/help/5014990)

## 2. Adding userPrincipalName to the Certificate Templates
While this is not mentioned in any of the official support articles, you will need to make sure that the Certificate Template your clients are using does include the userPrincipalName (UPN) in the Subject Alternative Name (SAN) as shown on this screenshot:

![Template](templatesubject.png)

## 3. Updating ADCS and re-enrolling Certificates 
After applying the 2022-05 Cumulative Updates to your Enterprise Issuing CAs, you will see that each enrolled certificate has a new property with the OID `1.3.6.1.4.1.311.25.2` under "Details". This new property holds the SID of the AD account that enrolled it.
To map existing certificates, please see the next paragraph.

![Template](oid.png)

# Mapping existing certificates to their AD Object
````Hint: For this to work, your Templates already need to include the UserPrincipalName as described above````

## Background Information
To avoid having to wait for all clients to re-enroll their certificate, you can map them to the AD Objects manually, however this is a lot of manual effort.

Mapping certificates is archived by adding an certain identifiers of the previously issued certificates to the `altSecurityIdentities` attribute of the AD Object. This identifier can be built using the following ways, some of them are not explicitly unique to the certificate and should therefor be avoided.

The recommended way to map it is using the certificate serial number in conjunction with the CA Name for example `X509:<I>DC=com,DC=contoso,CN=CONTOSO-DC-CA<SR>1200000000AC11000000002B`. 

|Mapping|Example|Type		|Remarks|
|-----------|-----------|-----------|-----------|
|X509IssuerSubject|"X509:<I>IssuerName<S>SubjectName"|Weak||
|X509SubjectOnly|"X509:<S>SubjectName"|Weak|Text|
|X509RFC822|"X509:<RFC822>user@contoso.com"|Weak|EmailAddress|
|X509IssuerSerialNumber|"X509:<I>IssuerName<SR>1234567890"|Strong|Recommended|
|X509SKI|"X509:<SKI>123456789abcdef"|Strong|Text|
|X509SHA1PublicKey|"X509:<SHA1-PUKEY>123456789abcdef"|Strong||
[Source - support.microsoft.com](https://support.microsoft.com/de-de/topic/kb5014754-certificate-based-authentication-changes-on-windows-domain-controllers-ad2c23b0-15d8-4340-a468-4d4f3b188f16#bkmk_certmap)

For this approach, the binary order of the serial number needs to be added backwards and the CA Name needs to be read backwards as well. As quoted [here](https://support.microsoft.com/de-de/topic/kb5014754-certificate-based-authentication-changes-on-windows-domain-controllers-ad2c23b0-15d8-4340-a468-4d4f3b188f16#bkmk_certmap):
````
Note that when you reverse the SerialNumber, you must keep the byte order. This means that reversing the SerialNumber “A1B2C3” should result in the string “C3B2A1” and not “3C2B1A”. For more information, see HowTo: Map a user to a certificate via all the methods available in the altSecurityIdentities attribute.
````

## Mapping using PowerShell 
Luckily PowerShell comes into play here and allows us to read the existing enrolled certificates from the Enterprise CA and automatically set them on the AD Object in question (no matter if user account or computer account).
The script has cross-domain support and will ask you for credentials for all trusted domains where the Enterprise CA issued certificates to.

To use the script, you will need to populate the following environment variables before you execute the script:
````PowerShell
[string]$CertAuthority = "<pkiname>" # Server Name of the Enterprise CA is enough
[array]$CertTemplates = 'DeviceCert', 'UserCert' # List of Certificate Templates to process
[bool]$DryRun = $true # With DryRun = $true, the script will not do any changes but will show you the impact
````
You will also need to install the `PSPKI` Module which is available [here](https://www.pkisolutions.com/tools/pspki/) or in the PS Gallery.

You can find the script here: https://github.com/system32blog/blog/blob/master/static/post/adsmapcertificates/Invoke-ADCSCertMapping.ps1