# BeaconScanner

BeaconScanner is an iPhone and Apple Watch proof of concept for detecting which piece of workout equipment is being used by measuring Bluetooth Low Energy (BLE) signal strength.

The original product idea was dumbbell weight tracking. Each dumbbell could carry a small BLE beacon, and a device worn on the wrist could infer which dumbbell was in the user's hand. That would create the foundation for automatically identifying the active weight during a workout without requiring the user to manually log every set.

This repository contains the prototype app, the Apple Watch companion app, the raw experiment data, and the first-pass analysis.

## The hypothesis

If each dumbbell has a distinct BLE beacon, the beacon on the dumbbell in the user's hand should usually have a stronger RSSI signal than the beacons on dumbbells resting nearby.

In other words:

> When a user picks up one dumbbell, the beacon attached to that dumbbell should become measurably stronger relative to the beacons that remain at rest.

The important product question was not whether a BLE signal can be detected. It was whether the signal contains enough information to distinguish **the dumbbell currently in use** from **the dumbbells sitting nearby**.

## Why test this?

Automatic weight tracking could remove a meaningful amount of friction from strength training. A successful system could eventually:

- Identify which weight a user picked up.
- Detect when a set begins and ends.
- Associate the active weight with movement or rep data.
- Build a more complete workout history without requiring manual input.
- Give athletes and coaches better information about training load and progression.

The first experiment intentionally focused on the smallest useful technical question: can proximity to the user's wrist create a reliable enough signal difference to identify the active dumbbell?

This was a discovery prototype, not a finished workout-tracking product. It tested the sensing primitive that a larger product would depend on.

## How the prototype worked

### BLE beacons

The experiment used multiple BLE beacons with names beginning with `BCPro_`. Each beacon represented a different piece of equipment. The prototype did not need to connect to the beacons as peripherals; it continuously scanned for advertisements and recorded the received signal strength indicator (RSSI) for every observation.

RSSI is reported in dBm. Values closer to zero generally indicate a stronger received signal. For example, `-50 dBm` is stronger than `-75 dBm`.

RSSI is only a noisy proxy for distance. It is affected by orientation, the human body, furniture, radio interference, reflections, and many other environmental factors. The experiment therefore treated RSSI as a signal to investigate, not as a direct measurement of distance.

### iPhone app

The iPhone app is built with SwiftUI and CoreBluetooth. It:

1. Scans for nearby BLE devices.
2. Allows duplicate advertisements so that signal strength can be tracked over time.
3. Displays discovered devices and their current RSSI.
4. Optionally filters the interface to devices whose names begin with `BCPro_`.
5. Writes every observation to a session CSV.
6. Exports the most recent session through the iOS share sheet.

The phone-side scanner uses a dedicated Bluetooth callback queue and a thread-safe device store. The UI refreshes from a snapshot several times per second rather than trying to update SwiftUI state directly from every BLE callback.

### Apple Watch app

The Apple Watch app was the more important product direction because a watch is naturally positioned near the user's hand.

It:

1. Scans for the same `BCPro_` beacons using CoreBluetooth.
2. Displays the currently visible beacons and their RSSI values.
3. Logs the same timestamped observations to CSV.
4. Starts a HealthKit workout session while scanning.
5. Uses the workout session to reduce the likelihood that the watch stops doing work with the user's wrist down.
6. Transfers the finished CSV to the paired iPhone using WatchConnectivity.

The iPhone receives the transferred file, stores it in Documents, and exposes it through the same export flow as a phone-recorded session.

### Data pipeline

Every recorded row has the following schema:

```text
timestamp_ms,peripheral_id,name,rssi,session_label
```

- `timestamp_ms`: Unix timestamp in milliseconds.
- `peripheral_id`: UUID observed for the BLE peripheral.
- `name`: Advertised or resolved device name.
- `rssi`: Received signal strength in dBm.
- `session_label`: Human-readable label for the test session.

The analysis filters to devices beginning with `BCPro_`, calculates per-beacon summary statistics, and plots both raw RSSI observations and two-second windowed means.

## Experimental design

The staged experiment included:

- `at_rest_baseline`: all beacons resting in the test environment.
- `held_213902`: beacon `BCPro_213902` held while the other beacons remained at rest.
- `held_213902_test_2`: a second trial holding `BCPro_213902`.
- `held_214160`: beacon `BCPro_214160` held while the others remained at rest.
- `curls_openmount_8lbs`: a workout-style movement session with an eight-pound open-mount curl setup.
- `validate_adv_internval_100ms`: a validation session for a faster advertisement interval.
- `watch_baseline`: watch-based baseline sessions.

The main analysis used two-second windows. In each window, the held beacon was compared with the strongest resting beacon. A window counted as separated when the held beacon's mean RSSI was stronger than the strongest resting beacon's mean RSSI.

## Results

### Controlled separation worked

The experiment demonstrated that the core idea can work in a contained environment.

The at-rest baseline means were:

| Beacon | Mean RSSI | Baseline standard deviation |
| --- | ---: | ---: |
| `BCPro_213902` | -71.7 dBm | 6.89 dB |
| `BCPro_214160` | -70.2 dBm | 6.28 dB |
| `BCPro_214250` | -72.4 dBm | 5.70 dB |

When `BCPro_213902` was held, the first trial produced only a modest average advantage over the resting beacons: approximately 3.1–3.9 dB. However, the second trial was much cleaner:

