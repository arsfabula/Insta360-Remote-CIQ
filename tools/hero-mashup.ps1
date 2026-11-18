# hero-mashup.ps1 — banniere 1440x720 : cascade de cadrans, partie gauche conservee
$d = "C:\Users\greg\git\int-x5\docs\Screenshots"
$order = @('Connecting.png','Starting.png','Recording.png','Main+settings.png','Menu.png','Main.png')
$out = Join-Path $d 'hero-1440x720.png'

Add-Type -AssemblyName System.Drawing

$Wc = 1440; $Hc = 720
$cv = New-Object System.Drawing.Bitmap($Wc, $Hc, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($cv)
$g.Clear([System.Drawing.Color]::Transparent)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$side = $Hc                               # chaque cadran a la hauteur pleine (720)
$pitch = [int](($Wc - $side) / ($order.Count - 1))   # pas = 144 : chacun montre sa gauche, recouvert a droite
"pas = $pitch px, cadran = $side px"

$i = 0
foreach ($name in $order) {
  $img = [System.Drawing.Image]::FromFile((Join-Path $d $name))
  $g.DrawImage($img, [int]($i * $pitch), 0, $side, $side)   # dessine par-dessus le precedent : le recouvre a droite
  $img.Dispose()
  "  couche $i : $name en x=$($i*$pitch)"
  $i++
}
$g.Dispose()
$cv.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$cv.Dispose()
"sauve: $out  $((Get-Item $out).Length) octets"
