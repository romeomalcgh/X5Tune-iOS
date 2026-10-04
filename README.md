# X5Tune

Read-only Xiaomi Electric Scooter 5 Plus BLE/GATT research workbench.

## Safety boundary

X5Tune exposes no BLE write path. It does not flash firmware, update firmware, reset the scooter, modify controller parameters, change regions, remove speed limits, or enable zero-start.

It can scan/connect, enumerate GATT services and characteristics, read readable characteristics, explicitly subscribe/unsubscribe to notifications/indications, capture received bytes, correlate packets against observation baselines, show byte-level diffs, and export research reports.

## Research features

- Safe stationary test profiles for brake, power, lights, lock state, battery, charging state, and passive baselines.
- Timestamped observation markers.
- Raw RX packet capture.
- Automatic packet correlation against a pre-action baseline.
- Byte-level packet diffs.
- Per-characteristic research notes/knowledge base.
- Theoretical simulator for zero-start, speed limit, acceleration curve, and region profile concepts. Simulator values are display-only and cannot reach the scooter.
- Copyable research report designed to be pasted into ChatGPT.
- JSON research-session, CSV packet, and HTML report export.

## Current known observation

The Xiaomi 5 Plus test unit has previously exposed the FE95 service. Characteristic 0004 returned APP firmware 2.7.0_0039. Characteristic 0005 and several other characteristics exposed NOTIFY capability. These observations are treated as evidence to test further, not as proof of protocol meaning.

## Build

GitHub Actions supplies the temporary macOS/Xcode build environment. The workflow deliberately produces an unsigned IPA. On Windows, AltServer can sign and sideload the IPA using the user's Apple Account.

Do not put an Apple password, certificate, or provisioning profile in this repository.

## Principle

Observe first. Hypothesize second. Never blindly write.
