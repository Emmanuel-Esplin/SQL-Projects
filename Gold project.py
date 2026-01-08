# Import all packages
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import xgboost as xgb

import warnings
warnings.filterwarnings("ignore")
sns.set_style("darkgrid", {"grid.color": ".6",
                            "grid.linestyle": ":"})

from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import PolynomialFeatures
from sklearn.pipeline import make_pipeline
from sklearn.linear_model import Lasso

from sklearn.ensemble import RandomForestRegressor
from xgboost import XGBRegressor
from sklearn.metrics import r2_score
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import GridSearchCV

# Load dataset
dataset = pd.read_csv("gold_price_data.csv", parse_dates=["Date"])


# Info about the dataset
dataset.info()

# Null values in the dataset
dataset.isna().sum().sort_values(ascending=False) 

# Calculation correlation matrix
correlation = dataset.drop("Date", axis=1).corr()

# Create a heatmap to visualize the corrrelation matrix
sns.heatmap(correlation, annot=True, cmap="coolwarm")

# Add title and axis labels
plt.title("Correlation Matrix Heatmap")
plt.xlabel("Features")
plt.ylabel("Features")

# Show the plot
plt.show()

# drop SLV column due to high correlation with target column
dataset.drop("SLV", axis=1, inplace=True)

# reset index to date column
dataset.set_index("Date", inplace=True)

# Plot price of gold for each increasing day
dataset["EUR/USD"].plot()
plt.title("Gold Price Over Time")
plt.xlabel("Date")
plt.ylabel("Gold Price")
plt.show()

# Apply rolling mean with window size of 3 
dataset["Gold_Price_Trend"] = dataset["EUR/USD"].rolling(window=20).mean()

# Reset the index to Date column for plotting
dataset.reset_index(inplace=True)

# Since rolling method is used, for 20 rows the first 2 rows will be NaN
dataset["Gold_Price_Trend"].loc[20:].plot()

# Add title of the chart
plt.title("Gold Price Trend Over Time")

# Set x and y labels
plt.xlabel("Date")
plt.ylabel("Gold Price")
plt.show()

# Plot figure
fig = plt.figure(figsize=(12, 8))

# Add subtitle of graph
fig.suptitle("Distribution of data across columns", fontsize=16)
temp = dataset.drop("Date", axis=1).columns.tolist()
for i, item in enumerate(temp):
    ax = fig.add_subplot(3, 3, i+1)
    sns.histplot(dataset[item], kde=True, ax=ax)
plt.tight_layout(pad=2.0, w_pad=2.0, h_pad=2.0)
plt.show()

# Skewness along the index axis
skewness = dataset.drop("Date", axis=1).skew(axis=0, skipna=True)
print(skewness)

# Apply sqrt root transformation to reduce skewness on USO
dataset["USO"] = np.sqrt(dataset["USO"])

# Boxplot to visualize the outliers
fig = plt.figure(figsize=(10, 8))
temp = dataset.drop("Date", axis=1).columns.tolist()
for i, item in enumerate(temp):
    plt.subplot(3, 3, i+1)
    sns.boxplot(data=dataset, x=item, color="lightblue")
plt.tight_layout(pad=1.0, w_pad=1.0, h_pad=2.0)
plt.show()

# Normalize the outliers present in the dataset
def outlier_removal(col):
    # Calculate the upper and lower limit
    upper_limit = col.quantile(0.95)
    lower_limit = col.quantile(0.05)
    col = np.where(col > upper_limit, upper_limit, col)
    col = np.where(col < lower_limit, lower_limit, col)
    return col

# Normalize all columns except Date
for i in dataset.columns:
    if i != "Date":
        dataset[i] = outlier_removal(dataset[i]) 

# Split the dataset into feature and targer variables
X = dataset.drop(["Date", "EUR/USD"], axis=1)
y = dataset["EUR/USD"]

# Split the dataset into training and testing sets
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)