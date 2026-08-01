#requires -Version 7.0
# Sample entrypoint (fixture).
Import-Module 'ExternalHelper'
. ./lib/Helper.psm1

class SampleThing {
    [int] $Value
}

function Invoke-Sample {
    param([int]$X)
    $w = [SampleThing]::new()
    $w.Value = $X
    return $w
}
