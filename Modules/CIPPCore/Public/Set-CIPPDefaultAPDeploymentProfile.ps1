function Set-CIPPDefaultAPDeploymentProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $tenantFilter,
        $displayname,
        $description,
        $devicenameTemplate,
        $allowWhiteGlove,
        $CollectHash,
        $usertype,
        $DeploymentMode,
        $hideChangeAccount,
        $AssignTo,
        $hidePrivacy,
        $hideTerms,
        $Autokeyboard,
        $Headers,
        $Language = 'os-default',
        $APIName = 'Add Default Enrollment Status Page'
    )

    $User = $Request.Headers

    try {
        If ($DeviceNameTemplate -like "*#SHORTNAME#*") {
            $TableProperties = Get-CippTable -tablename 'TenantProperties'
            $TableTenants = Get-CippTable -tablename 'Tenants'

            $Tenant = Get-CIPPAzDataTableEntity @TableTenants -Filter "PartitionKey eq 'Tenants' and defaultDomainName eq '$($tenantfilter)'" -Property RowKey, PartitionKey, customerId, displayName, defaultDomainName


            $Shortname = (Get-CIPPAzDataTableEntity @TableProperties -Filter "PartitionKey eq '$($tenant.customerId)' and RowKey eq 'Shortname'").Value

            if (!$Shortname) {
                Write-LogMessage -Headers $User -API $APIName -tenant $($tenantfilter) -message "Failed adding Autopilot Profile $($Displayname). Error: Tenant ShortName is not set for $($Tenant.defaultDomainName)" -Sev 'Error'
                throw "Tenant ShortName is not set for $($tenantFilter)"
                return
            }
            Write-Host "WAP: shortname $($Shortname)"
            #Write-Host "WAP: Org devTemplate $($DeviceNameTemplate)"
            #Write-Host "WAP: Org devTemplate Type $($DeviceNameTemplate.gettype())"
            $DeviceNameTemplate = $DeviceNameTemplate -replace "#SHORTNAME#", $Shortname
            #Write-Host "WAP: New devTemplate $($DeviceNameTemplate)"
        }
        Write-Host "WAP: language $($Language)"
        $ObjBody = [pscustomobject]@{
            '@odata.type'                            = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'
            'displayName'                            = "$($displayname)"
            'description'                            = "$($description)"
            'deviceNameTemplate'                     = "$($DeviceNameTemplate)"
            'language'                               = "$($Language)"
            'enableWhiteGlove'                       = $([bool]($allowWhiteGlove))
            'deviceType'                             = 'windowsPc'
            'extractHardwareHash'                    = $([bool]($CollectHash))
            'roleScopeTagIds'                        = @()
            'hybridAzureADJoinSkipConnectivityCheck' = $false
            'outOfBoxExperienceSetting'             = @{
                'deviceUsageType'           = "$DeploymentMode"
                'escapeLinkHidden'            = $([bool]($hideChangeAccount))
                'privacySettingsHidden'       = $([bool]($hidePrivacy))
                'eulaHidden'                  = $([bool]($hideTerms))
                'userType'                  = "$usertype"
                'keyboardSelectionPageSkipped' = $([bool]($Autokeyboard))
            }
        }
        $Body = ConvertTo-Json -InputObject $ObjBody
        Write-Host "WAP: Body $Body"

        $Profiles = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $tenantfilter | Where-Object -Property displayName -EQ $displayname
        if ($Profiles.count -gt 1) {
            $Profiles | ForEach-Object {
                if ($_.id -ne $Profiles[0].id) {
                    if ($PSCmdlet.ShouldProcess($_.displayName, 'Delete duplicate Autopilot profile')) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($_.id)" -tenantid $tenantfilter -type DELETE
                        Write-LogMessage -Headers $User -API $APIName -tenant $($tenantfilter) -message "Deleted duplicate Autopilot profile $($displayname)" -Sev 'Info'
                    }
                }
            }
            $Profiles = $Profiles[0]
        }
        if (!$Profiles) {
            if ($PSCmdlet.ShouldProcess($displayName, 'Add Autopilot profile')) {
                $Type = 'Add'
                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -body $body -tenantid $tenantfilter
                Write-LogMessage -Headers $User -API $APIName -tenant $($tenantfilter) -message "Added Autopilot profile $($displayname)" -Sev 'Info'
            }
        } else {
            $Type = 'Edit'
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($Profiles.id)" -tenantid $tenantfilter -body $body -type PATCH
            $GraphRequest = $Profiles | Select-Object -Last 1
        }

        if ($AssignTo -eq $true) {
            $AssignBody = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
            if ($PSCmdlet.ShouldProcess($AssignTo, "Assign Autopilot profile $displayname")) {
                #Get assignments
                $Assignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $tenantfilter
                if (!$Assignments) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $tenantfilter -type POST -body $AssignBody
                }
                Write-LogMessage -Headers $User -API $APIName -tenant $($tenantfilter) -message "Assigned autopilot profile $($Displayname) to $AssignTo" -Sev 'Info'
            }
        }
        "Successfully $($Type)ed profile for $($tenantfilter)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APIName -tenant $($tenantfilter) -message "Failed $($Type)ing Autopilot Profile $($Displayname). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to add profile for $($tenantfilter): $($ErrorMessage.NormalizedError)"
    }
}
