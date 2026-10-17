"""Manim cutaways for the video: how the fungus's mind works, straight out of lua/evil_fungus/sv_mind.lua.

No LaTeX needed, every formula is plain Text.

    manim -qh tools/brain_manim.py Harvest --media_dir renders/manim
"""
import math

import numpy as np
from manim import *

BG = "#0e0c0b"
HEX = "#3a302a"
FLESH = "#e6a5af"  # the kill icon's tint
VEIN = "#9a5f68"
PALE = "#d7cdbe"  # what a sleeper goes to as it's eaten
DIM = "#7a7068"
SANS = "Inter"
MONO = "Cascadia Mono"

config.background_color = BG

MIND_AT = np.array([-0.6, -2.0, 0.0])
HEAD_Y = 1.3

# brain is EvilFungus.Brain: NPCs off the BRAINS table, players 1 x (1 + skill).
# start/length are when each one gets eaten, as a share of the consume.
SLEEPERS = [
    dict(name="headcrab", brain=0.03, value="0.03", x=-4.8, r=0.32, start=0.0, length=0.3),
    dict(name="citizen", brain=0.3, value="0.3", x=-1.8, r=0.5, start=0.08, length=0.55),
    dict(name="player", brain=3.0, value="1 × (1 + skill)", x=1.3, r=0.5, start=0.16, length=0.84),
]

# What the player did to get away, against TACTICS in sv_mind.lua.
PLAYER_DID = [("bhop", "10s of 10", 1.0), ("rescued", "1 of 1", 1.0), ("noclip", "6s of 30", 0.2)]


def sans(s, size=24, color=PALE):
    return Text(s, font=SANS, font_size=size, color=color)


def mono(s, size=24, color=PALE):
    return Text(s, font=MONO, font_size=size, color=color)


def clip(x):
    return min(1.0, max(0.0, x))


def hexes(r=0.45):
    """The faint cell pattern pressed into the mat."""
    g = VGroup()
    for col in range(-12, 13):
        for row in range(-6, 7):
            x = col * 1.5 * r
            y = row * math.sqrt(3) * r + (col % 2) * math.sqrt(3) * r / 2
            g.add(RegularPolygon(6, radius=r).move_to([x, y, 0]))
    g.set_stroke(HEX, 1.5, 0.6)
    return g


def head(r):
    skull = Circle(radius=r, stroke_color=PALE, stroke_width=3, fill_color=BG, fill_opacity=1)
    eyes = VGroup(*[
        Arc(radius=r * 0.2, start_angle=PI, angle=PI, stroke_color=PALE, stroke_width=2.5).move_to(
            skull.get_center() + np.array([side * r * 0.36, r * 0.05, 0])
        )
        for side in (-1, 1)
    ])
    return VGroup(skull, eyes)


def blob(center, radius, phase):
    """The mind. Never quite holds still."""
    pts = []
    for i in range(48):
        a = TAU * i / 48
        k = 1 + 0.06 * math.sin(3 * a + 1.7 * phase) + 0.04 * math.sin(5 * a - 2.3 * phase) + 0.03 * math.sin(7 * a + 3.1 * phase)
        pts.append(center + radius * k * np.array([math.cos(a), math.sin(a), 0]))
    shape = VMobject().set_points_smoothly(pts + [pts[0]])
    return shape.set_fill("#2a1a1d", 1).set_stroke(FLESH, 3)


