\ M21: USB HID boot-protocol decoders + report ring (offline unit test)
load usbhid.fth
usb-init .
create r1 8 allot
create r2 8 allot
2 r1 c! 0 r1 1+ c! 4 r1 2 + c!
r1 kbd-decode . .
1 r2 c! 5 r2 1+ c! 253 r2 2 + c!
r2 mouse-decode . . .
r1 usb-push
r2 usb-push
usb-buf usb-pop .
usb-buf kbd-decode . .
usb-buf usb-pop .
usb-buf mouse-decode . . .
usb-buf usb-pop .
keyusb .
." M21-DONE" cr
