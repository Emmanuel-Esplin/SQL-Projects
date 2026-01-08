# Load necessary Libraries
from pathlib import Path
import logging
from typing import List, Dict

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
sns.set_style('whitegrid')
plt.rcParams.update({
    'figure.dpi': 140,
    'font.size': 11,
    'axes.titlesize': 14,
    'axes.labelsize': 12,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
})


def load_data(path: Path) -> pd.DataFrame:
    # Load CSV data from a path and return a DataFrame.
    path = Path(path)
    if not path.exists():
        logging.error('Data file not found: %s', path)
        raise FileNotFoundError(f"Data file not found: {path}")
    df = pd.read_csv(path)
    logging.info('Loaded data with shape %s', df.shape)
    return df


def identify_levels(series: pd.Series, min_count: int = 30) -> List:
    # Return levels that appear at least `min_count` times in `series`.
    counts = series.value_counts()
    return counts[counts >= min_count].index.tolist()


def preprocess(df: pd.DataFrame) -> pd.DataFrame:
    # Select useful columns, compute `Age`, and filter rare categorical levels.
    numerical_vars = [
        'SalePrice', 'LotArea', 'OverallQual', 'OverallCond',
        'YearBuilt', '1stFlrSF', '2ndFlrSF', 'BedroomAbvGr',
    ]
    categorical_vars = [
        'MSZoning', 'LotShape', 'Neighborhood', 'CentralAir',
        'SaleCondition', 'MoSold', 'YrSold',
    ]

    cols = [*numerical_vars, *categorical_vars]
    df = df.copy()
    df = df.loc[:, df.columns.intersection(cols)]

    # compute age and update numerical vars (without mutating original list)
    df['Age'] = df['YrSold'] - df['YearBuilt']
    numerical_vars2 = [v for v in numerical_vars if v != 'YearBuilt'] + ['Age']

    # filter categorical variables by level frequency
    keep_levels: Dict[str, List] = {}
    for var in categorical_vars:
        if var in df.columns:
            keep_levels[var] = identify_levels(df[var], min_count=30)
            df = df[df[var].isin(keep_levels[var])]

    logging.info('After filtering, shape is %s', df.shape)
    return df


def summary_statistics(df: pd.DataFrame) -> pd.DataFrame:
    # Return description of SalePrice and numerical variables.
    logging.info('SalePrice skewness: %0.3f', df['SalePrice'].skew())
    logging.info('SalePrice kurtosis: %0.3f', df['SalePrice'].kurt())
    return df.describe()


def plot_histograms(df: pd.DataFrame, numerical_vars: List[str], save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    # Plot histograms for provided numerical variables.
    df['SalePrice'].hist(edgecolor='black', bins=20)
    plt.title('Sale Price Distribution')
    plt.xlabel('Sale Price')
    plt.ylabel('Frequency')
    fig = plt.gcf()
    if save_plots:
        save_dir.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_dir / 'saleprice_distribution.png', bbox_inches='tight', dpi=150)
        plt.close(fig)
    else:
        plt.show()
    axes = df[numerical_vars].hist(edgecolor='black', bins=15, figsize=(14, 5), layout=(2, 4))
    # axes may be a 2D array depending on layout
    flat_axes = axes.flatten() if hasattr(axes, 'flatten') else [axes]
    for ax, col in zip(flat_axes, numerical_vars):
        label = col.replace('_', ' ').title()
        ax.set_title(label)
        ax.set_xlabel(label)
        ax.set_ylabel('Frequency')
        # format y axis if it looks like a price/count
        try:
            if 'price' in label.lower() or 'sale' in label.lower():
                import matplotlib.ticker as mtick
                ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, p: f'{int(x):,}'))
        except Exception:
            pass
    fig = plt.gcf()
    plt.tight_layout()
    if save_plots:
        save_dir.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_dir / 'numeric_histograms.png', bbox_inches='tight', dpi=150)
        plt.close(fig)
    else:
        plt.show()


