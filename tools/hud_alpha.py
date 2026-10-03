"""Keep native UI ink while making the cleared world transparent."""
import numpy as np


def clear_world_alpha(pixels):
    black = ~np.any(pixels[:, :, :3], axis=2)
    height, width = black.shape
    parents, edge, runs = [], [], []
    previous = []

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for y in range(height):
        changes = np.flatnonzero(np.diff(np.pad(black[y].astype(np.int8), (1, 1))))
        current = []
        cursor = 0
        for x0, x1 in zip(changes[::2], changes[1::2]):
            i = len(parents)
            parents.append(i)
            edge.append(y in (0, height-1) or x0 == 0 or x1 == width)
            current.append((int(x0), int(x1), i))
            runs.append((y, int(x0), int(x1), i))
            while cursor < len(previous) and previous[cursor][1] <= x0:
                cursor += 1
            k = cursor
            while k < len(previous) and previous[k][0] < x1:
                a, b = root(i), root(previous[k][2])
                if a != b:
                    parents[b] = a
                    edge[a] = edge[a] or edge[b]
                k += 1
        previous = current
    result = pixels.copy()
    result[:, :, 3] = 255
    for y, x0, x1, i in runs:
        if edge[root(i)]:
            result[y, x0:x1, 3] = 0
    return result


def clear_supplemental_hud_alpha(pixels):
    """Correct native warning fringes in the independently cleared HUD pass.

    FTL paints faint warning-text shadows with nonzero RGB and fractional
    alpha. The legacy screen conversion makes those almost-black pixels
    opaque. Use their actual coverage in the warning band only; framed HUD
    controls still need the contour fill to retain their original black ink.
    Full screens and native windows do not use this supplemental conversion.
    """
    result = clear_world_alpha(pixels)
    # At the native 1280x720 HUD coordinates, warnings sit between the top
    # controls and the weapon bar, to the right of crew and left of target UI.
    # They shift horizontally when an enemy arrives, so cover both positions.
    height, width = pixels.shape[:2]
    left, right = round(400 * width / 1280), round(872 * width / 1280)
    top, bottom = round(160 * height / 720), round(360 * height / 720)
    source = pixels[top:bottom,left:right]
    warning = result[top:bottom,left:right]
    if not source.size:
        return result
    # RGB already includes FTL's warning blink/fade. Do not multiply faded red
    # glyphs by their raw FBO alpha a second time: only recover coverage for
    # the almost-black texture fringe, relative to the current glyph peak.
    colors = source[:, :, :3].astype(np.int16)
    reddish = (colors[:, :, 0] > colors[:, :, 1] * 2) & (colors[:, :, 0] > colors[:, :, 2] * 2)
    glyphs = reddish & (colors[:, :, 0] > 8)
    if not np.any(glyphs):
        return result
    brightness = np.max(colors, axis=2)
    fringe_limit = max(1.0, float(colors[:, :, 0][glyphs].max()) * 0.35)
    faint_coverage = (source[:, :, 3] <= 8) & (brightness <= fringe_limit) & reddish
    warning[:, :, 3][faint_coverage] = source[:, :, 3][faint_coverage]
    return result
