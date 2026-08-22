#!/usr/bin/env python3
"""Cumulative iterations completed across every training attempt.

mlx_lm restarts its iteration counter at 1 on each resume, so the highest number
in the log is not the progress -- it is whatever the longest single attempt
reached. Reading it that way froze the supervisor's count at 125 and it looped
eleven times reporting "125 done, 475 to go" while the adapter quietly improved
underneath. Real progress is the sum of what each attempt got through.

Usage: progress.py <log>   ->  prints one integer
"""
import re
import sys

log = open(sys.argv[1], errors="replace").read()
attempts = re.split(r"=== attempt \d+:[^=]*===", log)[1:]
total = 0
for body in attempts:
    iters = [int(n) for n in re.findall(r"Iter (\d+): Train", body)]
    total += max(iters) if iters else 0
print(total)
