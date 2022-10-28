#region Static Definitions
[string]$CertAuthority = "<pkiname>"
[array]$CertTemplates = 'DeviceCert', 'UserCert'
[bool]$DryRun = $true
#endregion

#region Modules
Import-Module -Name 'PSPKI'
#endregion

#region Functions

# Thanks to Reddit / Github User xxdcmast for this function @xxdcmast, if you want me to remove this, let me know
function Reverse-CertificateIssuer {
    [CmdletBinding()]
    Param(
            [Parameter(Position = 0, mandatory = $true)]
            [string] $CertIssuer)

    #Split the issuer DN into parts by comma
    $CertIssuernospaces = $CertIssuer -replace ',\s',','
    $splitresults =$CertIssuernospaces -split "," -ne ''

    #Reverse the DN to create the reverse issuer
    $reversed =$splitresults[-1.. - $splitresults.Length] -join ', '

    $reversed.trimstart()

    #end function
}
# Thanks to Reddit / Github User xxdcmast for this function @xxdcmast, if you want me to remove this, let me know
function Reverse-CertificateSerialNumber {
    [CmdletBinding()]
    Param(
    [Parameter(Position=0,mandatory=$true)]
    [string] $CertSerialNumber)

    #Split the string into two characters to represent the byte encoding
    $splitresults = $CertSerialNumber  -split '(..)' -ne ''

    #Take the byte split serial number and reverse the digits to get the correct cert formatting
    $splitresults[-1..-$splitresults.Length] -join ''

    #end function
}
#endregion

#region Retrieve Data
$CAs = @{}

# Retrieve all Certificate Templates and their OIDs
Write-Host("[$(Get-Date)] Retrieving Certificate templates..")
$CertTemplateOIDs = $CertTemplates | ForEach-Object {
    (Get-CertificateTemplate -Name $_).oid.Value
}

# Retrieve all trusted domains
Write-Host("[$(Get-Date)] Retrieving all trusted domains..")
$Domains = @{}

Get-ADTrust -Filter * | ForEach-Object {
    [string]$DC = (Get-ADDomainController -Discover -DomainName $_.target).hostname
    $ADDomain = Get-ADDomain -Server $DC
    $ADForest = Get-ADForest -Server $DC
    $DNSRoot = $ADDomain.DNSRoot.ToLower()
    $Domains.$DNSRoot = @{
        DomainController = $DC
        UPNSuffixes = $ADForst.UPNSuffixes
    }
    $Domains.$DNSRoot.UPNSuffixes += $DNSRoot
}
[string]$DC = (Get-ADDomainController -Discover).hostname
$ADDomain = Get-ADDomain -Server $DC
$DNSRoot = $ADDomain.DNSRoot.ToLower()
$ADForest = Get-ADForest -Server $DC
$Domains.$DNSRoot = @{
    DomainController = $DC
    IsLocal = $true
    UPNSuffixes = $ADForst.UPNSuffixes
}
$Domains.$DNSRoot.UPNSuffixes += $DNSRoot

# Retrieve all certificates that match our template
Write-Host("[$(Get-Date)] Retrieving Certificates..")
$certs = Get-IssuedRequest -CertificationAuthority $CertAuthority -Filter "NotAfter -ge $(Get-Date)" | Where-Object { 
    $_.CertificateTemplate -in $CertTemplateOIDs
}
#endregion

