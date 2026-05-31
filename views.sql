USE green_taxi_trips_2023
GO

-- 1. Find the top 5 pickup locations by revenue (for each month separately)

CREATE VIEW vw_top5_pickup_locations_by_month AS
WITH pu_location_revenue AS (
	SELECT pu_location_id, MONTH(lpep_pickup_datetime) as month, SUM(total_amount) as revenue
	FROM trips
	GROUP BY pu_location_id, MONTH(lpep_pickup_datetime)
),
pu_location_rank AS (
SELECT month, RANK() OVER (PARTITION BY month ORDER BY revenue DESC) AS rank, pu_location_id, revenue
FROM pu_location_revenue
)
SELECT *
FROM pu_location_rank
WHERE rank <= 5


-- 2. Busiest rolling 3-hour window of the day
-- Business case: Operational planning and surge pricing. Determines when to deploy maximum fleet capacity and when to activate dynamic pricing.

CREATE VIEW vw_rolling_3_hour_demand AS
WITH trip_by_hour AS ( 
SELECT DATEPART(hour, lpep_pickup_datetime) AS hour, COUNT(*) as trip_count
FROM trips
GROUP BY DATEPART(hour, lpep_pickup_datetime)
),
hours_extended AS (
SELECT hour, trip_count
FROM trip_by_hour
UNION ALL
SELECT hour + 24, trip_count
FROM trip_by_hour
WHERE hour IN (0, 1)
),
rolling AS (
SELECT *, SUM(trip_count) OVER (ORDER BY hour ASC ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) as window_trip_count
FROM hours_extended
WHERE hour <= 23
)
SELECT hour as window_start, (hour + 3) % 24 AS window_end, window_trip_count
FROM rolling

-- 3. Revenue contribution % of each vendor per month
--	  Business case: Vendor portfolio analysis. Identifies which vendors are growing and which are stagnating — drives contract
--	  renewal decisions and investment allocation.
--	  filtered rows where vendor_id is NULL

CREATE VIEW vw_vendor_revenue_comparison AS
WITH total_revenue_by_month AS (
SELECT MONTH(lpep_pickup_datetime) as month, SUM(total_amount) AS total_revenue
FROM trips
WHERE vendor_id IS NOT NULL
GROUP BY MONTH(lpep_pickup_datetime)
),
vendor_revenue_by_month AS (
SELECT MONTH(lpep_pickup_datetime) as month, vendor_id, SUM(total_amount) AS vendor_revenue
FROM trips
WHERE vendor_id IS NOT NULL
GROUP BY MONTH(lpep_pickup_datetime), vendor_id
),
vendor_revenue_share_percentage_by_month AS (
SELECT vrbm.*, trbm.total_revenue, CAST(ROUND((vrbm.vendor_revenue * 100.0 / trbm.total_revenue), 1) AS DECIMAL(4, 1)) AS revenue_share_percentage
FROM vendor_revenue_by_month vrbm
INNER JOIN total_revenue_by_month trbm ON vrbm.month = trbm.month
),
vendor_revenue_comparison_by_month AS (
SELECT *, LAG(revenue_share_percentage, 1) OVER (PARTITION BY vendor_id ORDER BY month) AS previous_revenue_share_percentage
FROM vendor_revenue_share_percentage_by_month
)
SELECT month, vendor_id, vendor_revenue, total_revenue, revenue_share_percentage, previous_revenue_share_percentage,
	   revenue_share_percentage - previous_revenue_share_percentage AS revenue_share_difference,
       CASE
	   WHEN revenue_share_percentage - previous_revenue_share_percentage <= -5 THEN 1
	   ELSE 0
	   END AS flag
FROM vendor_revenue_comparison_by_month 

-- A threshold of 5% was selected based on observed data distribution — typical month-over-month fluctuations remain within 0.1–3.3%,
-- making 5% a meaningful signal of abnormal vendor performance.

-- 4. Top 10 most profitable routes (pickup → dropoff) with at least 100 trips

CREATE VIEW vw_top10_routes_by_revenue AS
WITH route_stats AS (
SELECT pu_location_id, do_location_id, COUNT(*) AS trips_count,
	   CAST(ROUND(AVG(total_amount), 2) as DECIMAL(8, 2)) AS average_revenue, CAST(ROUND(SUM(total_amount), 0) AS INT) AS total_revenue
FROM trips
GROUP BY pu_location_id, do_location_id
HAVING COUNT(trip_id) >= 100
),
route_rank AS (
SELECT RANK() OVER(ORDER BY total_revenue DESC) as rank, *
FROM route_stats
)
SELECT * 
FROM route_rank
WHERE rank <= 10 

-- 5. Anomalous trips: distance = 0, but fare > $10, or trip duration < 1 minute, but distance > 0

