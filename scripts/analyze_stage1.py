#!/usr/bin/env python3
"""Stage 1 analysis: does RSSI separate a held/moving beacon from resting ones?

Loads all session CSVs from data/stage1/, filters to BCPro_* beacons,
plots RSSI vs. time per session, and prints per-beacon stats. For the
held_* sessions, computes the gap between the held beacon's mean RSSI
and each resting beacon's mean, using the at_rest_baseline session's
per-beacon std as the noise reference.

Usage: python scripts/analyze_stage1.py
"""

import glob
import os
import re
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "stage1")
OUT_DIR = os.path.join(DATA_DIR, "analysis")

BASELINE_LABEL = "at_rest_baseline"
BEACON_PREFIX = "BCPro_"
WINDOW_S = 2.0  # windowed-mean width; ~20 samples per beacon at 100 ms adv interval
# held_<beacon id>, optionally followed by a trial suffix, e.g. held_213902_test_2
HELD_LABEL_RE = re.compile(r"^held_(\d+)")


def held_beacon_name(session_label):
    """Beacon name a held_* session label refers to, or None."""
    match = HELD_LABEL_RE.match(session_label)
    return BEACON_PREFIX + match.group(1) if match else None


def load_sessions(data_dir):
    """Return {session_label: DataFrame of BCPro_* rows} for every session CSV."""
    sessions = {}
    for path in sorted(glob.glob(os.path.join(data_dir, "*.csv"))):
        df = pd.read_csv(path)
        expected = {"timestamp_ms", "peripheral_id", "name", "rssi", "session_label"}
        if not expected.issubset(df.columns):
            print(f"skipping {os.path.basename(path)}: unexpected columns")
            continue
        label = df["session_label"].iloc[0]
        beacons = df[df["name"].str.startswith(BEACON_PREFIX, na=False)].copy()
        if beacons.empty:
            print(f"skipping {os.path.basename(path)} ({label}): no {BEACON_PREFIX}* rows")
            continue
        beacons["t_s"] = (beacons["timestamp_ms"] - beacons["timestamp_ms"].min()) / 1000.0
        sessions[label] = beacons
    return sessions


