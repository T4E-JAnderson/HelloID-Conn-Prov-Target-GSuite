#2021-01-25 - Disable Google Account
$config = ConvertFrom-Json $configuration
 
#Initialize default properties
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $False
$auditMessage = ""

$default_ou = "/Student Accounts/Inactive"

#Target OrgUnitPath
$calc_ou = ("{0}/{1}/{2}" -f
    $default_ou,
    $p.PrimaryContract.Department.ExternalID,
    $p.custom.GradYear
    )
Write-Information ("Target OU: {0}" -f $calc_ou )

#Support Functions
function google-refresh-accessToken()
{
    ### exchange the refresh token for an access token
    $requestUri = "https://www.googleapis.com/oauth2/v4/token"
        
    $refreshTokenParams = @{
            client_id=$config.clientId
            client_secret=$config.clientSecret
            redirect_uri=$config.redirectUri
            refresh_token=$config.refreshToken
            grant_type="refresh_token" # Fixed value
    };
    $response = Invoke-RestMethod -Method Post -Uri $requestUri -Body $refreshTokenParams -Verbose:$false
    $accessToken = $response.access_token
            
    #Add the authorization header to the request
    $authorization = [ordered]@{
        Authorization = "Bearer $accesstoken"
        'Content-Type' = "application/json"
        Accept = "application/json"
    }
    $authorization
}

#Change mapping here
$account = @{
    suspended = $True
    orgUnitPath = ""
}

try{
    $authorization = google-refresh-accessToken

    # Verify Target OU Exists.  Else, use Default OU
    $splat = @{
        Uri = ("https://www.googleapis.com/admin/directory/v1/customer/my_customer/orgunits{0}" -f $calc_ou)
        Method = 'GET'
        Headers = $authorization
        Verbose = $False
        ErrorAction = 'Stop'
    }
    #  API will error if target OU does not exist.
    try {
        $response = Invoke-RestMethod @splat
        $account.orgUnitPath = $calc_ou
    }
    catch {
        Write-Information ("Target OU Not found.  Using Default OU: {0}" -f $default_ou)
        $account.orgUnitPath = $default_ou
    }

    # Update Account
    if(-Not($dryRun -eq $True)){
        # Get Previous Account
        $splat = @{
            Uri = "https://www.googleapis.com/admin/directory/v1/users/$($aRef)" 
            Method = 'GET'
            Headers = $authorization 
            Verbose = $False
        }
        $previousAccount = Invoke-RestMethod @splat

        $splat = @{
            Uri = "https://www.googleapis.com/admin/directory/v1/users/$($aRef)"
            Method = 'PUT'
            Headers = $authorization
            Body = ($account | ConvertTo-Json -Depth 10)
            Verbose = $False
        }
        $disabledAccount = Invoke-RestMethod @splat
    }
    $success = $True
    $auditMessage = "Disabled account with PrimaryEmail $($newAccount.primaryEmail) and moved to OrgUnit [$($newAccount.orgUnitPath)]"
}catch{
    $auditMessage = "Error disabling account with PrimaryEmail $($newAccount.primaryEmail) - Error: $($_)"
    Write-Error -Verbose $_
}
 
#build up result
$result = [PSCustomObject]@{
    Success = $success
    AccountReference = $aRef
    AuditDetails = $auditMessage
    Account = $disabledAccount
    PreviousAccount = $previousAccount
    
    ExportData = [PSCustomObject]@{
        OrgUnitPath = $disabledAccount.orgUnitPath
    }
}

Write-Output ($result | ConvertTo-Json -Depth 10)
