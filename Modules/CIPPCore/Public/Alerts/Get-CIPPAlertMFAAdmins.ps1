function Get-CIPPAlertMFAAdmins {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -ErrorAction Stop)
        foreach ($Policy in $CAPolicies) {
            if ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa') {
                $DuoActive = $true
            }
        }
        if (!$DuoActive) {
            $users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&filter=IsAdmin eq true and isMfaRegistered eq false and userType eq 'member'&`$select=id,userDisplayName,userPrincipalName,lastUpdatedDateTime,isMfaRegistered,IsAdmin" -tenantid $($TenantFilter) | Where-Object { $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' }
            if ($users.UserPrincipalName) {
                if ($InputValue){
                    try {
                        $DisabledUsers = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&filter=accountEnabled eq false&`$select=id,userPrincipalName,accountEnabled" -tenantid $($TenantFilter)

                    }
                    catch {
                        Start-Sleep 5
                        $DisabledUsers = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&filter=accountEnabled eq false&`$select=id,userPrincipalName,accountEnabled" -tenantid $($TenantFilter)
                    }
                    $Results = $users.UserPrincipalName | Where-Object { $_ -notin $DisabledUsers.UserPrincipalName }
                }
                else {
                    $Results = $users.UserPrincipalName
                }
                $AlertData = "The following admins do not have MFA registered: $($Results -join ', ')"
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

            }
        } else {
            Write-LogMessage -message 'Potentially using Duo for MFA, could not check MFA status for Admins with 100% accuracy' -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
        }
    } catch {
        Write-LogMessage -message "Failed to check MFA status for Admins: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Error
    }
}
