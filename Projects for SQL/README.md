# SQL Projects Portfolio

A collection of SQL projects demonstrating various database concepts including queries, joins, stored procedures, views, and schema design.

---

## Project Files

### Data Retrieval & Queries

#### 1. **Order Status Report** (`order_status_report.sql`)
Retrieves order information with shipping status using UNION to categorize orders as either "SHIPPED" or "NOT SHIPPED" based on whether a ship date exists. Results are ordered chronologically by order date.
- **Concepts**: UNION, conditional logic with IS NULL/IS NOT NULL

#### 2. **Product Retrieval** (`product.sql`)
Queries all products from the database, displaying product codes, names, list prices, and discount percentages, sorted by price in descending order.
- **Concepts**: SELECT, ORDER BY, column sorting

#### 3. **Addresses Table** (`addresses.sql`)
Simple retrieval of all address records from the my_guitar_shop database.
- **Concepts**: Basic SELECT query

#### 4. **Categories Table** (`categories.sql`)
Retrieves all category records from the my_guitar_shop database.
- **Concepts**: Basic SELECT query

---

### Aggregation & Group By

#### 5. **Category Product Analysis** (`category_product_analysis.sql`)
Analyzes product distribution across categories by retrieving category names, product counts, and the highest price in each category. Results are sorted by product count in descending order.
- **Concepts**: JOIN, GROUP BY, COUNT(), MAX(), aggregate functions

---

### Subqueries & Advanced Selection

#### 6. **Product Categories Filter** (`product_categories_filter.sql`)
Retrieves distinct category names that contain products, using a subquery to filter only categories with existing products.
- **Concepts**: Subqueries, DISTINCT, IN operator

#### 7. **Products With Shared Pricing** (`products_with_shared_pricing.sql`)
Finds products that share the same list price with at least one other product, using a self-join to compare prices between product records.
- **Concepts**: Self-join, JOIN conditions, comparison operators

---

### Data Manipulation

#### 8. **Add New Product** (`add_new_product.sql`)
Inserts a new digital piano product into the products table with complete details, then retrieves the newly added record to confirm the insertion was successful.
- **Concepts**: INSERT, VALUES, SELECT verification

---

### Database Schema Design

#### 9. **E-commerce Database Schema** (`ecommerce_schema.sql`)
Creates a complete database schema for a web-based product download platform with three interconnected tables:
- **users**: Stores user authentication and profile information
- **products**: Stores product details
- **downloads**: Tracks user product downloads with foreign keys linking to users and products

- **Concepts**: CREATE DATABASE, CREATE TABLE, PRIMARY KEY, FOREIGN KEY, AUTO_INCREMENT, UNIQUE constraints, Indexes

---

### Views

#### 10. **Customer Address View** (`customer_address_view.sql`)
Creates a reusable view that combines customer information with their billing and shipping addresses using multiple joins. Simplifies queries involving customer address data.
- **Concepts**: CREATE VIEW, Multiple JOINs, aliasing, data consolidation

---

### Stored Procedures

#### 11. **Product Count Validation** (`product_count_validation.sql`)
Creates a stored procedure that checks the total number of products in the database and returns a conditional message based on whether the count is 7 or more.
- **Concepts**: DELIMITER, CREATE PROCEDURE, DECLARE variables, IF/ELSE logic, CALL procedure

#### 12. **Category Insert with Error Handling** (`category_insert_with_error_handling.sql`)
Creates a stored procedure that inserts new categories into the categories table with graceful error handling. If a category already exists (duplicate), it displays an error message instead of crashing.
- **Concepts**: DELIMITER, CREATE PROCEDURE, EXIT HANDLER, SQLEXCEPTION handling, error management

---

## Skills Demonstrated

- **Query Fundamentals**: SELECT, WHERE, ORDER BY, filtering
- **Advanced Queries**: Subqueries, DISTINCT, UNION
- **Joins**: INNER JOIN, self-joins, multiple table joins
- **Aggregation**: GROUP BY, COUNT, MAX, aggregate functions
- **Schema Design**: Database and table creation, constraints, relationships
- **Data Manipulation**: INSERT operations with verification
- **Views**: Creating reusable query abstractions
- **Stored Procedures**: Procedural logic with error handling, conditional statements
- **Error Handling**: Exception handling in stored procedures

---

## Database Context

Most projects reference the **my_guitar_shop** database, which contains:
- `customers`: Customer information
- `products`: Product catalog
- `categories`: Product categories
- `addresses`: Address records
- `orders`: Order transactions
- `downloads`: User download history (in schema design)

---

## Getting Started

1. Ensure you have a MySQL database server running
2. Open each `.sql` file in your SQL editor
3. Update database/table names if needed for your environment
4. Execute the scripts in sequence or independently based on dependencies
5. Review the comments in each file for specific use cases

---

## Notes

- Some projects require existing database tables (my_guitar_shop)
- The schema design project (`ecommerce_schema.sql`) creates a new database from scratch
- Stored procedures include test cases demonstrating functionality
- Views are useful for simplifying complex queries used frequently