def plot_categorical_counts(df: pd.DataFrame, categorical_vars: List[str], save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    fig, ax = plt.subplots(2, 4, figsize=(14, 6))
    for var, subplot in zip(categorical_vars, ax.flatten()):
        if var in df.columns:
            df[var].value_counts().plot(kind='bar', ax=subplot, color='C0')
            title = var.replace('_', ' ').title()
            subplot.set_title(f'Count of {title}')
            subplot.set_xlabel(title)
            subplot.set_ylabel('Count')
            for label in subplot.get_xticklabels():
                label.set_rotation(45)
                label.set_ha('right')
    fig = plt.gcf()
    if save_plots:
        save_dir.mkdir(parents=True, exist_ok=True)
        fig.tight_layout()
        fig.savefig(save_dir / 'categorical_counts.png', bbox_inches='tight', dpi=150)
        plt.close(fig)
    else:
        fig.tight_layout()
        plt.show()


def plot_correlations(df: pd.DataFrame, numerical_vars: List[str], save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    correlations = df[numerical_vars].corr()
    fig, ax = plt.subplots(figsize=(7, 5))
    sns.heatmap(correlations, ax=ax, annot=True, fmt='.2f', cmap='coolwarm', center=0, annot_kws={'size': 9})
    ax.set_title('Correlation Matrix')
    plt.xticks(rotation=45, ha='right')
    plt.yticks(rotation=0)
    fig.tight_layout()
    if save_plots:
        save_dir.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_dir / 'correlation_matrix.png', bbox_inches='tight', dpi=150)
        plt.close(fig)
    else:
        plt.show()


def plot_boxplots(df: pd.DataFrame, categorical_vars: List[str], save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    # draw some representative boxplots
    fig, ax = plt.subplots(3, 3, figsize=(14, 9))
    for var, subplot in zip(categorical_vars, ax.flatten()):
        if var in df.columns:
            sns.boxplot(x=var, y='SalePrice', data=df, ax=subplot)
            title = var.replace('_', ' ').title()
            subplot.set_title(f'Sale Price by {title}')
            subplot.set_xlabel(title)
            subplot.set_ylabel('Sale Price')
            for label in subplot.get_xticklabels():
                label.set_rotation(45)
                label.set_ha('right')
            # format y axis with thousands separator for readability
            try:
                import matplotlib.ticker as mtick
                subplot.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, p: f'{int(x):,}'))
            except Exception:
                pass
    fig = plt.gcf()
    fig.tight_layout()
    if save_plots:
        save_dir.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_dir / 'boxplots.png', bbox_inches='tight', dpi=150)
        plt.close(fig)
    else:
        plt.show()


