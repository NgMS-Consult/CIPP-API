function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) NudgeMFA
    .SYNOPSIS
        (Label) Sets the state for the request to setup Authenticator
    .DESCRIPTION
        (Helptext) Sets the state of the registration campaign for the tenant
        (DocsDescription) Sets the state of the registration campaign for the tenant. If enabled nudges users to set up the Microsoft Authenticator during sign-in.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.NudgeMFA.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"number","name":"standards.NudgeMFA.snoozeDurationInDays","label":"Number of days to allow users to skip registering Authenticator (0-14, default is 1)","defaultValue":1}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-12-08
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthenticationMethodPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'NudgeMFA'
    Write-Host "NudgeMFA: $($Settings | ConvertTo-Json -Compress)"
    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    $ExcludeList = New-Object System.Collections.Generic.List[System.Object]

    if ($Settings.excludeGroup){
        Write-Host "NudgeMFA: We're supposed to exclude a custom group. The group is $($Settings.excludeGroup)"
        try {
            $GroupNames = $Settings.excludeGroup.Split(',').Trim()
            $TenantGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $Tenant
            Write-Host "NudgeMFA: $($TenantGroups | ConvertTo-Json -Depth 5)"
            $GroupIds = $TenantGroups |
                ForEach-Object {
                    foreach ($SingleName in $GroupNames) {
                        write-host "$($SingleName)"
                        if ($_.displayName -like $SingleName) {
                            write-host "$($_.id)"
                            $_.id
                        }
                    }
                }
            Write-Host "NudgeMFA: $($GroupIds | ConvertTo-Json -Depth 5)"
            foreach ($gid in $GroupIds) {
                $ExcludeList.Add(
                    [PSCustomObject]@{
                        id = $gid
                        targetType = "group"
                    }
                )
            }
            Write-Host "NudgeMFA: $($ExcludeList | ConvertTo-Json -Depth 5)"
            Write-Host "NudgeMFA: ExcludeList.id.count $($ExcludeList.id.count)"
            Write-Host "NudgeMFA: GroupNames.count $($GroupNames.count)"

            if (!($ExcludeList.id.count -eq $GroupNames.count)){
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Unable to find exclude group $GroupNames in tenant" -sev Error
                exit 0
            }
        }
        catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to find exclude group $GroupNames in tenant" -sev Error -LogData (Get-CippException -Exception $_)
            exit 0
        }
    }


    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
        $StateIsCorrect = ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq $state) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays -eq $Settings.snoozeDurationInDays) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.enforceRegistrationAfterAllowedSnoozes -eq $true) -and
                        ($ExcludeList.id -in $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.excludeTargets.id)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to get Authenticator App Nudge state, check your permissions and try again' -sev Error -LogData (Get-CippException -Exception $_)
        exit 0
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is already set to $state and other settings is also correct" -sev Info
            return
        }
        $defaultIncludeTargets = @(
            @{
                id = 'all_users'
                targetType = 'group'
                targetedAuthenticationMethod = 'microsoftAuthenticator'
            }
        )

        $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.excludeTargets | ForEach-Object {
            if ($_.id -notin $ExcludeList.id) {
                $ExcludeList.add($_)
            }
        }

        $StateName = $Settings.state ? 'Enabled' : 'Disabled'
        try {
            $GraphRequest = @{
                tenantid    = $Tenant
                uri         = 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy'
                AsApp       = $false
                Type        = 'PATCH'
                ContentType = 'application/json'
                Body        = @{
                    registrationEnforcement = @{
                        authenticationMethodsRegistrationCampaign = @{
                            state                                  = $state
                            snoozeDurationInDays                   = $Settings.snoozeDurationInDays
                            enforceRegistrationAfterAllowedSnoozes = $true
                            includeTargets                         = ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.includeTargets.Count -gt 0) ? $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.includeTargets : $defaultIncludeTargets
                            excludeTargets                         = $ExcludeList
                        }
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            Write-Host "NudgeMFA Request: $($GraphRequest | ConvertTo-Json -Depth 5)"
            New-GraphPostRequest @GraphRequest
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "$StateName Authenticator App Nudge with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Authenticator App Nudge to $state. Error: $($_.Exception.message)" -sev Error -LogData $_
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-StandardsAlert -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -object ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign | Select-Object snoozeDurationInDays, state) -tenant $Tenant -standardName 'NudgeMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ? $true : ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign | Select-Object snoozeDurationInDays, state)
        Set-CIPPStandardsCompareField -FieldName 'standards.NudgeMFA' -FieldValue $state -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
