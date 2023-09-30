--DIGITAL ANALYSIS

--1. How many users are there?

SELECT COUNT (DISTINCT (user_id)) AS total_users
FROM clique_bait.users 

--2. How many cookies does each user have on average?

WITH totals AS(
SELECT
	COUNT (DISTINCT (user_id)) as total_users,
	COUNT(cookie_id) as total_cookies
FROM clique_bait.users 
)
select (total_cookies/total_users) as average_cookies_per_user
from totals

--3. What is the unique number of visits by all users per month?

SELECT
	DATEPART (month,event_time) as month,
	COUNT (DISTINCT(visit_id)) total_visits
FROM clique_bait.events
GROUP BY DATEPART (month,event_time)
ORDER BY DATEPART (month,event_time)

--4. What is the number of events for each event type?
SELECT
	e.event_type,
	ei.event_name,
	COUNT( DISTINCT(e.event_time)) as number_events
FROM clique_bait.events e
JOIN clique_bait.event_identifier ei
ON ei.event_type=e.event_type
GROUP BY e.event_type,event_name
ORDER BY event_type

--5. What is the percentage of visits which have a purchase event?

SELECT
    ROUND((SELECT COUNT(DISTINCT visit_id) FROM clique_bait.events WHERE event_type = 3) * 100.0 /
    (SELECT COUNT(DISTINCT visit_id) FROM clique_bait.events),3) AS purchase_percentage;

--6. What is the percentage of visits which view the checkout page but do not have a purchase event?
SELECT
    (SELECT COUNT(DISTINCT e.visit_id) 
     FROM clique_bait.events e
     WHERE e.page_id = 12 AND 
           e.visit_id NOT IN (SELECT DISTINCT visit_id FROM clique_bait.events WHERE event_type = 3)) * 100.0 /
    (SELECT COUNT(DISTINCT visit_id) FROM clique_bait.events WHERE page_id = 12) AS no_purchase_checkout_percentage;

--7. What are the top 3 pages by number of views?
SELECT TOP 3
	page_id,
	COUNT(event_type) AS number_views
FROM clique_bait.events
WHERE event_type=1
GROUP BY page_id
ORDER BY number_views desc;

--8. What is the number of views and cart adds for each product category?
SELECT 
	ph.product_category,
	SUM( CASE WHEN ei.event_name='Page View' THEN 1 ELSE 0 END) AS page_view,
	SUM( CASE WHEN ei.event_name='Add to Cart' THEN 1 ELSE 0 END) AS Add_Card_view

FROM clique_bait.page_hierarchy ph
JOIN clique_bait.events e
ON e.page_id=ph.page_id
JOIN clique_bait.event_identifier ei
ON ei.event_type=e.event_type
WHERE ph.product_category IS NOT null
GROUP BY product_category
ORDER BY page_view DESC;

--9. What are the top 3 products by purchases?
WITH purchases AS (
	SELECT visit_id
	FROM clique_bait.events
	WHERE event_type = 3
)
SELECT TOP 3
	ph.page_name,
	SUM(
		CASE WHEN e.event_type = 2 THEN 1 ELSE 0 END ) AS purchased
FROM clique_bait.page_hierarchy AS ph
	JOIN clique_bait.events AS e ON e.page_id = ph.page_id
	JOIN purchases AS gp ON e.visit_id = gp.visit_id
WHERE ph.product_category IS NOT NULL
	AND ph.page_id NOT in('1', '2', '12', '13')
	AND gp.visit_id = e.visit_id
GROUP BY ph.page_name
ORDER BY purchased DESC


--PRODUCT FUNNEL ANALYSIS
DROP TABLE ProductAnalysis;

-- Using Common Table Expressions (CTEs) for clarity
WITH ProductViews AS (
    SELECT 
        page_id,
        COUNT(visit_id) AS view_count
    FROM 
        clique_bait.events
    WHERE 
        event_type = 1
    GROUP BY 
        page_id
),

ProductCartAdd AS (
    SELECT 
        page_id,
        COUNT(visit_id) AS cart_add_count
    FROM 
        clique_bait.events
    WHERE 
        event_type = 2
    GROUP BY 
        page_id
),

ProductAbandoned AS (
    SELECT 
        e.page_id,
        COUNT(e.visit_id) AS abandoned_count
    FROM 
        clique_bait.events e
    WHERE 
        e.event_type = 2 AND NOT EXISTS (
            SELECT 1 
            FROM clique_bait.events ev2 
            WHERE ev2.visit_id = e.visit_id AND ev2.event_type = 3
        )
    GROUP BY 
        e.page_id
),

