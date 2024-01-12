
$ErrorActionPreference = "Stop"

$initLocation = Get-Location
$repoLocation = $null

function ExpandJsonElement($config, $elementName) {
    return $config | ConvertFrom-Json | Select-Object -expand $elementName
}

function ParseRepo($config) {
    $repoSettings = ExpandJsonElement $config 'repo'

    $repoConfig = New-Object -TypeName PSObject
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Name" -Value ($repoSettings | Select-Object -expand "name")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Folders" -Value ($repoSettings | Select-Object -expand "folders")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Url" -Value ($repoSettings | Select-Object -expand "url")
    
    return $repoConfig
}

function ParseDotNet($config) {
    $dotnet = ExpandJsonElement $config 'dotnet'

    $repoConfig = New-Object -TypeName PSObject
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Name" -Value ($dotnet | Select-Object -expand "name")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Type" -Value ($dotnet | Select-Object -expand "type")

    return $dotnet
}

function CreateRepoDirectories($repoSettings) {
    mkdir $repoSettings.name

    $repoLocation = (Join-Path -Path (Get-Location) -ChildPath $repoSettings.name)

    Set-Location $repoLocation

    mkdir "src"
    mkdir "test"
}
function GenerateAssetData($config, $repo) {    
    $user = ExpandJsonElement $config 'user'    
    $assetyml = ExpandJsonElement $config 'asset-yml'

    $asset = New-Object -TypeName PSObject    
    $asset | Add-Member -MemberType NoteProperty -Name "version" -Value 1
    $asset | Add-Member -MemberType NoteProperty -Name "platform" -Value "ado"
    $asset | Add-Member -MemberType NoteProperty -Name "organization" -Value "sb"
    $asset | Add-Member -MemberType NoteProperty -Name "project" -Value "Custom"
    $asset | Add-Member -MemberType NoteProperty -Name "repositoryType" -Value "git"
    $asset | Add-Member -MemberType NoteProperty -Name "repository" -Value ($repo | Select-Object -expand "name")

    $asset.iserverAssociatedRecords | Add-Member -MemberType NoteProperty -Name "addedBy" -Value $user.email
    $asset.serviceNowAssociatedRecords | Add-Member -MemberType NoteProperty -Name "addedBy" -Value $user.email
    $asset.serviceNowAssociatedRecords | Add-Member -MemberType NoteProperty -Name "technology" -Value "DotNetCore"

    $repoMetaData = New-Object -TypeName PSObject
    $repoMetaData | Add-Member -MemberType NoteProperty -Name "repoMetaData" -Value $asset

    return $repoMetaData
}

function WriteAssetYml($asset) {
    $filePath = (Join-Path -Path (Get-Location) -ChildPath "asset.yml")
    $asset | ConvertTo-Yaml | Out-File -FilePath $filePath
}

function InitDotNet($dotnet) {    
    dotnet new $dotnet.Type -n $dotnet.Name -o src --no-restore
    dotnet new xunit -n ($dotnet.Name + ".Tests") -o test --no-restore

    dotnet new sln -n $dotnet.Name
    dotnet sln add (Join-Path -Path src -ChildPath ($dotnet.Name + ".csproj"))
    dotnet sln add (Join-Path -Path test -ChildPath ($dotnet.Name + ".Tests.csproj"))
    dotnet new gitignore
}

  
$configFile = $args[0]
$schemaFile = $args[1]

$config = Get-Content $configFile -Raw   
$schema = Get-Content $schemaFile -Raw
$result = Test-Json -Json ($config) -schema $schema

if($result.ToString() -ne "True")
{
    echo $result
    return
}

$repo = ParseRepo $config
$dotnet = ParseDotNet $config 
$asset = GenerateAssetData $config $repo

CreateRepoDirectories $repo
InitDotNet $dotnet
WriteAssetYml $asset     

tree /f /a $repoLocation        

Set-Location $initLocation

