# Docs

* [`x5-protocol.md`](x5-protocol.md): Insta360 X5 remote-control protocol over BLE and Wi-Fi:
  framing, modes, capture, footage settings, status, notifications, Connect IQ limits. Each command
  is marked by how it was verified.
* [`watch-app.md`](watch-app.md): how the Garmin watch app maps onto the protocol, and confirmed
  features that are ready to add.
* [`tools.md`](tools.md): the BLE session, survey, test and settings tools, plus Wi-Fi and watch
  helpers.
* [`data/`](data/): generated results for camera firmware v1.13.21: the full command / option
  survey and the camera's own mode catalog.

Results from other cameras or firmware versions are welcome: run `tools/x5_probe.py` and
`tools/x5_report.py` and add the output under `data/` with the firmware version in the file name.
