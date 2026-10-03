"""Remove only edge-connected cleared black pixels, retaining black UI ink."""
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
