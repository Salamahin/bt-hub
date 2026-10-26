# BT Hub

A menu bar app that shows where each of your Bluetooth audio devices is connected — this Mac or another one on
the same network — and moves or disconnects them with one click.

- Lists every paired Bluetooth audio device (headphones, speakers, headsets); nothing is hard-coded.
- A device is on one Mac at a time. **Connect / Move** connects it to the chosen Mac; every other Mac lets go of it
  first. If a multipoint device connects to two Macs by itself, the Mac it was last moved to — or the one that had
  it first — keeps it and the others let go.
- **Disconnect** drops it from a Mac.
- Macs find each other over Bonjour. They talk over TLS 1.2 with a pre-shared key: a device without the key can
  neither read the traffic nor send commands. The key lives in the login keychain.
- English and Russian, following the system language.

## Install

```sh
brew install salamahin/tap/bt-hub
brew services start bt-hub        # start now and at every login
```

Then open **Settings…** from the menu bar icon: create a key on the first Mac and enter the same key on the others.
macOS asks for Bluetooth and local network access on first launch (and again after an upgrade, since the app is
signed locally).

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
swift test
scripts/build-app.sh --install    # builds "BT Hub.app" and copies it to ~/Applications
```
