"""Manim cutaways for the video: the fungus's mind as the functions in lua/evil_fungus/sv_mind.lua.

No LaTeX needed, every formula is plain Text.

    manim -qh tools/brain_manim.py Grasp --media_dir renders/manim
"""
from manim import *

BG = "#0e0c0b"
INK = "#d7cdbe"
DIM = "#7a7068"
CURVE = "#e6a5af"
MONO = "Cascadia Mono"

config.background_color = BG

LEAD_TIME = 1.5  # init.lua
WAVE_SPEED = 500  # sv_feel.lua
QUICKER = 1  # sv_feel.lua


def mono(s, size=28, color=INK):
    return Text(s, font=MONO, font_size=size, color=color)


def grasp(total):
    return 1 - 1 / (1 + total)


class Grasp(Scene):
    """Everything it's eaten comes down to one number, and that number makes it quicker and better at cutting you off."""

    def construct(self):
        title = mono("grasp = 1 − 1 / (1 + total)", 34).to_edge(UP, 0.5)
        total_def = mono("total = (kept + wired) × learning", 24, DIM).next_to(title, DOWN, 0.2)
        self.play(Write(title), run_time=1.5)
        self.play(FadeIn(total_def, shift=UP * 0.1))

        axes = Axes(
            x_range=[0, 10, 1], y_range=[0, 1, 0.25], x_length=6.8, y_length=4.2,
            axis_config={"color": DIM, "stroke_width": 2, "include_tip": False},
        ).move_to([-2.7, -0.9, 0])
        xs = VGroup(*[mono(str(x), 20, DIM).next_to(axes.c2p(x, 0), DOWN, 0.15) for x in (0, 2, 4, 6, 8, 10)])
        ys = VGroup(*[mono(f"{y:g}", 20, DIM).next_to(axes.c2p(0, y), LEFT, 0.15) for y in (0, 0.5, 1)])
        xl = mono("total", 22, DIM).next_to(axes.x_axis, DOWN, 0.55)
        yl = mono("grasp", 22, DIM).rotate(PI / 2).next_to(axes.y_axis, LEFT, 0.75)
        ceiling = DashedLine(axes.c2p(0, 1), axes.c2p(10, 1), color=DIM, stroke_width=1.5, dash_length=0.08)
        self.play(Create(axes), FadeIn(xs, ys, xl, yl), Create(ceiling))

        curve = axes.plot(grasp, x_range=[0, 10, 0.02], color=CURVE, stroke_width=4)
        self.play(Create(curve), run_time=2)

        total = ValueTracker(0)
        dot = always_redraw(lambda: Dot(axes.c2p(total.get_value(), grasp(total.get_value())), radius=0.08, color=CURVE))
        drop = always_redraw(lambda: VGroup(
            DashedLine(axes.c2p(total.get_value(), 0), axes.c2p(total.get_value(), grasp(total.get_value())), color=INK, stroke_width=1.5, dash_length=0.06),
            DashedLine(axes.c2p(0, grasp(total.get_value())), axes.c2p(total.get_value(), grasp(total.get_value())), color=INK, stroke_width=1.5, dash_length=0.06),
        ))

        panel = [1.8, 1.2, 0]

        def readouts():
            t = total.get_value()
            g = grasp(t)
            rows = VGroup(
                VGroup(mono("total", 26), mono(f"{t:5.2f}", 26, CURVE)),
                VGroup(mono("grasp", 26), mono(f"{g:5.2f}", 26, CURVE)),
            )
            for r in rows:
                r[1].move_to(r[0].get_left() + RIGHT * 1.4, aligned_edge=LEFT)
            return rows.arrange(DOWN, aligned_edge=LEFT, buff=0.2).move_to(panel, aligned_edge=UL)

        board = always_redraw(readouts)
        self.play(FadeIn(dot, drop, board))

        # Eating anything at all gets it halfway.
        self.play(total.animate.set_value(1), run_time=2, rate_func=smooth)
        self.wait(0.5)

        # What it uses that for.
        def uses():
            g = grasp(total.get_value())
            rows = VGroup(
                VGroup(mono(f"lead = {LEAD_TIME} s × grasp", 24), mono(f"{LEAD_TIME * g:.2f} s", 24, CURVE)),
                VGroup(mono(f"wave = {WAVE_SPEED} × (1 + grasp)", 24), mono(f"{WAVE_SPEED * (1 + QUICKER * g):.0f} u/s", 24, CURVE)),
            )
            for r in rows:
                r[1].move_to(r[0].get_left() + RIGHT * 1.15 + DOWN * 0.42, aligned_edge=LEFT)
            return rows.arrange(DOWN, aligned_edge=LEFT, buff=0.45).move_to([panel[0], -0.6, 0], aligned_edge=UL)

        effects = always_redraw(uses)
        self.play(FadeIn(effects, shift=UP * 0.1))
        self.wait(0.5)

        # A headcrab, a citizen and a player who got away a lot, all done with.
        self.play(total.animate.set_value(3.33), run_time=2.5, rate_func=smooth)
        self.wait(0.8)
        self.play(total.animate.set_value(10), run_time=4, rate_func=smooth)
        self.wait(2)
