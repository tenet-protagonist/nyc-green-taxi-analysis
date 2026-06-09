<p align="center">
<img src="https://img.shields.io/badge/SQL-green?style=for-the-badge"/>
<img src="https://img.shields.io/badge/Power%20BI-yellow?style=for-the-badge"/>
<img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge"/>
</p>

# 🚕 NYC Green Taxi Trips 2023

An end-to-end data analytics project covering data ingestion, cleaning, SQL-based analysis, and an interactive Power BI dashboard for New York City Green Taxi trips data in 2023.

---

## 📌 Project Overview

This project analyzes **787,000+ green taxi trips** across New York City in 2023. The goal is to extract actionable business insights around revenue patterns, demand seasonality, route profitability, and trip profiles using SQL Server for data processing and Power BI Desktop for visualization.

**Key questions answered:**
- When and where is demand highest throughout the week?
- Which routes and pickup zones generate the most revenue?
- How does trip distance affect fare efficiency?
- Which boroughs and zones command the highest average fares?
- What is the profile of a typical NYC green taxi trip?

---

## 📊 Dashboard
The Power BI report is organized into four pages:<br><br>
• **Overview**  

![Overview](/screenshots/overview.png)<br>
High-level KPIs and monthly trends across revenue, trip volume, payment methods, and average fares.<br><br>
• **Demand**  

![Demand](/screenshots/demand.png)<br>
Rolling 3-hour demand windows, an hour-by-day heatmap, and average fare by hour of day.<br><br>
• **Routes & Locations**  

![Routes & Locations](/screenshots/routes.png)<br>
Top 5 pickup zones by month, top 10 most profitable routes, and average fare broken down by borough.<br><br>
• **Trip Profiles**  

![Trip Profiles](/screenshots/trip_profiles.png)
Distance-bucket analysis (short/medium/long), revenue per mile, passenger count distribution, and average trip duration.

---

## 📌 Key Metrics
| Metric | Value 
|---|---|
| Total Trips | 746K |
| Total Revenue| $17.74M |
| Average Fare| $18.13 |
| Highest Fare Hour | 05:00 |
| Rush Hour Share | 33.6% |
| Peak Demand Index | 2.22 |
| Most Profitable Distance | short (<2mi)|
| Solo Trip Share | 85.1% |
| Average Distance | 3.08 mi |
| Average Duration | 19.68 min |

---

## 🛠️ Tech Stack

| Tool | Purpose |
|---|---|
| SQL Server | database, data ingestion, cleaning, and transformation |
| T-SQL | CTEs, window functions, stored procedures, views |
| Power BI | interactive, multi-page dashboard |

---

## 📂 Repository Structure

```
nyc-green-taxi-analysis/
├── dashboard/
│   └── dashboard.pbix       # Power BI dashboard file
├── screenshots/       # Dashboard page screenshots
│   ├── demand.png
│   ├── overview.png
│   ├── routes.png
│   └── trip_profiles.png
├── sql/
│   ├── setup_and_cleaning.sql       # Database setup and data cleaning
│   └── views.sql       # Analytical views
├── LICENSE
└── README.md
```

---

## 🗄️ Database Schema

`trips` (fact table)
| Column | Type | Notes |
|---|---|---|
| `trip_id` | INT | PK, auto-increment |
| `vendor_id` | INT | FK → `vendors` |
| `lpep_pickup_datetime` | DATETIME | |
| `lpep_dropoff_datetime` | DATETIME | |
| `rate_code_id` | INT | FK → `rate_codes` |
| `pu_location_id` | INT | FK → `zones` |
| `do_location_id` | INT | FK → `zones` |
| `passenger_count` | INT |
| `trip_distance` | DECIMAL(8,2) | NULL where ≥ 100 mi (physically impossible) |
| `fare_amount` | DECIMAL(8,2) | |
| `total_amount` | DECIMAL(9,2) | |
| `payment_type_id` | INT | FK → `payment_types` |
| `trip_type_id` | INT | FK → `trip_types` |

### Dimension Tables
| Table | Description |
|---|---|
| vendors | Vendor names (Creative Mobile Technologies, VeriFone Inc.) |
| rate_codes | Rate descriptions (Standard, JFK, Newark, Negotiated, etc.) |
| payment_types | Payment method labels (Credit card, Cash, No charge, etc.) |
| trip_types | Street-hail / Dispatch / Unknown
| zones | Borough, zone name, and service zone for each location ID |

### 🔧 Data Pipeline
All steps are in `setup_and_cleaning.sql`.

**1. Ingestion**<br>
Raw CSV is loaded into `raw_trips` via BULK INSERT. Columns with known formatting issues (`trip_distance`, `fare_amount`, `total_amount`) are temporarily typed as VARCHAR to avoid import failures.

**2. Format Validation**  
 A stored procedure (`usp_CheckForOtherChars`) scans the three VARCHAR columns for any characters beyond digits, dots, and commas.

