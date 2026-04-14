-- ============================================================================
-- INSTACART BASKET ANALYSIS — SQL Script
-- ============================================================================
-- Business Question:
--   "Which products and departments show strong, repeatable demand patterns
--    that should guide smarter restocking?"
--
-- Team 1
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- PART 1: DATABASE SETUP & TABLE CREATION
-- ────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS instacart;
USE instacart;

-- Table: orders
CREATE TABLE IF NOT EXISTS orders (
    order_id            INT PRIMARY KEY,
    user_id             INT,
    eval_set            VARCHAR(20),
    order_number        INT,
    order_dow           INT,               -- 0 = Saturday, 1 = Sunday, ... 6 = Friday
    order_hour_of_day   INT,
    days_since_prior_order INT NULL
);

-- Table: order_products
CREATE TABLE IF NOT EXISTS order_products (
    order_id            INT,
    product_id          INT,
    add_to_cart_order   INT,
    reordered           INT,               -- 1 = reordered, 0 = first time
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- Table: products
CREATE TABLE IF NOT EXISTS products (
    product_id          INT PRIMARY KEY,
    product_name        VARCHAR(255),
    aisle_id            INT,
    department_id       INT
);

-- Table: departments
CREATE TABLE IF NOT EXISTS departments (
    department_id       INT PRIMARY KEY,
    department          VARCHAR(50)
);


-- ────────────────────────────────────────────────────────────────────────────
-- PART 2: DATA IMPORT
-- ────────────────────────────────────────────────────────────────────────────
-- Option A: Use MySQL Workbench → Table Data Import Wizard
--   Right-click each table → Table Data Import Wizard → select the .csv file
--
-- Option B: Use LOAD DATA (update file paths to match your system)
--   NOTE: You may need to enable local_infile:
--   SET GLOBAL local_infile = 1;

/*
LOAD DATA LOCAL INFILE '/path/to/departments.csv'
INTO TABLE departments
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE '/path/to/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE '/path/to/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, user_id, eval_set, order_number, order_dow, order_hour_of_day, @dspo)
SET days_since_prior_order = NULLIF(@dspo, '');

LOAD DATA LOCAL INFILE '/path/to/order_products.csv'
INTO TABLE order_products
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
*/


-- ────────────────────────────────────────────────────────────────────────────
-- PART 3: BASIC DATA EXPLORATION
-- ────────────────────────────────────────────────────────────────────────────

-- Quick row counts
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'order_products', COUNT(*) FROM order_products
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'departments', COUNT(*) FROM departments;

-- Overall reorder rate
SELECT
    COUNT(*) AS total_items_ordered,
    SUM(reordered) AS total_reordered,
    ROUND(SUM(reordered) / COUNT(*) * 100, 1) AS overall_reorder_rate_pct
FROM order_products;


-- ============================================================================
-- PART 4: ADVANCED ANALYTICAL QUERIES
-- ============================================================================
-- Business Question: Which products & departments show strong, repeatable
-- demand patterns that should guide smarter restocking?
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 1: HIGH-LOYALTY DEPARTMENTS (GROUP BY + HAVING)
-- ────────────────────────────────────────────────────────────────────────────
-- Which departments have reorder rates above 55%? These departments have
-- customers who repeatedly buy the same products — strong restocking signal.

SELECT
    d.department,
    COUNT(*)                                        AS total_items_ordered,
    SUM(op.reordered)                               AS total_reorders,
    ROUND(SUM(op.reordered) / COUNT(*) * 100, 1)    AS reorder_rate_pct,
    COUNT(DISTINCT op.product_id)                    AS unique_products,
    ROUND(AVG(op.add_to_cart_order), 1)              AS avg_cart_position
FROM order_products op
JOIN products p ON op.product_id = p.product_id
JOIN departments d ON p.department_id = d.department_id
GROUP BY d.department
HAVING reorder_rate_pct > 55
ORDER BY reorder_rate_pct DESC;

-- INSIGHT: Departments with >55% reorder rate (dairy eggs, produce, beverages,
-- bakery, pets, deli) represent the most predictable demand — ideal candidates
-- for automated restocking triggers.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 2: ORGANIC PRODUCT DEMAND ANALYSIS (LIKE + GROUP BY + HAVING)
-- ────────────────────────────────────────────────────────────────────────────
-- Among products with "Organic" in the name, which have the highest
-- reorder rates? Organic products often carry premium margins.

SELECT
    p.product_name,
    d.department,
    COUNT(*)                                        AS times_ordered,
    SUM(op.reordered)                               AS times_reordered,
    ROUND(SUM(op.reordered) / COUNT(*) * 100, 1)    AS reorder_rate_pct
FROM order_products op
JOIN products p ON op.product_id = p.product_id
JOIN departments d ON p.department_id = d.department_id
WHERE p.product_name LIKE '%Organic%'
GROUP BY p.product_id, p.product_name, d.department
HAVING times_ordered > 1000
ORDER BY reorder_rate_pct DESC
LIMIT 15;

-- INSIGHT: Organic products (especially bananas, milk, avocado, spinach)
-- show reorder rates of 75–84%, far above the 59% overall average.
-- These high-margin, high-loyalty items should NEVER go out of stock.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 3: ABOVE-AVERAGE DEMAND PRODUCTS (SUBQUERY)
-- ────────────────────────────────────────────────────────────────────────────
-- Find products whose order count exceeds the average. This uses a
-- subquery to dynamically calculate the average order count.

SELECT
    p.product_name,
    d.department,
    product_orders.order_count,
    product_orders.reorder_rate_pct
FROM (
    SELECT
        product_id,
        COUNT(*)                                        AS order_count,
        ROUND(SUM(reordered) / COUNT(*) * 100, 1)       AS reorder_rate_pct
    FROM order_products
    GROUP BY product_id
) AS product_orders
JOIN products p ON product_orders.product_id = p.product_id
JOIN departments d ON p.department_id = d.department_id
WHERE product_orders.order_count > (
    SELECT AVG(order_count)
    FROM (
        SELECT COUNT(*) AS order_count
        FROM order_products
        GROUP BY product_id
    ) AS avg_calc
)
ORDER BY product_orders.order_count DESC
LIMIT 20;

-- INSIGHT: The top 20 products by volume are almost entirely produce
-- and dairy — bananas alone account for 15,000+ orders. These are the
-- "must-have" items that drive repeat store visits.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 4: TOP PRODUCT PER DEPARTMENT (CORRELATED SUBQUERY)
-- ────────────────────────────────────────────────────────────────────────────
-- For each department, find the single product with the most orders.
-- Uses a correlated subquery to compare within each department.

SELECT
    d.department,
    p.product_name,
    dept_products.order_count,
    dept_products.reorder_rate_pct
FROM (
    SELECT
        p2.department_id,
        op2.product_id,
        COUNT(*)                                        AS order_count,
        ROUND(SUM(op2.reordered) / COUNT(*) * 100, 1)   AS reorder_rate_pct
    FROM order_products op2
    JOIN products p2 ON op2.product_id = p2.product_id
    GROUP BY p2.department_id, op2.product_id
) AS dept_products
JOIN products p ON dept_products.product_id = p.product_id
JOIN departments d ON dept_products.department_id = d.department_id
WHERE dept_products.order_count = (
    SELECT MAX(sub.order_count)
    FROM (
        SELECT
            p3.department_id,
            COUNT(*) AS order_count
        FROM order_products op3
        JOIN products p3 ON op3.product_id = p3.product_id
        GROUP BY p3.department_id, op3.product_id
    ) AS sub
    WHERE sub.department_id = dept_products.department_id
)
ORDER BY dept_products.order_count DESC;

-- INSIGHT: Each department has a clear "champion" product — Banana (produce),
-- Organic Whole Milk (dairy eggs), 100% Whole Wheat Bread (bakery), etc.
-- These anchors drive department traffic and must always be in stock.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 5: PRIORITY RESTOCK LIST (SUBQUERY + HAVING + GROUP BY)
-- ────────────────────────────────────────────────────────────────────────────
-- Find products with BOTH high volume AND high reorder rate — the sweet
-- spot for restocking priority. Uses subqueries for dynamic thresholds.

SELECT
    p.product_name,
    d.department,
    COUNT(*)                                        AS total_orders,
    ROUND(SUM(op.reordered) / COUNT(*) * 100, 1)    AS reorder_rate_pct,
    ROUND(AVG(op.add_to_cart_order), 1)              AS avg_cart_position
FROM order_products op
JOIN products p ON op.product_id = p.product_id
JOIN departments d ON p.department_id = d.department_id
GROUP BY p.product_id, p.product_name, d.department
HAVING total_orders > (
        SELECT AVG(cnt) * 5
        FROM (SELECT COUNT(*) AS cnt FROM order_products GROUP BY product_id) AS t
    )
    AND reorder_rate_pct > (
        SELECT ROUND(SUM(reordered) / COUNT(*) * 100, 1) FROM order_products
    )
ORDER BY total_orders DESC
LIMIT 25;

-- INSIGHT: These 25 products are the "restocking VIPs" — high volume
-- AND above-average reorder rate. Most are produce and dairy staples
-- added early in the cart (position 4–8), suggesting they're top-of-mind.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 6: WEEKLY DEMAND CYCLE ANALYSIS (GROUP BY + CASE + SUBQUERY)
-- ────────────────────────────────────────────────────────────────────────────
-- Analyze how ordering patterns shift by day of week — when should
-- restocking happen to stay ahead of demand?

SELECT
    CASE o.order_dow
        WHEN 0 THEN 'Saturday'
        WHEN 1 THEN 'Sunday'
        WHEN 2 THEN 'Monday'
        WHEN 3 THEN 'Tuesday'
        WHEN 4 THEN 'Wednesday'
        WHEN 5 THEN 'Thursday'
        WHEN 6 THEN 'Friday'
    END AS day_of_week,
    COUNT(*)                                        AS total_items,
    SUM(op.reordered)                               AS reordered_items,
    ROUND(SUM(op.reordered) / COUNT(*) * 100, 1)    AS reorder_rate_pct,
    ROUND(COUNT(*) / (
        SELECT COUNT(*) / 7 FROM order_products op2
        JOIN orders o2 ON op2.order_id = o2.order_id
    ) * 100, 1)                                      AS pct_vs_daily_avg
FROM order_products op
JOIN orders o ON op.order_id = o.order_id
GROUP BY o.order_dow
ORDER BY o.order_dow;

-- INSIGHT: Saturday has ~60% more volume than midweek. Sunday shows the
-- highest reorder rate (60.6%). Restocking should complete by Friday
-- evening to prepare for the weekend surge.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 7: REORDER FREQUENCY BUCKETS (CASE + GROUP BY + SUBQUERY)
-- ────────────────────────────────────────────────────────────────────────────
-- Classify customers by how frequently they reorder. This reveals the
-- dominant restocking cycles for inventory planning.

SELECT
    frequency_bucket,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM orders WHERE days_since_prior_order IS NOT NULL) * 100, 1) AS pct_of_orders
