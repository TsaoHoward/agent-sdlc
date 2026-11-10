Describe "Pester exit-code intentional failure fixture" {
    It "fails so the npm script must return a nonzero ExitCode" {
        (1 + 1) | Should -Be 3
    }
}
