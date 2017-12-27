asnp *sharepoint*

function CreateField($web, $webUrl)
{
    [xml]$fieldXml = Get-Content "C:\Solutions\2017-12-19\Fields\TPPorocila_Jakost.xml" -encoding UTF8

    $lPorocila = $web.GetList($webUrl + "/Lists/Porocila")

    foreach ($field in $fieldXml.Fields.Field)
    { 
        $spField = $lPorocila.Fields.TryGetFieldByStaticName($field.Name)
        if ($spField -eq $null)
        {
            $lPorocila.Fields.AddFieldAsXml($field.OuterXml)
        }
    }
}

function CreateViews($web, $webUrl, $filePath, $listPath)
{
    $tempIDs = @{}

    $lPorocila = $web.GetList($webUrl + "/" + $listPath)

    [xml]$viewXml = Get-Content $filePath -encoding UTF8

    foreach ($view in $viewXml.Views.View)
    {                            
        $spView = $lPorocila.Views[$view.DisplayName]
        if(($spView -eq $null) -and (($view.DisplayName -notlike "All Documents") -or ($view.DisplayName -notlike "All items")))
        {                            
            $viewFields = New-Object System.Collections.Specialized.StringCollection
            foreach ($column in $view.ViewFields.Field)
            {                                              
                $viewFields.Add($column.Name) > $null
            }
            foreach ($column in $view.ViewFields.FieldRef)
            {                                               
                $viewFields.Add($column.Name) > $null
            }

            $query = $view.Query.InnerXml
    
            $rowLimit = $view.RowLimit

            $newview = $lPorocila.Views.Add($view.DisplayName, $viewFields, $query, $rowLimit, $true, $false)
            
            $tempIDs.Add($view.BaseViewID, $newview.ID)

            $lPorocila.Update()
        }
        else
        {
            $tempIDs.Add($view.BaseViewID, $spView.ID)
        }
    }

    return $tempIDs
}

function ReadPodprojektTemplate($siteUrl, $web, $webUrl, $name, $title, $IDs, $IDsOI2)
{
    [xml]$pageXml = Get-Content "C:\Solutions\2017-12-19\Pages\TPPodprojekt7-9.xml" -encoding UTF8

    $fileXml = $pageXml.Elements.Module.File | ?{$_.Url -eq "$name.aspx"}
    if (-not($fileXml)) {
        throw "Page definition missing"
    }

    $plDefinition = $fileXml.Property | Where { $_.Name -eq "PublishingPageLayout" }
    if (-not($plDefinition)) {
        throw "Page layout missing"
    }

    $plUrl = New-Object Microsoft.SharePoint.SPFieldUrlValue($plDefinition.Value)
    $plName = $plUrl.Url.Substring($plUrl.Url.LastIndexOf('/') + 1)

    $psite = New-Object Microsoft.SharePoint.Publishing.PublishingSite($siteUrl)
    $pl = $psite.GetPageLayouts($false) | Where { $_.Name -eq $plName }
    if (-not($pl)) {
        throw "Page layout not found"
    }

    $pweb = [Microsoft.SharePoint.Publishing.PublishingWeb]::GetPublishingWeb($web)
    $page = $pweb.AddPublishingPage("$name.aspx", $pl)
    $page.Title = $title
    $page.Update()

    $views = $fileXml.View
    foreach ($view in $views)
    {
        [xml]$cdata = $view | select -expand "#cdata-section"
        $wpProperties = $cdata.webParts.webPart.data.properties

        $listUrl = [Microsoft.SharePoint.Utilities.SPUtility]::GetLocalizedString($view.List, $null, 1033)
        $list = $web.getList($webUrl + "/" + $listUrl)

        if ($view.BaseViewID -eq 1)
        {
            $listView = $list.DefaultView
        }
        else
        {
            if ($listUrl -like "*OsnovnaInformacija")
            {
                $tempGUID = $IDsOI2[$view.BaseViewID]
            }
            else
            {
                $tempGUID = $IDs[$view.BaseViewID]
            }


            if (-not($tempGUID)) {
                throw "List view GUID not found"
            }

            $listView = $list.GetView($tempGUID)
            #$listView = $list.Views | Where { $_.BaseViewID -eq $view.BaseViewID }
        }

        if (-not($listView)) {
            throw "List view not found"
        }

        $wpmgr = $web.GetLimitedWebPartManager($page.Url, [System.Web.UI.WebControls.WebParts.PersonalizationScope]::Shared)  
        $listviewwebpart = New-Object Microsoft.SharePoint.WebPartPages.XsltListViewWebPart  
        $listviewwebpart.Title = ($wpProperties.property | Where { $_.Name -eq "Title" }).'#text'
        $listviewwebpart.ChromeType = ($wpProperties.property | Where { $_.Name -eq "ChromeType" }).'#text'
        $listviewwebpart.ListName = $list.ID.ToString("B")
        $listviewwebpart.ViewGuid = $listView.ID.ToString("B")
        $listviewwebpart.ExportMode = "All"  
        $wpmgr.AddWebPart($listviewwebpart, $view.WebPartZoneID, $view.WebPartOrder)  
    }

    $page.CheckIn("")
    $page.ListItem.File.Publish("");
}

# MAIN PROGRAM

$siteUrl = "{site-url}"

$site = Get-SPSite $siteUrl
foreach ($web in $site.AllWebs)
{
    if (!$web.IsRootWeb)
    {
        try
        {
            $webUrl = $web.Url

            Write-Host $webUrl

            $pages = $web.Lists["Strani"]
            if (-not($pages)) {
                $pages = $web.Lists["Pages"]
            }

            $items = $pages.Items

            CreateField $web $webUrl

            $IDs = CreateViews $web $webUrl "C:\Solutions\2017-12-19\Views\TPPorocila_Views7-9.xml" "Lists/Porocila"
            $IDsOI2 = CreateViews $web $webUrl "C:\Solutions\2017-12-19\Views\TPOsnovnaInformacija_Views7-9.xml" "Lists/OsnovnaInformacija"

            if ($items.Title -notcontains "Podprojekt 7") {
                ReadPodprojektTemplate $siteUrl $web $webUrl "Podprojekt7" "Podprojekt 7" $IDs $IDsOI2
            }

            if ($items.Title -notcontains "Podprojekt 8") {
                ReadPodprojektTemplate $siteUrl $web $webUrl "Podprojekt8" "Podprojekt 8" $IDs $IDsOI2
            }

            if ($items.Title -notcontains "Podprojekt 9") {
                ReadPodprojektTemplate $siteUrl $web $webUrl "Podprojekt9" "Podprojekt 9" $IDs $IDsOI2
            }
        }
        catch
        {
            Write-Host $_.Exception.Message
        }
    }
}