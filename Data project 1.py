# Load packages
from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import List

import numpy as np
import matplotlib.pyplot as plt
import requests
from datascience import Table

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
_HERE = Path(__file__).parent
_OUTPUT_DIR = _HERE / "outputs"
_OUTPUT_DIR.mkdir(exist_ok=True)


def read_url(url: str, timeout: float = 10.0) -> str:
    # Fetch text from `url` 
    resp = requests.get(url, timeout=timeout)
    resp.raise_for_status()
    # Collapse runs of whitespace to single space for easier splitting/counting
    return re.sub(r"\s+", " ", resp.text)


def chapters_from_text(text: str, split_token: str = "CHAPTER ", start_index: int = 0) -> List[str]:
    parts = text.split(split_token)
    return parts[start_index:]


def cumulative_name_counts(chapters: List[str], names: List[str]) -> Table:
    # Return a `Table` with cumulative counts of each name across chapters.
    cols = []
    for name in names:
        counts = np.char.count(chapters, name)
        cols.append(np.cumsum(counts))
    tbl = Table().with_columns(*sum(([n, c] for n, c in zip(names, cols)), []))
    tbl = tbl.with_column("Chapter", np.arange(1, len(chapters) + 1))
    return tbl


def chapter_lengths_and_periods(chapters: List[str]) -> Table:
    lengths = [len(s) for s in chapters]
    periods = np.char.count(chapters, '.')
    return Table().with_columns(
        "Chapter Length", lengths,
        "Number of Periods", periods,
    )


def save_cumulative_plot(tbl: Table, title: str, filename: str) -> None:
    plt.style.use("fivethirtyeight")
    plt.figure(figsize=(8, 6))
    # Plot each name column (all columns except 'Chapter') against Chapter
    chapter = tbl.column("Chapter")
    for col in tbl.labels:
        if col == "Chapter":
            continue
        plt.plot(chapter, tbl.column(col), label=col)
    plt.title(title, y=1.02)
    plt.xlabel("Chapter")
    plt.ylabel("Cumulative Count")
    plt.legend()
    out = _OUTPUT_DIR / filename
    # Tight layout and bbox to avoid clipping titles/labels when saving
    plt.tight_layout()
    plt.savefig(out, bbox_inches="tight", dpi=150)
    plt.close()
    logging.info("Saved plot: %s", out)


def save_scatter_lengths_periods(tbl1: Table, tbl2: Table, filename: str) -> None:
    plt.style.use("fivethirtyeight")
    plt.figure(figsize=(8, 6))
    plt.scatter(tbl1.column("Number of Periods"), tbl1.column("Chapter Length"), color="darkblue", label="Book 1")
    plt.scatter(tbl2.column("Number of Periods"), tbl2.column("Chapter Length"), color="gold", label="Book 2")
    plt.xlabel("Number of periods in chapter")
    plt.ylabel("Number of characters in chapter")
    plt.legend()
    out = _OUTPUT_DIR / filename
    plt.tight_layout()
    plt.savefig(out, bbox_inches="tight", dpi=150)
    plt.close()
    logging.info("Saved scatter plot: %s", out)


def main() -> None:
    # Sources
    huck_finn_url = "https://www.inferentialthinking.com/data/huck_finn.txt"
    little_women_url = "https://www.inferentialthinking.com/data/little_women.txt"

    try:
        huck_text = read_url(huck_finn_url)
        little_text = read_url(little_women_url)
    except requests.RequestException as e:
        logging.error("Failed to fetch book texts: %s", e)
        return

    huck_chapters = chapters_from_text(huck_text, start_index=44)
    little_chapters = chapters_from_text(little_text, start_index=1)

    # Cumulative name counts for Huck Finn
    names_huck = ["Jim", "Tom", "Huck"]
    cum_huck = cumulative_name_counts(huck_chapters, names_huck)
    save_cumulative_plot(cum_huck, "Cumulative Number of Times Each Name Appears (Huck Finn)", "huck_cumulative.png")

    # Cumulative name counts for Little Women
    names_little = ["Amy", "Beth", "Jo", "Meg", "Laurie"]
    cum_little = cumulative_name_counts(little_chapters, names_little)
    save_cumulative_plot(cum_little, "Cumulative Number of Times Each Name Appears (Little Women)", "little_cumulative.png")

    # Chapter lengths and periods
    chars_periods_huck = chapter_lengths_and_periods(huck_chapters)
    chars_periods_little = chapter_lengths_and_periods(little_chapters)
    save_scatter_lengths_periods(chars_periods_huck, chars_periods_little, "lengths_vs_periods.png")


if __name__ == "__main__":
    main()

