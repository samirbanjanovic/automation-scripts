
$ErrorActionPreference = "Stop"

$initLocation = Get-Location
$repoLocation = $null

function SetLocationToRepo($repo) {
    $repoLocation = (Join-Path -Path (Get-Location) -ChildPath $repo.name)

    Set-Location $repoLocation
}

function ParseRepo($config) {            
    $repoSettings = $config | ConvertFrom-Json | Select-Object -expand 'repo'    
    $repoConfig = New-Object -TypeName PSObject
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Name" -value ($repoSettings | Select-Object -expand "name")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Folders" -value ($repoSettings | Select-Object -expand "folders")
    $repoConfig | Add-Member -MemberType NoteProperty -Name "Url" -value ($repoSettings | Select-Object -expand "url")
    
    return $repoConfig
}

function ParsePipelineValues($config) {
    $sonarqube = $config | ConvertFrom-Json | Select-Object -expand 'sonarqube'
    $secapi = $config | ConvertFrom-Json | Select-Object -expand 'sec-api'
    
    $pipelineConfig = New-Object -TypeName PSObject
    $pipelineConfig | Add-Member -MemberType NoteProperty -Name "sqKey" -Value ($sonarqube | Select-Object -expand "key")
    $pipelineConfig | Add-Member -MemberType NoteProperty -Name "sqName" -Value ($sonarqube | Select-Object -expand "name")
    $pipelineConfig | Add-Member -MemberType NoteProperty -Name "secApiAppid" -Value ($secapi | Select-Object -expand "applicationId")
    
    return $pipelineConfig
}

function ParseDotNet($config) {
    $dotnet = $config | ConvertFrom-Json | Select-Object -expand 'dotnet'

    $dotnetConfig = New-Object -TypeName PSObject
    $dotnetConfig | Add-Member -MemberType NoteProperty -Name "Name" -Value ($dotnet | Select-Object -expand "name")
    $dotnetConfig | Add-Member -MemberType NoteProperty -Name "Type" -Value ($dotnet | Select-Object -expand "type")

    return $dotnetConfig
}

function GetZeroParamTemplate($templateName) {
    $template = New-Object -TypeName PSObject
    $template | Add-Member -MemberType NoteProperty -Name "template" -value "templates\$templateName@wpa-foundation-templates"

    return $template
}

function GetNpmStep {
    $npmStepParameters = New-Object -TypeName PSObject
    $npmStepParameters | Add-Member -MemberType NoteProperty -Name "workingDir" -value "`$(npmWorkingDir)"

    $npmStep = GetZeroParamTemplate "npm-steps.yml"
    $npmStep | Add-Member -MemberType NoteProperty -Name "parameters" -value $npmStepParameters

    return $npmStep
}

function GetPreBuildSteps($azurePipelines) {
    $preBuildParameters = New-Object -TypeName PSObject
    $preBuildParameters | Add-Member -MemberType NoteProperty -Name "projectKey" -value "`$(sonarQubeKey)"
    $preBuildParameters | Add-Member -MemberType NoteProperty -Name "projectName" -value "`$(sonarQubeName)"

    $preBuild = GetZeroParamTemplate "prebuild-steps.yml"
    $preBuild | Add-Member -MemberType NoteProperty -Name "parameters" -value $preBuildParameters

    return $preBuild
}

function GetCertifyAndCompleteSteps($repo, $pipelineParameters) {
    $finalizeParams = New-Object -TypeName PSObject    
    $finalizeParams | Add-Member -MemberType NoteProperty -Name "repoUrl" -value "`$(repoUrl)"
    $finalizeParams | Add-Member -MemberType NoteProperty -Name "secApiAppId" -value "`$(secApiAppId)"

    $preBuild = GetZeroParamTemplate "certify-and-complete-steps.yml"
    $preBuild | Add-Member -MemberType NoteProperty -Name "parameters" -value $finalizeParams

    return $preBuild
}

function GetTemplateRepoReference {
    $repoResource = New-Object -TypeName PSObject
    $repoResource | Add-Member -MemberType NoteProperty -Name "repository" -value "wpa-foundation-templates"
    $repoResource | Add-Member -MemberType NoteProperty -Name "type" -value "git"
    $repoResource | Add-Member -MemberType NoteProperty -Name "name" -value "Customer Experience Management/wpa-foundation"
    $repoResource | Add-Member -MemberType NoteProperty -Name "ref" -value "refs/heads/master"


    return $repoResource
}

