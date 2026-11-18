# Car Video – MP4 + YouTube on CarPlay (parked only)

A test app for watching video on the car screen while parked.

**iPhone**
- **My Videos** tab: add MP4/MOV files from the Files app (+ button), tap to play.
  The AirPlay button (top left) sends the video to the car screen.
- **YouTube** tab: paste a YouTube link and it plays in YouTube's official player.
  Tap the AirPlay icon inside the player to send it to the car.

**CarPlay**
- Shows a list of your MP4s. Tap one → it plays and opens the Now Playing screen
  (play/pause, skip ±15 s, progress bar).
- In a car that supports CarPlay video, the picture goes to the car screen when parked.
  In other cars you hear the sound only.

## How video gets to the car

- **iOS 26 and later:** AirPlay video to CarPlay, parked only, *if your car maker turned it on*.
  This app has AirPlay switched on, so it works with no extra code.
- **iOS 27:** Apple added full "CarPlay video apps" (browse videos on the car screen).
  These need a separate **CarPlay video entitlement** from Apple. You can request it at
  https://developer.apple.com/carplay/ . The new iOS 27 browsing screens are not in this
  version yet. Add them once you have the entitlement and the iOS 27 SDK docs.
- **YouTube on the CarPlay list:** not possible. YouTube videos can only be played in
  YouTube's own player, so they can't appear in the CarPlay list. AirPlay from the
  YouTube tab is the only way, and whether it reaches the car screen depends on YouTube and your car.

## Run it (needs a Mac with Xcode)

1. Xcode → File → New → Project → iOS → App. Name: `CarVideo`, Interface: SwiftUI,
   Language: Swift. Set **Minimum Deployment to iOS 17** or later.
2. Delete Xcode's own `ContentView.swift` and `CarVideoApp.swift`, then drag every
   `.swift` file from the `CarVideo` folder into the project.
3. **Info.plist:** set Build Settings → *Info.plist File* to `CarVideo/Info.plist`
   (or copy the keys into the target's Info tab).
4. **Entitlements:** add `CarVideo.entitlements` to the project and set Build Settings →
   *Code Signing Entitlements* to `CarVideo/CarVideo.entitlements`.
5. Run on an iPhone simulator. Then choose Simulator menu → **I/O → External Displays → CarPlay**.
   For testing video, use Apple's **CarPlay Simulator** (in "Additional Tools for Xcode").

### Getting MP4s into the app
- Tap **+** in My Videos and pick files, or
- Files app → On My iPhone → CarVideo → Videos, or
- Mac Finder → your iPhone → Files → CarVideo.

## Real phone / real car

You need an Apple Developer account ($99/year), and Apple must approve the CarPlay
entitlement for your app before it shows up in a real car.
