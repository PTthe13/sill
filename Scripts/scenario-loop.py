#!/usr/bin/env python3
"""Every scenario, over and over, checking the app rather than trusting it."""
import itertools, json, os, random, subprocess, sys, time

APP = "/Users/pt/Documents/PROJECTOS/Sill/build/Sill.app/Contents/MacOS/Sill"
DOM = "app.sill.Sill"
FW, FH = 3840.0, 1620.0                 # main display, points
VX, VY, VW, VH = 0.0, 0.0, 3787.0, 1590.0
T, INSET, GUTTER = 76.0, 2.0, 210.0

EDGES = ["right", "left", "top", "bottom"]
RAMPS = ["load", "teal", "amber", "violet", "mono"]
BACKS = ["none", "light", "shade", "glass"]
METRICS = ["cpu", "memory", "gpu", "network", "disk"]
SPANS = [0, 1, 5, 15, 60]
WIDTHS = [0.3, 0.4, 0.6, 1.0]
MATERIALS = ["clear", "tinted"]

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()

def write(key, value, kind="-string"):
    sh(f'defaults write {DOM} {key} {kind} "{value}"')

def reload_():
    sh(f'"{APP}" --reload')
    time.sleep(1.4)

def alive():
    return sh(f'pgrep -f "Sill.app/Contents/MacOS/Sill"') != ""

def windows():
    out, rects = sh(f'"{APP}" --windows'), []
    for line in out.splitlines():
        if "bounds (" in line:
            body = line.split("bounds (")[1].rstrip(")")
            rects.append([float(v) for v in body.split(", ")] + [line.split("layer ")[1].split(" ")[0]])
    return rects

def band_window():
    """The wave window, not the click catcher that sits one level above it."""
    below = [r for r in windows() if r[4].startswith("-")]
    if not below:
        return None
    return min(below, key=lambda r: int(r[4]))[:4]

def expected(edge, frac):
    length = min(VH - 2 * INSET, VH * frac) if edge in ("left", "right") else \
             min(VW - 2 * INSET, VW * frac)
    if edge in ("left", "right"):
        mid = min(max(FH / 2, VY + length / 2), VY + VH - length / 2)
        room = VW - T - INSET
        grow = min(max(0, room), GUTTER)
        x = VX + INSET if edge == "left" else VX + VW - INSET - T
        if edge == "right":
            x -= grow
        return [x, FH - (mid + length / 2), T + grow, length]
    mid = min(max(FW / 2, VX + length / 2), VX + VW - length / 2)
    room = VH - T - INSET
    grow = min(max(0, room), GUTTER)
    y = VY + VH - INSET - T - grow if edge == "top" else VY + INSET
    h = T + grow
    return [mid - length / 2, FH - (y + h), length, h]

fails, checks = [], 0
def check(name, ok, detail=""):
    global checks
    checks += 1
    if not ok:
        fails.append(f"{name}: {detail}")
        print(f"FAIL {name} {detail}", flush=True)

def scenario(edge, ramp, back, area, shape, fill, span, width, material, tag):
    write("edge", edge); write("ramp", ramp); write("background", back)
    write("areaFill", "true" if area else "false", "-bool")
    write("envelopeMetric", shape); write("fillMetric", fill)
    write("spanMinutes", span, "-float"); write("lengthFraction", width, "-float")
    write("material", material)
    reload_()
    if not alive():
        check(f"{tag} alive", False, "process gone")
        return False
    got, exp = band_window(), expected(edge, width)
    check(f"{tag} window", got is not None and all(abs(a - b) <= 2 for a, b in zip(got, exp)),
          f"got {got} expected {[round(v,1) for v in exp]}")
    dump = sh(f'"{APP}" --dump')
    for key, value in (("edge", edge), ("ramp", ramp), ("behind", back if back != "shade" else "shade")):
        if key == "behind":
            continue
        check(f"{tag} applied {key}", value in dump, dump.replace("\n", " | "))
    return True

random.seed(7)
rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 1
start = time.time()
try:
    for round_ in range(rounds):
        # exhaustive over the things that change geometry and drawing
        for edge, back in itertools.product(EDGES, BACKS):
            scenario(edge, random.choice(RAMPS), back, random.choice([True, False]),
                     random.choice(METRICS), random.choice(METRICS),
                     random.choice(SPANS), random.choice(WIDTHS),
                     random.choice(MATERIALS), f"r{round_} {edge}/{back}")
        for ramp in RAMPS:
            scenario(random.choice(EDGES), ramp, "none", False, "cpu", "memory",
                     0, 0.4, "tinted", f"r{round_} ramp/{ramp}")
        for shape, fillm in itertools.product(METRICS, METRICS):
            scenario("right", "load", "none", False, shape, fillm, 0, 0.4, "tinted",
                     f"r{round_} {shape}->{fillm}")
        for span in SPANS:
            scenario("right", "load", "none", False, "cpu", "memory", span, 0.4, "tinted",
                     f"r{round_} span/{span}")
        # open and close on every edge
        for edge in EDGES:
            scenario(edge, "load", "none", False, "cpu", "memory", 0, 0.4, "tinted",
                     f"r{round_} open/{edge}")
            closed = band_window()
            sh(f'"{APP}" --open'); time.sleep(1.8)
            # While open the wave window may be elevated above the catcher, so
            # take the biggest window the app owns rather than the lowest one.
            everything = windows()
            opened = max(everything, key=lambda r: r[2] * r[3])[:4] if everything else None
            # Open means the window grew to hold the panel — whether or not it
            # also came forward, which depends on how much desktop is free.
            grew = opened is not None and closed is not None and (
                opened[2] > closed[2] + 8 or opened[3] > closed[3] + 8)
            check(f"r{round_} open/{edge} grew", grew, f"{closed} -> {opened}")
            sh(f'"{APP}" --close'); time.sleep(1.5)
            check(f"r{round_} open/{edge} alive", alive())
        # displays: one band, a chosen band, every band
        uuids = []
        for line in sh(f'"{APP}" --screens').splitlines():
            for token in line.replace("*", " ").split():
                if len(token) == 36 and token.count("-") == 4:
                    uuids.append(token)
        for uuid in uuids:
            write("displayUUID", uuid); write("showsOnAllDisplays", "false", "-bool")
            reload_()
            check(f"r{round_} display/{uuid[:8]}", alive() and band_window() is not None)
        sh(f"defaults delete {DOM} displayUUID")
        write("showsOnAllDisplays", "true", "-bool"); reload_()
        bands = [r for r in windows() if r[4].startswith("-2147483604")]
        check(f"r{round_} every display", len(bands) == len(uuids),
              f"{len(bands)} bands for {len(uuids)} screens")
        write("showsOnAllDisplays", "false", "-bool"); reload_()
        pid = sh('pgrep -f "Sill.app/Contents/MacOS/Sill" | head -1')
        foot = sh(f"footprint -p {pid} 2>/dev/null | grep phys_footprint: | head -1")
        print(f"round {round_} done, {checks} checks, {len(fails)} failures, "
              f"{time.time() - start:.0f}s, {foot.strip()}", flush=True)
finally:
    for key in ("edge", "ramp", "background", "areaFill", "envelopeMetric", "fillMetric",
                "spanMinutes", "lengthFraction", "material"):
        sh(f"defaults delete {DOM} {key}")
    reload_()
    print(f"TOTAL {checks} checks, {len(fails)} failures")
    for f in fails:
        print("  -", f)
