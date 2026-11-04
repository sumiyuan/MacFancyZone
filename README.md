<img src="assets/icon.svg" width="64" height="64" alt="">

# MacPowertools

Created in [T3 Code](https://t3.codes).

A macOS menu bar app that snaps windows into zones, in the style of
FancyZones. It has a menu bar icon and no Dock icon.

## Build

Requires macOS 14 or newer and the Command Line Tools (Xcode isn't needed).

```sh
scripts/create-signing-cert.sh   # one time only
scripts/build-app.sh             # builds and signs build/MacPowertools.app
open build/MacPowertools.app
```

On first launch the app asks for the Accessibility permission, which it needs
to move and resize other apps' windows. Choose **Open System Settings** and turn
on MacPowertools under **Privacy & Security > Accessibility**. Until then, the
menu shows **Accessibility permission needed…**.

## Signing

macOS ties the Accessibility grant to the app's code signature. An ad-hoc
signature (`codesign -s -`) is just a hash of the binary, so every rebuild
would look like a different app and the grant would be lost.

Instead, `scripts/create-signing-cert.sh` creates a self-signed code-signing
certificate named **MacPowertools Local Signing** in your login keychain, and
`scripts/build-app.sh` signs every build with it. The app's designated
requirement then pins that certificate and the bundle ID
`com.sumiyuan.MacPowertools`, so the grant survives rebuilds. You can check it
with:

```sh
codesign -d -r- build/MacPowertools.app
```

The certificate is only used locally and doesn't need to be trusted. The
script is safe to run again; it does nothing if the identity already exists.

## Troubleshooting

- **The permission item stays in the menu after granting access**, or snapping
  does nothing: the grant may belong to an older signature (for example, if
  you recreated the certificate). Reset it, relaunch, and grant it again:

  ```sh
  tccutil reset Accessibility com.sumiyuan.MacPowertools
  ```

- **`build-app.sh` says the signing identity wasn't found**: run
  `scripts/create-signing-cert.sh`.