**3. Cleaning & Type Conversion**  
- Commas removed from all numeric-formatted strings, then columns converted to DECIMAL.
- `ehail_fee` dropped — 100% NULL.
- Column names standardized to snake_case; ID columns renamed from `payment_type` / `trip_type` to `payment_type_id` / `trip_type_id` for clarity.

**4. Data Quality Fixes**  
|Issue|Resolution|
|---|---|
| `trip_distance` ≥ 100 mi | Set to NULL (physically impossible in NYC) |
| NULL `payment_type_id` where `tip_amount` > 0 | Inferred as Credit card (type 2) |
| Remaining NULL `payment_type_id` / `trip_type_id` | Set to Unknown |
| `trip_distance`, `fare_amount`, or `total_amount` ≤ 0 | Rows deleted |
| Pickup or dropoff outside 2023 | Rows deleted |
| Unused financial columns | `store_and_fwd_flag`, `extra`, `mta_tax`, `tip_amount`, `tolls_amount`,<br> `improvement_surcharge`, `congestion_surcharge` dropped |

**5. Relational Modeling**  
- `raw_trips` renamed to `trips`, `trip_id` IDENTITY primary key added.
- Dimension tables created and populated from the data dictionary.
- Foreign keys added for all ID columns.

---

## 🔍 Analytical Views
All views are in `views.sql` and serve as the data layer for Power BI.
|View|Description|
|---|---|
| `vw_top5_pickup_locations_by_month` | Top 5 pickup zones by revenue, ranked<br> separately for each month |
| `vw_rolling_3_hour_demand` | Total trip count for every rolling 3-hour<br> window in the day (wraps midnight) |
| `vw_vendor_revenue_comparison` | Monthly revenue share % per vendor with<br> MoM delta and a flag for drops > 5 pp |
| `vw_top10_routes_by_revenue` | Ten highest-revenue pickup → dropoff pairs<br> with at least 100 trips |
| `vw_anomalies_summary` | Two anomaly categories: zero-distance trips<br> with fare > $10, and sub-1-minute trips<br> with distance > 0 |
| `vw_vendor_median_distance` | Median trip distance per vendor via<br> PERCENTILE_CONT |
| `vw_trip_distance_buckets` | Short / medium / long trip segments with trip<br> count, average fare, total revenue, and revenue<br> per mile |
| `vw_top_average_fare_hour_by_weekday` | The single peak-fare hour for each day of the<br> week |
| `vw_demand_index` | Trip count vs. the overall hourly average (168<br> slots), producing a demand index per<br> weekday-hour cell |
| `vw_pu_zones` / `vw_do_zones` | Separate zone views for pickup and dropoff to<br> support two independent relationships to<br> zones in Power BI |

---

## 💡 Key Insights

**Demand**
- The **busiest** 3-hour window is **16:00–19:00** (**171K** trips); **lowest** demand at **3:00-5:00 AM**
- The **peak** demand index of **2.22** means the busiest cells see more than double the average hourly volume.
- Despite high volume in the evening, the **highest average fare** occurs at **05:00** **($25+)**, likely due to longer airport or cross-borough runs in low-traffic conditions.
- Weekdays generate **22.5%** more trips than weekends.

**Revenue & Routes**

- **Street-hail** accounts for **86.35%** of total revenue, far outpacing **dispatch** (**4.32%**).
- The top route — **East Harlem North → East Harlem South** — produced **$318K** across **23K** trips.
- **EWR (Newark Airport)** has the highest average fare at **$91.87** — nearly **5x** the city average.
- **East Harlem North** is the most profitable pickup zone, appearing in the **top 5** every month
- **Average fares** trend upward through the year, peaking in **September** at **$20.36**.

**Trip Profiles**
- **Short trips (<2 mi)** generate **$11.79** per mile — nearly double medium trips and more than double long ones — making them the most efficient segment for drivers.
- **Short trips** also account for **57.16%** of total revenue despite lower per-trip fares.
- **85.1%** of all trips carry a **single passenger**.

---

## 🚀 How to Reproduce

1. Download the [2023 Green Taxi Trip Data](https://data.cityofnewyork.us/Transportation/2023-Green-Taxi-Trip-Data/mzxv-6e3d) and the [Taxi Zone Lookup CSV](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv) from NYC Open Data.
2. Update the file paths in `setup_and_cleaning.sql` to match your local directories.
3. Run `setup_and_cleaning.sql` in SQL Server Management Studio against a SQL Server instance.
4. Run `views.sql` in the same database to create all analytical views.
5. Open the Power BI file, update the data source connection to point at your SQL Server instance, and refresh.

---

## 📋 Data Source

- **Dataset:** NYC TLC Green Taxi Trip Records 2023
- **Source:** [NYC Open Data / TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
- **Zone lookup:** [taxi_zone_lookup.csv](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv)