#region Map certificates
Write-Host("[$(Get-Date)] Processing Certificates..")
foreach($cert in ($certs | Sort-Object -Property 'RequestID' -Descending)){
    try{
        $ADCSRow = Get-AdcsDatabaseRow -RowID $cert.RowId -Table Extension -CertificationAuthority $CertAuthority -Filter "ExtensionName -eq 2.5.29.17"
        $rawBytes = [convert]::frombase64string($ADCSRow.ExtensionRawValue)
        $ASN = New-Object Security.Cryptography.asnencodeddata @(,$rawBytes)
        $SAN = New-Object Security.Cryptography.x509certificates.x509subjectalternativenamesextension $ASN,0
        $UPN = $SAN.AlternativeNames | Where-Object { $_.Type -eq 'UserPrincipalName' } | Select-Object -First 1 -ExpandProperty 'Value'
        if($UPN){
            $requester = $cert.'Request.RequesterName'
            $UPNSplit = $UPN.Split("@")
            $UPNSuffix = $UPNSplit[-1]
            $CN = $UPNSplit[0..($UPNSplit.Count-2)] -join ""
        }else{
            Write-Host("[$($cert.RequestID) - $($cert.CommonName)] `"$($cert.CommonName)`" does not have UPN as SAN, skipping..")
            continue;
        }
    }catch{
        Write-Host("[$($cert.RequestID) - $($cert.CommonName)] Can't extract UPN for `"$($cert.CommonName)`", Error: $_")
    }
    # Check if we found this domain
    if(
        ($DomainEntry = $Domains.GetEnumerator() | Where-Object { $UPNSuffix -in $_.Value.UPNSuffixes }) -and
        ($UPNSuffix) -and
        ($CN)
    ){
        # Build AD Cmdlet Splatting
        $ADCmdletSplat = @{
            Server = $DomainEntry.Value.DomainController
        }

        # Check if this is the local domain, otherwise ask for credentials
        if(
            !($DomainEntry.Value.IsLocal) -and
            !($DomainEntry.Value.Credentials)
        ){
            $Domains.$Domain.Credentials = Get-Credential -Message "Please enter Credentials for Domain `"$Domain`"."
            $DomainEntry.Value.Credentials = $Domains.$Domain.Credentials
        }

        # Add the credential to the splatting if we have one
        if(!($DomainEntry.Value.IsLocal)){
            $ADCmdletSplat.Credential = $DomainEntry.Value.Credentials
        }

        # Retrieve AD Object
        if(
            (
                $UPN.Contains("$@") -and
                ($ADObject = Get-ADObject -Filter { sAMAccountName -eq $CN } -Properties 'altSecurityIdentities' -ErrorAction SilentlyContinue @ADCmdletSplat)
            ) -or
            (
                !($UPN.Contains("$@")) -and
                ($ADObject = Get-ADObject -Filter { userPrincipalName -eq $CN } -Properties 'altSecurityIdentities' -ErrorAction SilentlyContinue @ADCmdletSplat)
            )
        ){
            if(!($CAs.$($cert.ConfigString))){
                $CAs.$($cert.ConfigString) = Get-CA -ErrorAction SilentlyContinue | Where-Object { $_.ConfigString -eq $cert.ConfigString } 
            }
            
            # Build CA Cert Subject
            $CACertSubject = (Reverse-CertificateIssuer -CertIssuer $CAs.$($cert.ConfigString).Certificate.Subject).Replace(" ","")

            # Build Serial Numbers
            $CertForwardSN = $cert.SerialNumber
            $CertBackwardSN = (Reverse-CertificateSerialNumber -CertSerialNumber $CertForwardSN).ToUpper()

            # Build X509 Address
            $X509IssuerSerialNumber = "X509:<I>$CACertSubject<SR>$CertBackwardSN"

            # Check if the attribute is already set, otherwise initialize array
            if(!($altIDs = $ADObject.'altSecurityIdentities')){
                $altIDs = @()
            }

            # Check if our X509IssuerSerialNumber is already in it
            if($X509IssuerSerialNumber -notin $altIDs){

                # It is not, add it
                Write-Host("[$($cert.RequestID) - $CN] Adding X509: `"$X509IssuerSerialNumber`"")
                $altIDs += $X509IssuerSerialNumber

				if(!$DryRun){
					# Write out the AD Object
					$ADObject | Set-ADObject -Replace @{
						'altSecurityIdentities' = $altIDs
					} @ADCmdletSplat
				}
            } 
        }else{
            Write-Host("[$($cert.RequestID) - $CN] AD Object not found.")
        }        
    }
}
#endregion 
