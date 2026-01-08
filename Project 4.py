
from __future__ import annotations

import argparse
from typing import Iterable, Sequence

import matplotlib.pyplot as plt
import numpy as np

def simple_line_plots(show: bool = True) -> None:
    # Create a few simple line and scatter plots.
    x = [1, 2, 3, 4]
    plt.figure()
    plt.plot([1, 2, 3, 2.5], label='simple')
    plt.plot(x, [1, 4, 9, 16], label='squares')
    plt.plot(x, [10, 20, 25, 30], color='lightblue', linewidth=3, label='line')
    plt.scatter([0.3, 3.8, 1.2, 2.5], [11, 25, 9, 26], color='darkgreen', marker='^', label='points')
    plt.xlim(0.5, 4.5)
    plt.title('Basic combined plot')
    plt.xlabel('x')
    plt.ylabel('y')
    plt.legend()
    if show:
        plt.show()
    return plt.gcf()


def damped_cosine_example(show: bool = True) -> None:
    # Plot a damped cosine with two different time resolutions.
    def f(t: np.ndarray) -> np.ndarray:
        return np.exp(-t) * np.cos(2 * np.pi * t)

    t1 = np.arange(0.0, 5.0, 0.1)
    t2 = np.arange(0.0, 5.0, 0.02)

    plt.figure()
    plt.subplot(2, 1, 1)
    plt.plot(t1, f(t1), 'bo')
    plt.title('Damped cosine (coarse)')

    plt.subplot(2, 1, 2)
    plt.plot(t2, np.cos(2 * np.pi * t2), 'r--')
    plt.title('Cosine (fine)')
    plt.tight_layout()
    if show:
        plt.show()
    return plt.gcf()


def polynomial_subplots(show: bool = True) -> None:
    # Show several polynomial powers on multiple subplots.
    x = np.linspace(-5, 5, 150)
    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(8, 6))
    axes[0, 0].plot(x, x, color='red')
    axes[0, 0].set_title('Linear')
    axes[0, 1].plot(x, x**2, color='blue')
    axes[0, 1].set_title('Quadratic')
    axes[1, 0].plot(x, x**3, color='green')
    axes[1, 0].set_title('Cubic')
    axes[1, 1].plot(x, x**4, color='purple')
    axes[1, 1].set_title('4th power')
    fig.tight_layout()
    if show:
        plt.show()
    return fig


def sine_cosine_examples(show: bool = True) -> None:
    # Plot sine and cosine with custom ticks, annotations and legend.
    x = np.linspace(-np.pi, np.pi, 200)
    sine, cosine = np.sin(x), np.cos(x)

    fig, ax = plt.subplots()
    ax.plot(x, sine, color='red', label='Sine')
    ax.plot(x, cosine, color='#165181', label='Cosine')
    ax.set_xlim(-3.5, 3.5)
    ax.set_ylim(-1.2, 1.2)
    ax.set_xticks([-np.pi, -np.pi/2, 0, np.pi/2, np.pi])
    ax.set_yticks([-1, 0, 1])
    ax.set_xticklabels([r'$-\pi$', r'$-\pi/2$', r'$0$', r'$+\pi/2$', r'$+\pi$'], size=12)
    ax.set_yticklabels(['-1', '0', '+1'], size=12)
    ax.legend(loc='upper left')
    ax.text(-0.25, 0, '(0,0)')
    ax.text(np.pi - 0.25, 0, r'$(\pi,0)$', size=12)
    ax.annotate('Origin', xy=(0, 0), xytext=(1, -0.7), arrowprops=dict(facecolor='blue'))
    ax.axhline(0, color='black', alpha=0.9)
    ax.axvline(0, color='black', alpha=0.9)
    ax.grid(True)
    if show:
        plt.show()
    return fig


def olympics_bar_chart(show: bool = True) -> None:
    #Top 10 Rio Olympics medals bar chart (gold and silver).
    countries = ['USA', 'GBR', 'CHN', 'RUS', 'GER', 'JPN', 'FRA', 'KOR', 'ITA', 'AUS']
    gold = [46, 27, 26, 19, 17, 12, 10, 9, 8, 8]
    silver = [37, 23, 18, 18, 10, 8, 18, 3, 12, 11]

    ind = np.arange(len(countries))
    width = 0.4
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.bar(ind, gold, color="#FFDF00", width=width, label='Gold')
    ax.bar(ind + width, silver, color="#C0C0C0", width=width, label='Silver')
    ax.set_xticks(ind + width / 2)
    ax.set_xticklabels(countries)
    for x_pos, g, s in zip(ind, gold, silver):
        ax.text(x_pos - 0.05, g + 0.5, str(g), ha='center')
        ax.text(x_pos + width - 0.05, s + 0.5, str(s), ha='center')
    ax.set_title('Gold and Silver Medals at Rio', size=16)
    ax.set_xlabel('Country', size=14)
    ax.set_ylabel('Number of medals', size=14)
    ax.legend(loc='upper right')
    fig.tight_layout()
    if show:
        plt.show()
    return fig


def histogram_and_scatter(show: bool = True, seed: int = 0) -> None:
    # Create a histogram example and a scatter plot.
    rng = np.random.default_rng(seed)
    iqs = rng.normal(loc=100, scale=10, size=300)
    fig, axes = plt.subplots(nrows=1, ncols=2, figsize=(12, 4))
    axes[0].hist(iqs, bins=18, edgecolor='k')
    axes[0].set_title('Frequency histogram')
    axes[1].hist(iqs, bins=18, color='red', edgecolor='k')
    axes[1].set_title('Density histogram')
    fig.tight_layout()

    # Scatter: reuse olympics data for demonstration
    countries = ['USA', 'GBR', 'CHN', 'RUS', 'GER', 'JPN', 'FRA', 'KOR', 'ITA', 'AUS']
    gold = [46, 27, 26, 19, 17, 12, 10, 9, 8, 8]
    silver = [37, 23, 18, 18, 10, 8, 18, 3, 12, 11]
    fig2, ax2 = plt.subplots()
    ax2.scatter(gold, silver, marker='o')
    ax2.set_title('Gold vs. Silver at Rio Olympics', size=16)
    ax2.set_xlabel('Gold medals', size=14)
    ax2.set_ylabel('Silver medals', size=14)
    if show:
        plt.show()
    return fig, fig2


def run_all_examples() -> None:
    """Run all examples in sequence."""
    simple_line_plots(show=True)
    damped_cosine_example(show=True)
    polynomial_subplots(show=True)
    sine_cosine_examples(show=True)
    olympics_bar_chart(show=True)
    histogram_and_scatter(show=True)


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Run plotting examples')
    parser.add_argument('--example', '-e', choices=['all', 'simple', 'damped', 'poly', 'trig', 'olympics', 'hist'], default='all')
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> None:
    args = _parse_args(argv)
    mapping = {
        'all': run_all_examples,
        'simple': lambda: simple_line_plots(True),
        'damped': lambda: damped_cosine_example(True),
        'poly': lambda: polynomial_subplots(True),
        'trig': lambda: sine_cosine_examples(True),
        'olympics': lambda: olympics_bar_chart(True),
        'hist': lambda: histogram_and_scatter(True),
    }
    func = mapping.get(args.example, run_all_examples)
    func()


if __name__ == '__main__':
    main()
