-- 1. Explore Raw Table

-- see the data first
SELECT * FROM bike_stores LIMIT 5;

-- check column names and data types
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'bike_stores'
ORDER BY ordinal_position;

-- total rows
SELECT COUNT(*) AS total_rows FROM bike_stores;


-- 2. Data Quality Check

-- check nulls across all columns
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)      AS null_order_id,
    COUNT(*) FILTER (WHERE customers IS NULL)     AS null_customers,
    COUNT(*) FILTER (WHERE order_date IS NULL)    AS null_order_date,
    COUNT(*) FILTER (WHERE revenue IS NULL)       AS null_revenue,
    COUNT(*) FILTER (WHERE total_units IS NULL)   AS null_total_units,
    COUNT(*) FILTER (WHERE product_name IS NULL)  AS null_product_name,
    COUNT(*) FILTER (WHERE category_name IS NULL) AS null_category_name,
    COUNT(*) FILTER (WHERE brand_name IS NULL)    AS null_brand_name,
    COUNT(*) FILTER (WHERE store_name IS NULL)    AS null_store_name,
    COUNT(*) FILTER (WHERE sales_rep IS NULL)     AS null_sales_rep,
    COUNT(*) FILTER (WHERE city IS NULL)          AS null_city,
    COUNT(*) FILTER (WHERE state IS NULL)         AS null_state
FROM bike_stores;

-- check for duplicate order_id
SELECT
    order_id,
    COUNT(*) AS occurrences
FROM bike_stores
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- make sure no negative or zero values in revenue and units
SELECT
    MIN(total_units)  AS min_units,
    MAX(total_units)  AS max_units,
    MIN(revenue)      AS min_revenue,
    MAX(revenue)      AS max_revenue,
    COUNT(*) FILTER (WHERE total_units <= 0) AS zero_or_neg_units,
    COUNT(*) FILTER (WHERE revenue <= 0)     AS zero_or_neg_revenue
FROM bike_stores;

-- check date range
SELECT
    MIN(order_date) AS earliest_date,
    MAX(order_date) AS latest_date
FROM bike_stores;

-- list all months to see which years are complete
SELECT
    DISTINCT
    TO_CHAR(order_date, 'MM-YYYY')  AS month_year,
    EXTRACT(YEAR FROM order_date)   AS year,
    EXTRACT(MONTH FROM order_date)  AS month
FROM bike_stores
ORDER BY year, month;

-- transactions and revenue per year
-- 2020 only has a few months so we'll exclude it
SELECT
    EXTRACT(YEAR FROM order_date) AS year,
    COUNT(*)                      AS total_transactions,
    ROUND(SUM(revenue), 2)        AS total_revenue
FROM bike_stores
GROUP BY year
ORDER BY year;

-- check category names, make sure no typos
SELECT
    category_name,
    COUNT(*) AS row_count
FROM bike_stores
GROUP BY category_name
ORDER BY category_name;

-- check brand names
SELECT
    brand_name,
    COUNT(*) AS row_count
FROM bike_stores
GROUP BY brand_name
ORDER BY brand_name;

-- check store names
SELECT
    store_name,
    COUNT(*) AS row_count
FROM bike_stores
GROUP BY store_name
ORDER BY store_name;

-- check state values and how many cities per state
SELECT
    state,
    COUNT(DISTINCT city) AS city_count,
    COUNT(*)             AS row_count
FROM bike_stores
GROUP BY state
ORDER BY state;


-- 3. Add unit_price Column

-- unit_price is needed for price range analysis in Python
-- and for Power BI measures
ALTER TABLE bike_stores ADD COLUMN IF NOT EXISTS unit_price NUMERIC(18,2);

UPDATE bike_stores
SET unit_price = ROUND(revenue / NULLIF(total_units, 0), 2);

-- verify the calculation looks right
SELECT
    order_id,
    total_units,
    revenue,
    unit_price,
    ROUND(unit_price * total_units, 2) AS calculated_revenue,
    ABS(revenue - ROUND(unit_price * total_units, 2)) AS discrepancy
FROM bike_stores
ORDER BY order_id
LIMIT 10;

-- price range per brand
-- this helps explain why Trek revenue is higher than Electra
-- even though Electra sells more units
SELECT
    brand_name,
    ROUND(MIN(unit_price), 2)     AS min_price,
    ROUND(MAX(unit_price), 2)     AS max_price,
    ROUND(AVG(unit_price), 2)     AS avg_price,
    COUNT(DISTINCT product_name)  AS product_variants
FROM bike_stores
GROUP BY brand_name
ORDER BY avg_price DESC;


-- 4. Create View

-- filter to 2016-2019 only, exclude incomplete 2020
-- this view is what Python reads:
-- df = pd.read_sql("SELECT * FROM bike_sales.v_bike_sales", engine)
CREATE OR REPLACE VIEW bike_sales.v_bike_sales AS
SELECT
    order_id,
    customers,
    city,
    state,
    order_date,
    total_units,
    revenue,
    unit_price,
    product_name,
    category_name,
    brand_name,
    store_name,
    sales_rep
FROM bike_stores
WHERE EXTRACT(YEAR FROM order_date) BETWEEN 2016 AND 2019;

-- confirm the period is correct
SELECT
    MIN(order_date) AS earliest,
    MAX(order_date) AS latest,
    COUNT(*)        AS total_rows
FROM bike_sales.v_bike_sales;

