Configuration SharePointFarm
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [string]
        $DatabaseServer,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[PSCredential]
        $SPSetupCredential,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]
        $SPFarmCredential,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]
        $WebPoolManagedAccount,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]
        $ServicePoolManagedAccount,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]
        $Passphrase,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PublicUrl
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName SharePointDsc

    node localhost
    {
        #**********************************************************
        # Basic farm configuration
        #
        # This section creates the new SharePoint farm object, and
        # provisions generic services and components used by the
        # whole farm
        #**********************************************************
        SPFarm CreateSPFarm
        {
            Ensure                   = 'Present'
            DatabaseServer           = $DatabaseServer
            FarmConfigDatabaseName   = 'SP_Config'
            Passphrase               = $Passphrase
            FarmAccount              = $SPFarmCredential
            PsDscRunAsCredential     = $SPSetupCredential
            AdminContentDatabaseName = 'SP_AdminContent'
            RunCentralAdmin          = $true
        }

        SPManagedAccount ServicePoolManagedAccount
        {
            AccountName          = $ServicePoolManagedAccount.UserName
            Account              = $ServicePoolManagedAccount
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPManagedAccount WebPoolManagedAccount
        {
            AccountName          = $WebPoolManagedAccount.UserName
            Account              = $WebPoolManagedAccount
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPDiagnosticLoggingSettings ApplyDiagnosticLogSettings
        {
            PsDscRunAsCredential                        = $SPSetupCredential
            LogPath                                     = 'C:\ULS'
            LogSpaceInGB                                = 5
            AppAnalyticsAutomaticUploadEnabled          = $false
            CustomerExperienceImprovementProgramEnabled = $true
            DaysToKeepLogs                              = 7
            DownloadErrorReportingUpdatesEnabled        = $false
            ErrorReportingAutomaticUploadEnabled        = $false
            ErrorReportingEnabled                       = $false
            EventLogFloodProtectionEnabled              = $true
            EventLogFloodProtectionNotifyInterval       = 5
            EventLogFloodProtectionQuietPeriod          = 2
            EventLogFloodProtectionThreshold            = 5
            EventLogFloodProtectionTriggerPeriod        = 2
            LogCutInterval                              = 15
            LogMaxDiskSpaceUsageEnabled                 = $true
            ScriptErrorReportingDelay                   = 30
            ScriptErrorReportingEnabled                 = $true
            ScriptErrorReportingRequireAuth             = $true
            DependsOn                                   = '[SPFarm]CreateSPFarm'
        }

        SPUsageApplication UsageApplication
        {
            Name                  = 'Usage Service Application'
            DatabaseName          = 'SP_Usage'
            UsageLogCutTime       = 5
            UsageLogLocation      = 'C:\UsageLogs'
            UsageLogMaxFileSizeKB = 1024
            PsDscRunAsCredential  = $SPSetupCredential
            DependsOn             = '[SPFarm]CreateSPFarm'
        }

        SPStateServiceApp StateServiceApp
        {
            Name                 = 'State Service Application'
            DatabaseName         = 'SP_State'
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPDistributedCacheService EnableDistributedCache
        {
            Name                 = 'AppFabricCachingService'
            Ensure               = 'Present'
            CacheSizeInMB        = 1024
            ServiceAccount       = $ServicePoolManagedAccount.UserName
            PsDscRunAsCredential = $SPSetupCredential
            CreateFirewallRules  = $true
            DependsOn            = @('[SPFarm]CreateSPFarm','[SPManagedAccount]ServicePoolManagedAccount')
        }

        #**********************************************************
        # Web applications
        #
        # This section creates the web applications in the
        # SharePoint farm, as well as managed paths and other web
        # application settings
        #**********************************************************

        $webAppUrl = "http://sites.$PublicUrl"
        $hostHeader = "sites.$PublicUrl"

        SPWebApplication SharePointSites
        {
            Name                   = 'SharePoint Sites'
            ApplicationPool        = 'SharePoint Sites'
            ApplicationPoolAccount = $WebPoolManagedAccount.UserName
            AllowAnonymous         = $false
            DatabaseName           = 'SP_Content'
            Url                    = $webAppUrl
            HostHeader             = $hostHeader
            Port                   = 80
            PsDscRunAsCredential   = $SPSetupCredential
            DependsOn              = '[SPManagedAccount]WebPoolManagedAccount'
        }

        SPCacheAccounts WebAppCacheAccounts
        {
            WebAppUrl              = $webAppUrl
            SuperUserAlias         = 'CONTOSO\SP_SuperUser'
            SuperReaderAlias       = 'CONTOSO\SP_SuperReader'
            PsDscRunAsCredential   = $SPSetupCredential
            DependsOn              = '[SPWebApplication]SharePointSites'
        }

        SPSite TeamSite
        {
            Url                      = $webAppUrl
            OwnerAlias               = 'CONTOSO\SP_Admin'
            Name                     = 'DSC Demo Site'
            Template                 = 'STS#0'
            PsDscRunAsCredential     = $SPSetupCredential
            DependsOn                = '[SPWebApplication]SharePointSites'
        }


        #**********************************************************
        # Service instances
        #
        # This section describes which services should be running
        # and not running on the server
        #**********************************************************

        SPServiceInstance ClaimsToWindowsTokenServiceInstance
        {
            Name                 = 'Claims to Windows Token Service'
            Ensure               = 'Present'
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPServiceInstance SecureStoreServiceInstance
        {
            Name                 = 'Secure Store Service'
            Ensure               = 'Present'
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPServiceInstance SearchServiceInstance
        {
            Name                 = 'SharePoint Server Search'
            Ensure               = 'Present'
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        #**********************************************************
        # Service applications
        #
        # This section creates service applications and required
        # dependencies
        #**********************************************************

        $serviceAppPoolName = 'SharePoint Service Applications'
        SPServiceAppPool MainServiceAppPool
        {
            Name                 = $serviceAppPoolName
            ServiceAccount       = $ServicePoolManagedAccount.UserName
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = '[SPFarm]CreateSPFarm'
        }

        SPSecureStoreServiceApp SecureStoreServiceApp
        {
            Name                  = 'Secure Store Service Application'
            ApplicationPool       = $serviceAppPoolName
            AuditingEnabled       = $true
            AuditlogMaxSize       = 30
            DatabaseName          = 'SP_SecureStore'
            PsDscRunAsCredential  = $SPSetupCredential
            DependsOn             = '[SPServiceAppPool]MainServiceAppPool'
        }

        SPManagedMetaDataServiceApp ManagedMetadataServiceApp
        {
            Name                 = 'Managed Metadata Service Application'
            PsDscRunAsCredential = $SPSetupCredential
            ApplicationPool      = $serviceAppPoolName
            DatabaseName         = 'SP_MMS'
            DependsOn            = '[SPServiceAppPool]MainServiceAppPool'
        }

        SPBCSServiceApp BCSServiceApp
        {
            Name                  = 'BCS Service Application'
            ApplicationPool       = $serviceAppPoolName
            DatabaseName          = 'SP_BCS'
            PsDscRunAsCredential  = $SPSetupCredential
            DependsOn             = @('[SPServiceAppPool]MainServiceAppPool', '[SPSecureStoreServiceApp]SecureStoreServiceApp')
        }

        SPSearchServiceApp SearchServiceApp
        {
            Name                  = 'Search Service Application'
            DatabaseName          = 'SP_Search'
            ApplicationPool       = $serviceAppPoolName
            PsDscRunAsCredential  = $SPSetupCredential
            DependsOn             = '[SPServiceAppPool]MainServiceAppPool'
        }

        #**********************************************************
        # Local configuration manager settings
        #
        # This section contains settings for the LCM of the host
        # that this configuration is applied to
        #**********************************************************
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
    }
}
