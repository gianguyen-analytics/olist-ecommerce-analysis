/* =====================================================
   OLIST E-COMMERCE BUSINESS ANALYSIS
   ===================================================== */


/* 1. Monthly Revenue and Order Volume */
USE Olist_Ecommerce;
GO

WITH order_totals AS (
    SELECT
        o.order_id,
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        ) AS order_month,
        SUM(oi.price) AS order_revenue
    FROM dbo.orders AS o
    INNER JOIN dbo.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.order_id,
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        )
)

SELECT
    order_month,
    COUNT(order_id) AS total_orders,
    ROUND(SUM(order_revenue), 2) AS total_revenue,
    ROUND(AVG(order_revenue), 2) AS average_order_value
FROM order_totals
GROUP BY order_month
ORDER BY order_month;



/* 2. Top Product Categories by Revenue */
SELECT TOP 10
    COALESCE(
        ct.product_category_name_english,
        'Unknown'
    ) AS product_category,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(*) AS items_sold,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS average_product_price
FROM dbo.order_items AS oi
LEFT JOIN dbo.products AS p
    ON oi.product_id = p.product_id
LEFT JOIN dbo.category_translation AS ct
    ON p.product_category_name = ct.product_category_name
GROUP BY
    COALESCE(
        ct.product_category_name_english,
        'Unknown'
    )
ORDER BY total_revenue DESC;


/* 3. Revenue by Customer State */
WITH order_level AS (
    SELECT
        o.order_id,
        c.customer_state,
        SUM(oi.price) AS order_revenue,
        DATEDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0 AS delivery_days
    FROM dbo.orders AS o
    INNER JOIN dbo.customers AS c
        ON o.customer_id = c.customer_id
    INNER JOIN dbo.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY
        o.order_id,
        c.customer_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
),

state_summary AS (
    SELECT
        customer_state,
        COUNT(*) AS total_orders,
        SUM(order_revenue) AS total_revenue,
        AVG(order_revenue) AS average_order_value,
        AVG(delivery_days) AS average_delivery_days
    FROM order_level
    GROUP BY customer_state
)

SELECT
    customer_state,
    total_orders,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(
        total_revenue * 100.0
        / SUM(total_revenue) OVER (),
        2
    ) AS revenue_share_percent,
    ROUND(average_order_value, 2) AS average_order_value,
    ROUND(average_delivery_days, 2) AS average_delivery_days
FROM state_summary
ORDER BY total_revenue DESC;


/* 4. Repeat Purchase Rate */
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS number_of_orders
    FROM dbo.orders AS o
    INNER JOIN dbo.customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS total_customers,
    SUM(
        CASE
            WHEN number_of_orders > 1 THEN 1
            ELSE 0
        END
    ) AS repeat_customers,
    ROUND(
        SUM(
            CASE
                WHEN number_of_orders > 1 THEN 1.0
                ELSE 0.0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS repeat_purchase_rate_percent
FROM customer_order_counts;



/* 5. Payment Method Usage */
WITH payment_summary AS (
    SELECT
        payment_type,
        COUNT(*) AS total_payment_records,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(payment_value) AS total_payment_value,
        AVG(payment_value) AS average_payment_value
    FROM dbo.payments
    WHERE payment_type <> 'not_defined'
    GROUP BY payment_type
)

SELECT
    payment_type,
    total_payment_records,
    total_orders,
    ROUND(total_payment_value, 2) AS total_payment_value,
    ROUND(average_payment_value, 2) AS average_payment_value,
    ROUND(
        total_orders * 100.0 / SUM(total_orders) OVER (),
        2
    ) AS order_share_percent
FROM payment_summary
ORDER BY total_orders DESC;



/* 6. Delivery Performance and Review Scores */
WITH review_by_order AS (
    SELECT
        order_id,
        AVG(CAST(review_score AS decimal(10, 2))) AS review_score
    FROM dbo.reviews
    GROUP BY order_id
),

delivery_reviews AS (
    SELECT
        o.order_id,
        r.review_score,
        CASE
            WHEN o.order_delivered_customer_date
                 <= o.order_estimated_delivery_date
                THEN 'On Time or Early'
            ELSE 'Late'
        END AS delivery_status
    FROM dbo.orders AS o
    INNER JOIN review_by_order AS r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)

SELECT
    delivery_status,
    COUNT(*) AS total_orders,
    ROUND(AVG(review_score), 2) AS average_review_score
FROM delivery_reviews
GROUP BY delivery_status
ORDER BY average_review_score;



/* 7. High-Sales Sellers with Poor Ratings */

;WITH review_by_order AS (
    SELECT
        order_id,
        AVG(CAST(review_score AS DECIMAL(10, 2))) AS review_score
    FROM dbo.reviews
    GROUP BY order_id
),

delivered_items AS (
    SELECT
        oi.order_id,
        oi.order_item_id,
        oi.seller_id,
        oi.price
    FROM dbo.order_items AS oi
    INNER JOIN dbo.orders AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
),

seller_sales AS (
    SELECT
        seller_id,
        COUNT(DISTINCT order_id) AS total_orders,
        COUNT(*) AS items_sold,
        SUM(price) AS total_revenue
    FROM delivered_items
    GROUP BY seller_id
),

seller_orders AS (
    SELECT DISTINCT
        seller_id,
        order_id
    FROM delivered_items
),

seller_ratings AS (
    SELECT
        so.seller_id,
        AVG(r.review_score) AS average_review_score,
        COUNT(DISTINCT so.order_id) AS reviewed_orders
    FROM seller_orders AS so
    INNER JOIN review_by_order AS r
        ON so.order_id = r.order_id
    GROUP BY so.seller_id
),

seller_summary AS (
    SELECT
        s.seller_id,
        s.total_orders,
        s.items_sold,
        s.total_revenue,
        r.average_review_score,
        r.reviewed_orders
    FROM seller_sales AS s
    INNER JOIN seller_ratings AS r
        ON s.seller_id = r.seller_id
),

seller_threshold AS (
    SELECT
        ss.*,
        PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY ss.total_revenue)
        OVER () AS high_revenue_threshold
    FROM seller_summary AS ss
)

SELECT
    seller_id,
    total_orders,
    items_sold,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(average_review_score, 2) AS average_review_score,
    reviewed_orders,
    ROUND(high_revenue_threshold, 2) AS high_revenue_threshold
FROM seller_threshold
WHERE total_revenue >= high_revenue_threshold
  AND average_review_score < 3.5
  AND reviewed_orders >= 20
ORDER BY total_revenue DESC;