-- final check before handing off to Python
SELECT * FROM bike_sales.v_bike_sales ORDER BY order_id LIMIT 5;


-- 5. Exploratory Queries

-- yearly revenue overview
SELECT
    EXTRACT(YEAR FROM order_date)          AS year,
    COUNT(DISTINCT order_id)               AS total_orders,
    SUM(total_units)                       AS total_units_sold,
    ROUND(SUM(revenue), 2)                 AS total_revenue,
    ROUND(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS avg_order_value
FROM bike_sales.v_bike_sales
GROUP BY year
ORDER BY year;

-- revenue by state
SELECT
    state,
    ROUND(SUM(revenue), 2)                                     AS total_revenue,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER(), 2)  AS revenue_share_pct,
    COUNT(DISTINCT city)                                        AS city_count
FROM bike_sales.v_bike_sales
GROUP BY state
ORDER BY total_revenue DESC;

-- top 15 cities by revenue
-- used as reference for the expansion recommendation
SELECT
    city,
    state,
    ROUND(SUM(revenue), 2) AS total_revenue,
    COUNT(*)               AS total_orders
FROM bike_sales.v_bike_sales
GROUP BY city, state
ORDER BY total_revenue DESC
LIMIT 15;

-- revenue and units by brand, including price range
SELECT
    brand_name,
    SUM(total_units)          AS total_units_sold,
    ROUND(SUM(revenue), 2)    AS total_revenue,
    ROUND(MIN(unit_price), 2) AS min_price,
    ROUND(MAX(unit_price), 2) AS max_price,
    ROUND(AVG(unit_price), 2) AS avg_price
FROM bike_sales.v_bike_sales
GROUP BY brand_name
ORDER BY total_revenue DESC;

-- category revenue broken down by year
SELECT
    category_name,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2016 THEN revenue END), 2) AS rev_2016,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2017 THEN revenue END), 2) AS rev_2017,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2018 THEN revenue END), 2) AS rev_2018,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2019 THEN revenue END), 2) AS rev_2019,
    ROUND(SUM(revenue), 2)                                                          AS total_revenue
FROM bike_sales.v_bike_sales
GROUP BY category_name
ORDER BY total_revenue DESC;

-- top 10 products by total revenue
SELECT
    product_name,
    category_name,
    SUM(total_units)       AS total_units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM bike_sales.v_bike_sales
GROUP BY product_name, category_name
ORDER BY total_revenue DESC
LIMIT 10;

-- store contribution per year
SELECT
    EXTRACT(YEAR FROM order_date) AS year,
    store_name,
    ROUND(SUM(revenue), 2) AS store_revenue,
    ROUND(
        SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (
            PARTITION BY EXTRACT(YEAR FROM order_date)
        ), 2
    ) AS revenue_share_pct
FROM bike_sales.v_bike_sales
GROUP BY year, store_name
ORDER BY year, store_revenue DESC;

-- 2019 monthly orders - checking the decline pattern
SELECT
    EXTRACT(MONTH FROM order_date) AS month,
    TO_CHAR(order_date, 'Mon')     AS month_name,
    COUNT(DISTINCT order_id)       AS total_orders,
    ROUND(SUM(revenue), 2)         AS total_revenue
FROM bike_sales.v_bike_sales
WHERE EXTRACT(YEAR FROM order_date) = 2019
GROUP BY month, month_name
ORDER BY month;

-- brand performance 2018 vs 2019
SELECT
    brand_name,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2018 THEN revenue END), 2) AS rev_2018,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2019 THEN revenue END), 2) AS rev_2019,
    ROUND(
        (SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2019 THEN revenue END) -
         SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2018 THEN revenue END)) * 100.0 /
        NULLIF(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = 2018 THEN revenue END), 0),
    2) AS pct_change
FROM bike_sales.v_bike_sales
GROUP BY brand_name
ORDER BY rev_2018 DESC NULLS LAST;


-- 6. Post-Python Validation

-- check the table exported from Python
SELECT * FROM bike_sales.bike_sales_clean LIMIT 10;

-- fix data types - Python sometimes exports everything as text
ALTER TABLE bike_sales.bike_sales_clean
    ALTER COLUMN revenue     TYPE NUMERIC(10,2) USING revenue::NUMERIC(10,2),
    ALTER COLUMN unit_price  TYPE NUMERIC(10,2) USING unit_price::NUMERIC(10,2),
    ALTER COLUMN order_date  TYPE DATE          USING order_date::DATE,
    ALTER COLUMN total_units TYPE INT           USING total_units::INT;

-- verify data types look correct
SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'bike_sales'
  AND table_name   = 'bike_sales_clean'
ORDER BY ordinal_position;

-- make sure row count matches the source view
SELECT 'v_bike_sales'     AS source, COUNT(*) AS row_count FROM bike_sales.v_bike_sales
UNION ALL
SELECT 'bike_sales_clean' AS source, COUNT(*) AS row_count FROM bike_sales.bike_sales_clean;

-- confirm date range is still 2016-2019
SELECT
    MIN(order_date) AS earliest,
    MAX(order_date) AS latest
FROM bike_sales.bike_sales_clean;

-- spot check a few rows
SELECT
    order_id,
    customers,
    order_date,
    store_name,
    product_name,
    total_units,
    unit_price,
    revenue
FROM bike_sales.bike_sales_clean
ORDER BY order_id
LIMIT 10;