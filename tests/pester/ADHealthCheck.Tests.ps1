Describe "ADHealthCheck Core" {
    It "Loads settings file" {
        Test-Path (Join-Path $PSScriptRoot '..\..\config\settings.json') | Should -BeTrue
    }
    It "Parses DCDiag sample output" {
        . (Join-Path $PSScriptRoot '..\..\modules\ADHealthCheck.Diag.ps1')
        $sample = @("Starting test: Connectivity", "Server1 passed test Connectivity")
        $res = Parse-DcDiagOutput -Raw $sample -DC Server1
        $res.Tests | Should -Not -BeNullOrEmpty
    }
}
