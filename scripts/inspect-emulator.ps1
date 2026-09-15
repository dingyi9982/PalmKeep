$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t '127.0.0.1:5555' shell uitest dumpLayout -p /data/local/tmp/pv-check.json | Out-Null
$layout = (& $hdc -t '127.0.0.1:5555' shell cat /data/local/tmp/pv-check.json) | ConvertFrom-Json
function Show-Node($node) {
  $a = $node.attributes
  if ($a.text -or $a.hint -or $a.type -eq 'Video' -or $a.type -eq 'Image') {
    [PSCustomObject]@{ Type=$a.type; Text=if($a.type -in @('TextInput','TextArea')){'[input]'}else{$a.text}; Hint=$a.hint; Bounds=$a.bounds }
  }
  foreach($child in $node.children) { Show-Node $child }
}
Show-Node $layout | Format-Table -AutoSize
