# Description

This resource is used to define an alternate access mapping URL for a specified
web application. These can be assigned to specific zones for each web
application. Alternatively a URL can be removed from a zone to ensure that it
will remain empty and have no alternate URL.

To select the Central Administration site, use the following command to retrieve
the correct web application name:
(Get-SPWebApplication -IncludeCentralAdministration | Where-Object {
     $_.IsAdministrationWebApplication
 }).DisplayName

The default value for the Ensure parameter is Present. When not specifying this
parameter, the setting is configured.