ProductPurchased AS (
	SELECT 
		e.page_id,
		SUM( CASE WHEN event_type = 2 THEN 1 ELSE 0 END ) AS purchased_from_cart
	FROM clique_bait.page_hierarchy AS ph
			JOIN clique_bait.events AS e ON ph.page_id = e.page_id
	WHERE ph.product_id IS NOT NULL AND exists(
				SELECT visit_id
				FROM clique_bait.events
				WHERE event_type = 3
					AND e.visit_id = visit_id
)
GROUP BY e.page_id
)
-- Final Select Statement
SELECT 
    ph.product_id,
    ph.page_name,
    ISNULL(pv.view_count, 0) AS view_count,
    ISNULL(pca.cart_add_count, 0) AS cart_add_count,
    ISNULL(pa.abandoned_count, 0) AS abandoned_count,
    ISNULL(pp.purchased_from_cart, 0) AS purchase_count
INTO 
    ProductAnalysis
FROM 
    clique_bait.page_hierarchy ph
LEFT JOIN 
    ProductViews pv ON ph.page_id = pv.page_id
LEFT JOIN 
    ProductCartAdd pca ON ph.page_id = pca.page_id
LEFT JOIN 
    ProductAbandoned pa ON ph.page_id = pa.page_id
LEFT JOIN 
    ProductPurchased pp ON ph.page_id = pp.page_id
WHERE 
    ph.product_id IS NOT NULL;


--1.How many times was each product viewed?

SELECT 
	  product_id,
	  page_name,
	  view_count
FROM [clique_bait].[dbo].[ProductAnalysis]

--2.How many times was each product added to cart?

SELECT
	product_id,
	page_name,
	cart_add_count
FROM [clique_bait].[dbo].[ProductAnalysis]

--3.How many times was each product added to a cart but not purchased (abandoned)?
SELECT
	product_id,
	page_name,
	abandoned_count
FROM [clique_bait].[dbo].[ProductAnalysis]

--4.How many times was each product purchased?
SELECT
	product_id,
	page_name,
	purchase_count
FROM [clique_bait].[dbo].[ProductAnalysis]



--5.Which product had the most views, cart adds and purchases?
SELECT TOP 1
	page_name,
	view_count
FROM dbo.ProductAnalysis
ORDER BY view_count DESC;


--6.Which product was most likely to be abandoned?
SELECT TOP 1
	page_name,
	abandoned_count
FROM dbo.ProductAnalysis
ORDER BY abandoned_count DESC;


--7.Which product had the highest view to purchase percentage?
SELECT TOP 1
	page_name,
	(purchase_count *100 /view_count) AS view_to_purchase_percentage
FROM dbo.ProductAnalysis
ORDER BY view_to_purchase_percentage DESC;

--8.What is the average conversion rate from view to cart add?

WITH totals AS (
SELECT 
	SUM(cart_add_count) AS cart_add_total,
	SUM(view_count)     AS view_total
FROM dbo.ProductAnalysis
)
SELECT 
    CONVERT(DECIMAL(5, 2), (100.0 * cart_add_total / view_total)) AS conversion_rate_percentage
FROM totals;

--What is the average conversion rate from cart add to purchase?
WITH totals AS (
SELECT 
	SUM(purchase_count) AS purchase_total,
	SUM(cart_add_count)     AS cart_add_total
FROM dbo.ProductAnalysis
)
SELECT 
    CONVERT(DECIMAL(5, 2), (100.0 * purchase_total / cart_add_total)) AS conversion_rate_percentage
FROM totals;


--CAMPAIGN ANALYSIS

SELECT
    u.user_id,
    e.visit_id,
    MIN(e.event_time) AS visit_start_time, 
    SUM(CASE WHEN e.event_type=1 THEN 1 ELSE 0 END) AS page_views,
    SUM(CASE WHEN e.event_type=2 THEN 1 ELSE 0 END) AS cart_adds,
    MAX(CASE WHEN e.event_type=3 THEN 1 ELSE 0 END) AS purchase, 
    ci.campaign_name,
    SUM(CASE WHEN e.event_type=4 THEN 1 ELSE 0 END) AS impression,
    SUM(CASE WHEN e.event_type=5 THEN 1 ELSE 0 END) AS click
INTO 
    CampaignAnalysis
FROM 
    clique_bait.users u
JOIN clique_bait.events e ON u.cookie_id = e.cookie_id
LEFT JOIN clique_bait.campaign_identifier ci 
    ON e.event_time BETWEEN ci.start_date AND ci.end_date 
GROUP BY
    u.user_id,
    e.visit_id,
    ci.campaign_name;  


