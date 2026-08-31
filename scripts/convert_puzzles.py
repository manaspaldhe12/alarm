#!/usr/bin/env python3
"""Converts a slice of the Lichess puzzle database (CC0-licensed,
https://database.lichess.org/#puzzles) into this app's Puzzle.swift JSON
schema -- used to generate both MorningAlarm/Resources/Puzzles/puzzles.json
(bundled, offline) and puzzle-data/remote_puzzles.json (fetched on demand
via PuzzleLibraryView).

Lichess's own convention: `FEN` is the position *before* the puzzle starts,
and `Moves[0]` is an opponent "setup" move that's auto-played to reach the
actual puzzle position -- the solver's first move is `Moves[1]`.

This app's convention (see Domain/Chess/Puzzle.swift and ChessBoard.swift):
`fen` IS the starting position to render, and `solution[0]` is the player's
first move. So Moves[0] must be applied here to produce the real starting
FEN, and `solution` becomes Moves[1:].

Usage:
    # Stream just the first N rows of the puzzle CSV without downloading
    # the full ~300MB compressed database (requires zstd on PATH):
    curl -s https://database.lichess.org/lichess_db_puzzle.csv.zst \\
        | zstd -dc | head -n 50000 > lichess_sample.csv

    python3 convert_puzzles.py lichess_sample.csv puzzles_out.json \\
        --count 1500 --exclude-ids existing_ids.txt

`--exclude-ids` takes a text file of one Lichess PuzzleId per line (without
the "lichess_" prefix this script adds) to skip -- used to keep the bundled
and remote pools non-overlapping.
"""
import argparse
import csv
import json
import random
import sys

FILE_LETTERS = "abcdefgh"


def parse_fen(fen):
    placement, active, *_ = fen.split(" ")
    board = {}
    rank = 7
    file = 0
    for ch in placement:
        if ch == "/":
            rank -= 1
            file = 0
        elif ch.isdigit():
            file += int(ch)
        else:
            board[(file, rank)] = ch
            file += 1
    return board, active


def square_to_coord(sq):
    return (FILE_LETTERS.index(sq[0]), int(sq[1]) - 1)


def apply_uci(board, active, uci):
    frm = square_to_coord(uci[0:2])
    to = square_to_coord(uci[2:4])
    promo = uci[4] if len(uci) == 5 else None

    piece = board.get(frm)
    if piece is None:
        raise ValueError(f"no piece at {uci[0:2]}")
    is_white = piece.isupper()
    kind = piece.lower()

    # en passant: pawn moves diagonally onto an empty square
    if kind == "p" and frm[0] != to[0] and to not in board:
        board.pop((to[0], frm[1]), None)

    # castling: king moves two files -- also move the rook
    if kind == "k" and abs(to[0] - frm[0]) == 2:
        rank = frm[1]
        if to[0] > frm[0]:
            board[(5, rank)] = board.pop((7, rank), None)
        else:
            board[(3, rank)] = board.pop((0, rank), None)

    del board[frm]
    board[to] = (promo.upper() if is_white else promo.lower()) if promo else piece
    return "b" if is_white else "w"


def board_to_placement(board):
    rows = []
    for rank in range(7, -1, -1):
        row, empty = "", 0
        for file in range(8):
            piece = board.get((file, rank))
            if piece is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += piece
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows)


def convert(row):
    moves = row["Moves"].split(" ")
    board, active = parse_fen(row["FEN"])
    active = apply_uci(board, active, moves[0])
    fen = f"{board_to_placement(board)} {active} - - 0 1"
    return {
        "id": f"lichess_{row['PuzzleId']}",
        "rating": int(row["Rating"]),
        "fen": fen,
        "sideToMove": "white" if active == "w" else "black",
        "solution": moves[1:],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv_path", help="Lichess puzzle CSV (or a prefix slice of it)")
    parser.add_argument("out_path", help="where to write the converted JSON array")
    parser.add_argument("--count", type=int, default=1500, help="target puzzle count")
    parser.add_argument("--min-rating", type=int, default=400)
    parser.add_argument("--max-rating", type=int, default=2200)
    parser.add_argument("--max-solution-len", type=int, default=5, help="keep puzzles short -- a wake-up mission, not a study session")
    parser.add_argument("--exclude-ids", help="text file of Lichess PuzzleIds (one per line) to skip")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)
    excluded = set()
    if args.exclude_ids:
        with open(args.exclude_ids) as f:
            excluded = {line.strip() for line in f if line.strip()}

    candidates = []
    with open(args.csv_path, newline="") as f:
        for row in csv.DictReader(f):
            if row["PuzzleId"] in excluded:
                continue
            solution_len = len(row["Moves"].split(" ")) - 1
            if not (1 <= solution_len <= args.max_solution_len):
                continue
            rating = int(row["Rating"])
            if not (args.min_rating <= rating <= args.max_rating):
                continue
            candidates.append(row)

    print(f"candidates after filtering: {len(candidates)}", file=sys.stderr)

    # Bucket by rating band for a broad, even spread rather than whatever
    # the raw popularity-sorted dump happens to front-load.
    buckets = {}
    for row in candidates:
        buckets.setdefault(int(row["Rating"]) // 100 * 100, []).append(row)

    bands = sorted(buckets.keys())
    per_band = max(1, args.count // len(bands)) if bands else 0
    selected = []
    for band in bands:
        rows = buckets[band]
        random.shuffle(rows)
        selected.extend(rows[:per_band])
    random.shuffle(selected)

    puzzles, seen = [], set()
    for row in selected:
        if row["PuzzleId"] in seen:
            continue
        seen.add(row["PuzzleId"])
        try:
            puzzles.append(convert(row))
        except Exception:
            continue

    puzzles.sort(key=lambda p: p["rating"])
    print(f"converted: {len(puzzles)}", file=sys.stderr)

    with open(args.out_path, "w") as f:
        json.dump(puzzles, f, indent=2)


if __name__ == "__main__":
    main()
