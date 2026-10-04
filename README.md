# X5Tune

Read-only Xiaomi Electric Scooter 5 Plus BLE/GATT inspection app.

## Safety boundary

This build contains no BLE write path and does not flash firmware or modify scooter configuration. It scans, connects, enumerates GATT services/characteristics, reads readable characteristics, enables notifications/indications, logs received values, and exports a BLE snapshot.

The snapshot is not a firmware/NVM backup.

## Windows-only build/install path

GitHub Actions supplies the temporary macOS/Xcode build environment. The workflow deliberately produces an unsigned IPA. On Windows, AltServer can then sign and sideload that IPA using the user's Apple Account.

Do not put an Apple password, certificate, or provisioning profile in this repository.
