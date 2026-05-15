---------------------------------------------------------------------------------------------------------------------
-- 1. Number of active users per day over the two weeks between August 24th 2025 and September 14th 2025, inclusive.
---------------------------------------------------------------------------------------------------------------------
SELECT
    DATE(event_timestamp) AS date,
    COUNT(DISTINCT anonymous_id) AS active_users
FROM `daily_events_deduped`
WHERE DATE(event_timestamp) BETWEEN '2025-08-24' AND '2025-09-14'
GROUP BY date
ORDER BY date;


----------------------------------------------------------------------------------------------
-- 2. Number of users completed each step of the user journey per day, with conversion rates
--------------------------------------------------------------------------------------------

-- active users
WITH daily AS (
    SELECT
        DATE(event_timestamp) AS date,
        anonymous_id
    FROM `daily_events_deduped`
    WHERE DATE(event_timestamp) BETWEEN '2025-08-24' AND '2025-09-14'
),
-- users who added products to cart 
cart AS (
    SELECT
        DATE(event_timestamp) AS date,
        anonymous_id
    FROM `event_product_added_to_cart_deduped`
    WHERE DATE(event_timestamp) BETWEEN '2025-08-24' AND '2025-09-14'
),
-- users who ordered
orders AS (
    SELECT
        DATE(event_timestamp) AS date,
        anonymous_id
    FROM `orders_unpacked`
    WHERE DATE(event_timestamp) BETWEEN '2025-08-24' AND '2025-09-14'
    
),
-- funnel of distinct users
funnel AS (
    SELECT
        d.date,
        COUNT(DISTINCT d.anonymous_id) AS step1_active_users,
        COUNT(DISTINCT c.anonymous_id) AS step2_added_to_cart,
        COUNT(DISTINCT o.anonymous_id) AS step3_placed_order
    FROM daily d
    LEFT JOIN cart c
        ON d.anonymous_id = c.anonymous_id
        AND d.date = c.date
    LEFT JOIN orders o
        ON d.anonymous_id = o.anonymous_id
        AND d.date = o.date
    GROUP BY d.date
)
-- conversion rates
SELECT
    date,
    step1_active_users,
    step2_added_to_cart,
    step3_placed_order,
    ROUND(step2_added_to_cart / NULLIF(step1_active_users, 0) * 100, 1) AS active_to_cart_rate,
    ROUND(step3_placed_order / NULLIF(step2_added_to_cart, 0) * 100, 1) AS cart_to_order_rate,
    ROUND(step3_placed_order / NULLIF(step1_active_users, 0) * 100, 1) AS overall_conversion_rate
FROM funnel
ORDER BY date;

--------------------------------------------------
 -- 3. Best performing product placement
 ------------------------------------------------

-- users who added products to cart 
WITH cart AS (
    SELECT
        anonymous_id,
        product_sku,
        product_placement,
        event_timestamp AS cart_ts
    FROM `event_product_added_to_cart_deduped`
    WHERE product_sku IS NOT NULL
      AND product_placement IS NOT NULL
),
-- users who ordered deduped
orders AS (
    -- Deduplicate orders (handle JSON-unpacked rows)
    SELECT DISTINCT
        anonymous_id,
        product_sku,
        MIN(event_timestamp) AS order_ts
    FROM `orders_unpacked`
    GROUP BY anonymous_id, product_sku
),
-- 
joined AS (
    SELECT
        c.anonymous_id,
        c.product_sku,
        c.product_placement,
        c.cart_ts,
        o.order_ts
    FROM cart c
    LEFT JOIN orders o
        ON c.anonymous_id = o.anonymous_id
        AND c.product_sku = o.product_sku
),
    -- Only cart events before order time
valid_cart AS (
    SELECT *
    FROM joined
    WHERE order_ts IS NULL
       OR cart_ts < order_ts
),

-- attribute only cart_timestamp closest to order_timestamp
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY anonymous_id, product_sku
            ORDER BY 
                CASE 
                    WHEN order_ts IS NOT NULL THEN TIMESTAMP_DIFF(order_ts, cart_ts,SECOND) 
                    ELSE NULL 
                END ASC,
                cart_ts DESC
        ) AS rn
    FROM valid_cart
),