def windowed_means(df):
    """Per-beacon mean RSSI in WINDOW_S-wide time windows.

    Returns a DataFrame indexed by window start time (s), one column per
    beacon; NaN where a beacon had no samples in a window.
    """
    df = df.assign(window=(df["t_s"] // WINDOW_S) * WINDOW_S)
    return df.groupby(["window", "name"])["rssi"].mean().unstack()


def plot_session(label, df, out_dir):
    fig, ax = plt.subplots(figsize=(12, 6))
    windows = windowed_means(df)
    for name, group in df.groupby("name"):
        held = name == held_beacon_name(label)
        (raw_line,) = ax.plot(
            group["t_s"],
            group["rssi"],
            marker=".",
            markersize=2,
            linewidth=0.4,
            alpha=0.35,
            zorder=3 if held else 2,
        )
        ax.plot(
            windows.index + WINDOW_S / 2,
            windows[name],
            color=raw_line.get_color(),
            linewidth=2.2,
            label=f"{name} (held)" if held else name,
            zorder=5 if held else 4,
        )
    ax.set_xlabel("time (s)")
    ax.set_ylabel("RSSI (dBm)")
    ax.set_title(f"Session: {label}")
    ax.legend()
    ax.grid(True, alpha=0.3)
    out_path = os.path.join(out_dir, f"{label}.png")
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return out_path


def session_stats(sessions):
    """Per-beacon, per-session stats as a single DataFrame."""
    rows = []
    for label, df in sessions.items():
        for name, group in df.groupby("name"):
            rows.append(
                {
                    "session": label,
                    "beacon": name,
                    "n": len(group),
                    "mean": group["rssi"].mean(),
                    "std": group["rssi"].std(),
                    "min": group["rssi"].min(),
                    "max": group["rssi"].max(),
                }
            )
    return pd.DataFrame(rows)


def held_gaps(stats, baseline_std):
    """For each held_* session: held beacon mean minus each resting beacon mean.

    Gap is also expressed in units of the resting beacon's baseline std
    (noise reference) — higher means cleaner separation.
    """
    rows = []
    for label in stats["session"].unique():
        held_name = held_beacon_name(label)
        if held_name is None:
            continue
        session = stats[stats["session"] == label].set_index("beacon")
        if held_name not in session.index:
            print(f"warning: {label} has no rows for {held_name}")
            continue
        held_mean = session.loc[held_name, "mean"]
        for name, row in session.iterrows():
            if name == held_name:
                continue
            gap = held_mean - row["mean"]
            noise = baseline_std.get(name)
            rows.append(
                {
                    "session": label,
                    "held": held_name,
                    "resting": name,
                    "held_mean": held_mean,
                    "resting_mean": row["mean"],
                    "gap_db": gap,
                    "baseline_std": noise,
                    "gap_over_noise": gap / noise if noise else float("nan"),
                }
            )
    return pd.DataFrame(rows)


def windowed_separation(sessions):
    """Per held session: windowed held mean vs. the strongest resting beacon.

    A window "separates" when the held beacon's windowed mean exceeds the
    max windowed mean across resting beacons. Reports the per-window gap
    distribution — min/median and % of windows separated — i.e. how a
    simple windowed-mean classifier would have done.
    """
    rows = []
    for label, df in sessions.items():
        held_name = held_beacon_name(label)
        if held_name is None:
            continue
        windows = windowed_means(df)
        if held_name not in windows.columns:
            continue
        resting = windows.drop(columns=held_name)
        gap = (windows[held_name] - resting.max(axis=1)).dropna()
        if gap.empty:
            continue
        rows.append(
            {
                "session": label,
                "windows": len(gap),
                "gap_min": gap.min(),
                "gap_median": gap.median(),
                "gap_max": gap.max(),
                "pct_separated": 100.0 * (gap > 0).mean(),
            }
        )
    return pd.DataFrame(rows)


def main():
    sessions = load_sessions(DATA_DIR)
    if not sessions:
        sys.exit(f"no usable session CSVs in {DATA_DIR}")
    os.makedirs(OUT_DIR, exist_ok=True)

    for label, df in sessions.items():
        path = plot_session(label, df, OUT_DIR)
        print(f"wrote {os.path.relpath(path)}")

    stats = session_stats(sessions)
    print("\n=== Per-beacon, per-session stats ===")
    print(
        stats.to_string(
            index=False,
            float_format=lambda v: f"{v:.1f}",
            formatters={"mean": "{:.1f}".format, "std": "{:.2f}".format},
        )
    )

    if BASELINE_LABEL not in sessions:
        print(f"\nno {BASELINE_LABEL} session found — skipping gap analysis")
        return
    baseline = stats[stats["session"] == BASELINE_LABEL].set_index("beacon")["std"]

    gaps = held_gaps(stats, baseline)
    if gaps.empty:
        print("\nno held_* sessions found — skipping gap analysis")
        return
    print("\n=== Held vs. resting mean RSSI gaps ===")
    print("(gap_over_noise = gap / resting beacon's std in the baseline session)")
    print(
        gaps.to_string(
            index=False,
            formatters={
                "held_mean": "{:.1f}".format,
                "resting_mean": "{:.1f}".format,
                "gap_db": "{:+.1f}".format,
                "baseline_std": "{:.2f}".format,
                "gap_over_noise": "{:+.1f}".format,
            },
        )
    )

    windowed = windowed_separation(sessions)
    print(f"\n=== Windowed-mean separation ({WINDOW_S:.0f}s windows) ===")
    print("(gap = held windowed mean - strongest resting windowed mean, per window)")
    print(
        windowed.to_string(
            index=False,
            formatters={
                "gap_min": "{:+.1f}".format,
                "gap_median": "{:+.1f}".format,
                "gap_max": "{:+.1f}".format,
                "pct_separated": "{:.0f}%".format,
            },
        )
    )


if __name__ == "__main__":
    main()