function GetRepoRefHeader {
    $repoTemplate = GetTemplateRepoReference
    $repoRef = New-Object -TypeName PSObject    
    $repoRef | Add-Member -MemberType NoteProperty -Name "repositories" -value @($repoTemplate)

    return $repoRef
}

function GetBuildVariables($repo, $pipelineParameters, $dotnet) {
    $variables = New-Object -TypeName PSObject
    $variables | Add-Member -MemberType NoteProperty -name "poolName" -value "VS2019"
    $variables | Add-Member -MemberType NoteProperty -name "repoUrl" -value $repo.url
    $variables | Add-Member -MemberType NoteProperty -name "sonarQubeKey" -value $pipelineParameters.sqKey
    $variables | Add-Member -MemberType NoteProperty -name "sonarQubeName" -value $pipelineParameters.sqName
    $variables | Add-Member -MemberType NoteProperty -name "secApiAppId" -value $pipelineParameters.secApiAppid

    return $variables
}

function GetBuildJob($repo, $pipelineParameters, $dotnet) {
    #compile all the templated steps
    
    $npmStep = GetNpmStep
    $prebuildStep = GetPreBuildSteps $pipelineParameters 
    $dotnetStep = GetZeroParamTemplate "dotnet-steps.yml"
    $sqPublishStep = GetZeroParamTemplate "sonarqube-publish-steps.yml"
    $finalizeStep = GetCertifyAndCompleteSteps $repo $pipelineParameters
    
    $variables = GetBuildVariables $repo $pipelineParameters $dotnet

    $agentPool = New-Object -TypeName PSObject
    $agentPool | Add-Member -MemberType NoteProperty -name "name" -value "`$(poolName)"
    

    $buildJob = New-Object -TypeName PSObject
    $buildJob | Add-Member -MemberType NoteProperty -name "job" -value "Build"
    $buildJob | Add-Member -MemberType NoteProperty -name "variables" -value $variables
    $buildJob | Add-Member -MemberType NoteProperty -name "pool" -value $agentPool
    

    if('mvc', 'web', 'webapp' -contains $dotnet.Type) {
        $buildJob | Add-Member -MemberType NoteProperty -name "steps" -value @($npmStep, $prebuildStep, $dotnetStep, $sqPublishStep, $finalizeStep)
    } else {
        $buildJob | Add-Member -MemberType NoteProperty -name "steps" -value @($prebuildStep, $dotnetStep, $sqPublishStep, $finalizeStep)
    }

    return $buildJob
}

function GetAzurePipelines($repo, $pipelineParameters, $dotnet) {
    #create reference to wpa-foundation repo for templates
    $repoRef = GetRepoRefHeader
    
    $azurePipelines = New-Object -TypeName PSObject    
    $azurePipelines | Add-Member -MemberType NoteProperty -name "resources" -value $repoRef
    $azurePipelines | Add-Member -MemberType NoteProperty -name "trigger" -value master, development
    
    $buildJob = GetBuildJob $repo $pipelineParameters $dotnet
    
    $azurePipelines | Add-Member -MemberType NoteProperty -name "jobs" @($buildJob)

    return $azurePipelines
}

function WriteAzurePipelinesYaml($azurePipelines) {
    $filePath = (Join-Path -Path (Get-Location) -ChildPath "azure-pipelines.yaml")
    $azurePipelines | ConvertTo-Yaml | Out-File -FilePath $filePath
}

$configFile = $args[0]
$schemaFile = $args[1]

$config = Get-Content $configFile -Raw    
$schema = Get-Content $schemaFile -Raw
$result = Test-Json -Json $config -schema $schema

if($result.ToString() -ne "True")
{
    echo $result
    return
}

$repo = ParseRepo $config
$pipelineParameters = ParsePipelineValues $config
$dotnet = ParseDotNet $config 

SetLocationToRepo $repo 

$azurePipelines = GetAzurePipelines $repo $pipelineParameters $dotnet

WriteAzurePipelinesYaml $azurePipelines

echo "azure-pipelines.yaml created"
$azurePipelines | ConvertTo-Yaml 

Set-Location $initLocation