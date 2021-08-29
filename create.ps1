#####################################################
# HelloID-Conn-Prov-Target-ORION-Create
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    externalId   = $p.ExternalId.Trim('STUNTMAN')
    firstName    = $P.GivenName
    familyName   = $p.FamilyName
    emailAddress = '' #$p.Contact.Business.Email
    phoneNumber  = '' #$p.PhoneNumber
    title        = $p.Title
    description  = ''
}

#region Helper Functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj.ErrorMessage = $errorResponse
        }
        Write-Output $HttpErrorObj
    }
}

function Get-OrionUser {
    [CmdletBinding()]
    param (
        [string]
        $ExternalId
    )

    try {
       $response = Invoke-RestMethod -Uri "$($config.BaseUrl)/api/User/$ExternalId" -Method GET
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-HTTPError -Error $ex
            $response = "Could not retrieve orion user. Error: $($errorObj.ErrorMessage)"
        } else {
            $response = "Could not retrieve orion user. Error: $($ex.Exception.Message)"
        }
    } finally {
        Write-Output $response
    }
}
#endregion

try {
    # Begin
        $response = Get-OrionUser -ExternalId $($account.externalId)
        if ($response -like "Could*"){
            $action = @("Create")
        } else {
            $action = @("Correlate")
        }

    # Process
    if (-not ($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                $response = Invoke-RestMethod -Uri "$($config.BaseUrl)/api/User" -Method POST -Body ($account | ConvertTo-Json) -ContentType "application/json"
            }

            'Correlate'{
                $response = Invoke-RestMethod -Uri "$($config.BaseUrl)/api/User/$($account.externalId)" -Method GET
            }
        }
    }
} catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = Resolve-HTTPError -Error $ex
        Write-Error "Could not create orion user. Error: $errorMessage"
    } else {
        Write-Error "Could not create orion user. Error: $($ex.Exception.Message)"
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $response.Id
    Auditlogs        = $auditLogs
    Account          = $account
}

Write-Output $result | ConvertTo-Json -Depth 10