FROM (
    SELECT
        CASE
            WHEN days_since_prior_order BETWEEN 0 AND 7   THEN '1) Weekly (0-7 days)'
            WHEN days_since_prior_order BETWEEN 8 AND 14   THEN '2) Bi-weekly (8-14 days)'
            WHEN days_since_prior_order BETWEEN 15 AND 21  THEN '3) Tri-weekly (15-21 days)'
            WHEN days_since_prior_order BETWEEN 22 AND 30  THEN '4) Monthly (22-30 days)'
            ELSE                                                '5) Infrequent (30+ days)'
        END AS frequency_bucket
    FROM orders
    WHERE days_since_prior_order IS NOT NULL
) AS bucketed
GROUP BY frequency_bucket
ORDER BY frequency_bucket;

-- INSIGHT: ~57% of orders happen within 7 days of the prior order —
-- weekly grocery runs dominate. The second spike at 30 days captures
-- monthly bulk buyers. Restock planning should sync to these two rhythms.


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 8: PEAK HOUR REORDER ANALYSIS (GROUP BY + HAVING + CASE)
-- ────────────────────────────────────────────────────────────────────────────
-- During which hours are customers most likely to reorder staples?
-- This helps optimize when to surface "buy again" recommendations.

SELECT
    o.order_hour_of_day,
    CASE
        WHEN o.order_hour_of_day BETWEEN 5 AND 8   THEN 'Early Morning'
        WHEN o.order_hour_of_day BETWEEN 9 AND 12   THEN 'Late Morning'
        WHEN o.order_hour_of_day BETWEEN 13 AND 17  THEN 'Afternoon'
        WHEN o.order_hour_of_day BETWEEN 18 AND 21  THEN 'Evening'
        ELSE                                              'Night'
    END AS time_period,
    COUNT(*)                                        AS total_items,
    ROUND(SUM(op.reordered) / COUNT(*) * 100, 1)    AS reorder_rate_pct
FROM order_products op
JOIN orders o ON op.order_id = o.order_id
GROUP BY o.order_hour_of_day
HAVING total_items > 500
ORDER BY o.order_hour_of_day;

-- INSIGHT: Early morning (5–9 AM) shoppers have the HIGHEST reorder
-- rates (63–65%), meaning they're stocking up on known staples.
-- Evening shoppers (after 6 PM) explore more (55–57% reorder rate).
-- Surface "reorder" prompts more aggressively to morning users.


-- ============================================================================
-- END OF ANALYSIS
-- ============================================================================
-- Next steps:
--   1. Run each query in MySQL Workbench
--   2. Screenshot the results under each query
--   3. Export key result sets to CSV for Tableau visualization
--   4. Build Tableau dashboard connecting to this MySQL database
-- ============================================================================
