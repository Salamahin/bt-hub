# BT Hub

A menu bar app that shows, Mac by Mac, which Bluetooth audio devices are connected where — and moves or
disconnects them with one click.

- The panel lists each Mac on your network with the Bluetooth audio devices paired to it (headphones, speakers,
  headsets); nothing is hard-coded.
- A device is on one Mac at a time. **Connect** connects a free device; **Move here** takes it from the Mac that has it. If a multipoint device connects to two Macs by itself, the Mac it was last moved to — or the one that had
  it first — keeps it and the others let go. **Disconnect** drops it from a Mac.
- **Adding a Mac**: install BT Hub on it and press **Join** next to a Mac already in the network. Both Macs show
  the same six-digit code; allow the join on the member and the network key travels over, encrypted (X25519 key
  agreement, the code rules out a man in the middle). The key can also be copied or shared as a link in Settings.
- Members talk over TLS 1.2 with that pre-shared key: a device without it can neither read the traffic nor send
  commands. The key lives in `~/Library/Application Support/BT Hub/network-key`, readable only by your user.
- English and Russian, following the system language.

## Install

```sh
brew install salamahin/tap/bt-hub
brew services start bt-hub        # start now and at every login
```

Install it on every Mac, then on each new one press **Join** next to a Mac that already runs it.
macOS asks for Bluetooth and local network access on first launch (Bluetooth again after an upgrade, since the
app is signed locally).

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
swift test
scripts/build-app.sh --install    # builds "BT Hub.app" and copies it to ~/Applications
```
