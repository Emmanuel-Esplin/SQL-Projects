# GIA 4Cs in the Diamond Company Database

The database grades every diamond on the four Cs defined by the Gemological Institute of America (GIA): **Carat, Cut, Color and Clarity**. Each C has a reference table, and every value stored in `DIAMONDS` must exist in that table.

| C | Stored in `DIAMONDS` | Reference table | Scale |
|---|---|---|---|
| Carat | `carat DECIMAL(5,2)` | `CARAT_BAND` (reporting bands) | Weight, reported to the hundredth of a carat |
| Cut | `cut_grade` (nullable) | `CUT` | Excellent, Very Good, Good, Fair, Poor |
| Color | `color_grade CHAR(1)` | `COLOR` | D to Z (23 grades) |
| Clarity | `clarity_grade` | `CLARITY` | FL, IF, VVS1, VVS2, VS1, VS2, SI1, SI2, I1, I2, I3 |

The grade tables carry a `grade_rank` column (1 = best), so sort by rank, never alphabetically. `COLOR` and `CLARITY` also carry the GIA `category` for each grade. The data is seeded by `sql/02_reference_data.sql`.

## Carat

Carat is measured, not graded. One carat is 0.2 g. GIA reports the weight rounded to the hundredth of a carat, which is why `carat` is `DECIMAL(5,2)` and why both the transform script and the import round to 2 decimal places.

`CARAT_BAND` groups weights for reporting. The band edges sit at the weights where prices jump (0.30, 0.50, 0.70, 0.90, 1.00, 1.50, 2.00, 3.00 and 5.00 ct).

## Cut

GIA grades the cut of standard round brilliants on five levels, based on brightness, fire and scintillation. `cut_grade` is nullable because a stone has no cut grade until it is graded, and GIA assigns cut grades only to round brilliants.

## Color

| Range | Grades | GIA category |
|---|---|---|
| D-F | D, E, F | Colorless |
| G-J | G, H, I, J | Near Colorless |
| K-M | K, L, M | Faint |
| N-R | N, O, P, Q, R | Very Light |
| S-Z | S ... Z | Light |

### Fancy colors

Stones with a distinct hue (yellow, pink, blue and so on) are graded outside the D–Z scale. They have `color_type = 'FANCY'`, a `fancy_hue`, and a `fancy_intensity` on the GIA fancy scale: Faint, Very Light, Light, Fancy Light, Fancy, Fancy Intense, Fancy Vivid, Fancy Deep, Fancy Dark. A fancy stone never has a D–Z `color_grade`, and CHECK constraints enforce this. Fancy stones are priced manually, because the D–Z multipliers don't apply.

## Origin and polish state

- **Origin.** `origin` records whether a stone is `NATURAL` or `LAB_GROWN`. The two are graded on the same 4C scales.
- **Unpolished stones.** These are rough or partly worked stones, with `polish_state = 'UNPOLISHED'`. They are weighed but may have no grades yet.
- **Polished stones.** When a stone becomes `POLISHED`, the database requires a clarity grade, plus a D–Z color grade if it is white. Each weighing goes into `WEIGHT_LOG`, so the rough weight, the polished weight and the weight lost in polishing are all kept.

## Clarity

| Grade | GIA category |
|---|---|
| FL | Flawless: no inclusions or blemishes under 10x magnification |
| IF | Internally Flawless: no inclusions under 10x |
| VVS1, VVS2 | Very, Very Slightly Included: very hard to see under 10x |
| VS1, VS2 | Very Slightly Included: minor inclusions under 10x |
| SI1, SI2 | Slightly Included: noticeable under 10x |
| I1, I2, I3 | Included: may be visible to the naked eye |

## Pricing from the 4Cs

`sp_compute_price` combines the four Cs:

```
price_usd = carat × base_price_per_carat × cut.multiplier × color.multiplier × clarity.multiplier
```

An ungraded cut uses a multiplier of 1.0. The multipliers in `02_reference_data.sql` are illustrative values for this demo; they are not market data.

## Source data: Kaggle "Diamonds Prices 2022"

`data/raw/diamonds_prices_2022.csv` uses non-GIA cut names. `scripts/transform_to_gia.py` maps them onto the GIA scale and writes `data/processed/diamonds_prices_2022_gia.csv`. That output is generated, so it is gitignored.

| Source cut | GIA cut |
|---|---|
| Ideal | Excellent |
| Premium | Very Good |
| Very Good | Very Good |
| Good | Good |
| Fair | Fair |

Column mapping:

| Source | GIA CSV | `DIAMONDS` column |
|---|---|---|
| (index) | `diamond_id` | `sku` = `SKU-GIA-<id>` |
| carat | `carat_weight` | `carat` |
| cut | `cut_grade` | `cut_grade` |
| color | `color_grade` | `color_grade` |
| clarity | `clarity_grade` | `clarity_grade` |
| depth | `depth_percent` | `depth_pct` |
| table | `table_percent` | `table_pct` |
| x / y / z | `length_mm` / `width_mm` / `depth_mm` | same names |
| price | `price_usd` | `price_usd` |
| (new) | `certification_status` | `certified` |

The transform script rejects any row with a grade outside the GIA scales, a carat weight outside 0.01-100, a depth outside 30-80 %, a table outside 40-80 %, or a price of zero or less. With the 2022 dataset this keeps 53,942 of 53,943 rows; the one rejected row has a table of 95 %.

`sp_import_diamonds` checks every row again by joining it to `CUT`, `COLOR` and `CLARITY`. It also sets `base_price_per_carat = price / (carat × multipliers)`, so that running `sp_compute_price` later reproduces the price from the CSV.
