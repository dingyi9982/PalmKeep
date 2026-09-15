param([string]$Label, [string]$Value, [switch]$EnterText)
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell uitest dumpLayout -p /data/local/tmp/pv-action.json | Out-Null
$layout = (& $hdc -t 127.0.0.1:5555 shell cat /data/local/tmp/pv-action.json) | ConvertFrom-Json
function Find-Node($node) {
  $a = $node.attributes
  if (($EnterText -and $a.hint -eq $Label) -or (!$EnterText -and $a.text -eq $Label)) { $a }
  foreach($child in $node.children) { Find-Node $child }
}
$target = @(Find-Node $layout) | Select-Object -Last 1
if (!$target) { throw "Control not visible: $Label" }
$coords = [regex]::Matches($target.bounds, '\d+') | ForEach-Object { [int]$_.Value }
$x = [int](($coords[0]+$coords[2])/2); $y = [int](($coords[1]+$coords[3])/2)
if ($EnterText) {
  & $hdc -t 127.0.0.1:5555 shell uitest uiInput inputText $x $y $Value
  & $hdc -t 127.0.0.1:5555 shell uitest dumpLayout -p /data/local/tmp/pv-keyboard.json | Out-Null
  $keyboardLayout = & $hdc -t 127.0.0.1:5555 shell cat /data/local/tmp/pv-keyboard.json
  if ($keyboardLayout -match '华为安全键盘|com.huawei.hmos.inputmethod') {
    & $hdc -t 127.0.0.1:5555 shell uitest uiInput keyEvent Back
  }
} else { & $hdc -t 127.0.0.1:5555 shell uitest uiInput click $x $y }
