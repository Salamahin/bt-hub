# BT Hub

A menu bar app that shows where each of your Bluetooth audio devices is connected — this Mac or another one on
the same network — and moves or disconnects them with one click.

- Lists every paired Bluetooth audio device (headphones, speakers, headsets); nothing is hard-coded.
- **Connect / Move** connects a device to the chosen Mac; every other Mac lets go of it first.
- **Disconnect** drops it from one Mac, **Disconnect everywhere** from all of them.
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
