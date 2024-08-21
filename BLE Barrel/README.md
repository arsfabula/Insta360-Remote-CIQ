```
Insta360 bluetooth protocol description (partial):
Partial 'cause there still lot of work to be done.

With CIQ, BT messages are limited to 20 bytes in length. Longer messages must be sent in 20 bytes segments.

Byte position: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16
Description:   LL LL 00 00 04 00 00 XX 00 02 SS SS 00 80 00 00 PB

LLLL = Length of message, can be split into several packets. Max length for 1 packet is 20 bytes. Little endian. 
XX = Command 
SSSS = Sequence Number little endian
PB = Start of Protobuf 
Byte 4 is always 04 except for "keep alive" messages (05)

XX Byte 7: command to camera
  00 Keep Alive (7 bytes, empty, byte 4 = 05 instead of 04)
  03 photo
  04 start last byte (17) = 01 (Normal), 02 (Bullet), 03 (HDR), 06 (Loop)
  05 stop
  07 reset / set defauls 10682
  08 status request ?
  09 Settings, byte 24,25,26
      0a 18 02 Time Lapse
      0a 18 07 5k30fps
      0b 18 07 4k30fps ?
      0c 18 07 4k50fps
      0d 18 04 Bullet 
      0d 18 07 3k100fps
      13 18 07 5k25fps
      14 18 07 5k24fps 
      13 18 09 hdr 25fps
  0f Apply Settings
  16 Interval photo & video ? byte 18 = 0x01 (video) & 0x02 (photo)
  17 Stop TimeLapse & Interval byte 17 = 0x08 instead if 0x10 in standard video
  27 
  35 GPS Telemetry
  3c time highlight & "mark that" highlight
  41 X3 ? 
  42 X3 Status request ?
  
XX from camera:
  00 Keep Alive (7 bytes, empty, byte 4 = 05 instead of 04)
  06 saving ? 
  10 recording started or ended see Byte 18. >0 = start. 0=end.
  12 interval photo taken, byte 18 = Seq No
  0a photo taken (1 per file in case of burst / braketing / interval etc)
  C8 OK ? File name ?
  f4 error (camera is busy)

Video GPS Telemetry  All Little endian
00-15 47 00 00 00 04 00 00 35 00 02 ff 00 00 80 00 00
16-17 0a 35 Protobuf Header
18-21 UX Epoch - 32bit integer
22-25 00 00 00 00 
26-28 00 e6 03 41 ?
29-36 Latitude   - 64bit float
37 	  N / S  - ASCII
38-45 Longitude  - 64bit float
46 	  E / W  - ASCII
47-54 Speed m/s  - 64bit float
55-62 Heading    - 64bit float
63-70 Altitude M - 64bit float

Wireshark fitler: btatt.value contains 0004.0000
Search for 0004.0000.0900 (set video mode)
Search for 00122a00 (BT write request)
```