class Harvest(Scene):
    """Heads wire in as they're eaten, count for what they're wired in, and stay counted once it's done with them."""

    def construct(self):
        clock = ValueTracker(0)
        clock.add_updater(lambda m, dt: m.increment_value(dt))
        t = ValueTracker(0)
        self.add(clock)

        def eaten(s):
            return clip((t.get_value() - s["start"]) / s["length"])

        def wired():
            return sum(s["brain"] * eaten(s) ** 2 for s in SLEEPERS if eaten(s) < 1)

        def kept():
            return sum(s["brain"] for s in SLEEPERS if eaten(s) >= 1)

        def total():
            return wired() + kept()

        # The mat, and the mind under it.
        self.play(LaggedStart(*[FadeIn(h) for h in hexes()], lag_ratio=0.002, run_time=1.2))
        mind = always_redraw(lambda: blob(MIND_AT, 0.55 + 0.22 * math.log2(1 + total()), clock.get_value()))
        mind.set_z_index(2)
        mind_label = sans("the mind", 22, DIM).set_z_index(3)
        mind_label.add_updater(lambda m: m.next_to(mind, DOWN, 0.2))
        self.play(FadeIn(mind), FadeIn(mind_label))

        # Who's on it.
        heads, names, values = [], [], []
        for s in SLEEPERS:
            h = head(s["r"]).move_to([s["x"], HEAD_Y, 0])
            n = sans(s["name"], 26).move_to([s["x"], HEAD_Y + 1.15, 0])
            v = mono(s["value"], 24, FLESH).next_to(n, DOWN, 0.12)
            heads.append(h)
            names.append(n)
            values.append(v)
        self.play(LaggedStart(*[FadeIn(VGroup(h, n, v), shift=DOWN * 0.2) for h, n, v in zip(heads, names, values)], lag_ratio=0.25))

        # The player's worth goes with how hard they were to catch.
        rows = VGroup(*[
            VGroup(mono(what, 22), mono(of, 22, DIM), mono(f"{got:.1f}", 22, FLESH))
            for what, of, got in PLAYER_DID
        ])
        for row in rows:
            row[1].move_to(row[0].get_left() + RIGHT * 1.45, aligned_edge=LEFT)
            row[2].move_to(row[0].get_left() + RIGHT * 3.25, aligned_edge=LEFT)
        rows.arrange(DOWN, aligned_edge=LEFT, buff=0.18).move_to([5.1, HEAD_Y + 0.55, 0])
        rule = Line(LEFT, RIGHT, stroke_color=DIM, stroke_width=1.5).set_width(rows.width).next_to(rows, DOWN, 0.18)
        skill = VGroup(mono("skill", 22), mono("2.2", 22, DIM), mono("2 max", 22, FLESH))
        skill[1].move_to(skill[0].get_left() + RIGHT * 1.45, aligned_edge=LEFT)
        skill[2].move_to(skill[0].get_left() + RIGHT * 3.25, aligned_edge=LEFT)
        skill.next_to(rule, DOWN, 0.18).align_to(rows, LEFT)
        self.play(LaggedStart(*[FadeIn(r, shift=LEFT * 0.15) for r in rows], lag_ratio=0.35, run_time=1.6))
        self.play(Create(rule), FadeIn(skill), run_time=0.8)
        worth = mono("1 × (1 + 2) = 3", 24, FLESH).move_to(values[2])
        self.play(Transform(values[2], worth))
        self.wait(0.6)
        self.play(FadeOut(VGroup(rows, rule, skill)))

        # Strands from each neck down into the mind, thickening as it gets through them.
        veins = []
        for i, (s, h) in enumerate(zip(SLEEPERS, heads)):
            start = h.get_bottom()
            end = MIND_AT + np.array([(i - 1) * 0.2, 0.15, 0])
            veins.append(CubicBezier(start, start + DOWN * 1.4, end + UP * 1.8 + RIGHT * (s["x"] * 0.15), end).set_stroke(VEIN, 1.5, 0.35))
        self.play(*[Create(v) for v in veins], run_time=1.4)

        for s, v, h in zip(SLEEPERS, veins, heads):
            v.add_updater(lambda m, s=s: m.set_stroke(width=1.5 + 6 * eaten(s), opacity=0.35 + 0.65 * eaten(s)))
            h[0].add_updater(lambda m, s=s: m.set_stroke(interpolate_color(ManimColor(PALE), ManimColor(FLESH), eaten(s))))

        # Pale beads running down each neck vein, all the time once it's wired in.
        beads = VGroup()
        for s, v in zip(SLEEPERS, veins):
            for j in range(5):
                d = Dot(radius=0.05, color=PALE).set_z_index(1)

                def run(m, s=s, v=v, j=j):
                    p = (j / 5 + clock.get_value() * 0.3) % 1
                    m.move_to(v.point_from_proportion(p))
                    m.set_opacity(eaten(s) * math.sin(PI * p))
                    m.set_width(0.08 + 0.06 * eaten(s))

                d.add_updater(run)
                beads.add(d)
        self.add(beads)

        tags = []
        for s, h in zip(SLEEPERS, heads):
            def tag(s=s, h=h):
                k = eaten(s)
                txt = mono("kept", 20, FLESH) if k >= 1 else mono(f"{k * 100:.0f}%", 20, DIM)
                return txt.next_to(h, LEFT, 0.25)
            tags.append(always_redraw(tag))
        self.add(*tags)

        anchor = MIND_AT + np.array([1.9, 0.9, 0])

        def readout(name, value, note, row):
            g = VGroup(mono(name, 24), mono(f"{value():.2f}", 24, FLESH))
            g[1].move_to(g[0].get_left() + RIGHT * 1.15, aligned_edge=LEFT)
            if note:
                g.add(sans(note, 20, DIM).move_to(g[0].get_left() + RIGHT * 2.45, aligned_edge=LEFT))
            return g.move_to(anchor + DOWN * 0.5 * row, aligned_edge=LEFT)

        board = VGroup(
            always_redraw(lambda: readout("wired", wired, "brain × eaten²", 0)),
            always_redraw(lambda: readout("kept", kept, "for good", 1)),
            always_redraw(lambda: readout("total", total, None, 2)),
        )
        self.play(FadeIn(board))

        self.play(t.animate.set_value(1), run_time=9, rate_func=linear)
        self.wait(0.5)

        level = VGroup(
            mono(f"level = log₂(1 + total) = {math.log2(1 + total()):.2f}", 22),
            sans("each step up takes twice the heads", 20, DIM),
        ).arrange(DOWN, aligned_edge=LEFT, buff=0.15).move_to(anchor + DOWN * 1.9, aligned_edge=LEFT)
        self.play(FadeIn(level, shift=UP * 0.15))
        self.wait(2.5)