CREATE VIEW vw_anomalies_summary AS
SELECT 
    CASE 
        WHEN trip_distance = 0 AND total_amount > 10 THEN 'Zero distance, high total amount'
        WHEN DATEDIFF(MINUTE, lpep_pickup_datetime, lpep_dropoff_datetime) < 1 
             AND trip_distance > 0 THEN 'Impossible duration'
    END AS anomaly_type,
    COUNT(*) AS trip_count,
    CAST(ROUND(AVG(total_amount), 2) AS DECIMAL(8,2)) AS avg_total_amount,
    CAST(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM trips), 1) AS DECIMAL(4,1)) AS pct_of_total
FROM trips
WHERE (trip_distance = 0 AND total_amount > 10)
   OR (DATEDIFF(MINUTE, lpep_pickup_datetime, lpep_dropoff_datetime) < 1 AND trip_distance > 0)
GROUP BY 
    CASE 
        WHEN trip_distance = 0 AND total_amount > 10 THEN 'Zero distance, high total amount'
        WHEN DATEDIFF(MINUTE, lpep_pickup_datetime, lpep_dropoff_datetime) < 1 
             AND trip_distance > 0 THEN 'Impossible duration'
    END 

-- 6. Median trip distance per vendor

CREATE VIEW vw_vendor_median_distance AS
SELECT DISTINCT vendor_id, CAST(PERCENTILE_CONT(0.5)
								WITHIN GROUP (ORDER BY trip_distance)
								OVER (PARTITION BY vendor_id) as DECIMAL(8, 2)
							   ) AS median_distance
FROM trips

-- 7. Trip distance buckets: short / medium / long — trip count, avg fare, total revenue

CREATE VIEW vw_trip_distance_buckets AS
WITH distance_bucket AS (
SELECT CASE
       WHEN trip_distance < 2 THEN 'short (<2mi)'
       WHEN trip_distance BETWEEN 2 AND 10 THEN 'medium (2-10mi)'
       WHEN trip_distance > 10 THEN 'long (>10mi)'
       END AS trip_distance_bucket, total_amount, trip_distance
FROM trips
WHERE trip_distance > 0
)
SELECT trip_distance_bucket,
	   COUNT(*) AS trip_count,
	   CAST(ROUND(AVG(total_amount), 2) AS DECIMAL(8,2)) AS average_revenue,
       CAST(ROUND(SUM(total_amount), 0) AS DECIMAL(8,0)) AS total_revenue,
       CAST(ROUND((SUM(total_amount) / SUM(trip_distance)), 2) AS DECIMAL(10,2)) AS revenue_per_mile
FROM distance_bucket
GROUP BY trip_distance_bucket  

-- 8. For each day of the week find the hour with the highest average fare

CREATE VIEW vw_top_average_fare_hour_by_weekday AS
WITH average_fare_all_hours AS (
SELECT DATEPART(weekday, lpep_pickup_datetime) AS weekday, DATEPART(hour, lpep_pickup_datetime) AS hour, CAST(ROUND(AVG(total_amount), 2) AS DECIMAL (10, 2)) AS average_fare
FROM trips
GROUP BY DATEPART(weekday, lpep_pickup_datetime), DATEPART(hour, lpep_pickup_datetime)
),
average_fare_hours_rank AS (
SELECT *, RANK() OVER (PARTITION BY weekday ORDER BY average_fare DESC) AS rank
FROM average_fare_all_hours
)
SELECT weekday, hour, average_fare
FROM average_fare_hours_rank
WHERE rank = 1

-- 9. Demand seasonality index by hour and day of week

CREATE VIEW vw_demand_index AS
WITH trips_count_by_weekday_hour AS (
SELECT DATEPART(weekday, lpep_pickup_datetime) AS weekday, DATEPART(hour, lpep_pickup_datetime) AS hour, COUNT(*) AS trip_count
FROM trips
GROUP BY DATEPART(weekday, lpep_pickup_datetime), DATEPART(hour, lpep_pickup_datetime)
),
average_trip_count AS (
SELECT CAST(COUNT(*) AS DECIMAL(10, 2)) / 168 AS average_trip_count
FROM trips
)
SELECT tcbwh.*,
	   CAST(ROUND(atc.average_trip_count, 0) AS INT) AS average_trip_count,
	   CAST(ROUND(tcbwh.trip_count / atc.average_trip_count, 2) AS DECIMAL(8,  2)) AS demand_index
FROM trips_count_by_weekday_hour tcbwh
CROSS JOIN average_trip_count atc

-- Create views for zones table (to manage relationships between do/pu locations and zones table

CREATE VIEW vw_pu_zones AS
SELECT id, borough, zone, service_zone
FROM zones

CREATE VIEW vw_do_zones AS
SELECT id, borough, zone, service_zone
FROM zones