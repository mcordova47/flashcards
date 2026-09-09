// The QR decoder, bundled on its own and fetched only when someone taps Scan
// on a browser without `BarcodeDetector` — Safari, mostly, which is exactly
// where an iPhone needs it.
//
// It is 47 KB gzipped against a 135 KB app, for something used once per
// device, so precaching it would be a third more to install for a feature
// most launches never touch. Pairing needs the network anyway.
import jsQR from "jsqr"

window.__jsQR = jsQR
