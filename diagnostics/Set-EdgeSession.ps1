param([ValidateSet('status','on','off')][string]$Action='status')
$ErrorActionPreference='Stop'
$name='LandingEdgeControl-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$pipe=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut)
try {
    $pipe.Connect(2000)
    $reader=[IO.StreamReader]::new($pipe)
    $writer=[IO.StreamWriter]::new($pipe)
    $writer.AutoFlush=$true
    $writer.WriteLine($Action)
    $pending=$reader.ReadLineAsync()
    if(-not $pending.Wait(6000)){throw 'The configurator did not respond'}
    $json=$pending.Result
    if(-not $json){throw 'The configurator disconnected'}
    $state=$json|ConvertFrom-Json
    if(-not $state.ok){throw $state.error}
    $json
} finally {$pipe.Dispose()}
