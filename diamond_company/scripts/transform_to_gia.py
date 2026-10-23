#!/usr/bin/env python3
"""
Transform Diamonds CSV to GIA Standard Format
Ensures compliance with Gemological Institute of America standards (the 4Cs)

Usage (from anywhere):
    python3 diamond_company/scripts/transform_to_gia.py [INPUT_CSV] [OUTPUT_CSV]
"""

import csv
import sys
from pathlib import Path

# Default paths, relative to the diamond_company/ project folder
PROJECT_DIR = Path(__file__).resolve().parent.parent
INPUT_FILE = PROJECT_DIR / "data" / "raw" / "diamonds_prices_2022.csv"
OUTPUT_FILE = PROJECT_DIR / "data" / "processed" / "diamonds_prices_2022_gia.csv"

# GIA Cut Grade Mapping - standardize all cuts to GIA scale
CUT_MAPPING = {
    'Ideal': 'Excellent',
    'Premium': 'Very Good',
    'Very Good': 'Very Good',
    'Good': 'Good',
    'Fair': 'Fair',
    'Poor': 'Poor'
}

# Valid GIA Grades per GIA standards
VALID_COLORS = set('DEFGHIJKLMNOPQRSTUVWXYZ')
VALID_CLARITIES = {'FL', 'IF', 'VVS1', 'VVS2', 'VS1', 'VS2', 'SI1', 'SI2', 'I1', 'I2', 'I3'}

def transform_diamonds_to_gia(input_file=INPUT_FILE, output_file=OUTPUT_FILE):
    """Transform CSV to GIA standards with validation"""
    transformed_count = 0
    skipped_count = 0
    errors = []

    output_file = Path(output_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(input_file, 'r', newline='') as infile, open(output_file, 'w', newline='') as outfile:
        reader = csv.DictReader(infile)
        
        # GIA Standard headers
        fieldnames = [
            'diamond_id',
            'carat_weight',
            'cut_grade',
            'color_grade',
            'clarity_grade',
            'depth_percent',
            'table_percent',
            'length_mm',
            'width_mm',
            'depth_mm',
            'price_usd',
            'certification_status'
        ]
        
        # Unix line endings so LOAD DATA ... LINES TERMINATED BY '\n' is clean
        writer = csv.DictWriter(outfile, fieldnames=fieldnames, lineterminator='\n')
        writer.writeheader()
        
        for row_num, row in enumerate(reader, start=2):
            try:
                # Extract and validate data
                diamond_id = row.get('').strip() if row.get('') else str(row_num - 1)
                # GIA reports carat weight to the hundredth of a carat
                carat_weight = round(float(row['carat']), 2)
                cut_raw = row['cut'].strip()
                color_grade = row['color'].strip().upper()
                clarity_raw = row['clarity'].strip().upper()
                depth_percent = float(row['depth'])
                table_percent = float(row['table'])
                length_mm = float(row['x'])
                width_mm = float(row['y'])
                depth_mm = float(row['z'])
                price_usd = float(row['price'])
                
                # Validate and map cut grade to GIA standard
                if cut_raw not in CUT_MAPPING:
                    raise ValueError(f"Invalid cut grade: {cut_raw}")
                cut_grade = CUT_MAPPING[cut_raw]
                
                # Validate color grade (GIA uses D-Z scale)
                if color_grade not in VALID_COLORS:
                    raise ValueError(f"Invalid color grade: {color_grade}")
                
                # Validate clarity grade (GIA scale)
                if clarity_raw not in VALID_CLARITIES:
                    raise ValueError(f"Invalid clarity grade: {clarity_raw}")
                
                # Validate numeric ranges per GIA standards
                if not (0.01 <= carat_weight <= 100):
                    raise ValueError(f"Invalid carat weight: {carat_weight}")
                if not (30 <= depth_percent <= 80):
                    raise ValueError(f"Invalid depth percent: {depth_percent}")
                if not (40 <= table_percent <= 80):
                    raise ValueError(f"Invalid table percent: {table_percent}")
                if price_usd <= 0:
                    raise ValueError(f"Invalid price: {price_usd}")
                
                # Write transformed row with GIA standards
                writer.writerow({
                    'diamond_id': diamond_id,
                    'carat_weight': carat_weight,
                    'cut_grade': cut_grade,
                    'color_grade': color_grade,
                    'clarity_grade': clarity_raw,
                    'depth_percent': depth_percent,
                    'table_percent': table_percent,
                    'length_mm': length_mm,
                    'width_mm': width_mm,
                    'depth_mm': depth_mm,
                    'price_usd': price_usd,
                    'certification_status': 'NOT_CERTIFIED'
                })
                transformed_count += 1
                
            except (ValueError, KeyError) as e:
                skipped_count += 1
                if len(errors) < 5:
                    errors.append(f"Row {row_num}: {str(e)}")

    # Print results
    print(f"\n✓ GIA Standard Transformation Complete!")
    print(f"  Transformed records: {transformed_count:,}")
    print(f"  Skipped records: {skipped_count}")
    if errors:
        print(f"\n  First errors encountered:")
        for error in errors:
            print(f"    - {error}")
    print(f"  Output file: {output_file}")

    return transformed_count, skipped_count

if __name__ == "__main__":
    transform_diamonds_to_gia(*sys.argv[1:3])