def plot_scatter_and_joint(df: pd.DataFrame, save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    # Scatter and joint plot for 1stFlrSF vs SalePrice.
    if {'1stFlrSF', 'SalePrice'}.issubset(df.columns):
        fig = df.plot.scatter(x='1stFlrSF', y='SalePrice').get_figure()
        plt.title('1st Floor Area vs Sale Price')
        plt.xlabel('1st Floor Area (sq ft)')
        plt.ylabel('Sale Price')
        fig.tight_layout()
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            fig.savefig(save_dir / 'scatter_1stflrsf_saleprice.png', bbox_inches='tight', dpi=150)
            plt.close(fig)
        else:
            plt.show()

        jp = sns.jointplot(x='1stFlrSF', y='SalePrice', data=df, joint_kws={"s": 10})
        jp.set_axis_labels('1st Floor Area (sq ft)', 'Sale Price')
        jp.fig.tight_layout()
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            jp.fig.savefig(save_dir / 'joint_1stflrsf_saleprice.png', bbox_inches='tight', dpi=150)
            plt.close(jp.fig)
        else:
            plt.show()


def plot_pairplots(df: pd.DataFrame, save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    # Create pairplots.
    numeric_cols = [c for c in df.select_dtypes(include=[np.number]).columns if c != 'SalePrice']
    if len(numeric_cols) >= 4:
        pp = sns.pairplot(df[numeric_cols[:4]], plot_kws={"s": 10})
        pp.fig.suptitle('Pairplot of first numeric variables', y=1.02)
        pp.fig.tight_layout()
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            pp.fig.savefig(save_dir / 'pairplot_first4.png', bbox_inches='tight', dpi=150)
            plt.close(pp.fig)
        else:
            plt.show()

    if len(numeric_cols) > 4:
        cols = ['SalePrice'] + numeric_cols[4:]
        # ensure at least two columns for pairplot
        if len(cols) >= 2:
            pp2 = sns.pairplot(df[cols], plot_kws={"s": 10})
            pp2.fig.suptitle('Pairplot of SalePrice with other numeric vars', y=1.02)
            pp2.fig.tight_layout()
            if save_plots:
                save_dir.mkdir(parents=True, exist_ok=True)
                pp2.fig.savefig(save_dir / 'pairplot_saleprice_others.png', bbox_inches='tight', dpi=150)
                plt.close(pp2.fig)
            else:
                plt.show()


def plot_facet_grids(df: pd.DataFrame, save_plots: bool = False, save_dir: Path = Path('outputs/plots')) -> None:
    # Create FacetGrid conditional plots.
    if {'YrSold', 'SaleCondition', 'CentralAir', 'Age', 'SalePrice'}.issubset(df.columns):
        g = sns.FacetGrid(df, col='YrSold', row='SaleCondition', hue='CentralAir')
        g.map(plt.scatter, 'Age', 'SalePrice').add_legend()
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            g.fig.tight_layout()
            g.fig.savefig(save_dir / 'facetgrid_yrsold_salecondition.png', bbox_inches='tight', dpi=150)
            plt.close(g.fig)
        else:
            plt.show()

    if 'Neighborhood' in df.columns and {'OverallQual', 'SalePrice'}.issubset(df.columns):
        g = sns.FacetGrid(df, col='Neighborhood', col_wrap=4)
        g.map(plt.scatter, 'OverallQual', 'SalePrice')
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            g.fig.tight_layout()
            g.fig.savefig(save_dir / 'facetgrid_neighborhood_overallqual.png', bbox_inches='tight', dpi=150)
            plt.close(g.fig)
        else:
            plt.show()

    # repeat of conditional grid from original script (kept for completeness)
    if {'YrSold', 'SaleCondition', 'CentralAir', 'Age', 'SalePrice'}.issubset(df.columns):
        g2 = sns.FacetGrid(df, col='YrSold', row='SaleCondition', hue='CentralAir')
        g2.map(plt.scatter, 'Age', 'SalePrice').add_legend()
        if save_plots:
            save_dir.mkdir(parents=True, exist_ok=True)
            g2.fig.tight_layout()
            g2.fig.savefig(save_dir / 'facetgrid_yrsold_salecondition_2.png', bbox_inches='tight', dpi=150)
            plt.close(g2.fig)
        else:
            plt.show()


def main(data_path: str = 'house_train.csv') -> None:
    # Run the light EDA pipeline and produce plots.
    data = load_data(Path(data_path))
    df = preprocess(data)

    # choose variables for plotting from processed df
    numerical_vars = [c for c in df.select_dtypes(include=[np.number]).columns if c != 'SalePrice']
    categorical_vars = [c for c in df.select_dtypes(include=['object', 'category']).columns]

    _ = summary_statistics(df)
    # Save plots to outputs/plots by default so they are available when running non-interactively.
    save_dir = Path('outputs/plots')
    plot_histograms(df, ['LotArea', 'OverallQual', 'OverallCond', '1stFlrSF', '2ndFlrSF', 'BedroomAbvGr', 'Age'], save_plots=True, save_dir=save_dir)
    plot_categorical_counts(df, categorical_vars[:8], save_plots=True, save_dir=save_dir)
    plot_correlations(df, ['SalePrice'] + numerical_vars[:7], save_plots=True, save_dir=save_dir)
    plot_boxplots(df, categorical_vars[:8], save_plots=True, save_dir=save_dir)

    # restored exploratory plots
    plot_scatter_and_joint(df, save_plots=True, save_dir=save_dir)
    plot_pairplots(df, save_plots=True, save_dir=save_dir)
    plot_facet_grids(df, save_plots=True, save_dir=save_dir)


if __name__ == '__main__':
    main()