- Median two-second separation: **9.0 dB**
- Percentage of two-second windows separated: **100%**
- Maximum observed windowed separation: **24.9 dB**

When `BCPro_214160` was held:

- Median two-second separation: **15.7 dB**
- Percentage of two-second windows separated: **100%**
- Minimum observed windowed separation: **9.8 dB**
- Maximum observed windowed separation: **25.3 dB**

Across these contained trials, the held beacon was clearly distinguishable from the resting beacons often enough to support the original hypothesis. The result is particularly encouraging because the classifier only used a simple windowed RSSI comparison; it did not use a sophisticated model.

### The result was not uniformly clean

The first `held_213902` trial was weaker:

- Median two-second separation: **2.1 dB**
- Percentage of windows separated: **86%**
- Minimum windowed separation: **-1.9 dB**

That trial shows why this should not be described as a solved problem. The signal can be strong enough to separate the active dumbbell, but the margin depends on positioning and conditions. A real product would need to handle noisy windows, temporary reversals, and potentially indistinguishable signal values.

The curls session also produced substantially stronger signals for all three beacons, which reinforces that the environment and body position materially affect RSSI. It is useful evidence that the signal changes during movement, but it is not by itself proof that the system can identify every individual rep or every active dumbbell in an arbitrary gym.

### Watch reliability was the main blocker

The watch was the intended sensing platform, but watch data collection was not yet reliable enough for a real-world product.

The repository contains two watch baseline sessions with different outcomes:

- One watch baseline session contained **no `BCPro_` rows** after filtering.
- Another watch baseline session did capture all three `BCPro_` beacons.

This inconsistency is important. The contained RSSI result shows that the sensing concept has promise, but a consumer product needs dependable data collection every time. If the watch drops scanning, stops transferring data, or fails to keep the session alive with the wrist down, the product cannot reliably infer what happened during the workout.

The prototype attempted to address this with a HealthKit workout session and background file transfer, but the problem was not fully solved. The next iteration would need to treat watch continuity, session lifecycle, and data completeness as first-class product and engineering requirements.

## What the experiment established

The experiment established that:

1. Multiple nearby BLE beacons can be observed and logged continuously from iPhone and Apple Watch.
2. In a contained setup, the beacon on the held dumbbell can be stronger than the beacons resting nearby.
3. Simple time-windowed RSSI comparisons can separate held and resting beacons in favorable trials.
4. The signal is noisy and sensitive to the physical setup.
5. Watch continuity and reliability were the largest practical obstacle.

## What it did not establish

The prototype did not yet establish that it can:

- Reliably identify the active dumbbell in every gym environment.
- Count repetitions.
- Detect set boundaries.
- Distinguish every movement from every other movement.
- Infer exact distance or weight from RSSI alone.
- Run continuously without watch dropouts.
- Replace a production-grade workout tracker.

Those are follow-on questions, not results claimed by this repository.

## Product path from here

The most useful next steps would be:

### 1. Make data collection trustworthy

- Measure session completeness and transfer success explicitly.
- Detect when the watch stops producing beacon observations.
- Add clear recovery behavior when Bluetooth, HealthKit, or WatchConnectivity fails.
- Test wrist-down scanning over full workout durations.

### 2. Repeat the experiment at realistic scale

- Test different wrist positions, grips, and body orientations.
- Test multiple dumbbell spacings.
- Test different rooms, floors, and gym layouts.
- Test interference from other Bluetooth devices.
- Repeat trials across users rather than relying on a single contained setup.

### 3. Build a more robust inference layer

- Smooth RSSI without hiding meaningful transitions.
- Use hysteresis so a brief noisy reversal does not switch the active dumbbell.
- Require a confidence threshold before changing the inferred weight.
- Combine RSSI with time, motion, and workout-state information.
- Log ground-truth labels for every pickup, set, and replacement event.

### 4. Validate the product behavior

The real test is not whether a graph looks separated. It is whether a user can complete a workout without thinking about the system and receive an accurate training log afterward. That requires measuring false switches, missed pickups, delayed detection, battery impact, and user trust—not just average RSSI gaps.

## Repository structure

```text
BeaconScanner/
├── BeaconScanner/              # iPhone SwiftUI app
├── BeaconScannerWatch/         # Apple Watch companion app
├── Shared/                     # CSV logging and thread-safe device storage
├── data/stage1/                # Raw staged experiment CSVs
│   └── analysis/               # Generated plots from the analysis script
├── scripts/analyze_stage1.py   # RSSI statistics and visualization
└── BeaconScanner.xcodeproj/    # Xcode project
```

## Running the analysis

From the repository root:

```bash
python3 scripts/analyze_stage1.py
```

The script filters the raw CSVs to `BCPro_` devices, writes per-session RSSI plots to `data/stage1/analysis/`, and prints:

- Per-beacon sample counts and RSSI statistics.
- Held-versus-resting mean gaps.
- Gaps relative to baseline noise.
- Two-second windowed separation results.

## Running the app

Open `BeaconScanner.xcodeproj` in Xcode and select a configured iPhone or Apple Watch target. The app requires Bluetooth permissions. The watch target also requests HealthKit workout permissions so it can attempt to keep scanning active while the user's wrist is down.

This project is a research and product-discovery prototype. It is best understood as evidence about a promising sensing approach, alongside a clear demonstration that reliability and real-world validation still need work.
