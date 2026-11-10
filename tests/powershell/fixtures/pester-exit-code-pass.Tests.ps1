Describe "Pester exit-code passing fixture" {
    It "passes so the npm script must return ExitCode 0" {
        (1 + 1) | Should -Be 2
    }
}