attributed AS (
    SELECT
        anonymous_id,
        product_sku,
        product_placement,
        --Last-touch: only closest cart gets purchase credit
        CASE 
            WHEN order_ts IS NOT NULL AND rn = 1 THEN 1
            ELSE 0
        END AS purchased
    FROM ranked
),

final AS (
    SELECT
        product_placement,

        -- each user-product counted once
        COUNT(DISTINCT CONCAT(anonymous_id, product_sku)) AS user_product_added_to_cart,

        -- attributed purchases
        COUNT(DISTINCT CASE 
            WHEN purchased = 1 
            THEN CONCAT(anonymous_id, product_sku) 
        END) AS user_product_purchased,

        ROUND(
            COUNT(DISTINCT CASE 
                WHEN purchased = 1 
                THEN CONCAT(anonymous_id, product_sku) 
            END)
            / NULLIF(COUNT(DISTINCT CONCAT(anonymous_id, product_sku)), 0) * 100,
            1
        ) AS conversion_rate

    FROM attributed
    GROUP BY product_placement
)

SELECT
    *,
    RANK() OVER (ORDER BY user_product_added_to_cart DESC) AS volume_rank,
    RANK() OVER (ORDER BY conversion_rate DESC) AS conversion_rank
FROM final
ORDER BY conversion_rate DESC;

-------------------------------------------------------------------------------
-- 4.  products with the highest conversion rate from add to cart to purchase
---------------------------------------------------------------------------------

-- select products if exists in cart
WITH cart_products AS (
    SELECT
        product_sku,
        anonymous_id,
        MIN(event_timestamp) AS first_cart_ts
    FROM `event_product_added_to_cart_deduped`
    WHERE product_sku IS NOT NULL
    GROUP BY product_sku, anonymous_id
),
-- select products if ordered
orders AS (
    SELECT
        product_sku,
        anonymous_id,
        MIN(event_timestamp) AS order_ts
    FROM `orders_unpacked`
    GROUP BY product_sku, anonymous_id
),

joined AS (
    SELECT
        c.product_sku,
        c.anonymous_id,
        -- product purchased only when order_ts is greater than cart_ts and if order exists for the product
        CASE 
            WHEN o.order_ts IS NOT NULL 
                 AND c.first_cart_ts < o.order_ts 
            THEN 1 
            ELSE 0 
        END AS purchased
    FROM cart_products c
    LEFT JOIN orders o
        ON c.product_sku = o.product_sku
        AND c.anonymous_id = o.anonymous_id
)

SELECT
    product_sku,
    COUNT(*) AS users_added_to_cart,
    SUM(purchased) AS users_purchased,
    ROUND(SUM(purchased) / NULLIF(COUNT(*), 0) * 100, 1) AS conversion_rate
FROM joined
GROUP BY product_sku
HAVING COUNT(*) >= 10
ORDER BY conversion_rate DESC, product_sku
LIMIT 20;

------------------------------------------------------------------------------------
-- 5. Session analysis based on gaps between events
------------------------------------------------------------------------------------

SELECT
    gap_bucket,
    COUNT(*) AS count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct
FROM (
    SELECT
        CASE
            WHEN gap_minutes < 1 THEN '0-1 min'
            WHEN gap_minutes < 5 THEN '1-5 mins'
            WHEN gap_minutes < 15 THEN '5-15 mins'
            WHEN gap_minutes < 30 THEN '15-30 mins'
            WHEN gap_minutes < 60 THEN '30-60 mins'
            ELSE '60+ mins'
        END AS gap_bucket,
        gap_minutes
    FROM (
        SELECT
            -- time difference between preceeding event timestamps
            TIMESTAMP_DIFF( 
                event_timestamp,
                LAG(event_timestamp) OVER (
                    PARTITION BY anonymous_id
                    ORDER BY event_timestamp
                ),
                MINUTE
            ) AS gap_minutes
        FROM `daily_events_deduped`
    )
    WHERE gap_minutes IS NOT NULL
)
GROUP BY gap_bucket
ORDER BY MIN(gap_minutes);