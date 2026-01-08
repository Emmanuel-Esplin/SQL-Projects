# Analysis of student grades and alcohol consumption.
# This script loads student data, computes an alcohol index and categorical level, and runs basic statistical comparisons and plots.

from pathlib import Path
from typing import Tuple

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

# Visualization defaults
sns.set_theme(style="whitegrid")


def load_student_data(path: Path) -> pd.DataFrame:
    """Load student data from CSV and perform initial cleaning.

    Args:
        path: Path to the CSV file.

    Returns:
        A cleaned DataFrame with `gender` column and alcohol index.
    """
    try:
        df = pd.read_csv(path, sep=";")
    except FileNotFoundError:
        raise

    # Standardize column names and compute alcohol index
    df = df.rename(columns={"sex": "gender"})
    df["alcohol_index"] = (5 * df["Dalc"] + 2 * df["Walc"]) / 7
    df["acl"] = np.where(df["alcohol_index"] <= 2, "Low", "High")
    return df


def confidence_interval_mean(series: pd.Series, confidence: float = 0.95) -> Tuple[float, float]:
    """Compute a normal-theory confidence interval for the mean.

    Uses sample standard deviation divided by sqrt(n).
    """
    n = len(series)
    mean = series.mean()
    se = series.std(ddof=1) / np.sqrt(n)
    return stats.norm.interval(confidence, loc=mean, scale=se)


def confidence_interval_prop(p: float, n: int, confidence: float = 0.98) -> Tuple[float, float]:
    """Compute normal-approx confidence interval for a proportion.

    Args:
        p: sample proportion
        n: sample size
    """
    se = np.sqrt(p * (1 - p) / n)
    return stats.norm.interval(confidence, loc=p, scale=se)


def plot_binomial_probs(n: int, p: float = 0.25, figsize: Tuple[int, int] = (14, 4)) -> plt.Figure:
    """Return a figure showing PMF and CDF of Binomial(n, p)."""
    fig, ax = plt.subplots(1, 2, figsize=figsize)
    k = np.arange(n + 1)
    ax[0].bar(k, stats.binom.pmf(k=k, n=n, p=p))
    ax[0].set_xticks(k)
    ax[0].set_title("Probability mass function")
    ax[1].plot(k, stats.binom.cdf(k=k, n=n, p=p), marker="o")
    ax[1].set_xticks(k)
    ax[1].set_title("Cumulative distribution function")
    fig.tight_layout()
    return fig


def compare_grades_by_acl(df: pd.DataFrame) -> dict:
    # Compare `G3` grades between low and high alcohol consumption groups.
    # Returns dictionary with variance table, Bartlett and t-test results and a figure.
    
    res = {}
    groups = df.groupby("acl")["G3"]
    res["variance_by_acl"] = groups.var()

    low = df.loc[df["acl"] == "Low", "G3"]
    high = df.loc[df["acl"] == "High", "G3"]
    res["bartlett"] = stats.bartlett(low, high)
    res["ttest"] = stats.ttest_ind(low, high, equal_var=True)

    fig, axes = plt.subplots(1, 2, figsize=(14, 4))
    sns.boxplot(x="acl", y="G3", data=df, ax=axes[0])
    sns.pointplot(x="acl", y="G3", data=df, ax=axes[1])
    fig.tight_layout()
    res["figure"] = fig
    return res


def contingency_analysis_gender_acl(df: pd.DataFrame) -> dict:
    # Perform chi-square contingency analysis for gender and alcohol level.
    # Returns observed table, expected table, chi2 results and a figure comparing observed vs expected.
    
    res = {}
    table = pd.crosstab(df["acl"], df["gender"])  # rows: acl, cols: gender
    res["observed"] = table
    chi2_stat, p_value, dof, expected = stats.chi2_contingency(table)
    res["chi2"] = (chi2_stat, p_value, dof)
    expected_table = pd.DataFrame(expected, index=table.index, columns=table.columns)
    res["expected"] = expected_table

    fig, axes = plt.subplots(1, 2, figsize=(14, 4))
    table.plot(kind="bar", stacked=True, ax=axes[0], title="Observed")
    (100 * (table.T / table.sum(axis=1)).T).plot(kind="bar", stacked=True, ax=axes[1], title="Observed %")
    fig.tight_layout()
    res["figure"] = fig
    return res


def main(data_path: Path | None = None) -> None:
    """Main entrypoint for script execution.

    If `data_path` is None, attempts to load `student.csv` from the script directory.
    """
    if data_path is None:
        try:
            base = Path(__file__).parent
        except NameError:
            base = Path.cwd()
        data_path = base / "student.csv"

    df = load_student_data(data_path)

    n = len(df)
    print(f"Sample size: {n}")

    mean_ci = confidence_interval_mean(df["G3"], confidence=0.95)
    print(f"95% CI for mean G3: {mean_ci}")

    prop_high = (df["acl"] == "High").mean()
    prop_ci = confidence_interval_prop(prop_high, n, confidence=0.98)
    print(f"Proportion High ACL: {prop_high:.3f}, 98% CI: {prop_ci}")

    # Show binomial example figure (not displayed automatically in non-interactive runs)
    fig_binom = plot_binomial_probs(10)
    fig_binom.savefig("binomial_example.png")

    grade_res = compare_grades_by_acl(df)
    grade_res["figure"].savefig("grades_by_acl.png")

    cont_res = contingency_analysis_gender_acl(df)
    cont_res["figure"].savefig("gender_acl_contingency.png")


if __name__ == "__main__":
    main()

