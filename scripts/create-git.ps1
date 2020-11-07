$ErrorActionPreference = "Stop"

$initLocation = Get-Location
$repoLocation = $null
$B64Pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$ENV:GIT_ADO_PAT"))

function SetLocationToRepo($repo) {
    $repoLocation = (Join-Path -Path (Get-Location) -ChildPath $repo.name)

    Set-Location $repoLocation
}

function ParseRepo($config) {
    $repoSettings = $config | ConvertFrom-Json | Select-Object -expand 'repo'

    $repoConfig = New-Object -TypeName PSObject
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Name" -Value ($repoSettings | Select-Object -expand "name")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Folders" -Value ($repoSettings | Select-Object -expand "folders")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Url" -Value ($repoSettings | Select-Object -expand "url")
    
    return $repoConfig
}

function ParseUser($config) {
    $user = $config | ConvertFrom-Json | Select-Object -expand 'user'

    $repoConfig = New-Object -TypeName PSObject
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Name" -Value ($user | Select-Object -expand "name")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Email" -Value ($user | Select-Object -expand "email")

    return $user
}

function InitGit($user) {    
    git config --global user.email ($user.Email)
    git config --global user.name ($user.Name)

    git init
    git add .
    git commit -m "initial commit"
}

function GitPushRemote($repo) {     
    git remote add origin $repo.Url
    git -c http.extraHeader="Authorization: Basic $B64Pat" push --set-upstream origin master
    git checkout -b development
    git -c http.extraHeader="Authorization: Basic $B64Pat" push --set-upstream origin development 
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
$user = ParseUser $config
            
SetLocationToRepo $repo

InitGit $user
GitPushRemote $repo

Set-Location $initLocation