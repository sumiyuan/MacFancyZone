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
panel shows an orange **Accessibility permission needed** banner with an
**Open Settings** button.

## Using it

- **Snap a window:** hold **Shift** while dragging a window by its title bar.
  The zones of the monitor under the cursor appear; drop the window on one to
  snap it there. Release Shift before dropping to move it normally.
- **Menu bar panel:** click the menu bar icon to open the panel (click away
  or press **Esc** to close it). It shows six layout tiles for the monitor
  under the pointer; with more than one monitor, a picker switches monitors.
  Click a tile to make it that monitor's layout (the active one is outlined in
  blue); the tiles stay where they are when you pick one. Tiles show your
  favourites first, then the layouts you saved or picked most recently on that
  monitor. **＋ New layout** and **Edit current…** open the
  layout editor, and the **Window Switcher** and **Launch at Login** switches
  turn those features on or off.
- **All Layouts window:** **All layouts…** in the panel lists every layout.
  Click the star to make a layout a favourite (up to six), which pins it to
  the front of the panel. Use the pencil to rename a layout and the trash to
  delete it (after confirming). **＋ New Layout** opens the editor on the
  monitor the window is on. **Restore Starter Presets** brings back any
  deleted starter presets. The layout open in the editor can't be renamed or
  deleted until the editor closes.
- **Layout editor:** click a zone to split it side by side; Shift-click to
  stack it top and bottom. Drag a divider handle to resize. Right-click a
  divider between two plain (unsplit) zones to merge them. Set the name,
  spacing, and outer gap in the toolbar, then **Save**; **Esc** or **Cancel**
  discards the changes.
- **Window switcher:** press **Option+Tab** to list your windows, most recent
  first. Keep holding Option and tap **Tab** to move down (**Shift+Tab** to move
  up), then release Option to switch to the highlighted window. **Esc**
  cancels, and clicking a row switches to it. It lists the windows on the
  current desktop, plus minimized windows and hidden apps' windows. Turn it
  off or on with **Window Switcher** in the menu bar panel.

## Signing

macOS ties the Accessibility grant to the app's code signature. An ad-hoc
signature (`codesign -s -`) is just a hash of the binary, so every rebuild
would look like a different app and the grant would be lost.

Instead, `scripts/create-signing-cert.sh` creates a self-signed code-signing
certificate named **MacPowertools Local Signing** in your login keychain, and
`scripts/build-app.sh` signs every build with it. The app's designated
requirement then pins that certificate and the bundle ID
`com.sumiyuan.MacPowertools`. The grant surviving rebuilds relies on that
requirement staying the same from build to build. Check it with:

```sh
codesign -d -r- build/MacPowertools.app
```

The output should contain `certificate leaf = H"..."` (and the bundle ID). If it
doesn't, or the grant is lost after a rebuild anyway, reset the grant,
relaunch, and grant it again:

```sh
tccutil reset Accessibility com.sumiyuan.MacPowertools
```

The certificate is only used locally and doesn't need to be trusted. The
script is safe to run again; it does nothing if the identity already exists.

## Troubleshooting

- **The permission banner stays in the panel after granting access**, or snapping
  does nothing: the grant may belong to an older signature (for example, if
  you recreated the certificate). Reset it, relaunch, and grant it again:

  ```sh
  tccutil reset Accessibility com.sumiyuan.MacPowertools
  ```

- **`build-app.sh` says the signing identity wasn't found**: run
  `scripts/create-signing-cert.sh`.
