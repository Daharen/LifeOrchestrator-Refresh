# Helper module (fixture).
function Get-Thing {
    param([string]$Name)
    return "thing:$Name"
}

class Widget {
    [string] $Label
}
