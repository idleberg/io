# io

A macOS menu bar utility that routes audio from a selected input device to a selected output device — inspired by the discontinued [Line In](https://rogueamoeba.com/freebies/) by Rogue Amoeba.

## Features

- Select any audio input and output device
- Listen toggle to start or stop routing
- Input gain control from −40 dB to +20 dB
- Stereo level meters with peak hold, flanking the Listen button
- Launch at Login
- Responds to device plug/unplug and sleep/wake events

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (for building)

## Build

```sh
make build
```

Or with Xcode:

```sh
xcodebuild -scheme io -configuration Release
```

## License

[The MIT License](LICENSE) - Feel free to use, modify, and distribute this code.
